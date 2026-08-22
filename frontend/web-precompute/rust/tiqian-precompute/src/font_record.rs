//! `loadRecord` port of `frontend/web/npm/precompute-fonts.js`: decode the
//! source, validate the face, and assemble the `FontRecord` evidence the
//! session exposes (ADR 0050 parity oracle).
//!
//! Inputs arrive as the values `String(...)` normalization in JS produces;
//! the Neon boundary is responsible for that coercion. Error names and the
//! `${family}` interpolations match the JS messages.

use crate::base_table::base_ideo_idtp;
use crate::font_source::{decode_font_source, sha256_hex, FontSourceError};
use crate::js_compat::{js_number_string, js_trim};
use crate::name_table::local_names;
use crate::sfnt::{fvar_axes, s16_at, table, units_per_em, AxisInfo};

/// Weight spec as JS sees it: a two-element array or a single value.
/// Number-coercion quirks of other array shapes live at the Neon boundary.
#[derive(Debug, Clone, PartialEq)]
pub enum FontWeightSpec {
    Range(f64, f64),
    Single(Option<f64>),
}

/// One `@font-face` input.
#[derive(Debug, Clone)]
pub struct FontFaceSpec<'a> {
    pub family: &'a str,
    pub public_url: &'a str,
    pub source: &'a [u8],
    pub face_index: Option<f64>,
    pub weight: FontWeightSpec,
    pub style: &'a str,
    pub unicode_range: Option<&'a str>,
    /// Pre-validated by the session layer (`orderedFaceSpecs`); JS keeps the
    /// resolved value on the record.
    pub source_order: u32,
}

/// Errors of the load step; names match the JS `throw new Error(...)` strings.
#[derive(Debug, PartialEq)]
pub enum LoadRecordError {
    MissingFontFaceFamily,
    MissingPublicFontUrl(String),
    UnsupportedFontCollection(String),
    Woff2Decode(String),
    UnsupportedFontFaceIndex { family: String, face_index: String },
    InvalidOpenTypeFace(String),
    UnsupportedVariableFontAxes { family: String, axes: String },
    UnsupportedVariableFontMetrics(String),
    InvalidFontFaceWeight,
    UnsupportedFontFaceStyle { family: String, style: String },
}

/// `tableMetrics` output: OS/2 typo metrics with the BASE cross-assignment
/// `typoAscender: idtp ?? typoAscender`, `typoDescender: ideo ?? typoDescender`.
#[derive(Debug, PartialEq)]
pub struct TableMetrics {
    pub typo_ascender: Option<i16>,
    pub typo_descender: Option<i16>,
    pub base_ideo: Option<i16>,
    pub base_idtp: Option<i16>,
    pub base_has_variation_index: bool,
}

fn table_metrics(sfnt: &[u8]) -> TableMetrics {
    let os2 = table(sfnt, b"OS/2");
    let typo_ascender = os2
        .filter(|bytes| bytes.len() >= 72)
        .map(|bytes| s16_at(bytes, 68));
    let typo_descender = os2
        .filter(|bytes| bytes.len() >= 72)
        .map(|bytes| s16_at(bytes, 70));
    let base = base_ideo_idtp(table(sfnt, b"BASE"));
    TableMetrics {
        typo_ascender: base.idtp.or(typo_ascender),
        typo_descender: base.ideo.or(typo_descender),
        base_ideo: base.ideo,
        base_idtp: base.idtp,
        base_has_variation_index: base.has_variation_index,
    }
}

