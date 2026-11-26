//! Paragraph request lane of the precompute port (ADR 0050 amendment
//! `PrecomputeInRust`).
//!
//! The typed request is the Rust port of `PrecomputeWire.kt`. Domain
//! validation is single-sourced in the generated protocol model
//! (tiqian_protocol ParagraphRequestChecks, Stage1-P5): this module
//! adapts its lane request into the generated one and maps the generated
//! issue variants to NamedError through the generated Display, whose
//! strings are the published issue names. The engine consumes the
//! generated Rust types directly (crate tiqian, module engine); the
//! f64 to f32 narrowing at the engine boundary matches the Kotlin
//! toFloat() casts of the packed ABI era, and the validation runs on
//! the f64 values the caller passed.

use tiqian::NamedError;
use tiqian_protocol::org::tiqian::protocol::inline_box_input::InlineBoxInput as GenInlineBoxInput;
use tiqian_protocol::org::tiqian::protocol::line_break_span_input::LineBreakSpanInput as GenLineBreakSpanInput;
use tiqian_protocol::org::tiqian::protocol::paragraph_request::ParagraphRequest as GeneratedRequest;
use tiqian_protocol::org::tiqian::protocol::paragraph_request_checks::ParagraphRequestChecks;
use tiqian_protocol::org::tiqian::protocol::text_span_input::TextSpanInput as GenTextSpanInput;
use tiqian_protocol::runtime::u_string::UString;

// The request lane keeps the code types of the former packed engine ABI;
// callers building a ParagraphRequest take the codes from here. The
// generated engine model carries the same codes as enums
// (org.tiqian.core.{LineBreakPolicy, InlineBoxOuterSpacing}); the lane
// keeps its own copies so the wire contract of this module stays stable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineBreakPolicyCode {
    ProgressiveTechnical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InlineBoxOuterSpacingCode {
    Narrow,
    Source,
}



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
    pub text_spans: Vec<TextSpanInputLane>,
    pub line_break_spans: Vec<LineBreakSpanInputLane>,
    pub inline_boxes: Vec<InlineBoxInputLane>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TextSpanInputLane {
    pub start: i32,
    pub end: i32,
    pub families: Vec<String>,
    pub font_size_px: f64,
    pub font_weight: i32,
    pub italic: bool,
    pub baseline_shift: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineBreakSpanInputLane {
    pub start: i32,
    pub end: i32,
    pub policy: LineBreakPolicyCode,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InlineBoxInputLane {
    pub start: i32,
    pub end: i32,
    pub inline_start: f64,
    pub inline_end: f64,
    pub outer_spacing: InlineBoxOuterSpacingCode,
}

pub type TextSpanInput = TextSpanInputLane;
pub type LineBreakSpanInput = LineBreakSpanInputLane;
pub type InlineBoxInput = InlineBoxInputLane;

impl ParagraphRequest {
    /// Runs the single-sourced domain checks (generated
    /// ParagraphRequestChecks) and reports the first failure as a
    /// NamedError whose name is the generated Display string.
    pub fn validate(&self) -> Result<(), NamedError> {
        ParagraphRequestChecks::paragraph_request_checks_validate(self.to_generated())
            .map_err(|error| NamedError(error.to_string()))
    }

    /// Adapts this lane request into the generated model. The i32 to u32
    /// casts keep the check outcomes: a negative range end wraps above
    /// any text length and fails the same named range check, and an
    /// out-of-range weight fails the weight check. The generated model
    /// optional emphasis gap and its inline-object and decoration
    /// sections are fields this Rust consumer does not send; they read
    /// as absent and stay unvalidated here.
    fn to_generated(&self) -> GeneratedRequest {
        // Every text field crosses into the generated model's Haxe string
        // domain (UTF-16 units) through the generated `From<&str>`
        // conversion; the lane keeps `String` end to end.
        let to_ustring = |text: &String| UString::from(text.as_str());
        GeneratedRequest {
            font_session_id: to_ustring(&self.font_session_id),
            text: to_ustring(&self.text),
            max_width_px: self.max_width_px,
            font_families: self.font_families.iter().map(to_ustring).collect(),
            font_size_px: self.font_size_px,
            line_height_px: self.line_height_px,
            locale: to_ustring(&self.locale),
            font_weight: self.font_weight as u32,
            italic: self.italic,
            first_line_indent_ic: self.first_line_indent_ic,
            line_length_grid_enabled: self.line_length_grid_enabled,
            emphasis_dot_gap_em: None,
            source_boundaries: self
                .source_boundaries
                .iter()
                .map(|value| *value as u32)
                .collect(),
            text_spans: self
                .text_spans
                .iter()
                .map(|span| GenTextSpanInput {
                    start: span.start as u32,
                    end: span.end as u32,
                    families: span.families.iter().map(to_ustring).collect(),
                    font_size_px: span.font_size_px,
                    font_weight: span.font_weight as u32,
                    italic: span.italic,
                    baseline_shift: span.baseline_shift,
                })
                .collect(),
            line_break_spans: self
                .line_break_spans
                .iter()
                .map(|span| GenLineBreakSpanInput {
                    start: span.start as u32,
                    end: span.end as u32,
                    policy: line_break_policy_name(span.policy),
                })
                .collect(),
            inline_boxes: self
                .inline_boxes
                .iter()
                .map(|box_input| GenInlineBoxInput {
                    start: box_input.start as u32,
                    end: box_input.end as u32,
                    inline_start: box_input.inline_start,
                    inline_end: box_input.inline_end,
                    outer_spacing: outer_spacing_name(box_input.outer_spacing),
                })
                .collect(),
            inline_objects: Vec::new(),
            decorations: Vec::new(),
        }
    }
}

/// Kotlin `String.length`: UTF-16 code units. Every engine range and boundary
/// lives in this space.
pub fn utf16_length(text: &str) -> i32 {
    text.chars()
        .map(|c| {
            let code = c as u32;
            if code <= 0xffff { 1 } else { 2 }
        })
        .sum()
}

fn line_break_policy_name(policy: LineBreakPolicyCode) -> UString {
    match policy {
        LineBreakPolicyCode::ProgressiveTechnical => UString::from("ProgressiveTechnical"),
    }
}

fn outer_spacing_name(outer_spacing: InlineBoxOuterSpacingCode) -> UString {
    match outer_spacing {
        InlineBoxOuterSpacingCode::Narrow => UString::from("Narrow"),
        InlineBoxOuterSpacingCode::Source => UString::from("Source"),
    }
}