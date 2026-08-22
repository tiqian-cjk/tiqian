//! Input normalization of the snapshot precompute orchestration (ADR 0050
//! amendment `PrecomputeInRust`). The rules, defaults, check order and named
//! issues mirror `precompute.js` one to one; the normalized forms feed the
//! paragraph request, the cache key and the snapshot artifact hashes.

use tiqian::NamedError;

use crate::js_compat::{trunc_sat_i32, trunc_sat_i64};
use crate::json::{member, Json};
use crate::paragraph::{utf16_length, InlineBoxInput, InlineBoxOuterSpacingCode, TextSpanInput};
use crate::snapshot_source::{js_number_value, js_string_value};
use crate::unicode_tables::{self as tables};

/// The only locale the snapshot path typesets.
pub const SNAPSHOT_LOCALE: &str = "zh-Hans";

/// Upper bound of the font-contract capture measure.
pub const FONT_CONTRACT_CAPTURE_MAX_WIDTH_PX: f64 = 16_777_216.0;

const FAMILY_SEPARATOR: char = '\u{001f}';
const RECORD_SEPARATOR: char = '\u{001e}';
const FIELD_SEPARATOR: char = '\u{001d}';

/// Issues the paragraph pipeline reports as capability limits instead of
/// crashes; the order is the js classification order.
pub const PARAGRAPH_CAPABILITY_ISSUES: &[&str] = &[
    "NoExactFontFace",
    "MissingGlyph",
    "NoExactMetricFace",
    "NonUniformUnicodeRangeMetrics",
    "MissingShapingFontEvidence",
    "EmptyParagraph",
    "SnapshotRenderFlowMismatch",
];

/// Issues the semantic normalization reports as capability limits.
pub const SEMANTIC_CAPABILITY_ISSUES: &[&str] = &[
    "UnsupportedSnapshotSemanticAttribute",
    "UnsupportedSnapshotSemanticTag",
    "UnsafeSnapshotSemanticHref",
    "CrossingSnapshotSemanticRanges",
];

/// Loose typography input: every field is optional the way the js object is.
#[derive(Clone, Default)]
pub struct TypographyInput {
    pub font_families: Option<Vec<String>>,
    pub font_size_px: Option<f64>,
    pub line_height_px: Option<f64>,
    pub font_weight: Option<f64>,
    pub first_line_indent_ic: Option<f64>,
    pub letter_spacing_px: Option<f64>,
    pub locale: Option<String>,
    pub line_length_grid_enabled: Option<bool>,
    pub italic: Option<bool>,
    pub font_feature_settings: Option<String>,
    pub font_variation_settings: Option<String>,
    pub font_variant_numeric: Option<String>,
}

impl TypographyInput {
    /// Reads the wire form `JSON.stringify(options.typography)` produced.
    /// Every member follows its js coercion: families map over `String`,
    /// numbers go through `Number`, `null` reads the same as absent for the
    /// `??` defaults.
    pub fn from_json(value: &Json) -> TypographyInput {
        let read = |name: &str| member(value, name);
        let number = |name: &str| read(name).map(js_number_value);
        let string = |name: &str| read(name).map(js_string_value);
        let font_families = match read("fontFamilies") {
            Some(Json::Arr(items)) => Some(items.iter().map(js_string_value).collect::<Vec<_>>()),
            _ => None,
        };
        TypographyInput {
            font_families,
            font_size_px: number("fontSizePx"),
            line_height_px: number("lineHeightPx"),
            font_weight: number("fontWeight"),
            first_line_indent_ic: number("firstLineIndentIc"),
            letter_spacing_px: number("letterSpacingPx"),
            locale: string("locale"),
            line_length_grid_enabled: match read("lineLengthGridEnabled") {
                Some(Json::Bool(enabled)) => Some(*enabled),
                _ => None,
            },
            italic: match read("italic") {
                Some(Json::Bool(true)) => Some(true),
                _ => None,
            },
            font_feature_settings: string("fontFeatureSettings"),
            font_variation_settings: string("fontVariationSettings"),
            font_variant_numeric: string("fontVariantNumeric"),
        }
    }
}

