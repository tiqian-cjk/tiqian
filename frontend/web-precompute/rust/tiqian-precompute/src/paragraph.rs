//! Paragraph precompute over the engine ABI (ADR 0050 amendment
//! `PrecomputeInRust`).
//!
//! The typed request, the domain validation and the LayoutInput packing are
//! the Rust port of `PrecomputeWire.kt`; error names match that port and the
//! npm assertions byte for byte, and checks run in the same order so the
//! first failure names the same issue on both sides. Validation works without
//! the engine archive; the engine call exists only when build.rs linked it.

use tiqian::layout_request::{InlineBoxSpec, LayoutRequest, LineBreakSpanSpec, TextSpanSpec};
use tiqian::NamedError;

// The request's own field types; callers building a `ParagraphRequest` take
// the codes from here.
pub use tiqian::layout_request::{InlineBoxOuterSpacingCode, LineBreakPolicyCode};

use crate::js_compat::kotlin_to_float;

#[cfg(tiqian_engine_link)]
use crate::plan::Plan;

#[derive(Debug, Clone, PartialEq)]
pub struct ParagraphRequest {
    pub font_session_id: String,
    pub text: String,
    pub max_width_px: f64,
    pub font_families: Vec<String>,
    pub font_size_px: f64,
    pub line_height_px: f64,
    pub locale: String,
    pub font_weight: i32,
    pub italic: bool,
    pub first_line_indent_ic: f64,
    pub line_length_grid_enabled: bool,
    pub source_boundaries: Vec<i32>,
    pub text_spans: Vec<TextSpanInput>,
    pub line_break_spans: Vec<LineBreakSpanInput>,
    pub inline_boxes: Vec<InlineBoxInput>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TextSpanInput {
    pub start: i32,
    pub end: i32,
    pub families: Vec<String>,
    pub font_size_px: f64,
    pub font_weight: i32,
    pub italic: bool,
    pub baseline_shift: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineBreakSpanInput {
    pub start: i32,
    pub end: i32,
    pub policy: LineBreakPolicyCode,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InlineBoxInput {
    pub start: i32,
    pub end: i32,
    pub inline_start: f64,
    pub inline_end: f64,
    pub outer_spacing: InlineBoxOuterSpacingCode,
}

impl ParagraphRequest {
    /// Runs the domain checks in the PrecomputeWire order. Every failure is a
    /// named issue; blank family strings drop the way the Kotlin filter drops
    /// them.
    pub fn validate(&self) -> Result<(), NamedError> {
        if self.text.trim().is_empty() {
            return Err(named("EmptyParagraph"));
        }
        if !self.max_width_px.is_finite() || self.max_width_px <= 0.0 {
            return Err(named("InvalidMaximumMeasure"));
        }
        if !self.font_size_px.is_finite() || self.font_size_px <= 0.0 {
            return Err(named("InvalidFontSize"));
        }
        if !self.line_height_px.is_finite() || self.line_height_px <= 0.0 {
            return Err(named("InvalidLineHeight"));
        }
        if !self.first_line_indent_ic.is_finite() {
            return Err(named("InvalidFirstLineIndent"));
        }
        if !(1..=1000).contains(&self.font_weight) {
            return Err(named("InvalidFontWeight"));
        }
        if families(&self.font_families).is_empty() {
            return Err(named("MissingExplicitFontFamilies"));
        }
        let text_length = utf16_length(&self.text);
        for span in &self.text_spans {
            if !valid_range(span.start, span.end, text_length) {
                return Err(named("InvalidTextSpanRange"));
            }
            if families(&span.families).is_empty() {
                return Err(named("MissingTextSpanFontFamilies"));
            }
            if !span.font_size_px.is_finite() || span.font_size_px <= 0.0 {
                return Err(named("InvalidTextSpanFontSize"));
            }
            if !(1..=1000).contains(&span.font_weight) {
                return Err(named("InvalidTextSpanFontWeight"));
            }
            if !span.baseline_shift.is_finite() {
                return Err(named("InvalidTextSpanBaselineShift"));
            }
        }
        for boundary in &self.source_boundaries {
            if !(*boundary >= 0 && *boundary <= text_length) {
                return Err(named("InvalidSourceBoundary"));
            }
        }
        for span in &self.line_break_spans {
            if !valid_range(span.start, span.end, text_length) {
                return Err(named("InvalidLineBreakSpanRange"));
            }
        }
        for inline_box in &self.inline_boxes {
            if !valid_range(inline_box.start, inline_box.end, text_length) {
                return Err(named("InvalidInlineBoxRange"));
            }
            if !inline_box.inline_start.is_finite() || !inline_box.inline_end.is_finite() {
                return Err(named("InvalidInlineBoxGeometry"));
            }
        }
        Ok(())
    }

    /// Validates, then builds the engine-level packed request. The f64 to f32
    /// narrowing matches the Kotlin `toFloat()` casts; validation runs on the
    /// f64 values the caller passed.
    pub fn to_layout_request(&self) -> Result<LayoutRequest, NamedError> {
        self.validate()?;
        Ok(LayoutRequest {
            max_width_px: kotlin_to_float(self.max_width_px),
            font_size_px: kotlin_to_float(self.font_size_px),
            line_height_px: kotlin_to_float(self.line_height_px),
            first_line_indent_ic: kotlin_to_float(self.first_line_indent_ic),
            font_weight: self.font_weight,
            italic: self.italic,
            line_length_grid_enabled: self.line_length_grid_enabled,
            locale: self.locale.clone(),
            families: self.font_families.clone(),
            text: self.text.clone(),
            text_spans: self
                .text_spans
                .iter()
                .map(|span| TextSpanSpec {
                    start: span.start,
                    end: span.end,
                    font_size_px: kotlin_to_float(span.font_size_px),
                    font_weight: span.font_weight,
                    italic: span.italic,
                    baseline_shift: kotlin_to_float(span.baseline_shift),
                    families: span.families.clone(),
                })
                .collect(),
            source_boundaries: self.source_boundaries.clone(),
            line_break_spans: self
                .line_break_spans
                .iter()
                .map(|span| LineBreakSpanSpec {
                    start: span.start,
                    end: span.end,
                    policy: span.policy,
                })
                .collect(),
            inline_boxes: self
                .inline_boxes
                .iter()
                .map(|inline_box| InlineBoxSpec {
                    start: inline_box.start,
                    end: inline_box.end,
                    inline_start: kotlin_to_float(inline_box.inline_start),
                    inline_end: kotlin_to_float(inline_box.inline_end),
                    outer_spacing: inline_box.outer_spacing,
                })
                .collect(),
            font_session_id: self.font_session_id.clone(),
        })
    }
}

/// Packs, calls the engine over the ABI and deserializes the plan JSON.
/// Exists only when the engine archive is linked (`TIQIAN_NATIVE_LIB_DIR` at
/// build time); the font backend must already be installed.
#[cfg(tiqian_engine_link)]
pub fn precompute_paragraph(request: &ParagraphRequest) -> Result<Plan, NamedError> {
    let packed = request.to_layout_request()?.pack()?;
    let plan_json = tiqian::engine::layout_paragraph(&packed)?;
    Plan::from_json_str(&plan_json)
}

fn named(name: &str) -> NamedError {
    NamedError(name.to_string())
}

fn families(values: &[String]) -> Vec<&String> {
    values
        .iter()
        .filter(|value| !value.trim().is_empty())
        .collect()
}

fn valid_range(start: i32, end: i32, text_length: i32) -> bool {
    start >= 0 && start < end && end <= text_length
}

/// Kotlin `String.length`: UTF-16 code units. Every engine range and boundary
/// lives in this space.
pub fn utf16_length(text: &str) -> i32 {
    text.chars()
        .map(|c| match c {
            '\0'..='\u{ffff}' => 1,
            _ => 2,
        })
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> ParagraphRequest {
        ParagraphRequest {
            font_session_id: "tq-font-test-1".to_string(),
            text: "正文一段".to_string(),
            max_width_px: 80.0,
            font_families: vec!["Fake CJK".to_string()],
            font_size_px: 16.0,
            line_height_px: 24.0,
            locale: "zh-Hans".to_string(),
            font_weight: 400,
            italic: false,
            first_line_indent_ic: 0.0,
            line_length_grid_enabled: false,
            source_boundaries: Vec::new(),
            text_spans: Vec::new(),
            line_break_spans: Vec::new(),
            inline_boxes: Vec::new(),
        }
    }

    fn error_of(request: &ParagraphRequest) -> String {
        request.validate().unwrap_err().0
    }

    #[test]
    fn valid_request_passes() {
        assert_eq!(request().validate(), Ok(()));
    }

    #[test]
    fn paragraph_level_checks_report_precompute_names_in_order() {
        let mut blank = request();
        blank.text = "   ".to_string();
        assert_eq!(error_of(&blank), "EmptyParagraph");
        blank.text = String::new();
        assert_eq!(error_of(&blank), "EmptyParagraph");

        let mut measure = request();
        measure.max_width_px = 0.0;
        assert_eq!(error_of(&measure), "InvalidMaximumMeasure");
        measure.max_width_px = f64::NAN;
        assert_eq!(error_of(&measure), "InvalidMaximumMeasure");

        let mut size = request();
        size.font_size_px = -1.0;
        assert_eq!(error_of(&size), "InvalidFontSize");

        let mut height = request();
        height.line_height_px = f64::INFINITY;
        assert_eq!(error_of(&height), "InvalidLineHeight");

        let mut indent = request();
        indent.first_line_indent_ic = f64::NAN;
        assert_eq!(error_of(&indent), "InvalidFirstLineIndent");

        let mut weight = request();
        weight.font_weight = 0;
        assert_eq!(error_of(&weight), "InvalidFontWeight");
        weight.font_weight = 1001;
        assert_eq!(error_of(&weight), "InvalidFontWeight");

        let mut families = request();
        families.font_families = vec!["  ".to_string()];
        assert_eq!(error_of(&families), "MissingExplicitFontFamilies");
    }

    #[test]
    fn span_checks_cover_range_families_and_numbers() {
        let mut request = request();
        request.text_spans = vec![TextSpanInput {
            start: 2,
            end: 1,
            families: vec!["Fake CJK".to_string()],
            font_size_px: 16.0,
            font_weight: 400,
            italic: false,
            baseline_shift: 0.0,
        }];
        assert_eq!(error_of(&request), "InvalidTextSpanRange");
        request.text_spans[0].start = 0;
        request.text_spans[0].end = 9;
        assert_eq!(error_of(&request), "InvalidTextSpanRange");

        request.text_spans[0].end = 2;
        request.text_spans[0].families = vec![String::new()];
        assert_eq!(error_of(&request), "MissingTextSpanFontFamilies");

        request.text_spans[0].families = vec!["Fake CJK".to_string()];
        request.text_spans[0].font_size_px = 0.0;
        assert_eq!(error_of(&request), "InvalidTextSpanFontSize");
        request.text_spans[0].font_size_px = 16.0;
        request.text_spans[0].font_weight = 1001;
        assert_eq!(error_of(&request), "InvalidTextSpanFontWeight");
        request.text_spans[0].font_weight = 400;
        request.text_spans[0].baseline_shift = f64::NAN;
        assert_eq!(error_of(&request), "InvalidTextSpanBaselineShift");
    }

    #[test]
    fn boundaries_and_boxes_check_against_utf16_length() {
        let mut boundaries = request();
        boundaries.source_boundaries = vec![5];
        assert_eq!(error_of(&boundaries), "InvalidSourceBoundary");
        boundaries.source_boundaries = vec![4];
        assert_eq!(boundaries.validate(), Ok(()));

        let mut spans = request();
        spans.line_break_spans = vec![LineBreakSpanInput {
            start: 0,
            end: 5,
            policy: LineBreakPolicyCode::ProgressiveTechnical,
        }];
        assert_eq!(error_of(&spans), "InvalidLineBreakSpanRange");

        let mut boxes = request();
        boxes.inline_boxes = vec![InlineBoxInput {
            start: 0,
            end: 1,
            inline_start: 0.0,
            inline_end: f64::NAN,
            outer_spacing: InlineBoxOuterSpacingCode::Narrow,
        }];
        assert_eq!(error_of(&boxes), "InvalidInlineBoxGeometry");
        boxes.inline_boxes[0].end = 5;
        assert_eq!(error_of(&boxes), "InvalidInlineBoxRange");
    }

    #[test]
    fn utf16_length_counts_astral_characters_as_two_units() {
        let mut request = request();
        request.text = "😀字".to_string();
        // One astral character plus one BMP character: length 3 in UTF-16.
        request.source_boundaries = vec![3];
        assert_eq!(request.validate(), Ok(()));
        request.source_boundaries = vec![4];
        assert_eq!(error_of(&request), "InvalidSourceBoundary");
    }

    #[test]
    fn packing_carries_the_typed_sections() {
        let mut request = request();
        request.text_spans = vec![TextSpanInput {
            start: 0,
            end: 2,
            families: vec!["Fake CJK".to_string()],
            font_size_px: 18.0,
            font_weight: 500,
            italic: true,
            baseline_shift: 2.0,
        }];
        request.line_break_spans = vec![LineBreakSpanInput {
            start: 0,
            end: 4,
            policy: LineBreakPolicyCode::ProgressiveTechnical,
        }];
        request.inline_boxes = vec![InlineBoxInput {
            start: 2,
            end: 3,
            inline_start: 1.0,
            inline_end: 2.0,
            outer_spacing: InlineBoxOuterSpacingCode::Source,
        }];
        let packed = request.to_layout_request().unwrap().pack().unwrap();
        assert_eq!(
            tiqian::layout_request::LAYOUT_REQUEST_MAGIC,
            u32::from_le_bytes(packed[0..4].try_into().unwrap())
        );
        // The sections exist as counts: textSpans 1, lineBreakSpans 1, inlineBoxes 1.
        assert!(packed.windows(4).any(|window| window == 1u32.to_le_bytes()));
        let invalid = ParagraphRequest {
            font_weight: 0,
            ..request
        };
        assert!(invalid.to_layout_request().is_err());
    }

    #[cfg(tiqian_engine_link)]
    #[test]
    fn engine_call_without_font_backend_reports_the_named_issue() {
        let error = precompute_paragraph(&request()).unwrap_err();
        assert_eq!(error.name(), "FontBackendNotInstalled");
    }
}