/// `normalizeWeight`: valid ranges pass through; everything else falls back
/// to a single-value reading, and non-positive or non-finite results throw.
fn normalize_weight(spec: &FontWeightSpec) -> Result<[f64; 2], LoadRecordError> {
    if let FontWeightSpec::Range(low, high) = spec {
        if low.is_finite() && high.is_finite() && *low > 0.0 && *high >= *low {
            return Ok([*low, *high]);
        }
    }
    // Number(two-element array) is NaN for numeric elements; other array
    // shapes were collapsed by the boundary.
    let weight = match spec {
        FontWeightSpec::Single(value) => value.unwrap_or(400.0),
        FontWeightSpec::Range(..) => f64::NAN,
    };
    if !weight.is_finite() || weight <= 0.0 {
        return Err(LoadRecordError::InvalidFontFaceWeight);
    }
    Ok([weight, weight])
}

/// `normalizeStyle`: prefix match on the trimmed lowercase value.
fn normalize_style(value: &str) -> &'static str {
    let normalized = js_trim(value).to_lowercase();
    if normalized.starts_with("italic") {
        "italic"
    } else if normalized.starts_with("oblique") {
        "oblique"
    } else {
        "normal"
    }
}

/// The loaded face record; JS keeps `blob`/`face` for shaping here, which
/// the Rust session layer rebuilds from `sfnt` on demand.
#[derive(Debug, PartialEq)]
pub struct FontRecord {
    pub sfnt: Vec<u8>,
    pub upem: u32,
    pub face_index: f64,
    pub source_order: u32,
    pub family: String,
    pub style: &'static str,
    pub weight_range: [f64; 2],
    pub unicode_range: String,
    /// Parsed `unicodeRange`; `None` means the face declares no range and
    /// covers every code point.
    pub unicode_ranges: Option<Vec<(u32, u32)>>,
    pub public_url: String,
    pub source_sha256: String,
    pub sfnt_sha256: String,
    pub axis_infos: Vec<AxisInfo>,
    pub local_names: Vec<String>,
    pub table_metrics: TableMetrics,
    pub face_id: String,
}

impl FontRecord {
    /// The `wght` axis; object-key assignment in JS lets the last duplicate
    /// win, so the search runs from the end.
    pub fn wght_axis(&self) -> Option<&AxisInfo> {
        self.axis_infos.iter().rev().find(|axis| axis.tag == "wght")
    }
}