/// The canonical typography of one precomputer. The fixed fields carry their
/// default values; the artifact hashes serialize this form.
#[derive(Debug, Clone, PartialEq)]
pub struct SnapshotTypography {
    pub font_families: Vec<String>,
    pub font_size_px: f64,
    pub line_height_px: f64,
    pub locale: String,
    pub font_weight: i32,
    pub italic: bool,
    pub first_line_indent_ic: f64,
    pub line_length_grid_enabled: bool,
    pub letter_spacing_px: f64,
    pub font_feature_settings: &'static str,
    pub font_variation_settings: &'static str,
    pub font_variant_numeric: String,
}

/// Loose text-span input before range, family and number checks.
#[derive(Clone)]
pub struct TextSpanRaw {
    pub start: Option<f64>,
    pub end: Option<f64>,
    pub font_families: Option<Vec<String>>,
    pub font_size_px: Option<f64>,
    pub font_weight: Option<f64>,
    pub italic: Option<bool>,
    pub baseline_shift_px: Option<f64>,
}

/// Loose inline-box input before range, geometry and spacing checks.
#[derive(Clone)]
pub struct InlineBoxRaw {
    pub start: Option<f64>,
    pub end: Option<f64>,
    pub inline_start_px: Option<f64>,
    pub inline_end_px: Option<f64>,
    pub outer_spacing: Option<String>,
}

/// `normalizeTypography`: trims and filters families, fills the defaults and
/// rejects every field the snapshot path cannot typeset, in the js check
/// order.
pub fn normalize_typography(value: TypographyInput) -> Result<SnapshotTypography, NamedError> {
    let font_families = normalized_families(value.font_families.as_deref().unwrap_or(&[]));
    if font_families.is_empty() {
        return Err(named("MissingExplicitFontFamilies"));
    }
    let font_size_px = value.font_size_px.unwrap_or(f64::NAN);
    if !font_size_px.is_finite() || font_size_px <= 0.0 {
        return Err(named("InvalidFontSize"));
    }
    let line_height_px = value.line_height_px.unwrap_or(f64::NAN);
    if !line_height_px.is_finite() || line_height_px <= 0.0 {
        return Err(named("InvalidLineHeight"));
    }
    let font_weight = safe_integer_weight(value.font_weight.unwrap_or(400.0))
        .ok_or_else(|| named("InvalidFontWeight"))?;
    let first_line_indent_ic = value.first_line_indent_ic.unwrap_or(0.0);
    if !first_line_indent_ic.is_finite() || first_line_indent_ic != 0.0 {
        return Err(named("UnsupportedSnapshotFirstLineIndent"));
    }
    if value.letter_spacing_px.unwrap_or(0.0) != 0.0 {
        return Err(named("UnsupportedLetterSpacing"));
    }
    let locale = value.locale.unwrap_or_else(|| SNAPSHOT_LOCALE.to_string());
    if locale != SNAPSHOT_LOCALE {
        return Err(named("UnsupportedSnapshotLocale"));
    }
    if value.line_length_grid_enabled == Some(false) {
        return Err(named("UnsupportedSnapshotLineLengthGrid"));
    }
    if let Some(settings) = &value.font_feature_settings {
        if settings != "normal" {
            return Err(named("UnsupportedFontFeatureSettings"));
        }
    }
    if let Some(settings) = &value.font_variation_settings {
        if settings != "normal" {
            return Err(named("UnsupportedFontVariationSettings"));
        }
    }
    let font_variant_numeric = value
        .font_variant_numeric
        .unwrap_or_else(|| "normal".to_string());
    if font_variant_numeric != "normal" && font_variant_numeric != "lining-nums" {
        return Err(named("UnsupportedFontVariantNumeric"));
    }
    Ok(SnapshotTypography {
        font_families,
        font_size_px,
        line_height_px,
        locale,
        font_weight,
        italic: value.italic == Some(true),
        first_line_indent_ic,
        line_length_grid_enabled: true,
        letter_spacing_px: 0.0,
        font_feature_settings: "normal",
        font_variation_settings: "normal",
        font_variant_numeric,
    })
}

