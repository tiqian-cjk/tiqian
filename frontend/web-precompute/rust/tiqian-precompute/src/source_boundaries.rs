//! Source-boundary port of `frontend/web/npm/font-face-boundaries.js`
//! (ADR 0050). The descriptor matching primitives of the same JS file live in
//! `font_face.rs` and `selection.rs`; this module keeps the boundary scan
//! itself: the exact-face run boundaries the layout core consumes, the Worker
//! contract variant, and serialized-boundary merging.

use crate::font_face::{
    css_weight_matched, font_record_matches_family, parse_unicode_range, unicode_range_contains,
};
use crate::js_compat::{js_number_string, js_to_number};
use crate::json::Json;
use crate::selection::no_exact_font_face_message;

const FAMILY_SEPARATOR: char = '\u{1f}';
const RECORD_SEPARATOR: char = '\u{1e}';
const FIELD_SEPARATOR: char = '\u{1d}';

/// The style one boundary decision runs under: the paragraph base style or a
/// span's override. `baseline_shift_px` mirrors `baselineShiftPx ?? 0`.
#[derive(Debug)]
pub struct BoundaryStyle {
    pub font_families: Vec<String>,
    pub font_size_px: f64,
    pub font_weight: f64,
    pub italic: bool,
    pub baseline_shift_px: Option<f64>,
}

/// A DOM text span in the Worker contract: source range plus style override.
#[derive(Debug)]
pub struct BoundaryTextSpan {
    pub start: f64,
    pub end: f64,
    pub style: BoundaryStyle,
}

/// `sourceBoundariesForSelectedFace` (ExactSubsetCoverageBoundary): the UTF-16
/// offsets where the selected face or effective style changes. The selector
/// returns the face identity that enters the run signature. Structural
/// no-shape controls advance the offset without a decision, so they never
/// split a face run; CRLF keeps two code units but one cluster.
pub fn source_boundaries_for_selected_face(
    text: &str,
    base_style: &BoundaryStyle,
    spans: &[BoundaryTextSpan],
    mut select_face: impl FnMut(&BoundaryStyle, char) -> Result<String, String>,
) -> Result<Vec<f64>, String> {
    let mut boundaries = Vec::new();
    let mut offset: f64 = 0.0;
    let mut previous_signature: Option<String> = None;
    for point in text.chars() {
        if is_structural_no_shape_control(point) {
            offset += match point {
                '\0'..='\u{ffff}' => 1.0,
                _ => 2.0,
            };
            continue;
        }
        let style = spans
            .iter()
            .rev()
            .find(|span| offset >= span.start && offset < span.end)
            .map(|span| &span.style)
            .unwrap_or(base_style);
        let identity = select_face(style, point)?;
        let signature = format!(
            "{}|{}|{}|{}|{}|{}",
            identity,
            style.font_families.join("\u{1f}"),
            js_number_string(style.font_size_px),
            js_number_string(style.font_weight),
            if style.italic { "true" } else { "false" },
            js_number_string(style.baseline_shift_px.unwrap_or(0.0)),
        );
        if let Some(previous) = &previous_signature {
            if &signature != previous {
                boundaries.push(offset);
            }
        }
        previous_signature = Some(signature);
        offset += match point {
            '\0'..='\u{ffff}' => 1.0,
            _ => 2.0,
        };
    }
    Ok(boundaries)
}

/// StructuralBreakControlNoShape: UAX #14 mandatory-break controls and
/// U+200B. They shape to no glyph, so exact-face selection must neither
/// require a covering face nor split the runs around them.
fn is_structural_no_shape_control(point: char) -> bool {
    matches!(
        point,
        '\u{000a}' // LF
            | '\u{000b}' // VT
            | '\u{000c}' // FF
            | '\u{000d}' // CR
            | '\u{0085}' // NEL
            | '\u{200b}' // ZWSP
            | '\u{2028}' // LS
            | '\u{2029}' // PS
    )
}

/// A `@font-face` metadata record as the Worker font contract carries it.
/// `unicode_ranges` is the parsed `unicode_range` declaration.
pub struct MetadataFace {
    pub family: String,
    pub local_names: Vec<String>,
    pub style: String,
    pub weight: (f64, f64),
    pub unicode_range: Option<String>,
    pub public_url: String,
    pub face_index: f64,
    pub source_order: f64,
    pub unicode_ranges: Option<Vec<(u32, u32)>>,
}

