//! The station-table binary encoding (ADR 0052 `BundleLayering`): the frozen
//! table of one build as a fixed-layout byte file. Little-endian throughout.
//! Offset regions carry u32 deltas summed from an implicit zero start; row
//! data lives in per-column regions of homogeneous width, so the repeated
//! small integers and the few distinct f64 payloads stay visible to the
//! transport compression:
//!
//! ```text
//! magic "TIQTBL03"                              8 bytes
//! replayStringCount stringCount                 u32 each, 56-byte header
//! metricCount metricValuePoolCount
//! probeCount probeAdvancePoolCount probeStylePoolCount probeFeaturesPoolCount
//! faceCount typographyCount valueStyleCount fontPreloadCount
//! stringDeltas          stringCount x u32       offsets into stringBytes
//! stringBytes           UTF-8, concatenated
//! metricFamiliesRefs    metricCount x u32       columns of the key-sorted rows
//! metricWeights         metricCount x f64
//! metricItalics         metricCount x u8
//! metricRoleRefs        metricCount x u32
//! metricFaceSelRefs     metricCount x u32
//! metricPoolRefs        metricCount x u32
//! metricValuePool       poolCount x 40 B        5 x f64, NaN bits = absent
//! probeTextRefs         probeCount x u32
//! probeAdvanceRefs      probeCount x u16
//! probeStyleRefs        probeCount x u16
//! probeFeatureRefs      probeCount x u16
//! probeAdvancePool      poolCount x f64
//! probeStylePool        poolCount x 25 B
//! probeFeatureDeltas    poolCount x u32         offsets into probeFeaturesRows
//! probeFeaturesRows     row = u16 count + count x u32
//! faceDeltas            faceCount x u32         canonical JSON text per row
//! typographyDeltas      typographyCount x u32
//! valueStyleDeltas      valueStyleCount x u32
//! fontPreloadDeltas     fontPreloadCount x u32
//! revisionText          canonical JSON of the revisions object (tail region)
//! ```
//!
//! Metric rows sort by `(familiesRef, weight, italic, roleRef,
//! faceSelectionRef)`, so two builds that absorb the same content in
//! different orders freeze to the same bytes. Metric values are f64, not
//! f32: rounded values could flip line breaks against the server render.
//! The encoding is deterministic: the same table content produces the same
//! bytes, so restoring a frozen file and freezing again reproduces it.

use std::cmp::Ordering;
use std::collections::HashMap;

use tiqian::NamedError;

use crate::js_compat::trunc_sat_usize;
use crate::json::{parse_json, Json};
use crate::schema::stable_stringify;
use crate::snapshot_manifest::{arr_of, field};
use crate::snapshot_tables::SnapshotTables;

const MAGIC: [u8; 8] = *b"TIQTBL03";
const HEADER_U32_COUNT: usize = 12;
const METRIC_POOL_ROW_BYTES: usize = 40;
const PROBE_STYLE_ROW_BYTES: usize = 25;

fn invalid() -> NamedError {
    NamedError("SnapshotTableBinaryInvalid".to_string())
}

/// Every size and offset computation runs through these guards so overflow
/// surfaces as the named decode issue instead of wrapping.
fn checked_add(a: usize, b: usize) -> Result<usize, NamedError> {
    a.checked_add(b).ok_or_else(invalid)
}

fn checked_mul(count: usize, unit_bytes: usize) -> Result<usize, NamedError> {
    count.checked_mul(unit_bytes).ok_or_else(invalid)
}

fn try_usize(value: u32) -> Result<usize, NamedError> {
    usize::try_from(value).map_err(|_| invalid())
}

fn try_u32(value: usize) -> Result<u32, NamedError> {
    u32::try_from(value).map_err(|_| invalid())
}

fn try_u16(value: u32) -> Result<u16, NamedError> {
    u16::try_from(value).map_err(|_| invalid())
}

/// One metric row split into its binary columns; the value quintuple lives in
/// the shared pool.
struct MetricRow {
    families_ref: u32,
    weight: f64,
    italic: u8,
    role_ref: u32,
    face_selection_ref: u32,
    value_bits: [u64; 5],
    value_pool_ref: u32,
}

/// The metric sort key without the pooled values; shared by the encoder sort
/// and the decoder's strict-order validation.
struct MetricKey {
    families_ref: u32,
    weight: f64,
    italic: u8,
    role_ref: u32,
    face_selection_ref: u32,
}

impl MetricKey {
    fn order(&self, other: &MetricKey) -> Ordering {
        self.families_ref
            .cmp(&other.families_ref)
            .then_with(|| self.weight.total_cmp(&other.weight))
            .then_with(|| self.italic.cmp(&other.italic))
            .then_with(|| self.role_ref.cmp(&other.role_ref))
            .then_with(|| self.face_selection_ref.cmp(&other.face_selection_ref))
    }
}

/// One probe row split into pooled columns. The pool refs stay u16: the pools
/// hold distinct values, which stay far below the u32 row indexes.
struct ProbeRow {
    text_ref: u32,
    advance_pool_ref: u16,
    style_pool_ref: u16,
    features_pool_ref: u16,
}

struct ProbeStyle {
    font_size: f64,
    weight: f64,
    italic: u8,
    script_ref: u32,
    language_ref: u32,
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    fn new() -> Self {
        Writer { bytes: Vec::new() }
    }
    fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }
    fn u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }
    fn u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }
    fn f64(&mut self, value: f64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }
    fn bytes(&mut self, value: &[u8]) {
        self.bytes.extend_from_slice(value);
    }
}

fn number_of(value: &Json) -> Result<f64, NamedError> {
    let Json::Num(number) = value else {
        return Err(invalid());
    };
    Ok(*number)
}

fn finite_number_of(value: &Json) -> Result<f64, NamedError> {
    let number = number_of(value)?;
    if !number.is_finite() {
        return Err(invalid());
    }
    Ok(number)
}

fn u32_index_of(value: &Json) -> Result<u32, NamedError> {
    let number = number_of(value)?;
    if number.fract() != 0.0 || number < 0.0 || number >= 4294967296.0 {
        return Err(invalid());
    }
    u32::try_from(trunc_sat_usize(number)).map_err(|_| invalid())
}

fn string_of<'a>(value: &'a Json) -> Result<&'a str, NamedError> {
    let Json::Str(text) = value else {
        return Err(invalid());
    };
    Ok(text)
}

/// The full string region: the replay strings keep their indexes, probe-only
/// strings append after them in first-seen scan order.
struct StringRegion {
    texts: Vec<String>,
    map: HashMap<String, u32>,
    replay_count: usize,
}