/// `normalizeTextSpans`: ranges first, then inherited or explicit families,
/// then the numbers. Absent input is the empty list.
pub fn normalize_text_spans(
    text: &str,
    value: Option<Vec<TextSpanRaw>>,
    typography: &SnapshotTypography,
) -> Result<Vec<TextSpanInput>, NamedError> {
    let Some(spans) = value else {
        return Ok(Vec::new());
    };
    let text_length = utf16_length(text);
    let mut normalized = Vec::with_capacity(spans.len());
    for span in spans {
        let (start, end) = valid_range(
            span.start,
            span.end,
            text_length,
            "InvalidSnapshotTextSpanRange",
        )?;
        let families = match span.font_families.as_deref() {
            Some(list) => normalized_families(list),
            None => typography.font_families.clone(),
        };
        if families.is_empty()
            || families.iter().any(|family| {
                family.contains(FAMILY_SEPARATOR)
                    || family.contains(FIELD_SEPARATOR)
                    || family.contains(RECORD_SEPARATOR)
            })
        {
            return Err(named("InvalidSnapshotTextSpanFontFamilies"));
        }
        let font_size_px = span.font_size_px.unwrap_or(typography.font_size_px);
        if !font_size_px.is_finite() || font_size_px <= 0.0 {
            return Err(named("InvalidSnapshotTextSpanFontSize"));
        }
        let font_weight = safe_integer_weight(
            span.font_weight
                .unwrap_or(f64::from(typography.font_weight)),
        )
        .ok_or_else(|| named("InvalidSnapshotTextSpanFontWeight"))?;
        let baseline_shift_px = span.baseline_shift_px.unwrap_or(0.0);
        if !baseline_shift_px.is_finite() {
            return Err(named("InvalidSnapshotTextSpanBaselineShift"));
        }
        normalized.push(TextSpanInput {
            start,
            end,
            families,
            font_size_px,
            font_weight,
            italic: span.italic.unwrap_or(typography.italic),
            baseline_shift: baseline_shift_px,
        });
    }
    Ok(normalized)
}

/// `normalizeInlineBoxes`: ranges first, then geometry, then the spacing tag.
pub fn normalize_inline_boxes(
    text: &str,
    value: Option<Vec<InlineBoxRaw>>,
) -> Result<Vec<InlineBoxInput>, NamedError> {
    let Some(boxes) = value else {
        return Ok(Vec::new());
    };
    let text_length = utf16_length(text);
    let mut normalized = Vec::with_capacity(boxes.len());
    for inline_box in boxes {
        let (start, end) = valid_range(
            inline_box.start,
            inline_box.end,
            text_length,
            "InvalidSnapshotInlineBoxRange",
        )?;
        let inline_start_px = inline_box.inline_start_px.unwrap_or(0.0);
        let inline_end_px = inline_box.inline_end_px.unwrap_or(0.0);
        if !inline_start_px.is_finite() || !inline_end_px.is_finite() {
            return Err(named("InvalidSnapshotInlineBoxGeometry"));
        }
        let outer_spacing = match inline_box.outer_spacing.as_deref() {
            None | Some("Narrow") => InlineBoxOuterSpacingCode::Narrow,
            Some("Source") => InlineBoxOuterSpacingCode::Source,
            Some(_) => return Err(named("InvalidSnapshotInlineBoxOuterSpacing")),
        };
        normalized.push(InlineBoxInput {
            start,
            end,
            inline_start: inline_start_px,
            inline_end: inline_end_px,
            outer_spacing,
        });
    }
    Ok(normalized)
}

/// `fontContractCaptureWidth`: a source-derived wide measure so font contracts
/// capture the complete source without publishing line geometry.
pub fn font_contract_capture_width(
    text_utf16_length: i32,
    text_spans: &[TextSpanInput],
    inline_boxes: &[InlineBoxInput],
    base_font_size_px: f64,
) -> f64 {
    let largest_font_size = text_spans
        .iter()
        .map(|span| span.font_size_px)
        .fold(base_font_size_px, f64::max);
    let inline_advance = inline_boxes
        .iter()
        .map(|inline_box| inline_box.inline_start.abs() + inline_box.inline_end.abs())
        .sum::<f64>();
    let estimated_unbroken_advance =
        1.0_f64.max(f64::from(text_utf16_length)) * largest_font_size * 2.0 + inline_advance;
    FONT_CONTRACT_CAPTURE_MAX_WIDTH_PX.min(largest_font_size.max(estimated_unbroken_advance))
}