impl MetadataFace {
    /// Parses the `unicode-range` declaration the way
    /// `workerExactSubsetSourceBoundaries` spreads it in.
    pub fn from_contract(face: MetadataFaceSpec) -> MetadataFace {
        let unicode_ranges = face.unicode_range.as_deref().and_then(parse_unicode_range);
        MetadataFace {
            family: face.family,
            local_names: face.local_names,
            style: face.style,
            weight: face.weight,
            unicode_range: face.unicode_range,
            public_url: face.public_url,
            face_index: face.face_index,
            source_order: face.source_order,
            unicode_ranges,
        }
    }
}

/// The face fields before `unicode-range` parsing.
pub struct MetadataFaceSpec {
    pub family: String,
    pub local_names: Vec<String>,
    pub style: String,
    pub weight: (f64, f64),
    pub unicode_range: Option<String>,
    pub public_url: String,
    pub face_index: f64,
    pub source_order: f64,
}

/// `metadataFaceIdentity`: the identity the Worker signature embeds. It keys
/// on the full descriptor, not `faceId`, because the Worker only owns
/// validated metadata.
fn metadata_face_identity(face: &MetadataFace) -> String {
    Json::Arr(vec![
        Json::str(face.family.clone()),
        Json::str(face.style.clone()),
        Json::Arr(vec![Json::Num(face.weight.0), Json::Num(face.weight.1)]),
        match &face.unicode_range {
            Some(value) => Json::str(value.clone()),
            None => Json::Null,
        },
        Json::str(face.public_url.clone()),
        Json::Num(face.face_index),
        Json::Num(face.source_order),
    ])
    .render()
}

/// `selectMetadataFace`: family, style, then CSS weight rank, then the later
/// `@font-face` rule for overlapping unicode-range coverage. A point outside
/// every declared range is a `NoExactFontFace` miss.
fn select_metadata_face<'a>(
    faces: &'a [MetadataFace],
    style: &BoundaryStyle,
    point: char,
) -> Result<&'a MetadataFace, String> {
    let desired_style = if style.italic { "italic" } else { "normal" };
    for family in &style.font_families {
        let family_matches: Vec<&MetadataFace> = faces
            .iter()
            .filter(|face| {
                font_record_matches_family(&face.family, &face.local_names, family)
                    && face.style == desired_style
            })
            .collect();
        let weight_matched =
            css_weight_matched(&family_matches, style.font_weight, |face| face.weight);
        for face in weight_matched.into_iter().rev() {
            if unicode_range_contains(&face.unicode_ranges, u32::from(point)) {
                return Ok(face);
            }
        }
    }
    Err(no_exact_font_face_message(
        &style.font_families,
        style.font_weight,
        style.italic,
        &point.to_string(),
    ))
}

/// `workerTextSpans`: the serialized span list of the Worker contract.
/// Records split on U+001E, fields on U+001D, families on U+001F.
pub fn worker_text_spans(value: &str) -> Result<Vec<BoundaryTextSpan>, String> {
    if value.is_empty() {
        return Ok(Vec::new());
    }
    let mut spans = Vec::new();
    for record in value.split(RECORD_SEPARATOR) {
        let fields: Vec<&str> = record.split(FIELD_SEPARATOR).collect();
        if fields.len() != 7 {
            return Err("InvalidLayoutWorkerTextSpan".to_string());
        }
        let italic = fields[5];
        let span = BoundaryTextSpan {
            start: js_to_number(fields[0]),
            end: js_to_number(fields[1]),
            style: BoundaryStyle {
                font_families: fields[2]
                    .split(FAMILY_SEPARATOR)
                    .filter(|family| !family.is_empty())
                    .map(str::to_string)
                    .collect(),
                font_size_px: js_to_number(fields[3]),
                font_weight: js_to_number(fields[4]),
                italic: italic == "true",
                baseline_shift_px: Some(js_to_number(fields[6])),
            },
        };
        if !is_safe_integer(span.start)
            || !is_safe_integer(span.end)
            || span.start < 0.0
            || span.end <= span.start
            || span.style.font_families.is_empty()
            || !span.style.font_size_px.is_finite()
            || span.style.font_size_px <= 0.0
            || !span.style.font_weight.is_finite()
            || !span.style.baseline_shift_px.unwrap_or(0.0).is_finite()
            || (italic != "true" && italic != "false")
        {
            return Err("InvalidLayoutWorkerTextSpan".to_string());
        }
        spans.push(span);
    }
    Ok(spans)
}