impl StringRegion {
    fn build(tables: &SnapshotTables) -> Result<Self, NamedError> {
        let mut region = StringRegion {
            texts: Vec::new(),
            map: HashMap::new(),
            replay_count: 0,
        };
        for row in tables.strings.rows() {
            region.intern(string_of(&row)?)?;
            region.replay_count += 1;
        }
        if region.texts.len() != region.replay_count {
            // Replay strings intern deduplicated; a repeat means the table
            // state would no longer round-trip its own indexes.
            return Err(invalid());
        }
        Ok(region)
    }
    fn intern(&mut self, text: &str) -> Result<u32, NamedError> {
        if let Some(existing) = self.map.get(text) {
            return Ok(*existing);
        }
        let index = try_u32(self.texts.len())?;
        self.texts.push(text.to_string());
        self.map.insert(text.to_string(), index);
        Ok(index)
    }
}

/// Encodes the state of one table set; finalize is the sanctioned caller.
pub(crate) fn encode(tables: &SnapshotTables) -> Result<Vec<u8>, NamedError> {
    let mut strings = StringRegion::build(tables)?;

    // Metric rows: split, sort by the key tuple, then pool the value
    // quintuples in sorted order so a restored rebuild re-encodes the same
    // pool sequence.
    let mut metrics: Vec<MetricRow> = Vec::with_capacity(tables.metrics.len());
    for row in &tables.metrics {
        metrics.push(metric_row_of(row)?);
    }
    metrics.sort_by(|a, b| metric_order(a, b));
    let mut value_pool: Vec<[u64; 5]> = Vec::new();
    let mut value_pool_indexes: HashMap<[u64; 5], u32> = HashMap::new();
    for row in &mut metrics {
        let pool_ref = match value_pool_indexes.get(&row.value_bits) {
            Some(existing) => *existing,
            None => {
                let index = try_u32(value_pool.len())?;
                value_pool.push(row.value_bits);
                value_pool_indexes.insert(row.value_bits, index);
                index
            }
        };
        row.value_pool_ref = pool_ref;
    }

    // Probe rows: strict canonical shape (the emit walk produces exactly
    // these fields), pooled advances/styles/feature lists.
    let mut probes: Vec<ProbeRow> = Vec::with_capacity(tables.probes.len());
    let mut advance_pool: Vec<u64> = Vec::new();
    let mut advance_indexes: HashMap<u64, u32> = HashMap::new();
    let mut style_pool: Vec<ProbeStyle> = Vec::new();
    let mut style_indexes: HashMap<(u64, u64, u8, u32, u32), u32> = HashMap::new();
    let mut features_pool: Vec<Vec<u32>> = Vec::new();
    let mut features_indexes: HashMap<Vec<u32>, u32> = HashMap::new();
    for probe in &tables.probes {
        let text_ref = strings.intern(string_of(field(probe, "text").ok_or_else(invalid)?)?)?;
        let advance = finite_number_of(field(probe, "advancePx").ok_or_else(invalid)?)?;
        let font_size = finite_number_of(field(probe, "fontSizePx").ok_or_else(invalid)?)?;
        let weight = finite_number_of(field(probe, "fontWeight").ok_or_else(invalid)?)?;
        let italic = match field(probe, "italic").ok_or_else(invalid)? {
            Json::Bool(value) => u8::from(*value),
            _ => return Err(invalid()),
        };
        let script_ref = strings.intern(string_of(field(probe, "script").ok_or_else(invalid)?)?)?;
        let language_ref =
            strings.intern(string_of(field(probe, "language").ok_or_else(invalid)?)?)?;
        let features = arr_of(field(probe, "features")).ok_or_else(invalid)?;
        let mut feature_refs: Vec<u32> = Vec::with_capacity(features.len());
        for feature in features {
            feature_refs.push(strings.intern(string_of(feature)?)?);
        }
        let advance_bits = advance.to_bits();
        let advance_pool_ref = match advance_indexes.get(&advance_bits) {
            Some(existing) => *existing,
            None => {
                let index = try_u32(advance_pool.len())?;
                advance_pool.push(advance_bits);
                advance_indexes.insert(advance_bits, index);
                index
            }
        };
        let style_key = (
            font_size.to_bits(),
            weight.to_bits(),
            italic,
            script_ref,
            language_ref,
        );
        let style_pool_ref = match style_indexes.get(&style_key) {
            Some(existing) => *existing,
            None => {
                let index = try_u32(style_pool.len())?;
                style_pool.push(ProbeStyle {
                    font_size,
                    weight,
                    italic,
                    script_ref,
                    language_ref,
                });
                style_indexes.insert(style_key, index);
                index
            }
        };
        let features_pool_ref = match features_indexes.get(&feature_refs) {
            Some(existing) => *existing,
            None => {
                let index = try_u32(features_pool.len())?;
                features_pool.push(feature_refs.clone());
                features_indexes.insert(feature_refs, index);
                index
            }
        };
        probes.push(ProbeRow {
            text_ref,
            advance_pool_ref: try_u16(advance_pool_ref)?,
            style_pool_ref: try_u16(style_pool_ref)?,
            features_pool_ref: try_u16(features_pool_ref)?,
        });
    }

    let face_texts: Vec<String> = tables
        .faces
        .iter()
        .map(|face| stable_stringify(face))
        .collect();
    let typography_texts: Vec<String> = tables
        .typographies
        .iter()
        .map(|row| stable_stringify(row))
        .collect();
    let font_preloads = tables.derived_font_preload_urls();

    let mut revisions: Vec<(String, Json)> = Vec::new();
    if let Some(value) = &tables.backend_revision {
        revisions.push(("backendRevision".to_string(), value.clone()));
    }
    if let Some(value) = &tables.harfbuzz_version {
        revisions.push(("harfbuzzVersion".to_string(), value.clone()));
    }
    let revision_text = stable_stringify(&Json::Obj(revisions));

    let mut writer = Writer::new();
    writer.bytes(&MAGIC);
    writer.u32(try_u32(strings.replay_count)?);
    writer.u32(try_u32(strings.texts.len())?);
    writer.u32(try_u32(metrics.len())?);
    writer.u32(try_u32(value_pool.len())?);
    writer.u32(try_u32(probes.len())?);
    writer.u32(try_u32(advance_pool.len())?);
    writer.u32(try_u32(style_pool.len())?);
    writer.u32(try_u32(features_pool.len())?);
    writer.u32(try_u32(face_texts.len())?);
    writer.u32(try_u32(typography_texts.len())?);
    writer.u32(try_u32(tables.value_styles.len())?);
    writer.u32(try_u32(font_preloads.len())?);

    write_deltas(
        &mut writer,
        &strings.texts.iter().map(String::as_str).collect::<Vec<_>>(),
    )?;
    for text in &strings.texts {
        writer.bytes(text.as_bytes());
    }

    for row in &metrics {
        writer.u32(row.families_ref);
    }
    for row in &metrics {
        writer.f64(row.weight);
    }
    for row in &metrics {
        writer.u8(row.italic);
    }
    for row in &metrics {
        writer.u32(row.role_ref);
    }
    for row in &metrics {
        writer.u32(row.face_selection_ref);
    }
    for row in &metrics {
        writer.u32(row.value_pool_ref);
    }
    for bits in &value_pool {
        for slot in bits {
            writer.f64(f64::from_bits(*slot));
        }
    }

    for row in &probes {
        writer.u32(row.text_ref);
    }
    for row in &probes {
        writer.u16(row.advance_pool_ref);
    }
    for row in &probes {
        writer.u16(row.style_pool_ref);
    }
    for row in &probes {
        writer.u16(row.features_pool_ref);
    }
    for bits in &advance_pool {
        writer.f64(f64::from_bits(*bits));
    }
    for style in &style_pool {
        writer.f64(style.font_size);
        writer.f64(style.weight);
        writer.u8(style.italic);
        writer.u32(style.script_ref);
        writer.u32(style.language_ref);
    }
    let features_rows: Vec<&[u32]> = features_pool.iter().map(|refs| refs.as_slice()).collect();
    write_feature_deltas(&mut writer, &features_rows)?;
    for refs in &features_pool {
        writer.u16(u16::try_from(refs.len()).map_err(|_| invalid())?);
        for reference in refs {
            writer.u32(*reference);
        }
    }

    write_deltas(&mut writer, &face_texts)?;
    for text in &face_texts {
        writer.bytes(text.as_bytes());
    }
    write_deltas(&mut writer, &typography_texts)?;
    for text in &typography_texts {
        writer.bytes(text.as_bytes());
    }
    write_deltas(&mut writer, &tables.value_styles)?;
    for declaration in &tables.value_styles {
        writer.bytes(declaration.as_bytes());
    }
    write_deltas(&mut writer, &font_preloads)?;
    for url in &font_preloads {
        writer.bytes(url.as_bytes());
    }
    writer.bytes(revision_text.as_bytes());
    Ok(writer.bytes)
}

