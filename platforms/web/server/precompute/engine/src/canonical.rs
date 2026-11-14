//! Canonical byte form of one submission (ADR 0052). The form is the hash
//! preimage of the Paragraph and FontContracts cache layers and the content
//! encoding of the binary bridge: hashing it, sending it and resupplying it
//! all consume the same bytes, so the host and Rust agree on one identity per
//! input. The TypeScript mirror is `npm/src/canonical.ts`; golden vectors
//! assert both implementations produce identical bytes.
//!
//! The identity contract is "decode(encode(x)) reads exactly like the JSON
//! lane's `JSON.stringify` round trip": every field is carried the way
//! `JSON.stringify` would carry it. Non-finite numbers become absent fields
//! (`JSON.stringify` writes `null`, which every reader coalesces away) and
//! `-0` becomes `+0` (`JSON.stringify` prints both as `0`). The caller's
//! logical `key` is deliberately absent: entries are keyed by content and the
//! key is backfilled by the caller after a hit.

use sha2::{Digest, Sha256};

use tiqian::NamedError;
use tiqian_protocol_gen::runtime::u_string::UString;

use crate::json::{member, Json};
use crate::snapshot_source::js_number_value;

pub const CANONICAL_MAGIC: &[u8; 4] = b"TQCS";
pub const CANONICAL_VERSION: u8 = 1;
/// Snapshot paragraph submission: carries `maxWidthPx`.
pub const KIND_SNAPSHOT: u8 = 0;
/// Font contract submission: the capture width is derived in Rust, no width
/// crosses the bridge.
pub const KIND_CONTRACT: u8 = 1;

const SEM_ATTRS: u8 = 0x01;
const SEM_ORDER: u8 = 0x02;
const SEM_TAG_NAME: u8 = 0x04;

const SPAN_FAMILIES: u8 = 0x01;
const SPAN_FONT_SIZE_PX: u8 = 0x02;
const SPAN_FONT_WEIGHT: u8 = 0x04;
const SPAN_ITALIC: u8 = 0x08;
const SPAN_BASELINE_SHIFT_PX: u8 = 0x10;

const BOX_INLINE_START_PX: u8 = 0x01;
const BOX_INLINE_END_PX: u8 = 0x02;
const BOX_OUTER_SPACING: u8 = 0x04;

/// The `??` step shared with the wire readers: absent and null both read as
/// absent.
/// Mirrors the parsed wire JSON into the generated wire value. Object field
/// order is the parser's document order, the identity order of attribute
/// pairs.
fn json_to_wire(value: &Json) -> tiqian_protocol_gen::org::tiqian::protocol::wire_value::WireValue {
    use tiqian_protocol_gen::org::tiqian::protocol::wire_field::WireField;
    use tiqian_protocol_gen::org::tiqian::protocol::wire_value::WireValue;
    match value {
        Json::Null => WireValue::WNull,
        Json::Bool(inner) => WireValue::WBool { value: *inner },
        Json::Num(inner) => WireValue::WNum { value: *inner },
        // The wire lane stores Haxe strings (UTF-16 units); the parsed
        // JSON lane keeps `String`, so the adapter encodes UTF-16 at the
        // boundary with the generated `From<&str>` conversion.
        Json::Str(inner) => WireValue::WStr { value: UString::from(inner.as_str()) },
        Json::Arr(items) => WireValue::WArr {
            items: items.iter().map(json_to_wire).collect(),
        },
        Json::Obj(fields) => WireValue::WObj {
            fields: fields
                .iter()
                .map(|(name, value)| WireField {
                    name: UString::from(name.as_str()),
                    value: json_to_wire(value),
                })
                .collect(),
        },
    }
}

/// Encodes one wire input object (the shape `PrepareInput::from_json` reads)
/// into its canonical bytes. The byte form is the generated single source
/// (org.tiqian.protocol.Canonical); this function adapts the parsed JSON and
/// raises the named issue the wire readers report.
pub fn encode_input(value: &Json, kind: u8) -> Result<Vec<u8>, NamedError> {
    use tiqian_protocol_gen::org::tiqian::protocol::canonical::Canonical;
    use tiqian_protocol_gen::org::tiqian::protocol::encode_result::EncodeResult;
    match Canonical::canonical_encode(json_to_wire(value), kind as u32) {
        EncodeResult::COk { mut bytes } => {
            crate::numeric::append_canonical(value, &mut bytes)?;
            Ok(bytes)
        },
        // The generated issue is a Haxe string; the host lane reports it
        // as the UTF-8 `String` inside `NamedError`.
        EncodeResult::CErr { issue } => Err(NamedError(issue.to_utf8_lossy())),
    }
}