/// `snapshotPlainTextIssue`: the ordered plain-text gate of the snapshot
/// path. `None` means the text can enter typesetting.
pub fn snapshot_plain_text_issue(text: &str) -> Option<&'static str> {
    if text.contains('\u{FFFC}') {
        return Some("UnsupportedInlineObject");
    }
    if text.contains('\u{200D}')
        || text
            .chars()
            .any(|point| ('\u{FE00}'..='\u{FE0F}').contains(&point))
    {
        return Some("UnsupportedEmojiSequence");
    }
    if text
        .chars()
        .any(|point| tables::table_contains(tables::EXTENDED_PICTOGRAPHIC, u32::from(point)))
    {
        return Some("UnsupportedEmojiFallback");
    }
    if text.chars().any(|point| {
        tables::table_contains(tables::FORMAT_CHARACTERS, u32::from(point))
            || (point.is_control() && point != '\n')
    }) {
        return Some("UnsupportedControlCharacter");
    }
    if text.chars().any(|point| !snapshot_script_allowed(point)) {
        return Some("UnsupportedSnapshotScript");
    }
    if text.contains('—') || text.contains('⸺') {
        return Some("CjkDashRequiresBrowserFaceVerification");
    }
    None
}

/// `paragraphCapabilityIssue` / `semanticCapabilityIssue`: the first list entry
/// the message contains, in list order.
pub fn paragraph_capability_issue(message: &str) -> Option<&'static str> {
    capability_issue(PARAGRAPH_CAPABILITY_ISSUES, message)
}

pub fn semantic_capability_issue(message: &str) -> Option<&'static str> {
    capability_issue(SEMANTIC_CAPABILITY_ISSUES, message)
}