fn metric_order(a: &MetricRow, b: &MetricRow) -> Ordering {
    MetricKey {
        families_ref: a.families_ref,
        weight: a.weight,
        italic: a.italic,
        role_ref: a.role_ref,
        face_selection_ref: a.face_selection_ref,
    }
    .order(&MetricKey {
        families_ref: b.families_ref,
        weight: b.weight,
        italic: b.italic,
        role_ref: b.role_ref,
        face_selection_ref: b.face_selection_ref,
    })
}

/// One offsets region as u32 deltas above an implicit zero start; the rows
/// themselves are written by the caller after this region.
fn write_deltas<S: AsRef<str>>(writer: &mut Writer, texts: &[S]) -> Result<(), NamedError> {
    let mut offset: u32 = 0;
    for text in texts {
        let next = offset
            .checked_add(u32::try_from(text.as_ref().len()).map_err(|_| invalid())?)
            .ok_or_else(invalid)?;
        writer.u32(next - offset);
        offset = next;
    }
    Ok(())
}

fn write_feature_deltas(writer: &mut Writer, rows: &[&[u32]]) -> Result<(), NamedError> {
    let mut offset: u32 = 0;
    for refs in rows {
        let count = u16::try_from(refs.len()).map_err(|_| invalid())?;
        let next = offset
            .checked_add(
                u32::from(count)
                    .checked_mul(4)
                    .and_then(|value| value.checked_add(2))
                    .ok_or_else(invalid)?,
            )
            .ok_or_else(invalid)?;
        writer.u32(next - offset);
        offset = next;
    }
    Ok(())
}

fn metric_row_of(row: &Json) -> Result<MetricRow, NamedError> {
    let Json::Arr(values) = row else {
        return Err(invalid());
    };
    if values.len() != 10 {
        return Err(invalid());
    }
    let italic_number = finite_number_of(&values[2])?;
    if italic_number != 0.0 && italic_number != 1.0 {
        return Err(invalid());
    }
    let mut value_bits = [0u64; 5];
    for (slot, value) in values[5..10].iter().enumerate() {
        value_bits[slot] = match value {
            Json::Null => f64::NAN.to_bits(),
            Json::Num(_) => finite_number_of(value)?.to_bits(),
            _ => return Err(invalid()),
        };
    }
    Ok(MetricRow {
        families_ref: u32_index_of(&values[0])?,
        weight: finite_number_of(&values[1])?,
        italic: u8::from(italic_number == 1.0),
        role_ref: u32_index_of(&values[3])?,
        face_selection_ref: u32_index_of(&values[4])?,
        value_bits,
        value_pool_ref: 0,
    })
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Reader { bytes, position: 0 }
    }
    fn take(&mut self, count: usize) -> Result<&'a [u8], NamedError> {
        let end = checked_add(self.position, count)?;
        if end > self.bytes.len() {
            return Err(invalid());
        }
        let slice = &self.bytes[self.position..end];
        self.position = end;
        Ok(slice)
    }
}

fn read_u32_at(bytes: &[u8], at: usize) -> Result<u32, NamedError> {
    let mut raw = [0u8; 4];
    raw.copy_from_slice(bytes.get(at..checked_add(at, 4)?).ok_or_else(invalid)?);
    Ok(u32::from_le_bytes(raw))
}

fn read_u16_at(bytes: &[u8], at: usize) -> Result<u16, NamedError> {
    let mut raw = [0u8; 2];
    raw.copy_from_slice(bytes.get(at..checked_add(at, 2)?).ok_or_else(invalid)?);
    Ok(u16::from_le_bytes(raw))
}

fn read_f64_at(bytes: &[u8], at: usize) -> Result<f64, NamedError> {
    let mut raw = [0u8; 8];
    raw.copy_from_slice(bytes.get(at..checked_add(at, 8)?).ok_or_else(invalid)?);
    Ok(f64::from_le_bytes(raw))
}

fn read_u8_at(bytes: &[u8], at: usize) -> Result<u8, NamedError> {
    Ok(*bytes.get(at).ok_or_else(invalid)?)
}