/// Reads a canonical buffer with bounds checks; every failure is the one
/// named issue, the buffer is foreign input.
struct Reader<'a> {
    bytes: &'a [u8],
    cursor: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Reader { bytes, cursor: 0 }
    }

    fn take(&mut self, len: usize) -> Result<&'a [u8], NamedError> {
        let end = self.cursor.checked_add(len).ok_or_else(|| invalid())?;
        let slice = self.bytes.get(self.cursor..end).ok_or_else(|| invalid())?;
        self.cursor = end;
        Ok(slice)
    }

    fn u8(&mut self) -> Result<u8, NamedError> {
        let slice = self.take(1)?;
        Ok(slice[0])
    }

    fn u32(&mut self) -> Result<u32, NamedError> {
        let slice = self.take(4)?;
        Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
    }

    fn f64(&mut self) -> Result<f64, NamedError> {
        let slice = self.take(8)?;
        let mut bits = [0u8; 8];
        bits.copy_from_slice(slice);
        Ok(f64::from_bits(u64::from_le_bytes(bits)))
    }

    fn str(&mut self) -> Result<String, NamedError> {
        let len = self.length()?;
        let slice = self.take(len)?;
        let text = std::str::from_utf8(slice).map_err(|_| invalid())?;
        Ok(text.to_string())
    }

    fn raw(&mut self) -> Result<Vec<u8>, NamedError> {
        let len = self.length()?;
        Ok(self.take(len)?.to_vec())
    }

    fn length(&mut self) -> Result<usize, NamedError> {
        let len = self.u32()?;
        usize::try_from(len).map_err(|_| invalid())
    }

    fn done(&self) -> Result<(), NamedError> {
        if self.cursor == self.bytes.len() {
            Ok(())
        } else {
            Err(invalid())
        }
    }
}

fn invalid() -> NamedError {
    NamedError("InvalidCanonicalForm".to_string())
}
fn read_number_field(reader: &mut Reader) -> Result<Option<f64>, NamedError> {
    if reader.u8()? == 1 {
        Ok(Some(reader.f64()?))
    } else {
        Ok(None)
    }
}

/// The decoded submission: the wire fields as JSON trees, shaped exactly the
/// way the JSON lane's parse would leave them.
pub struct DecodedSubmission {
    pub value: Json,
}

/// Decodes canonical bytes back into the wire input object. The object feeds
/// `PrepareInput::from_json` and must behave identically to the JSON lane's
/// parse of the same input.
pub fn decode_input(bytes: &[u8], kind: u8) -> Result<DecodedSubmission, NamedError> {
    let mut reader = Reader::new(bytes);
    if reader.take(4)? != CANONICAL_MAGIC || reader.u8()? != CANONICAL_VERSION {
        return Err(invalid());
    }
    if reader.u8()? != kind {
        return Err(NamedError("CanonicalKindMismatch".to_string()));
    }
    let text = reader.str()?;
    let mut fields: Vec<(String, Json)> = Vec::new();
    fields.push(("text".to_string(), Json::Str(text)));
    if kind == KIND_SNAPSHOT {
        if let Some(width) = read_number_field(&mut reader)? {
            fields.push(("maxWidthPx".to_string(), Json::Num(width)));
        }
    }
    fields.push(("semantics".to_string(), decode_semantics(&mut reader)?));
    fields.push(("textSpans".to_string(), decode_spans(&mut reader)?));
    fields.push(("inlineBoxes".to_string(), decode_boxes(&mut reader)?));
    let mut boundaries = Vec::new();
    for _ in 0..reader.length()? {
        boundaries.push(Json::Num(reader.f64()?));
    }
    fields.push(("sourceBoundaries".to_string(), Json::Arr(boundaries)));
    // Older inputs keep their original bytes; a numeric trailer restores the
    // added text-span field before the cached request reaches the precomputer.
    if reader.cursor < reader.bytes.len() {
        if reader.take(4)? != b"TQNV" { return Err(invalid()) }
        let variants = crate::json::parse_json(&reader.str()?).map_err(|_| invalid())?;
        let spans = fields.iter_mut().find(|(name, _)| name == "textSpans")
            .ok_or_else(invalid)?;
        crate::numeric::restore_canonical(&mut spans.1, variants)?;
    }
    reader.done()?;
    Ok(DecodedSubmission {
        value: Json::Obj(fields),
    })
}