/// The Worker boundary request: the validated font contract fields the Worker
/// owns. `font_families` and `text_spans` stay serialized; the Worker contract
/// defines their separators.
pub struct WorkerBoundaryRequest<'a> {
    pub text: &'a str,
    pub font_families: &'a str,
    pub font_size_px: f64,
    pub font_weight: f64,
    pub italic: bool,
    pub text_spans: &'a str,
}

/// `workerExactSubsetSourceBoundaries`: rebuilds the build-time font-shard
/// boundaries from the validated Worker contract, keyed on metadata identity.
pub fn worker_exact_subset_source_boundaries(
    faces: &[MetadataFaceSpec],
    request: &WorkerBoundaryRequest<'_>,
) -> Result<Vec<f64>, String> {
    let faces: Vec<MetadataFace> = faces
        .iter()
        .map(|spec| {
            MetadataFace::from_contract(MetadataFaceSpec {
                family: spec.family.clone(),
                local_names: spec.local_names.clone(),
                style: spec.style.clone(),
                weight: spec.weight,
                unicode_range: spec.unicode_range.clone(),
                public_url: spec.public_url.clone(),
                face_index: spec.face_index,
                source_order: spec.source_order,
            })
        })
        .collect();
    let base_style = BoundaryStyle {
        font_families: request
            .font_families
            .split(FAMILY_SEPARATOR)
            .filter(|family| !family.is_empty())
            .map(str::to_string)
            .collect(),
        font_size_px: request.font_size_px,
        font_weight: request.font_weight,
        italic: request.italic,
        baseline_shift_px: Some(0.0),
    };
    if faces.is_empty()
        || base_style.font_families.is_empty()
        || !base_style.font_size_px.is_finite()
        || base_style.font_size_px <= 0.0
        || !base_style.font_weight.is_finite()
    {
        return Err("InvalidLayoutWorkerFontContract".to_string());
    }
    source_boundaries_for_selected_face(
        request.text,
        &base_style,
        &worker_text_spans(request.text_spans)?,
        |style, point| {
            Ok(metadata_face_identity(select_metadata_face(
                &faces, style, point,
            )?))
        },
    )
}

/// `mergeSerializedSourceBoundaries`: dedupes serialized and additional
/// boundaries, validates them, and returns the sorted serialization. Numbers
/// keep `Number()` coercion semantics; anything that is not a safe
/// non-negative integer is an `InvalidSourceBoundary`.
pub fn merge_serialized_source_boundaries(
    serialized: &str,
    additional: &[f64],
) -> Result<String, String> {
    let mut boundaries: Vec<f64> = Vec::new();
    for token in serialized.split(',').filter(|token| !token.is_empty()) {
        let value = js_to_number(token);
        if !boundaries.contains(&value) {
            boundaries.push(value);
        }
    }
    for value in additional {
        if !boundaries.contains(value) {
            boundaries.push(*value);
        }
    }
    if boundaries
        .iter()
        .any(|value| !is_safe_integer(*value) || *value < 0.0)
    {
        return Err("InvalidSourceBoundary".to_string());
    }
    boundaries.sort_by(|left, right| left.total_cmp(right));
    Ok(boundaries
        .iter()
        .map(|value| js_number_string(*value))
        .collect::<Vec<_>>()
        .join(","))
}