/// The six metric columns; every column holds `metric_count` entries.
struct MetricColumns {
    families_refs: usize,
    weights: usize,
    italics: usize,
    role_refs: usize,
    face_selection_refs: usize,
    pool_refs: usize,
}

/// The four probe columns; the three pool columns hold u16 refs.
struct ProbeColumns {
    text_refs: usize,
    advance_refs: usize,
    style_refs: usize,
    features_refs: usize,
}

/// The validated region layout of one binary table: every region's absolute
/// start plus its offsets vector. All invariants the runtime relies on
/// (strict metric order, refs in range) hold when this parses.
struct Layout {
    replay_string_count: usize,
    string_count: usize,
    string_offsets: Vec<u32>,
    string_bytes_start: usize,
    metric_count: usize,
    metrics: MetricColumns,
    metric_value_pool_start: usize,
    probe_count: usize,
    probes: ProbeColumns,
    probe_advance_pool_start: usize,
    probe_style_pool_start: usize,
    probe_features_offsets: Vec<u32>,
    probe_features_rows_start: usize,
    face_text_offsets: Vec<u32>,
    face_text_start: usize,
    typography_text_offsets: Vec<u32>,
    typography_text_start: usize,
    value_style_offsets: Vec<u32>,
    value_style_start: usize,
    revision_text_start: usize,
}

/// Parses and validates the region layout of a binary table.
fn decode_layout(bytes: &[u8]) -> Result<Layout, NamedError> {
    let mut reader = Reader::new(bytes);
    if reader.take(8)? != MAGIC {
        return Err(invalid());
    }
    let mut counts = [0u32; HEADER_U32_COUNT];
    for count in &mut counts {
        let mut raw = [0u8; 4];
        raw.copy_from_slice(reader.take(4)?);
        *count = u32::from_le_bytes(raw);
    }
    let count = |index: usize| -> Result<usize, NamedError> {
        usize::try_from(counts[index]).map_err(|_| invalid())
    };
    let replay_string_count = count(0)?;
    let string_count = count(1)?;
    let metric_count = count(2)?;
    let metric_value_pool_count = count(3)?;
    let probe_count = count(4)?;
    let probe_advance_pool_count = count(5)?;
    let probe_style_pool_count = count(6)?;
    let probe_features_pool_count = count(7)?;
    let face_count = count(8)?;
    let typography_count = count(9)?;
    let value_style_count = count(10)?;
    let font_preload_count = count(11)?;
    if replay_string_count > string_count {
        return Err(invalid());
    }

    let string_offsets = read_deltas(&mut reader, string_count)?;
    let string_bytes_start = reader.position;
    let string_bytes_len = try_usize(*string_offsets.last().ok_or_else(invalid)?)?;
    reader.take(string_bytes_len)?;

    let metric_families_start = reader.position;
    reader.take(checked_mul(metric_count, 4)?)?;
    let metric_weights_start = reader.position;
    reader.take(checked_mul(metric_count, 8)?)?;
    let metric_italics_start = reader.position;
    reader.take(metric_count)?;
    let metric_role_start = reader.position;
    reader.take(checked_mul(metric_count, 4)?)?;
    let metric_face_selection_start = reader.position;
    reader.take(checked_mul(metric_count, 4)?)?;
    let metric_pool_start = reader.position;
    reader.take(checked_mul(metric_count, 4)?)?;
    let metric_value_pool_start = reader.position;
    reader.take(checked_mul(metric_value_pool_count, METRIC_POOL_ROW_BYTES)?)?;

    let probe_text_start = reader.position;
    reader.take(checked_mul(probe_count, 4)?)?;
    let probe_advance_refs_start = reader.position;
    reader.take(checked_mul(probe_count, 2)?)?;
    let probe_style_refs_start = reader.position;
    reader.take(checked_mul(probe_count, 2)?)?;
    let probe_features_refs_start = reader.position;
    reader.take(checked_mul(probe_count, 2)?)?;
    let probe_advance_pool_start = reader.position;
    reader.take(checked_mul(probe_advance_pool_count, 8)?)?;
    let probe_style_pool_start = reader.position;
    reader.take(checked_mul(probe_style_pool_count, PROBE_STYLE_ROW_BYTES)?)?;
    let probe_features_offsets = read_deltas(&mut reader, probe_features_pool_count)?;
    let probe_features_rows_start = reader.position;
    let features_bytes_len = try_usize(*probe_features_offsets.last().ok_or_else(invalid)?)?;
    reader.take(features_bytes_len)?;

    let face_text_offsets = read_deltas(&mut reader, face_count)?;
    let face_text_start = reader.position;
    reader.take(try_usize(*face_text_offsets.last().ok_or_else(invalid)?)?)?;
    let typography_text_offsets = read_deltas(&mut reader, typography_count)?;
    let typography_text_start = reader.position;
    reader.take(try_usize(
        *typography_text_offsets.last().ok_or_else(invalid)?,
    )?)?;
    let value_style_offsets = read_deltas(&mut reader, value_style_count)?;
    let value_style_start = reader.position;
    reader.take(try_usize(*value_style_offsets.last().ok_or_else(invalid)?)?)?;
    let font_preload_offsets = read_deltas(&mut reader, font_preload_count)?;
    let font_preload_text_start = reader.position;
    reader.take(try_usize(
        *font_preload_offsets.last().ok_or_else(invalid)?,
    )?)?;
    let revision_text_start = reader.position;

    let metrics = MetricColumns {
        families_refs: metric_families_start,
        weights: metric_weights_start,
        italics: metric_italics_start,
        role_refs: metric_role_start,
        face_selection_refs: metric_face_selection_start,
        pool_refs: metric_pool_start,
    };
    let probes = ProbeColumns {
        text_refs: probe_text_start,
        advance_refs: probe_advance_refs_start,
        style_refs: probe_style_refs_start,
        features_refs: probe_features_refs_start,
    };
    validate_strings(&string_offsets, string_count, string_bytes_start, bytes)?;
    validate_metric_columns(
        &metrics,
        metric_count,
        string_count,
        metric_value_pool_count,
        bytes,
    )?;
    validate_metric_value_pool(metric_value_pool_start, metric_value_pool_count, bytes)?;
    validate_probe_columns(
        &probes,
        probe_count,
        string_count,
        probe_advance_pool_count,
        probe_style_pool_count,
        probe_features_pool_count,
        bytes,
    )?;
    validate_probe_advance_pool(probe_advance_pool_start, probe_advance_pool_count, bytes)?;
    validate_probe_style_pool(
        probe_style_pool_start,
        probe_style_pool_count,
        string_count,
        bytes,
    )?;
    validate_probe_features(
        &probe_features_offsets,
        probe_features_rows_start,
        string_count,
        bytes,
    )?;
    validate_text_region(&face_text_offsets, face_text_start, bytes)?;
    validate_text_region(&typography_text_offsets, typography_text_start, bytes)?;
    validate_text_region(&value_style_offsets, value_style_start, bytes)?;
    validate_text_region(&font_preload_offsets, font_preload_text_start, bytes)?;

    Ok(Layout {
        replay_string_count,
        string_count,
        string_offsets,
        string_bytes_start,
        metric_count,
        metrics,
        metric_value_pool_start,
        probe_count,
        probes,
        probe_advance_pool_start,
        probe_style_pool_start,
        probe_features_offsets,
        probe_features_rows_start,
        face_text_offsets,
        face_text_start,
        typography_text_offsets,
        typography_text_start,
        value_style_offsets,
        value_style_start,
        revision_text_start,
    })
}