fn decode_semantics(reader: &mut Reader) -> Result<Json, NamedError> {
    let mut items = Vec::new();
    for _ in 0..reader.length()? {
        let flags = reader.u8()?;
        let mut fields: Vec<(String, Json)> = Vec::new();
        if let Some(value) = read_number_field(reader)? {
            fields.push(("start".to_string(), Json::Num(value)));
        }
        if let Some(value) = read_number_field(reader)? {
            fields.push(("end".to_string(), Json::Num(value)));
        }
        if flags & SEM_TAG_NAME != 0 {
            fields.push(("tagName".to_string(), Json::Str(reader.str()?)));
        }
        if flags & SEM_ORDER != 0 {
            fields.push(("order".to_string(), Json::Num(reader.f64()?)));
        }
        if flags & SEM_ATTRS != 0 {
            fields.push(("attributes".to_string(), decode_attributes(reader)?));
        }
        items.push(Json::Obj(fields));
    }
    Ok(Json::Arr(items))
}

fn decode_attributes(reader: &mut Reader) -> Result<Json, NamedError> {
    match reader.u8()? {
        0 => Ok(Json::Obj(Vec::new())),
        1 => {
            let mut fields = Vec::new();
            for _ in 0..reader.length()? {
                let name = reader.str()?;
                let value = reader.str()?;
                fields.push((name, Json::Str(value)));
            }
            Ok(Json::Obj(fields))
        }
        2 => {
            let raw = reader.raw()?;
            let text = String::from_utf8(raw).map_err(|_| invalid())?;
            crate::json::parse_json(&text).map_err(|_| invalid())
        }
        _ => Err(invalid()),
    }
}

fn decode_spans(reader: &mut Reader) -> Result<Json, NamedError> {
    let mut items = Vec::new();
    for _ in 0..reader.length()? {
        let flags = reader.u8()?;
        let mut fields: Vec<(String, Json)> = Vec::new();
        if let Some(value) = read_number_field(reader)? {
            fields.push(("start".to_string(), Json::Num(value)));
        }
        if let Some(value) = read_number_field(reader)? {
            fields.push(("end".to_string(), Json::Num(value)));
        }
        if flags & SPAN_FAMILIES != 0 {
            let mut names = Vec::new();
            for _ in 0..reader.length()? {
                names.push(Json::Str(reader.str()?));
            }
            fields.push(("fontFamilies".to_string(), Json::Arr(names)));
        }
        if flags & SPAN_FONT_SIZE_PX != 0 {
            fields.push(("fontSizePx".to_string(), Json::Num(reader.f64()?)));
        }
        if flags & SPAN_FONT_WEIGHT != 0 {
            fields.push(("fontWeight".to_string(), Json::Num(reader.f64()?)));
        }
        if flags & SPAN_ITALIC != 0 {
            fields.push(("italic".to_string(), Json::Bool(reader.u8()? != 0)));
        }
        if flags & SPAN_BASELINE_SHIFT_PX != 0 {
            fields.push(("baselineShiftPx".to_string(), Json::Num(reader.f64()?)));
        }
        items.push(Json::Obj(fields));
    }
    Ok(Json::Arr(items))
}

fn decode_boxes(reader: &mut Reader) -> Result<Json, NamedError> {
    let mut items = Vec::new();
    for _ in 0..reader.length()? {
        let flags = reader.u8()?;
        let mut fields: Vec<(String, Json)> = Vec::new();
        if let Some(value) = read_number_field(reader)? {
            fields.push(("start".to_string(), Json::Num(value)));
        }
        if let Some(value) = read_number_field(reader)? {
            fields.push(("end".to_string(), Json::Num(value)));
        }
        if flags & BOX_INLINE_START_PX != 0 {
            fields.push(("inlineStartPx".to_string(), Json::Num(reader.f64()?)));
        }
        if flags & BOX_INLINE_END_PX != 0 {
            fields.push(("inlineEndPx".to_string(), Json::Num(reader.f64()?)));
        }
        if flags & BOX_OUTER_SPACING != 0 {
            fields.push(("outerSpacing".to_string(), Json::Str(reader.str()?)));
        }
        items.push(Json::Obj(fields));
    }
    Ok(Json::Arr(items))
}