/// `Number.isSafeInteger`.
fn is_safe_integer(value: f64) -> bool {
    value.is_finite() && value.fract() == 0.0 && value.abs() <= 9_007_199_254_740_991.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn contract_face(source_order: f64, unicode_range: &str, public_url: &str) -> MetadataFaceSpec {
        MetadataFaceSpec {
            family: "MiSans VF".to_string(),
            local_names: vec!["MiSans VF".to_string()],
            style: "normal".to_string(),
            weight: (100.0, 900.0),
            unicode_range: Some(unicode_range.to_string()),
            public_url: public_url.to_string(),
            face_index: 0.0,
            source_order,
        }
    }

    fn request<'a>(text: &'a str, families: &'a str, spans: &'a str) -> WorkerBoundaryRequest<'a> {
        WorkerBoundaryRequest {
            text,
            font_families: families,
            font_size_px: 18.0,
            font_weight: 460.0,
            italic: false,
            text_spans: spans,
        }
    }

    #[test]
    fn worker_recreates_boundary_between_latin_and_punctuation_shards() {
        let faces = [
            contract_face(0.0, "U+0041-005A", "/fonts/latin.woff2"),
            contract_face(1.0, "U+201D", "/fonts/punctuation.woff2"),
        ];
        let request = request("B\u{201d}", "MiSans VF\u{1f}ui-sans-serif", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            vec![1.0]
        );
        assert_eq!(merge_serialized_source_boundaries("", &[1.0]).unwrap(), "1");
    }

    #[test]
    fn worker_preserves_span_boundaries_and_utf16_offsets() {
        let faces = [
            contract_face(0.0, "U+0041-005A", "/fonts/latin.woff2"),
            contract_face(1.0, "U+201D", "/fonts/punctuation.woff2"),
        ];
        // Span [2,3) carries weight 700, so the second B starts a new run.
        let spans = ["2", "3", "MiSans VF", "18", "700", "false", "0"].join("\u{1d}");
        let request = request("B\u{201d}B", "MiSans VF", &spans);
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            vec![1.0, 2.0]
        );
        assert_eq!(
            merge_serialized_source_boundaries("2,0", &[1.0, 2.0]).unwrap(),
            "0,1,2"
        );
    }

    #[test]
    fn worker_follows_css_source_order_on_overlapping_declarations() {
        let faces = [
            contract_face(0.0, "U+0041-005A", "/fonts/latin-a.woff2"),
            contract_face(1.0, "U+0042", "/fonts/latin-b.woff2"),
        ];
        let request = request("AB", "MiSans VF", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            vec![1.0]
        );
    }

    #[test]
    fn zero_width_soft_break_needs_no_face() {
        let faces = [
            contract_face(0.0, "U+0041-005A", "/fonts/latin.woff2"),
            contract_face(1.0, "U+201D", "/fonts/punctuation.woff2"),
        ];
        let request = request("B\u{200b}\u{201d}", "MiSans VF", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            vec![2.0]
        );
    }

    #[test]
    fn mandatory_break_controls_need_no_coverage() {
        let faces = [contract_face(0.0, "U+4E00-9FFF", "/fonts/cjk.woff2")];
        let request = request(
            "\u{7531}\n\u{000b}\u{000c}\r\u{0085}\u{2028}\u{2029}\u{7531}",
            "MiSans VF",
            "",
        );
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            Vec::<f64>::new()
        );
    }

    #[test]
    fn utf16_boundaries_survive_crlf() {
        let faces = [
            contract_face(0.0, "U+4E00-9FFF", "/fonts/cjk.woff2"),
            contract_face(1.0, "U+0041-005A", "/fonts/latin.woff2"),
        ];
        let request = request("\u{7531}\r\nB", "MiSans VF", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap(),
            vec![3.0]
        );
    }

    #[test]
    fn uncovered_point_reports_no_exact_font_face() {
        let faces = [contract_face(0.0, "U+4E00-9FFF", "/fonts/cjk.woff2")];
        let request = request("B", "MiSans VF", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &request).unwrap_err(),
            "NoExactFontFace:families=MiSans VF;weight=460;italic=false;text=\"B\""
        );
    }

    #[test]
    fn empty_contract_is_rejected() {
        let plain_request = request("B", "MiSans VF", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&[], &plain_request).unwrap_err(),
            "InvalidLayoutWorkerFontContract"
        );
        // Faces without a requested family is the same named error.
        let faces = [contract_face(0.0, "U+41", "/fonts/f.woff2")];
        let no_family_request = request("B", "", "");
        assert_eq!(
            worker_exact_subset_source_boundaries(&faces, &no_family_request).unwrap_err(),
            "InvalidLayoutWorkerFontContract"
        );
    }

    #[test]
    fn span_field_count_and_values_are_validated() {
        assert_eq!(
            worker_text_spans("0\u{1d}1\u{1d}F").unwrap_err(),
            "InvalidLayoutWorkerTextSpan"
        );
        let no_families = ["0", "1", "", "18", "400", "false", "0"].join("\u{1d}");
        assert_eq!(
            worker_text_spans(&no_families).unwrap_err(),
            "InvalidLayoutWorkerTextSpan"
        );
        let bad_italic = ["0", "1", "F", "18", "400", "maybe", "0"].join("\u{1d}");
        assert_eq!(
            worker_text_spans(&bad_italic).unwrap_err(),
            "InvalidLayoutWorkerTextSpan"
        );
        let inverted = ["2", "1", "F", "18", "400", "false", "0"].join("\u{1d}");
        assert_eq!(
            worker_text_spans(&inverted).unwrap_err(),
            "InvalidLayoutWorkerTextSpan"
        );
        assert!(worker_text_spans("").unwrap().is_empty());
        let valid = ["0", "1", "F", "18", "400", "true", "0"].join("\u{1d}");
        assert_eq!(worker_text_spans(&valid).unwrap().len(), 1);
    }

    #[test]
    fn merge_dedupes_and_rejects_unsafe_values() {
        assert_eq!(
            merge_serialized_source_boundaries("2,2,0", &[1.0]).unwrap(),
            "0,1,2"
        );
        assert_eq!(
            merge_serialized_source_boundaries("x", &[]).unwrap_err(),
            "InvalidSourceBoundary"
        );
        assert_eq!(
            merge_serialized_source_boundaries("1.5", &[]).unwrap_err(),
            "InvalidSourceBoundary"
        );
        assert_eq!(
            merge_serialized_source_boundaries("-1", &[]).unwrap_err(),
            "InvalidSourceBoundary"
        );
        // Number() coercion: hex, exponent, and padded forms are numbers.
        assert_eq!(
            merge_serialized_source_boundaries(" 3 ,0x2,1e1", &[]).unwrap(),
            "2,3,10"
        );
        // -0 passes the sign check and serializes as 0.
        assert_eq!(merge_serialized_source_boundaries("-0", &[]).unwrap(), "0");
    }

    #[test]
    fn identity_embeds_the_full_descriptor() {
        let face = MetadataFace::from_contract(contract_face(2.0, "U+41", "/fonts/a.woff2"));
        assert_eq!(
            metadata_face_identity(&face),
            "[\"MiSans VF\",\"normal\",[100,900],\"U+41\",\"/fonts/a.woff2\",0,2]"
        );
        let mut unbound = contract_face(2.0, "U+41", "/fonts/a.woff2");
        unbound.unicode_range = None;
        assert_eq!(
            metadata_face_identity(&MetadataFace::from_contract(unbound)),
            "[\"MiSans VF\",\"normal\",[100,900],null,\"/fonts/a.woff2\",0,2]"
        );
    }

    #[test]
    fn later_span_wins_on_overlap() {
        // sourceBoundariesForSelectedFace reads the last span containing the
        // offset, the way `[...spans].reverse().find(...)` does.
        let base = BoundaryStyle {
            font_families: vec!["F".to_string()],
            font_size_px: 18.0,
            font_weight: 400.0,
            italic: false,
            baseline_shift_px: None,
        };
        let spans = vec![
            BoundaryTextSpan {
                start: 0.0,
                end: 2.0,
                style: BoundaryStyle {
                    font_families: vec!["A".to_string()],
                    font_size_px: 18.0,
                    font_weight: 700.0,
                    italic: false,
                    baseline_shift_px: None,
                },
            },
            BoundaryTextSpan {
                start: 0.0,
                end: 2.0,
                style: BoundaryStyle {
                    font_families: vec!["B".to_string()],
                    font_size_px: 18.0,
                    font_weight: 700.0,
                    italic: false,
                    baseline_shift_px: None,
                },
            },
        ];
        let mut identities: Vec<String> = Vec::new();
        source_boundaries_for_selected_face("BB", &base, &spans, |style, _| {
            identities.push(style.font_families[0].clone());
            Ok("face".to_string())
        })
        .unwrap();
        assert_eq!(identities, vec!["B", "B"]);
    }
}