/// One delta-coded offsets region: `count` u32 deltas summed from an implicit
/// zero. Any delta sequence decodes monotone; the checked additions keep a
/// hostile file from wrapping past the u32 range.
fn read_deltas(reader: &mut Reader, count: usize) -> Result<Vec<u32>, NamedError> {
    let mut offsets = Vec::with_capacity(checked_add(count, 1)?);
    offsets.push(0);
    let mut offset: u32 = 0;
    for _ in 0..count {
        let mut raw = [0u8; 4];
        raw.copy_from_slice(reader.take(4)?);
        offset = offset
            .checked_add(u32::from_le_bytes(raw))
            .ok_or_else(invalid)?;
        offsets.push(offset);
    }
    Ok(offsets)
}

fn string_slice_at<'a>(
    offsets: &[u32],
    string_bytes_start: usize,
    bytes: &'a [u8],
    index: usize,
) -> Result<&'a [u8], NamedError> {
    let start = try_usize(*offsets.get(index).ok_or_else(invalid)?)?;
    let end = try_usize(*offsets.get(checked_add(index, 1)?).ok_or_else(invalid)?)?;
    bytes
        .get(checked_add(string_bytes_start, start)?..checked_add(string_bytes_start, end)?)
        .ok_or_else(invalid)
}

/// Every string must decode as UTF-8; the region feeds every lookup.
fn validate_strings(
    offsets: &[u32],
    count: usize,
    string_bytes_start: usize,
    bytes: &[u8],
) -> Result<(), NamedError> {
    for index in 0..count {
        std::str::from_utf8(string_slice_at(offsets, string_bytes_start, bytes, index)?)
            .map_err(|_| invalid())?;
    }
    Ok(())
}

fn metric_key_at(
    bytes: &[u8],
    columns: &MetricColumns,
    index: usize,
) -> Result<MetricKey, NamedError> {
    Ok(MetricKey {
        families_ref: read_u32_at(
            bytes,
            checked_add(columns.families_refs, checked_mul(index, 4)?)?,
        )?,
        weight: read_f64_at(bytes, checked_add(columns.weights, checked_mul(index, 8)?)?)?,
        italic: read_u8_at(bytes, checked_add(columns.italics, index)?)?,
        role_ref: read_u32_at(
            bytes,
            checked_add(columns.role_refs, checked_mul(index, 4)?)?,
        )?,
        face_selection_ref: read_u32_at(
            bytes,
            checked_add(columns.face_selection_refs, checked_mul(index, 4)?)?,
        )?,
    })
}

fn validate_metric_columns(
    columns: &MetricColumns,
    count: usize,
    string_count: usize,
    value_pool_count: usize,
    bytes: &[u8],
) -> Result<(), NamedError> {
    for index in 0..count {
        let key = metric_key_at(bytes, columns, index)?;
        if index > 0 {
            let previous = metric_key_at(bytes, columns, index - 1)?;
            if previous.order(&key) != Ordering::Less {
                return Err(invalid());
            }
        }
        if !key.weight.is_finite() || key.italic > 1 {
            return Err(invalid());
        }
        if try_usize(key.families_ref)? >= string_count
            || try_usize(key.role_ref)? >= string_count
            || try_usize(key.face_selection_ref)? >= string_count
        {
            return Err(invalid());
        }
        let pool_ref = read_u32_at(
            bytes,
            checked_add(columns.pool_refs, checked_mul(index, 4)?)?,
        )?;
        if try_usize(pool_ref)? >= value_pool_count {
            return Err(invalid());
        }
    }
    Ok(())
}

/// A pool slot is either finite or the canonical absent-NaN bit pattern.
fn validate_metric_value_pool(start: usize, count: usize, bytes: &[u8]) -> Result<(), NamedError> {
    for index in 0..count {
        for slot in 0..5 {
            let value = read_f64_at(
                bytes,
                checked_add(
                    checked_add(start, checked_mul(index, METRIC_POOL_ROW_BYTES)?)?,
                    checked_mul(slot, 8)?,
                )?,
            )?;
            if !value.is_finite() && value.to_bits() != f64::NAN.to_bits() {
                return Err(invalid());
            }
        }
    }
    Ok(())
}

fn validate_probe_columns(
    columns: &ProbeColumns,
    count: usize,
    string_count: usize,
    advance_count: usize,
    style_count: usize,
    features_count: usize,
    bytes: &[u8],
) -> Result<(), NamedError> {
    for index in 0..count {
        let text_ref = read_u32_at(
            bytes,
            checked_add(columns.text_refs, checked_mul(index, 4)?)?,
        )?;
        if try_usize(text_ref)? >= string_count {
            return Err(invalid());
        }
        let advance_ref = read_u16_at(
            bytes,
            checked_add(columns.advance_refs, checked_mul(index, 2)?)?,
        )?;
        if usize::from(advance_ref) >= advance_count {
            return Err(invalid());
        }
        let style_ref = read_u16_at(
            bytes,
            checked_add(columns.style_refs, checked_mul(index, 2)?)?,
        )?;
        if usize::from(style_ref) >= style_count {
            return Err(invalid());
        }
        let features_ref = read_u16_at(
            bytes,
            checked_add(columns.features_refs, checked_mul(index, 2)?)?,
        )?;
        if usize::from(features_ref) >= features_count {
            return Err(invalid());
        }
    }
    Ok(())
}

fn validate_probe_advance_pool(start: usize, count: usize, bytes: &[u8]) -> Result<(), NamedError> {
    for index in 0..count {
        let value = read_f64_at(bytes, checked_add(start, checked_mul(index, 8)?)?)?;
        if !value.is_finite() {
            return Err(invalid());
        }
    }
    Ok(())
}