/// Reads the kind byte out of a canonical form, checking the magic and the
/// version first. Submissions derive their tier from the content itself, so
/// no lane duplicates what the bytes already carry.
pub fn kind_of(bytes: &[u8]) -> Result<u8, NamedError> {
    if bytes.len() < 6
        || &bytes[0..4] != CANONICAL_MAGIC
        || bytes[4] != CANONICAL_VERSION
        || (bytes[5] != KIND_SNAPSHOT && bytes[5] != KIND_CONTRACT)
    {
        return Err(invalid());
    }
    Ok(bytes[5])
}

/// Raw SHA-256 digest of canonical bytes; the cache-layer content hash.
pub fn digest(bytes: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let finished = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&finished);
    out
}

/// The store key: the combination rule lives in Rust only (ADR 0052). The
/// context fingerprint and the content hash jointly identify one entry.
pub fn store_key(context_fingerprint: &[u8; 32], content_hash: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(context_fingerprint);
    hasher.update(content_hash);
    let finished = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&finished);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::parse_json;

    fn wire(text: &str) -> Json {
        parse_json(text).expect("test wire parses")
    }

    /// The cross-language golden vectors: the TypeScript mirror in
    /// `npm/src/canonical.ts` pins the same hex strings, so both encoders
    /// produce identical bytes for the same inputs.
    #[test]
    fn golden_vectors_pin_the_bytes() {
        let cases: &[(&str, u8, &str)] = &[
            (
                r#"{"key":"p-1","text":"中文","maxWidthPx":144}"#,
                KIND_SNAPSHOT,
                "54514353010006000000e4b8ade6968701000000000000624000000000000000000000000000000000",
            ),
            (
                r#"{"key":"fc-1","text":"中文"}"#,
                KIND_CONTRACT,
                "54514353010106000000e4b8ade6968700000000000000000000000000000000",
            ),
            (
                r#"{"key":"p-2","text":"中文字排版","maxWidthPx":144,"semantics":[{"tagName":"a","start":2,"end":4,"attributes":{"href":"https://example.com","class":"link"},"order":1},{"tagName":"em","start":0,"end":1}],"textSpans":[{"start":0,"end":2,"fontFamilies":["Dela Gothic One"],"fontSizePx":18,"fontWeight":400,"italic":true,"baselineShiftPx":-0.5},{"start":2,"end":4,"fontFamilies":[]}],"inlineBoxes":[{"start":1,"end":2,"inlineStartPx":8,"inlineEndPx":4,"outerSpacing":"Source"},{"start":3,"end":4}],"sourceBoundaries":[0,18,36]}"#,
                KIND_SNAPSHOT,
                "5451435301000f000000e4b8ade69687e5ad97e68e92e7898801000000000000624002000000070100000000000000400100000000000010400100000061000000000000f03f010200000004000000687265661300000068747470733a2f2f6578616d706c652e636f6d05000000636c617373040000006c696e6b0401000000000000000001000000000000f03f02000000656d020000001f010000000000000000010000000000000040010000000f00000044656c6120476f74686963204f6e650000000000003240000000000000794001000000000000e0bf0101000000000000004001000000000000104000000000020000000701000000000000f03f0100000000000000400000000000002040000000000000104006000000536f757263650001000000000000084001000000000000104003000000000000000000000000000000000032400000000000004240",
            ),
            (
                r#"{"key":"p-3","text":" coerce ","maxWidthPx":"144.5","semantics":[{"tagName":"i","start":"1","end":2,"attributes":[["a","1"],["b",2]]}],"textSpans":[{"start":0,"end":1,"italic":"no"}],"inlineBoxes":[{"start":0,"end":1,"outerSpacing":7}],"sourceBoundaries":["3",null]}"#,
                KIND_SNAPSHOT,
                "5451435301000800000020636f6572636520010000000000106240010000000501000000000000f03f010000000000000040010000006902130000005b5b2261222c2231225d2c5b2262222c325d5d010000000001000000000000000001000000000000f03f010000000401000000000000000001000000000000f03f01000000370200000000000000000008400000000000000000",
            ),
        ];
        for (input, kind, hex) in cases {
            let value = parse_json(input).expect("golden input parses");
            let bytes = encode_input(&value, *kind).expect("golden input encodes");
            let rendered: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
            assert_eq!(&rendered, hex, "golden vector mismatch");
        }
    }

    fn round_trip(value: &Json, kind: u8) -> Json {
        let encoded = encode_input(value, kind).expect("encode succeeds");
        decode_input(&encoded, kind).expect("decode succeeds").value
    }

    fn assert_member_equal(round: &Json, original: &Json, name: &str) {
        let expected = member(original, name).cloned().unwrap_or(Json::Null);
        let actual = member(round, name).cloned().unwrap_or(Json::Null);
        assert_eq!(actual, expected, "field {name} survives the round trip");
    }

    #[test]
    fn full_submission_round_trips_every_field() {
        let original = wire(
            r#"{"key":"p1","text":"中文与 English 混排","maxWidthPx":640.5,
                "semantics":[{"start":0,"end":4,"tagName":"a",
                    "attributes":{"href":"/x","class":"y"}}],
                "textSpans":[{"start":0,"end":4,"fontFamilies":["Fira Code"],
                    "fontSizePx":16,"fontWeight":400,"italic":true,
                    "baselineShiftPx":-0.15}],
                "inlineBoxes":[{"start":2,"end":3,"inlineStartPx":4,
                    "inlineEndPx":5,"outerSpacing":"Narrow"}],
                "sourceBoundaries":[0,2,7]}"#,
        );
        let round = round_trip(&original, KIND_SNAPSHOT);
        for name in [
            "text",
            "maxWidthPx",
            "semantics",
            "textSpans",
            "inlineBoxes",
            "sourceBoundaries",
        ] {
            assert_member_equal(&round, &original, name);
        }
        // The logical key never enters the canonical form.
        assert_eq!(member(&round, "key"), None);
    }

    #[test]
    fn contract_kind_drops_the_width() {
        let original = wire(r#"{"text":"正文","maxWidthPx":900}"#);
        let round = round_trip(&original, KIND_CONTRACT);
        assert_eq!(member(&round, "maxWidthPx"), None);
    }

    #[test]
    fn null_and_absent_fields_collapse() {
        let original = wire(
            r#"{"text":"t","semantics":null,"textSpans":null,
                "inlineBoxes":null,"sourceBoundaries":null}"#,
        );
        let round = round_trip(&original, KIND_SNAPSHOT);
        assert_eq!(member(&round, "semantics"), Some(&Json::Arr(Vec::new())));
        assert_eq!(member(&round, "textSpans"), Some(&Json::Arr(Vec::new())));
        assert_eq!(member(&round, "inlineBoxes"), Some(&Json::Arr(Vec::new())));
        assert_eq!(
            member(&round, "sourceBoundaries"),
            Some(&Json::Arr(Vec::new()))
        );
    }

    #[test]
    fn non_finite_numbers_read_as_absent() {
        // JSON.stringify turns NaN and Infinity into null; readers coalesce
        // null away, so the canonical form carries them as absent fields.
        let mut original = wire(r#"{"text":"t","textSpans":[{"start":0,"end":2}]}"#);
        if let Json::Obj(fields) = &mut original {
            fields.push(("maxWidthPx".to_string(), Json::Num(f64::INFINITY)));
            if let Some(Json::Arr(spans)) = fields
                .iter_mut()
                .find(|(name, _)| name == "textSpans")
                .map(|(_, value)| value)
            {
                if let Some(Json::Obj(span)) = spans.first_mut() {
                    span.push(("fontSizePx".to_string(), Json::Num(f64::NAN)));
                }
            }
        }
        let round = round_trip(&original, KIND_SNAPSHOT);
        assert_eq!(member(&round, "maxWidthPx"), None);
        let spans = member(&round, "textSpans").cloned().unwrap_or(Json::Null);
        let Json::Arr(items) = spans else {
            panic!("spans decode");
        };
        let first = items.first().cloned().unwrap_or(Json::Null);
        assert_eq!(member(&first, "fontSizePx"), None);
    }

    #[test]
    fn negative_zero_collapses_to_positive_zero() {
        let original = wire(r#"{"text":"t","maxWidthPx":-0.0}"#);
        let encoded = encode_input(&original, KIND_SNAPSHOT).expect("encode succeeds");
        // The width survives as +0: the present flag follows the text
        // section, and the eight width bytes are all zero.
        let flag_offset = 4 + 1 + 1 + 4 + 1;
        assert_eq!(encoded[flag_offset], 1);
        assert!(encoded[flag_offset + 1..flag_offset + 9]
            .iter()
            .all(|byte| *byte == 0));
        let round = decode_input(&encoded, KIND_SNAPSHOT)
            .expect("decode succeeds")
            .value;
        match member(&round, "maxWidthPx") {
            Some(Json::Num(value)) => {
                assert_eq!(*value, 0.0);
                assert!(!value.is_sign_negative());
            }
            other => panic!("width decodes to {other:?}"),
        }
    }

    #[test]
    fn loose_values_coerce_the_reader_way() {
        // String numbers and boolean italics go through the same coercions
        // the wire readers apply, so both lanes agree on the parsed values.
        let original =
            parse_json(r#"{"text":123,"textSpans":[{"start":"4","end":"8","italic":1}]}"#)
                .expect("parses");
        let round = round_trip(&original, KIND_SNAPSHOT);
        assert_eq!(member(&round, "text"), Some(&Json::str("123")));
        let spans = member(&round, "textSpans").cloned().unwrap_or(Json::Null);
        let Json::Arr(items) = spans else {
            panic!("spans decode");
        };
        let first = items.first().cloned().unwrap_or(Json::Null);
        assert_eq!(member(&first, "start"), Some(&Json::Num(4.0)));
        assert_eq!(member(&first, "italic"), None);
    }

    #[test]
    fn attribute_shapes_carry_their_reader_semantics() {
        // Object attributes decode as string pairs; array attributes ride as
        // JSON text so an invalid pair shape still raises the reader's named
        // error; other shapes read as empty.
        let object_form = wire(
            r#"{"text":"t","semantics":[{"start":0,"end":1,"tagName":"a",
                "attributes":{"href":"/x"}}]}"#,
        );
        let round = round_trip(&object_form, KIND_SNAPSHOT);
        let semantics = member(&round, "semantics").cloned().unwrap_or(Json::Null);
        let Json::Arr(items) = semantics else {
            panic!("semantics decode");
        };
        let attributes = member(items.first().unwrap_or(&Json::Null), "attributes")
            .cloned()
            .unwrap_or(Json::Null);
        assert_eq!(attributes, parse_json(r#"{"href":"/x"}"#).expect("parses"));

        let array_form = wire(
            r#"{"text":"t","semantics":[{"start":0,"end":1,"tagName":"a",
                "attributes":[["href","/x"]]}]}"#,
        );
        let round = round_trip(&array_form, KIND_SNAPSHOT);
        let semantics = member(&round, "semantics").cloned().unwrap_or(Json::Null);
        let Json::Arr(items) = semantics else {
            panic!("semantics decode");
        };
        let attributes = member(items.first().unwrap_or(&Json::Null), "attributes")
            .cloned()
            .unwrap_or(Json::Null);
        assert_eq!(
            attributes,
            parse_json(r#"[["href","/x"]]"#).expect("parses")
        );
    }

    #[test]
    fn non_array_semantics_rejects_with_the_reader_name() {
        let original = wire(r#"{"text":"t","semantics":"nope"}"#);
        let error = encode_input(&original, KIND_SNAPSHOT).expect_err("rejects");
        assert_eq!(error.0, "InvalidSnapshotSemantics");
    }

    #[test]
    fn truncated_buffers_reject() {
        let original = wire(r#"{"text":"正文正文"}"#);
        let encoded = encode_input(&original, KIND_SNAPSHOT).expect("encode succeeds");
        for cut in 1..encoded.len() {
            assert!(
                decode_input(&encoded[..cut], KIND_SNAPSHOT).is_err(),
                "prefix of {cut} bytes must not decode"
            );
        }
    }

    #[test]
    fn digest_matches_sha256_of_the_bytes() {
        let original = wire(r#"{"text":"t"}"#);
        let encoded = encode_input(&original, KIND_SNAPSHOT).expect("encode succeeds");
        assert_eq!(crate::font_source::sha256_hex(&encoded), {
            let raw = digest(&encoded);
            raw.iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>()
        });
    }

    #[test]
    fn store_key_combines_both_hashes() {
        let context = [7u8; 32];
        let content = [9u8; 32];
        let key = store_key(&context, &content);
        // The combination depends on both inputs and is stable.
        assert_eq!(key, store_key(&context, &content));
        assert_ne!(key, store_key(&[8u8; 32], &content));
        assert_ne!(key, store_key(&context, &[10u8; 32]));
    }
}