/// Loads one face spec. Step order mirrors `loadRecord`.
pub fn load_record(spec: &FontFaceSpec) -> Result<FontRecord, LoadRecordError> {
    let family = js_trim(spec.family).to_string();
    if family.is_empty() {
        return Err(LoadRecordError::MissingFontFaceFamily);
    }
    let public_url = js_trim(spec.public_url).to_string();
    if public_url.is_empty() {
        return Err(LoadRecordError::MissingPublicFontUrl(family.clone()));
    }
    let decoded = decode_font_source(spec.source).map_err(|error| match error {
        FontSourceError::UnsupportedFontCollection => {
            LoadRecordError::UnsupportedFontCollection(family.clone())
        }
        FontSourceError::Woff2Decode(message) => LoadRecordError::Woff2Decode(message),
    })?;
    let sfnt = decoded.sfnt;
    let face_index = spec.face_index.unwrap_or(0.0);
    if face_index != 0.0 {
        return Err(LoadRecordError::UnsupportedFontFaceIndex {
            family: family.clone(),
            face_index: js_number_string(face_index),
        });
    }
    // JS rejects non-finite or zero upem with InvalidOpenTypeFace; hb coerces
    // every face to 16..=16384 or 1000, so that branch never fires here.
    let upem = units_per_em(&sfnt);
    let axis_infos = fvar_axes(&sfnt);
    let unsupported: Vec<&str> = axis_infos
        .iter()
        .filter(|axis| axis.tag != "wght")
        .map(|axis| axis.tag.as_str())
        .collect();
    if !unsupported.is_empty() {
        return Err(LoadRecordError::UnsupportedVariableFontAxes {
            family: family.clone(),
            axes: unsupported.join(","),
        });
    }
    let metrics = table_metrics(&sfnt);
    if !axis_infos.is_empty()
        && (table(&sfnt, b"MVAR").is_some() || metrics.base_has_variation_index)
    {
        return Err(LoadRecordError::UnsupportedVariableFontMetrics(
            family.clone(),
        ));
    }
    let source_sha256 = sha256_hex(spec.source);
    let sfnt_sha256 = sha256_hex(&sfnt);
    let weight_range = normalize_weight(&spec.weight)?;
    let style = normalize_style(spec.style);
    if style == "oblique" {
        return Err(LoadRecordError::UnsupportedFontFaceStyle {
            family: family.clone(),
            style: style.to_string(),
        });
    }
    let names = local_names(table(&sfnt, b"name"), table(&sfnt, b"ltag"));
    let unicode_ranges = crate::font_face::parse_unicode_range(spec.unicode_range.unwrap_or(""));
    let face_id = format!(
        "{family}|{style}|{}-{}|{}|{}",
        js_number_string(weight_range[0]),
        js_number_string(weight_range[1]),
        &sfnt_sha256[..16],
        js_number_string(face_index),
    );
    Ok(FontRecord {
        sfnt,
        upem,
        face_index,
        source_order: spec.source_order,
        family,
        style,
        weight_range,
        unicode_range: spec.unicode_range.unwrap_or("").to_string(),
        unicode_ranges,
        public_url,
        source_sha256,
        sfnt_sha256,
        axis_infos,
        local_names: names,
        table_metrics: metrics,
        face_id,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal sfnt with the tables passed in.
    fn sfnt_with(tables: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&0x00010000u32.to_be_bytes());
        bytes.extend_from_slice(
            &u16::try_from(tables.len())
                .expect("fixture table count fits u16")
                .to_be_bytes(),
        );
        bytes.extend_from_slice(&0u16.to_be_bytes());
        bytes.extend_from_slice(&0u16.to_be_bytes());
        bytes.extend_from_slice(&0u16.to_be_bytes());
        let mut offset = 12 + tables.len() * 16;
        let mut body = Vec::new();
        for (tag, data) in tables {
            bytes.extend_from_slice(tag.as_slice());
            bytes.extend_from_slice(&0u32.to_be_bytes());
            bytes.extend_from_slice(
                &u32::try_from(offset)
                    .expect("fixture offset fits u32")
                    .to_be_bytes(),
            );
            bytes.extend_from_slice(
                &u32::try_from(data.len())
                    .expect("fixture table size fits u32")
                    .to_be_bytes(),
            );
            body.extend_from_slice(data);
            offset += data.len();
        }
        bytes.extend_from_slice(&body);
        bytes
    }

    fn head(upem: u16) -> Vec<u8> {
        let mut head = vec![0u8; 54];
        head[18..20].copy_from_slice(&upem.to_be_bytes());
        head
    }

    fn os2(typo_ascender: i16, typo_descender: i16) -> Vec<u8> {
        let mut os2 = vec![0u8; 72];
        os2[68..70].copy_from_slice(&typo_ascender.to_be_bytes());
        os2[70..72].copy_from_slice(&typo_descender.to_be_bytes());
        os2
    }

    fn fvar_wght(min: i32, default: i32, max: i32) -> Vec<u8> {
        let mut fvar = Vec::new();
        fvar.extend_from_slice(&[0u8, 1, 0, 0]); // version 1.0
        fvar.extend_from_slice(&16u16.to_be_bytes()); // firstAxis
        fvar.extend_from_slice(&2u16.to_be_bytes()); // countSizePairs
        fvar.extend_from_slice(&1u16.to_be_bytes()); // axisCount
        fvar.extend_from_slice(&20u16.to_be_bytes()); // axisSize
        fvar.extend_from_slice(&0u16.to_be_bytes()); // instanceCount
        fvar.extend_from_slice(&8u16.to_be_bytes()); // instanceSize
        fvar.extend_from_slice(b"wght");
        fvar.extend_from_slice(&(min << 16).to_be_bytes());
        fvar.extend_from_slice(&(default << 16).to_be_bytes());
        fvar.extend_from_slice(&(max << 16).to_be_bytes());
        fvar.extend_from_slice(&0u16.to_be_bytes());
        fvar.extend_from_slice(&0u16.to_be_bytes());
        fvar
    }

    fn spec<'a>(family: &'a str, source: &'a [u8]) -> FontFaceSpec<'a> {
        FontFaceSpec {
            family,
            public_url: "/fonts/body.woff2",
            source,
            face_index: None,
            weight: FontWeightSpec::Single(Some(400.0)),
            style: "normal",
            unicode_range: Some("U+4E00-9FFF"),
            source_order: 0,
        }
    }

    #[test]
    fn loads_static_font_with_all_evidence() {
        let source = sfnt_with(&[(b"head", head(1000)), (b"OS/2", os2(880, -120))]);
        let record = load_record(&spec("Body", &source)).unwrap();
        assert_eq!(record.family, "Body");
        assert_eq!(record.style, "normal");
        assert_eq!(record.weight_range, [400.0, 400.0]);
        assert_eq!(record.unicode_range, "U+4E00-9FFF");
        assert_eq!(record.upem, 1000);
        assert!(record.axis_infos.is_empty());
        assert!(record.local_names.is_empty());
        assert_eq!(record.table_metrics.typo_ascender, Some(880));
        assert_eq!(record.table_metrics.typo_descender, Some(-120));
        assert_eq!(record.source_sha256, sha256_hex(&source));
        assert_eq!(record.sfnt_sha256, sha256_hex(&source));
        assert_eq!(
            record.face_id,
            format!("Body|normal|400-400|{}|0", &sha256_hex(&source)[..16])
        );
    }

    #[test]
    fn garbage_bytes_load_with_defaults() {
        // JS accepts garbage: hb coerces upem to 1000 and every table is null.
        let record = load_record(&spec("X", b"not a font at all")).unwrap();
        assert_eq!(record.upem, 1000);
        assert_eq!(record.table_metrics.typo_ascender, None);
    }

    #[test]
    fn missing_family_and_url_names_match_js() {
        let source = sfnt_with(&[]);
        let error = load_record(&spec("  ", &source)).unwrap_err();
        assert_eq!(error, LoadRecordError::MissingFontFaceFamily);
        let mut no_url = spec("Body", &source);
        no_url.public_url = " ";
        assert_eq!(
            load_record(&no_url),
            Err(LoadRecordError::MissingPublicFontUrl("Body".into()))
        );
    }

    #[test]
    fn nonzero_face_index_is_rejected() {
        let source = sfnt_with(&[]);
        let mut indexed = spec("Body", &source);
        indexed.face_index = Some(2.0);
        assert_eq!(
            load_record(&indexed),
            Err(LoadRecordError::UnsupportedFontFaceIndex {
                family: "Body".into(),
                face_index: "2".into(),
            })
        );
    }

    #[test]
    fn non_wght_axis_is_rejected_with_tag_list() {
        let mut wide = Vec::new();
        wide.extend_from_slice(&[0u8, 1, 0, 0]); // version 1.0
        wide.extend_from_slice(&16u16.to_be_bytes()); // firstAxis
        wide.extend_from_slice(&2u16.to_be_bytes()); // countSizePairs
        wide.extend_from_slice(&2u16.to_be_bytes()); // axisCount
        wide.extend_from_slice(&20u16.to_be_bytes()); // axisSize
        wide.extend_from_slice(&0u16.to_be_bytes()); // instanceCount
        wide.extend_from_slice(&12u16.to_be_bytes()); // instanceSize
        for (tag, min, default, max) in
            [(b"wght", 100i32, 400i32, 900i32), (b"wdth", 100, 100, 200)]
        {
            wide.extend_from_slice(tag.as_slice());
            wide.extend_from_slice(&(min << 16).to_be_bytes());
            wide.extend_from_slice(&(default << 16).to_be_bytes());
            wide.extend_from_slice(&(max << 16).to_be_bytes());
            wide.extend_from_slice(&0u16.to_be_bytes());
            wide.extend_from_slice(&0u16.to_be_bytes());
        }
        let font = sfnt_with(&[(b"head", head(1000)), (b"fvar", wide)]);
        assert_eq!(
            load_record(&spec("Body", &font)),
            Err(LoadRecordError::UnsupportedVariableFontAxes {
                family: "Body".into(),
                axes: "wdth".into(),
            })
        );
    }

    #[test]
    fn mvar_rejected_only_with_axes() {
        let static_font = sfnt_with(&[(b"head", head(1000)), (b"MVAR", vec![0u8; 16])]);
        assert!(load_record(&spec("Body", &static_font)).is_ok());
        let variable = sfnt_with(&[
            (b"head", head(1000)),
            (b"MVAR", vec![0u8; 16]),
            (b"fvar", fvar_wght(100, 400, 900)),
        ]);
        assert_eq!(
            load_record(&spec("Body", &variable)),
            Err(LoadRecordError::UnsupportedVariableFontMetrics(
                "Body".into()
            ))
        );
    }

    #[test]
    fn base_coordinates_cross_assign_into_typo_metrics() {
        let base =
            crate::base_table::base_table_bytes(&["ideo", "idtp"], "hani", &[(1, 770), (1, -230)]);
        let font = sfnt_with(&[
            (b"head", head(1000)),
            (b"OS/2", os2(880, -120)),
            (b"BASE", base),
        ]);
        let record = load_record(&spec("Body", &font)).unwrap();
        assert_eq!(record.table_metrics.typo_ascender, Some(-230)); // idtp
        assert_eq!(record.table_metrics.typo_descender, Some(770)); // ideo
    }

    #[test]
    fn weight_spec_normalization() {
        let source = sfnt_with(&[]);
        let mut ranged = spec("Body", &source);
        ranged.weight = FontWeightSpec::Range(300.0, 700.0);
        assert_eq!(load_record(&ranged).unwrap().weight_range, [300.0, 700.0]);
        let mut inverted = spec("Body", &source);
        inverted.weight = FontWeightSpec::Range(700.0, 300.0);
        assert_eq!(
            load_record(&inverted),
            Err(LoadRecordError::InvalidFontFaceWeight)
        );
        let mut zero = spec("Body", &source);
        zero.weight = FontWeightSpec::Single(Some(0.0));
        assert_eq!(
            load_record(&zero),
            Err(LoadRecordError::InvalidFontFaceWeight)
        );
        let mut absent = spec("Body", &source);
        absent.weight = FontWeightSpec::Single(None);
        assert_eq!(load_record(&absent).unwrap().weight_range, [400.0, 400.0]);
    }

    #[test]
    fn style_prefix_matching_and_oblique_rejection() {
        let source = sfnt_with(&[]);
        let mut italic = spec("Body", &source);
        italic.style = " Italic 400";
        assert_eq!(load_record(&italic).unwrap().style, "italic");
        let mut oblique = spec("Body", &source);
        oblique.style = "OBLIQUE";
        assert_eq!(
            load_record(&oblique),
            Err(LoadRecordError::UnsupportedFontFaceStyle {
                family: "Body".into(),
                style: "oblique".into(),
            })
        );
    }

    #[test]
    fn variable_font_passes_with_wght_axis() {
        let font = sfnt_with(&[(b"head", head(2048)), (b"fvar", fvar_wght(100, 400, 900))]);
        let record = load_record(&spec("Body", &font)).unwrap();
        assert_eq!(record.wght_axis().map(|axis| axis.max), Some(900.0));
        assert_eq!(record.upem, 2048);
    }
}