fn validate_probe_style_pool(
    start: usize,
    count: usize,
    string_count: usize,
    bytes: &[u8],
) -> Result<(), NamedError> {
    for index in 0..count {
        let at = checked_add(start, checked_mul(index, PROBE_STYLE_ROW_BYTES)?)?;
        let font_size = read_f64_at(bytes, at)?;
        let weight = read_f64_at(bytes, checked_add(at, 8)?)?;
        let italic = read_u8_at(bytes, checked_add(at, 16)?)?;
        let script_ref = read_u32_at(bytes, checked_add(at, 17)?)?;
        let language_ref = read_u32_at(bytes, checked_add(at, 21)?)?;
        if !font_size.is_finite() || !weight.is_finite() || italic > 1 {
            return Err(invalid());
        }
        if try_usize(script_ref)? >= string_count || try_usize(language_ref)? >= string_count {
            return Err(invalid());
        }
    }
    Ok(())
}

fn validate_probe_features(
    offsets: &[u32],
    rows_start: usize,
    string_count: usize,
    bytes: &[u8],
) -> Result<(), NamedError> {
    for index in 0..offsets.len().saturating_sub(1) {
        let from = try_usize(offsets[index])?;
        let to = try_usize(*offsets.get(checked_add(index, 1)?).ok_or_else(invalid)?)?;
        let row = bytes
            .get(checked_add(rows_start, from)?..checked_add(rows_start, to)?)
            .ok_or_else(invalid)?;
        let count = read_u16_at(row, 0)?;
        if row.len() != checked_add(2, checked_mul(usize::from(count), 4)?)? {
            return Err(invalid());
        }
        for slot in 0..usize::from(count) {
            let reference = read_u32_at(row, checked_add(2, checked_mul(slot, 4)?)?)?;
            if try_usize(reference)? >= string_count {
                return Err(invalid());
            }
        }
    }
    Ok(())
}