fn capability_issue(issues: &[&'static str], message: &str) -> Option<&'static str> {
    issues
        .iter()
        .find(|issue| message.contains(*issue))
        .copied()
}

/// The allowed class of the script check: Han, Common, ASCII letters and the
/// Latin Extended range the js regex spells out.
fn snapshot_script_allowed(point: char) -> bool {
    let value = u32::from(point);
    point.is_ascii_alphabetic()
        || ('\u{00C0}'..='\u{024F}').contains(&point)
        || tables::table_contains(tables::SCRIPT_HAN, value)
        || tables::table_contains(tables::SCRIPT_COMMON, value)
}

/// `String.trim` then drop empty entries, the js family cleanup.
fn normalized_families(value: &[String]) -> Vec<String> {
    value
        .iter()
        .map(|family| family.trim().to_string())
        .filter(|family| !family.is_empty())
        .collect()
}

/// `Number.isSafeInteger` plus the 1 to 1000 window of the weight field.
fn safe_integer_weight(value: f64) -> Option<i32> {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    if value.fract() != 0.0 || value.abs() > MAX_SAFE_INTEGER {
        return None;
    }
    let weight = trunc_sat_i64(value);
    if (1..=1000).contains(&weight) {
        // The window check bounds value, so the i32 step keeps it unchanged.
        Some(trunc_sat_i32(value))
    } else {
        None
    }
}

/// `validRange`: safe-integer indices inside the UTF-16 text length, `start`
/// strictly below `end`.
fn valid_range(
    start: Option<f64>,
    end: Option<f64>,
    text_length: i32,
    issue: &str,
) -> Result<(i32, i32), NamedError> {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    let checked = |value: Option<f64>| -> Option<f64> {
        let value = value?;
        if value.fract() != 0.0 || value.abs() > MAX_SAFE_INTEGER {
            return None;
        }
        Some(value)
    };
    let Some(start_value) = checked(start) else {
        return Err(named(issue));
    };
    let Some(end_value) = checked(end) else {
        return Err(named(issue));
    };
    let start = trunc_sat_i64(start_value);
    let end = trunc_sat_i64(end_value);
    if start < 0 || end <= start || end > i64::from(text_length) {
        return Err(named(issue));
    }
    // The window check bounds both values by the i32 text length, so the
    // final conversions cannot saturate.
    Ok((trunc_sat_i32(start_value), trunc_sat_i32(end_value)))
}

fn named(name: &str) -> NamedError {
    NamedError(name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn typography_input() -> TypographyInput {
        TypographyInput {
            font_families: Some(vec!["Fake CJK".to_string()]),
            font_size_px: Some(18.0),
            line_height_px: Some(27.0),
            font_weight: None,
            first_line_indent_ic: None,
            letter_spacing_px: None,
            locale: None,
            line_length_grid_enabled: None,
            italic: None,
            font_feature_settings: None,
            font_variation_settings: None,
            font_variant_numeric: None,
        }
    }

    fn error_of(input: TypographyInput) -> String {
        normalize_typography(input).unwrap_err().0
    }

    #[test]
    fn defaults_fill_and_canonical_form_is_fixed() {
        let normalized = normalize_typography(typography_input()).unwrap();
        assert_eq!(normalized.font_weight, 400);
        assert_eq!(normalized.locale, "zh-Hans");
        assert_eq!(normalized.first_line_indent_ic, 0.0);
        assert!(normalized.line_length_grid_enabled);
        assert_eq!(normalized.letter_spacing_px, 0.0);
        assert_eq!(normalized.font_feature_settings, "normal");
        assert_eq!(normalized.font_variation_settings, "normal");
        assert_eq!(normalized.font_variant_numeric, "normal");
        assert!(!normalized.italic);
        // lining-nums passes through; it is the one variant the path supports.
        let mut lnum = typography_input();
        lnum.font_variant_numeric = Some("lining-nums".to_string());
        assert_eq!(
            normalize_typography(lnum).unwrap().font_variant_numeric,
            "lining-nums"
        );
    }

    #[test]
    fn families_trim_filter_and_require_explicit_entries() {
        let mut blank = typography_input();
        blank.font_families = Some(vec!["  ".to_string(), String::new()]);
        assert_eq!(error_of(blank), "MissingExplicitFontFamilies");
        let mut padded = typography_input();
        padded.font_families = Some(vec!["  Fake CJK  ".to_string()]);
        assert_eq!(
            normalize_typography(padded).unwrap().font_families,
            vec!["Fake CJK".to_string()]
        );
    }

    #[test]
    fn typography_checks_report_precompute_names_in_order() {
        let mut size = typography_input();
        size.font_size_px = Some(0.0);
        assert_eq!(error_of(size), "InvalidFontSize");
        let mut height = typography_input();
        height.line_height_px = Some(f64::NAN);
        assert_eq!(error_of(height), "InvalidLineHeight");
        let mut weight = typography_input();
        weight.font_weight = Some(1001.0);
        assert_eq!(error_of(weight.clone()), "InvalidFontWeight");
        weight.font_weight = Some(400.5);
        assert_eq!(error_of(weight.clone()), "InvalidFontWeight");
        let mut indent = typography_input();
        indent.first_line_indent_ic = Some(2.0);
        assert_eq!(error_of(indent), "UnsupportedSnapshotFirstLineIndent");
        let mut spacing = typography_input();
        spacing.letter_spacing_px = Some(0.1);
        assert_eq!(error_of(spacing), "UnsupportedLetterSpacing");
        let mut locale = typography_input();
        locale.locale = Some("zh-Hant".to_string());
        assert_eq!(error_of(locale), "UnsupportedSnapshotLocale");
        let mut grid = typography_input();
        grid.line_length_grid_enabled = Some(false);
        assert_eq!(error_of(grid), "UnsupportedSnapshotLineLengthGrid");
        let mut features = typography_input();
        features.font_feature_settings = Some("\"smcp\" 1".to_string());
        assert_eq!(error_of(features.clone()), "UnsupportedFontFeatureSettings");
        features.font_feature_settings = None;
        features.font_variation_settings = Some("\"wght\" 700".to_string());
        assert_eq!(error_of(features), "UnsupportedFontVariationSettings");
        let mut variant = typography_input();
        variant.font_variant_numeric = Some("oldstyle-nums".to_string());
        assert_eq!(error_of(variant), "UnsupportedFontVariantNumeric");
    }

    #[test]
    fn italic_accepts_only_boolean_true() {
        let mut italic = typography_input();
        italic.italic = Some(true);
        assert!(normalize_typography(italic).unwrap().italic);
    }

    fn typography() -> SnapshotTypography {
        normalize_typography(typography_input()).unwrap()
    }

    #[test]
    fn absent_span_input_is_empty_and_ranges_validate() {
        let base = typography();
        assert!(normalize_text_spans("正文", None, &base)
            .unwrap()
            .is_empty());
        let bad_range = vec![TextSpanRaw {
            start: Some(2.0),
            end: Some(1.0),
            font_families: None,
            font_size_px: None,
            font_weight: None,
            italic: None,
            baseline_shift_px: None,
        }];
        assert_eq!(
            normalize_text_spans("正文", Some(bad_range), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanRange"
        );
        let astral = vec![TextSpanRaw {
            start: None,
            end: Some(4.0),
            font_families: None,
            font_size_px: None,
            font_weight: None,
            italic: None,
            baseline_shift_px: None,
        }];
        assert_eq!(
            normalize_text_spans("😀字", Some(astral), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanRange"
        );
    }

    #[test]
    fn span_families_inherit_or_validate() {
        let base = typography();
        let inherited = vec![TextSpanRaw {
            start: Some(0.0),
            end: Some(2.0),
            font_families: None,
            font_size_px: None,
            font_weight: None,
            italic: None,
            baseline_shift_px: None,
        }];
        let normalized = normalize_text_spans("正文", Some(inherited), &base).unwrap();
        assert_eq!(normalized[0].families, base.font_families);
        let separator = vec![TextSpanRaw {
            start: Some(0.0),
            end: Some(2.0),
            font_families: Some(vec!["Bad\u{001f}Family".to_string()]),
            font_size_px: None,
            font_weight: None,
            italic: None,
            baseline_shift_px: None,
        }];
        assert_eq!(
            normalize_text_spans("正文", Some(separator), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanFontFamilies"
        );
    }

    #[test]
    fn span_numbers_inherit_then_validate() {
        let base = typography();
        let mut span = TextSpanRaw {
            start: Some(0.0),
            end: Some(2.0),
            font_families: None,
            font_size_px: None,
            font_weight: None,
            italic: Some(false),
            baseline_shift_px: None,
        };
        let normalized = normalize_text_spans("正文", Some(vec![span.clone()]), &base).unwrap();
        assert_eq!(normalized[0].font_size_px, base.font_size_px);
        assert_eq!(normalized[0].font_weight, base.font_weight);
        assert!(!normalized[0].italic, "explicit false must not inherit");
        span.font_size_px = Some(0.0);
        assert_eq!(
            normalize_text_spans("正文", Some(vec![span.clone()]), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanFontSize"
        );
        span.font_size_px = None;
        span.font_weight = Some(0.0);
        assert_eq!(
            normalize_text_spans("正文", Some(vec![span.clone()]), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanFontWeight"
        );
        span.font_weight = None;
        span.baseline_shift_px = Some(f64::NAN);
        assert_eq!(
            normalize_text_spans("正文", Some(vec![span]), &base)
                .unwrap_err()
                .0,
            "InvalidSnapshotTextSpanBaselineShift"
        );
    }

    #[test]
    fn inline_boxes_validate_range_geometry_and_spacing() {
        let mut box_input = InlineBoxRaw {
            start: Some(0.0),
            end: Some(1.0),
            inline_start_px: None,
            inline_end_px: None,
            outer_spacing: None,
        };
        let normalized = normalize_inline_boxes("正文", Some(vec![box_input.clone()])).unwrap();
        assert_eq!(normalized[0].inline_start, 0.0);
        assert_eq!(
            normalized[0].outer_spacing,
            InlineBoxOuterSpacingCode::Narrow
        );
        box_input.end = Some(5.0);
        assert_eq!(
            normalize_inline_boxes("正文", Some(vec![box_input.clone()]))
                .unwrap_err()
                .0,
            "InvalidSnapshotInlineBoxRange"
        );
        box_input.end = Some(1.0);
        box_input.inline_end_px = Some(f64::NAN);
        assert_eq!(
            normalize_inline_boxes("正文", Some(vec![box_input.clone()]))
                .unwrap_err()
                .0,
            "InvalidSnapshotInlineBoxGeometry"
        );
        box_input.inline_end_px = None;
        box_input.outer_spacing = Some("Wide".to_string());
        assert_eq!(
            normalize_inline_boxes("正文", Some(vec![box_input.clone()]))
                .unwrap_err()
                .0,
            "InvalidSnapshotInlineBoxOuterSpacing"
        );
        box_input.outer_spacing = Some("Source".to_string());
        assert_eq!(
            normalize_inline_boxes("正文", Some(vec![box_input])).unwrap()[0].outer_spacing,
            InlineBoxOuterSpacingCode::Source
        );
    }

    #[test]
    fn capture_width_grows_with_spans_and_boxes() {
        let base = typography();
        let spans = vec![TextSpanInput {
            start: 0,
            end: 2,
            families: base.font_families.clone(),
            font_size_px: 20.0,
            font_weight: 400,
            italic: false,
            baseline_shift: 0.0,
        }];
        let boxes = vec![InlineBoxInput {
            start: 2,
            end: 3,
            inline_start: 6.0,
            inline_end: -2.0,
            outer_spacing: InlineBoxOuterSpacingCode::Narrow,
        }];
        // 4 * 20 * 2 + |6| + |-2| = 168
        assert_eq!(font_contract_capture_width(4, &spans, &boxes, 18.0), 168.0);
        assert_eq!(font_contract_capture_width(0, &[], &[], 18.0), 36.0);
    }

    #[test]
    fn plain_text_issue_checks_in_order() {
        assert_eq!(
            snapshot_plain_text_issue("文\u{FFFC}字"),
            Some("UnsupportedInlineObject")
        );
        assert_eq!(
            snapshot_plain_text_issue("字\u{200D}字"),
            Some("UnsupportedEmojiSequence")
        );
        assert_eq!(
            snapshot_plain_text_issue("字\u{FE0F}字"),
            Some("UnsupportedEmojiSequence")
        );
        assert_eq!(
            snapshot_plain_text_issue("🦀中文"),
            Some("UnsupportedEmojiFallback")
        );
        assert_eq!(
            snapshot_plain_text_issue("中\u{00AD}文"),
            Some("UnsupportedControlCharacter")
        );
        assert_eq!(
            snapshot_plain_text_issue("中\t文"),
            Some("UnsupportedControlCharacter")
        );
        assert_eq!(
            snapshot_plain_text_issue("中\n文"),
            None,
            "newline alone passes every gate"
        );
        assert_eq!(
            snapshot_plain_text_issue("中文ОК"),
            Some("UnsupportedSnapshotScript"),
            "Cyrillic letters fall outside the allowed class"
        );
        assert_eq!(
            snapshot_plain_text_issue("中文あ"),
            Some("UnsupportedSnapshotScript"),
            "kana is its own script"
        );
        assert_eq!(
            snapshot_plain_text_issue("中—文"),
            Some("CjkDashRequiresBrowserFaceVerification")
        );
        assert_eq!(
            snapshot_plain_text_issue("中⸺文"),
            Some("CjkDashRequiresBrowserFaceVerification")
        );
        assert_eq!(
            snapshot_plain_text_issue("中文ＡＢ"),
            Some("UnsupportedSnapshotScript"),
            "fullwidth latin letters are Latin script, outside the allowed class"
        );
        assert_eq!(
            snapshot_plain_text_issue("中文１２"),
            None,
            "fullwidth digits are Common"
        );
        assert_eq!(
            snapshot_plain_text_issue("中文Àéñ"),
            None,
            "Latin Extended range is allowed"
        );
    }

    #[test]
    fn capability_classification_matches_list_order() {
        assert_eq!(
            paragraph_capability_issue("shape failed: MissingGlyph in run"),
            Some("MissingGlyph")
        );
        assert_eq!(
            paragraph_capability_issue("engine reports NoExactMetricFace at 3"),
            Some("NoExactMetricFace")
        );
        assert_eq!(paragraph_capability_issue("some other failure"), None);
        // The message contains two issues; the earlier list entry wins.
        assert_eq!(
            paragraph_capability_issue("EmptyParagraph after MissingShapingFontEvidence"),
            Some("MissingShapingFontEvidence")
        );
        assert_eq!(
            semantic_capability_issue("UnsupportedSnapshotSemanticTag: ruby"),
            Some("UnsupportedSnapshotSemanticTag")
        );
        assert_eq!(semantic_capability_issue("MissingGlyph"), None);
    }
}