fn validate_text_region(offsets: &[u32], start: usize, bytes: &[u8]) -> Result<(), NamedError> {
    let region_len = try_usize(*offsets.last().ok_or_else(invalid)?)?;
    let region = bytes
        .get(start..checked_add(start, region_len)?)
        .ok_or_else(invalid)?;
    std::str::from_utf8(region).map_err(|_| invalid())?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Materialization for restore
// ---------------------------------------------------------------------------

/// The decoded rows of one binary table in the shape [`SnapshotTables`]
/// restores.
pub(crate) struct DecodedTable {
    pub(crate) replay_string_count: usize,
    pub(crate) typographies: Vec<Json>,
    pub(crate) faces: Vec<Json>,
    pub(crate) probes: Vec<Json>,
    pub(crate) strings: Vec<Json>,
    pub(crate) metrics: Vec<Json>,
    pub(crate) value_styles: Vec<String>,
    pub(crate) backend_revision: Option<Json>,
    pub(crate) harfbuzz_version: Option<Json>,
}

fn region_text(
    offsets: &[u32],
    start: usize,
    bytes: &[u8],
    index: usize,
) -> Result<String, NamedError> {
    let from = try_usize(*offsets.get(index).ok_or_else(invalid)?)?;
    let to = try_usize(*offsets.get(checked_add(index, 1)?).ok_or_else(invalid)?)?;
    let slice = bytes
        .get(checked_add(start, from)?..checked_add(start, to)?)
        .ok_or_else(invalid)?;
    String::from_utf8(slice.to_vec()).map_err(|_| invalid())
}

/// Decodes a binary table into restorable rows. The layout validation of
/// [`decode_layout`] ran first; the materialization parses the JSON text
/// regions and rebuilds the canonical row shapes.
pub(crate) fn decode(bytes: &[u8]) -> Result<DecodedTable, NamedError> {
    let layout = decode_layout(bytes)?;
    let mut strings: Vec<Json> = Vec::with_capacity(layout.string_count);
    for index in 0..layout.string_count {
        let slice = string_slice_at(
            &layout.string_offsets,
            layout.string_bytes_start,
            bytes,
            index,
        )?;
        strings.push(Json::str(
            String::from_utf8(slice.to_vec()).map_err(|_| invalid())?,
        ));
    }
    let string_at = |reference: u32| -> Result<Json, NamedError> {
        Ok(strings
            .get(try_usize(reference)?)
            .ok_or_else(invalid)?
            .clone())
    };

    let mut metrics: Vec<Json> = Vec::with_capacity(layout.metric_count);
    for index in 0..layout.metric_count {
        let families_ref = read_u32_at(
            bytes,
            checked_add(layout.metrics.families_refs, checked_mul(index, 4)?)?,
        )?;
        let weight = read_f64_at(
            bytes,
            checked_add(layout.metrics.weights, checked_mul(index, 8)?)?,
        )?;
        let italic = read_u8_at(bytes, checked_add(layout.metrics.italics, index)?)?;
        let role_ref = read_u32_at(
            bytes,
            checked_add(layout.metrics.role_refs, checked_mul(index, 4)?)?,
        )?;
        let face_selection_ref = read_u32_at(
            bytes,
            checked_add(layout.metrics.face_selection_refs, checked_mul(index, 4)?)?,
        )?;
        let pool_ref = read_u32_at(
            bytes,
            checked_add(layout.metrics.pool_refs, checked_mul(index, 4)?)?,
        )?;
        let pool_at = checked_add(
            layout.metric_value_pool_start,
            checked_mul(try_usize(pool_ref)?, METRIC_POOL_ROW_BYTES)?,
        )?;
        let mut values: Vec<Json> = Vec::with_capacity(10);
        values.push(Json::Num(f64::from(families_ref)));
        values.push(Json::Num(weight));
        values.push(Json::Num(f64::from(italic)));
        values.push(Json::Num(f64::from(role_ref)));
        values.push(Json::Num(f64::from(face_selection_ref)));
        for slot in 0..5 {
            let bits = read_f64_at(bytes, checked_add(pool_at, checked_mul(slot, 8)?)?)?.to_bits();
            if bits == f64::NAN.to_bits() {
                values.push(Json::Null);
            } else {
                values.push(Json::Num(f64::from_bits(bits)));
            }
        }
        metrics.push(Json::Arr(values));
    }

    let mut probes: Vec<Json> = Vec::with_capacity(layout.probe_count);
    for index in 0..layout.probe_count {
        let text_ref = read_u32_at(
            bytes,
            checked_add(layout.probes.text_refs, checked_mul(index, 4)?)?,
        )?;
        let advance_ref = read_u16_at(
            bytes,
            checked_add(layout.probes.advance_refs, checked_mul(index, 2)?)?,
        )?;
        let style_ref = read_u16_at(
            bytes,
            checked_add(layout.probes.style_refs, checked_mul(index, 2)?)?,
        )?;
        let features_pool_ref = read_u16_at(
            bytes,
            checked_add(layout.probes.features_refs, checked_mul(index, 2)?)?,
        )?;
        let advance = read_f64_at(
            bytes,
            checked_add(
                layout.probe_advance_pool_start,
                checked_mul(usize::from(advance_ref), 8)?,
            )?,
        )?;
        let style_at = checked_add(
            layout.probe_style_pool_start,
            checked_mul(usize::from(style_ref), PROBE_STYLE_ROW_BYTES)?,
        )?;
        let features_row = {
            let from = try_usize(
                *layout
                    .probe_features_offsets
                    .get(usize::from(features_pool_ref))
                    .ok_or_else(invalid)?,
            )?;
            let to = try_usize(
                *layout
                    .probe_features_offsets
                    .get(checked_add(usize::from(features_pool_ref), 1)?)
                    .ok_or_else(invalid)?,
            )?;
            bytes
                .get(
                    checked_add(layout.probe_features_rows_start, from)?
                        ..checked_add(layout.probe_features_rows_start, to)?,
                )
                .ok_or_else(invalid)?
        };
        let features_count = read_u16_at(features_row, 0)?;
        let mut features: Vec<Json> = Vec::with_capacity(usize::from(features_count));
        for slot in 0..usize::from(features_count) {
            features.push(string_at(read_u32_at(
                features_row,
                checked_add(2, checked_mul(slot, 4)?)?,
            )?)?);
        }
        probes.push(Json::Obj(vec![
            ("text".to_string(), string_at(text_ref)?),
            ("advancePx".to_string(), Json::Num(advance)),
            (
                "fontSizePx".to_string(),
                Json::Num(read_f64_at(bytes, style_at)?),
            ),
            (
                "fontWeight".to_string(),
                Json::Num(read_f64_at(bytes, checked_add(style_at, 8)?)?),
            ),
            (
                "italic".to_string(),
                Json::Bool(read_u8_at(bytes, checked_add(style_at, 16)?)? == 1),
            ),
            (
                "script".to_string(),
                string_at(read_u32_at(bytes, checked_add(style_at, 17)?)?)?,
            ),
            (
                "language".to_string(),
                string_at(read_u32_at(bytes, checked_add(style_at, 21)?)?)?,
            ),
            ("features".to_string(), Json::Arr(features)),
        ]));
    }

    let mut typographies = Vec::new();
    for index in 0..layout.typography_text_offsets.len().saturating_sub(1) {
        let text = region_text(
            &layout.typography_text_offsets,
            layout.typography_text_start,
            bytes,
            index,
        )?;
        typographies.push(parse_json(&text).map_err(|_| invalid())?);
    }
    let mut faces = Vec::new();
    for index in 0..layout.face_text_offsets.len().saturating_sub(1) {
        let text = region_text(
            &layout.face_text_offsets,
            layout.face_text_start,
            bytes,
            index,
        )?;
        faces.push(parse_json(&text).map_err(|_| invalid())?);
    }
    let mut value_styles = Vec::new();
    for index in 0..layout.value_style_offsets.len().saturating_sub(1) {
        value_styles.push(region_text(
            &layout.value_style_offsets,
            layout.value_style_start,
            bytes,
            index,
        )?);
    }

    let revision_text = String::from_utf8(
        bytes
            .get(layout.revision_text_start..)
            .ok_or_else(invalid)?
            .to_vec(),
    )
    .map_err(|_| invalid())?;
    let revisions = parse_json(&revision_text).map_err(|_| invalid())?;

    Ok(DecodedTable {
        replay_string_count: layout.replay_string_count,
        typographies,
        faces,
        probes,
        strings,
        metrics,
        value_styles,
        backend_revision: field(&revisions, "backendRevision").cloned(),
        harfbuzz_version: field(&revisions, "harfbuzzVersion").cloned(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn probe() -> Json {
        Json::Obj(vec![
            ("text".to_string(), Json::str("永")),
            ("advancePx".to_string(), Json::Num(18.0)),
            ("fontSizePx".to_string(), Json::Num(18.0)),
            ("fontWeight".to_string(), Json::Num(400.0)),
            ("italic".to_string(), Json::Bool(false)),
            ("script".to_string(), Json::str("hani")),
            ("language".to_string(), Json::str("ZH")),
            ("features".to_string(), Json::Arr(vec![Json::str("kern")])),
        ])
    }

    fn metric(key: &str, values: Vec<Json>) -> Json {
        Json::Obj(vec![
            ("key".to_string(), Json::str(key.to_string())),
            ("valuesEm".to_string(), Json::Arr(values)),
        ])
    }

    fn absorbing_entry() -> Json {
        Json::Obj(vec![
            ("key".to_string(), Json::str("p1")),
            ("sourceSha256".to_string(), Json::str("a".repeat(64))),
            (
                "typography".to_string(),
                Json::Obj(vec![("fontSizePx".to_string(), Json::Num(18.0))]),
            ),
            (
                "fontEvidence".to_string(),
                Json::Obj(vec![
                    ("backendRevision".to_string(), Json::str("backend-1")),
                    ("harfbuzzVersion".to_string(), Json::str("hb-1")),
                    (
                        "faces".to_string(),
                        Json::Arr(vec![Json::Obj(vec![
                            ("publicUrl".to_string(), Json::str("/fonts/main.woff2")),
                            ("family".to_string(), Json::str("serif")),
                            ("coverageText".to_string(), Json::str("同文")),
                            ("probe".to_string(), probe()),
                        ])]),
                    ),
                    (
                        "replay".to_string(),
                        Json::Obj(vec![
                            (
                                "revision".to_string(),
                                Json::str(crate::schema::FONT_REPLAY_REVISION),
                            ),
                            ("shapes".to_string(), Json::Arr(Vec::new())),
                            (
                                "metrics".to_string(),
                                Json::Arr(vec![
                                    metric(
                                        "[\"serif\",400,false,\"null\",\"测\"]",
                                        vec![
                                            Json::Num(1.0),
                                            Json::Null,
                                            Json::Num(2.0),
                                            Json::Num(3.0),
                                            Json::Num(4.0),
                                        ],
                                    ),
                                    metric(
                                        "[\"sans\",700,true,\"null\",\"验\"]",
                                        vec![
                                            Json::Num(5.0),
                                            Json::Num(6.0),
                                            Json::Num(7.0),
                                            Json::Num(8.0),
                                            Json::Num(9.0),
                                        ],
                                    ),
                                ]),
                            ),
                        ]),
                    ),
                ]),
            ),
        ])
    }

    #[test]
    fn encode_decode_round_trips_every_region() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
            .expect("absorbs");
        tables.intern_value_style("font-weight:600");
        let bytes = encode(&tables).expect("encodes");
        let decoded = decode(&bytes).expect("decodes");
        // Every region round-trips: the leading replay strings keep their
        // indexes (probe aux strings follow them in the region), faces,
        // probes with their pooled style/features, value styles and both
        // revisions.
        assert_eq!(
            &decoded.strings[..decoded.replay_string_count],
            &tables.strings.rows()[..]
        );
        // Faces and probes compare through the canonical rendering: the text
        // regions store that form and every dedup gate keys on it, not on
        // in-memory field order.
        let canon = |rows: &[Json]| -> Vec<String> { rows.iter().map(stable_stringify).collect() };
        assert_eq!(canon(&decoded.faces), canon(&tables.faces));
        assert_eq!(canon(&decoded.probes), canon(&tables.probes));
        assert_eq!(decoded.value_styles, tables.value_styles);
        assert_eq!(decoded.backend_revision, Some(Json::str("backend-1")));
        assert_eq!(decoded.harfbuzz_version, Some(Json::str("hb-1")));
        // Metrics come back sorted by the key tuple's ref columns: the serif
        // row interned first (ref 0), so it leads regardless of byte order.
        assert_eq!(decoded.metrics.len(), 2);
        let serif_ref = tables.strings.find(&Json::str("serif")).expect("serif");
        let sans_ref = tables.strings.find(&Json::str("sans")).expect("sans");
        let Json::Arr(first) = &decoded.metrics[0] else {
            panic!("row");
        };
        let Json::Num(families) = &first[0] else {
            panic!("ref");
        };
        assert_eq!(*families, f64::from(u32::try_from(serif_ref).expect("ref")));
        // The null metric value survives the pool round trip.
        assert_eq!(first[6], Json::Null);
        // The sans row (larger ref) follows with all five values present.
        let Json::Arr(second) = &decoded.metrics[1] else {
            panic!("row");
        };
        let Json::Num(second_families) = &second[0] else {
            panic!("ref");
        };
        assert_eq!(
            *second_families,
            f64::from(u32::try_from(sans_ref).expect("ref"))
        );
        assert_eq!(second[6], Json::Num(6.0));
    }

    #[test]
    fn restore_reproduces_identical_bytes() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
            .expect("absorbs");
        let bytes = encode(&tables).expect("encodes");
        let mut restored = SnapshotTables::from_binary(&bytes).expect("restores");
        let rebytes = encode(&restored).expect("re-encodes");
        assert_eq!(bytes, rebytes);
        // Finalize hashes the same bytes and keeps the same URL.
        let file = restored.finalize().expect("freezes");
        assert_eq!(file.bytes, bytes);
    }

    #[test]
    fn determinism_holds_for_equal_content() {
        let build = || {
            let mut tables = SnapshotTables::new();
            tables
                .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
                .expect("absorbs");
            tables.intern_value_style("font-weight:600");
            tables
        };
        assert_eq!(
            encode(&build()).expect("encodes"),
            encode(&build()).expect("encodes")
        );
    }

    #[test]
    fn corrupt_inputs_fail_the_named_error() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
            .expect("absorbs");
        let bytes = encode(&tables).expect("encodes");
        let error = match decode(&bytes[..bytes.len() - 1]) {
            Ok(_) => panic!("truncated file rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableBinaryInvalid");
        let mut bad_magic = bytes.clone();
        bad_magic[0] = b'X';
        assert!(decode(&bad_magic).is_err());
    }

    #[test]
    fn inflated_string_delta_fails_validation() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
            .expect("absorbs");
        let bytes = encode(&tables).expect("encodes");
        let layout = decode_layout(&bytes).expect("layout");
        assert!(layout.string_count >= 2, "fixture interned strings");
        // The string deltas begin right after the header; inflating one delta
        // pushes the prefix sum past the bytes the file holds.
        let deltas_start = 8 + checked_mul(HEADER_U32_COUNT, 4).expect("header");
        let mut inflated = bytes.clone();
        let at = checked_add(deltas_start, 4).expect("offset");
        inflated[at] = 0xff;
        inflated[checked_add(at, 1).expect("offset")] = 0xff;
        inflated[checked_add(at, 2).expect("offset")] = 0xff;
        inflated[checked_add(at, 3).expect("offset")] = 0xff;
        let error = match decode_layout(&inflated) {
            Ok(_) => panic!("inflated delta rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableBinaryInvalid");
    }

    fn swap_span(bytes: &mut [u8], first: usize, second: usize, len: usize) {
        for byte in 0..len {
            bytes.swap(first + byte, second + byte);
        }
    }

    #[test]
    fn unsorted_metric_rows_fail_validation() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![absorbing_entry()]))
            .expect("absorbs");
        let mut bytes = encode(&tables).expect("encodes");
        let layout = decode_layout(&bytes).expect("layout");
        if layout.metric_count < 2 {
            return;
        }
        // Swap the two metric rows across every column; the strict-order
        // validation must trip.
        let columns = &layout.metrics;
        swap_span(
            &mut bytes,
            columns.families_refs,
            checked_add(columns.families_refs, 4).expect("offset"),
            4,
        );
        swap_span(
            &mut bytes,
            columns.weights,
            checked_add(columns.weights, 8).expect("offset"),
            8,
        );
        swap_span(
            &mut bytes,
            columns.italics,
            checked_add(columns.italics, 1).expect("offset"),
            1,
        );
        swap_span(
            &mut bytes,
            columns.role_refs,
            checked_add(columns.role_refs, 4).expect("offset"),
            4,
        );
        swap_span(
            &mut bytes,
            columns.face_selection_refs,
            checked_add(columns.face_selection_refs, 4).expect("offset"),
            4,
        );
        swap_span(
            &mut bytes,
            columns.pool_refs,
            checked_add(columns.pool_refs, 4).expect("offset"),
            4,
        );
        let error = match decode_layout(&bytes) {
            Ok(_) => panic!("unsorted metrics rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableBinaryInvalid");
    }
}
