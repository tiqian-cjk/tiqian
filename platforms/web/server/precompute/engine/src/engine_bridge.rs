//! Session-backed host components for the generated Rust engine (ADR 0050
//! Slice C, cutover to the boring engine-rust bundle).
//!
//! The generated `ExplainableStubParagraphLayoutEngine` receives shaping and
//! font metrics through the generated trait objects (`TextShaper`,
//! `FontMetricsResolver`). This module presents a [`FontSession`] and its
//! capture window as those components, the direct-Rust successor of the
//! former C ABI vtable bridge, and runs one paragraph request through
//! `tiqian::engine::Engine`. The engine `LayoutResult` goes through the
//! generated prepared-paragraph JSON emitter, and the existing plan reader
//! parses that JSON, so callers keep receiving the same [`Plan`] the packed
//! ABI path produced.
//!
//! The component mapping mirrors the Kotlin `NativeFontBackendTextShaper`
//! and `NativeFontBackendFontMetricsResolver` of the nativeMain shaper: one
//! cluster, one glyph run and one shaping decision per backend shape call,
//! and the five metric doubles mapped onto `RawFontMetrics`.

use std::cell::RefCell;
use std::rc::Rc;

use tiqian::engine::{Engine, EngineComponents};
use tiqian::NamedError;
use tiqian_engine_gen::org::tiqian::core::cluster::Cluster;
use tiqian_engine_gen::runtime::u_string::UString;
use tiqian_engine_gen::org::tiqian::core::glyph::Glyph;
use tiqian_engine_gen::org::tiqian::core::glyph_run::GlyphRun;
use tiqian_engine_gen::org::tiqian::core::ic::Ic;
use tiqian_engine_gen::org::tiqian::core::illegal_state_exception::IllegalStateException;
use tiqian_engine_gen::org::tiqian::core::inline_box_outer_spacing::InlineBoxOuterSpacing;
use tiqian_engine_gen::org::tiqian::core::inline_box_span::InlineBoxSpan;
use tiqian_engine_gen::org::tiqian::core::layout_constraints::LayoutConstraints;
use tiqian_engine_gen::org::tiqian::core::layout_input::LayoutInput;
use tiqian_engine_gen::org::tiqian::core::line_break_policy::LineBreakPolicy;
use tiqian_engine_gen::org::tiqian::core::line_break_span::LineBreakSpan;
use tiqian_engine_gen::org::tiqian::core::line_length_grid::LineLengthGrid;
use tiqian_engine_gen::org::tiqian::core::paragraph_style::ParagraphStyle;
use tiqian_engine_gen::org::tiqian::core::rect::Rect;
use tiqian_engine_gen::org::tiqian::core::shaping_decision_info::ShapingDecisionInfo;
use tiqian_engine_gen::org::tiqian::core::text_range::TextRange;
use tiqian_engine_gen::org::tiqian::core::text_span::TextSpan;
use tiqian_engine_gen::org::tiqian::core::text_style::TextStyle;
use tiqian_engine_gen::org::tiqian::core::tiqian_text_content::TiqianTextContent;
use tiqian_engine_gen::org::tiqian::font::font_metric_source::FontMetricSource;
use tiqian_engine_gen::org::tiqian::font::font_metrics::{
    FontMetricsRequest, FontMetricsResolver, StubFontMetricsResolver,
};
use tiqian_engine_gen::org::tiqian::font::raw_font_metrics::RawFontMetrics;
use tiqian_engine_gen::org::tiqian::layout::prepared_paragraph::PreparedParagraphFns;
use tiqian_engine_gen::org::tiqian::shaping::text_shaper::{
    TextShaper, ShapingInput, ShapingResult, ShapingSource, TextShaperShapeFault,
};

use crate::paragraph::{InlineBoxOuterSpacingCode, ParagraphRequest};
use crate::session::{CaptureEvidence, FontSession, MetricsInput, ShapeInput};

/// Presents one font session and its capture window to the engine as the
/// `TextShaper` and `FontMetricsResolver` implementations.
///
/// The struct erases the borrows into raw pointers because the generated
/// trait objects require a `_static` type. The obligations that keep this
/// sound:
///
/// - `precompute_paragraph` holds the `&FontSession` and the
///   `&mut CaptureEvidence` borrows for the whole engine call, so both
///   pointers stay valid while the engine can reach them.
/// - The engine runs its layout synchronously on the calling thread, so all
///   access through these pointers happens on one thread, sequentially:
///   never concurrently, never re-entrantly.
///
/// The invariants are the direct-Rust form of the former thread-local lend
/// slot; obligations are recorded in docs/rust-unsafe-inventory.md, section
/// "engine_bridge.rs".
struct SessionBackend {
    session: *const FontSession,
    evidence: *mut CaptureEvidence,
    /// The most recent metrics-resolution failure the generated engine cannot
    /// be told about. The generated `FontMetricsResolver::resolve` is
    /// infallible (the Haxe contract has no throw there), so the fault is
    /// parked here and `precompute_paragraph` fails the whole call after
    /// layout: a plan built on a substituted metric never escapes. A further
    /// failure overwrites the cell, so the reported message is the failure in
    /// effect when layout finishes.
    ///
    /// No `Send`/`Sync` impls: these are P-1 interface handles
    /// (`Rc<RefCell<dyn Trait>>`, target-semantic-policy:49-51) and the
    /// policy's final boundary forbids smuggling Arc/Mutex in for a possible
    /// future threaded host (target-semantic-policy:43-56).
    fault: Rc<RefCell<Option<String>>>,
}

impl SessionBackend {
    /// # Safety
    /// Both pointers must stay valid, and the pointees exclusively owned by
    /// this call, for as long as the built engine lives.
    /// `precompute_paragraph` guarantees both.
    unsafe fn new(
        session: &FontSession,
        evidence: &mut CaptureEvidence,
        fault: Rc<RefCell<Option<String>>>,
    ) -> Self {
        Self {
            session: std::ptr::from_ref(session),
            evidence: std::ptr::from_mut(evidence),
            fault,
        }
    }

    fn with_access<T>(
        &self,
        call: impl FnOnce(&FontSession, &mut CaptureEvidence) -> T,
    ) -> T {
        // SAFETY: obligation list on `SessionBackend`: the borrows held by
        // `precompute_paragraph` cover the engine call, and the engine
        // invokes the components sequentially on its calling thread.
        call(unsafe { &*self.session }, unsafe { &mut *self.evidence })
    }

    /// The `shape` body, kept free of the fault mapping so the error strings
    /// read the same as the former vtable error slot contents.
    fn shape_record(&self, input: &ShapingInput) -> Result<ShapingResult, String> {
        let shaped = self.with_access(|session, evidence| {
            // The generated shaper inputs are Haxe strings (UTF-16 units);
            // the session lane keeps `String`/`&str`, so the shape call
            // decodes its inputs once at the component boundary through
            // the generated `to_utf8_lossy` reader.
            let display_text = input.display_text.to_utf8_lossy();
            let text = input.text.to_utf8_lossy();
            let font_families: Vec<String> = input
                .style
                .font_families
                .iter()
                .map(|family| family.to_utf8_lossy())
                .collect();
            let locale = input.style.locale.to_utf8_lossy();
            let source_text = utf16_substring(&text, input.range.start, input.range.end);
            let input = ShapeInput {
                display_text: &display_text,
                font_families: &font_families,
                font_size: input.style.font_size,
                font_weight: f64::from(input.style.font_weight),
                italic: input.style.italic,
                locale: &locale,
                role: Some(input.font_decision.role.name()),
                source_text: Some(&source_text),
            };
            session
                .shape_into(evidence, &input)
                .map(|record| (record, source_text))
        })?;
        let (record, source_text) = shaped;
        let range = input.range.clone();
        let glyphs: Vec<Glyph> = record
            .glyphs
            .iter()
            .map(|glyph| {
                Glyph::new(
                    glyph.id,
                    range.clone(),
                    glyph.advance,
                    Some(glyph.x),
                    Some(glyph.y),
                    None,
                    glyph
                        .bounds
                        .map(|bounds| Rect::new(bounds[0], bounds[1], bounds[2], bounds[3])),
                    None,
                    None,
                )
            })
            .collect::<Result<Vec<Glyph>, IllegalStateException>>()
            .map_err(|error| error.message)?;
        let advance = record.advance;
        let key = input.font_decision.candidate.key.clone();
        let features = record.features.clone();
        // The generated cluster and run carry Haxe strings; the session
        // record is `String`, so the texts and the feature list convert
        // through the generated `From<&str>` conversion here.
        let cluster = Cluster::new(
            range.clone(),
            &UString::from(source_text.as_str()),
            &key,
            advance,
            Some(input.display_text.clone()),
            None,
            None,
            None,
        );
        let run = GlyphRun::new(
            range,
            &key,
            glyphs,
            advance,
            Some(features.iter().map(|f| UString::from(f.as_str())).collect()),
        );
        // The reason string stays byte-identical to the former native backend
        // decision so engine dumps remain diffable across the cutover.
        let reason = format!(
            "SharedHarfBuzzSession:face={}; instance={}; current-segment-context; features={}; unsafeToBreakGlyphs={}",
            record.face_id,
            record.font_instance_id,
            if features.is_empty() {
                "default".to_string()
            } else {
                features.join(",")
            },
            record.unsafe_break_count,
        );
        let glyph_count = u32::try_from(run.glyphs.len()).unwrap_or(u32::MAX);
        let without_ink_bounds = u32::try_from(
            run.glyphs.iter().filter(|glyph| glyph.bounds.is_none()).count(),
        )
        .unwrap_or(u32::MAX);
        let missing_glyphs =
            u32::try_from(run.glyphs.iter().filter(|glyph| glyph.id == 0).count())
                .unwrap_or(u32::MAX);
        let decision = ShapingDecisionInfo::new(
            input.range.clone(),
            &UString::from(source_text.as_str()),
            &input.display_text,
            &key,
            glyph_count,
            advance,
            &UString::from(ShapingSource::HarfBuzz.name()),
            &UString::from(reason.as_str()),
            Some(without_ink_bounds),
            Some(missing_glyphs),
            Some(UString::from(record.face_id.as_str())),
            Some(UString::from(record.script.as_str())),
            Some(input.style.locale.clone()),
            None,
            (!features.is_empty()).then(|| UString::from(features.join(",").as_str())),
            None,
        );
        Ok(ShapingResult::new(
            vec![cluster],
            vec![run],
            Some(vec![decision]),
        ))
    }

    fn resolve_metrics(&self, request: &FontMetricsRequest) -> Result<[f64; 5], String> {
        self.with_access(|session, evidence| {
            // Same boundary decode as `shape_record`: generated Haxe
            // strings in, host `String`/`&str` out.
            let font_families: Vec<String> = request
                .font_families
                .iter()
                .map(|family| family.to_utf8_lossy())
                .collect();
            let face_selection_text = request.face_selection_text.to_utf8_lossy();
            let input = MetricsInput {
                font_families: &font_families,
                font_size: request.font_size,
                font_weight: f64::from(request.font_weight),
                italic: request.italic,
                role: Some(request.role.name()),
                face_selection_text: Some(&face_selection_text),
            };
            session.metrics_into(evidence, &input)
        })
    }
}

impl TextShaper for SessionBackend {
    fn __haxe_type_name(&self) -> &'static str {
        "tiqian_precompute.engine_bridge.SessionBackend"
    }
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
    fn clone_box(&self) -> Box<dyn TextShaper> {
        Box::new(SessionBackend {
            session: self.session,
            evidence: self.evidence,
            fault: Rc::clone(&self.fault),
        })
    }
    fn shape(&mut self, input: ShapingInput) -> Result<ShapingResult, TextShaperShapeFault> {
        self.shape_record(&input).map_err(|message| {
            TextShaperShapeFault::IllegalStateExceptionFault(IllegalStateException::new(&message))
        })
    }
}

impl FontMetricsResolver for SessionBackend {
    fn __haxe_type_name(&self) -> &'static str {
        "tiqian_precompute.engine_bridge.SessionBackend"
    }
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
    fn clone_box(&self) -> Box<dyn FontMetricsResolver> {
        Box::new(SessionBackend {
            session: self.session,
            evidence: self.evidence,
            fault: Rc::clone(&self.fault),
        })
    }
    /// The generated contract has no failure channel here: `resolve` is
    /// infallible. A resolution failure is parked in the shared `fault` cell
    /// (and `precompute_paragraph` fails the call) while this returns the
    /// engine's own stub metric, so the layout it must not keep stays
    /// well-formed rather than dividing by a substituted zero.
    fn resolve(&self, request: FontMetricsRequest) -> RawFontMetrics {
        match self.resolve_metrics(&request) {
            Ok([ascent, descent, leading, typo_ascent, typo_descent]) => RawFontMetrics::new(
                ascent,
                descent,
                Some(leading),
                Some(FontMetricSource::RawTables),
                typo_ascent.is_finite().then_some(typo_ascent),
                typo_descent.is_finite().then_some(typo_descent),
            ),
            Err(message) => {
                *self.fault.borrow_mut() = Some(message);
                StubFontMetricsResolver::new().borrow().resolve(request)
            }
        }
    }
}
/// Adapts the lane request into the generated engine input. The generated
/// engine is the f64 bundle, so the values keep full f64 precision here; the
/// i32 to u32 range casts keep the check outcomes of the validation, which
/// ran on the i32 values the caller passed.
fn layout_input(request: &ParagraphRequest) -> Result<LayoutInput, NamedError> {
    fn text_range(start: i32, end: i32) -> Result<TextRange, NamedError> {
        TextRange::new(start as u32, end as u32).map_err(|error| NamedError(error.to_string()))
    }
    // The generated engine input carries Haxe strings (UTF-16 units); the
    // lane request keeps `String`, so every text field converts through
    // the generated `From<&str>` conversion at this one boundary.
    let text_style = TextStyle::new(
        Some(
            request
                .font_families
                .iter()
                .map(|family| UString::from(family.as_str()))
                .collect(),
        ),
        Some(request.font_size_px),
        Some(UString::from(request.locale.as_str())),
        Some(request.font_weight as u32),
        Some(request.italic),
        Some(0.0),
        None,
    );
    let spans = request
        .text_spans
        .iter()
        .map(|span| {
            Ok(TextSpan::new(
                text_range(span.start, span.end)?,
                TextStyle::new(
                    Some(
                        span.families
                            .iter()
                            .map(|family| UString::from(family.as_str()))
                            .collect(),
                    ),
                    Some(span.font_size_px),
                    None,
                    Some(span.font_weight as u32),
                    Some(span.italic),
                    Some(span.baseline_shift),
                    None,
                ),
            ))
        })
        .collect::<Result<Vec<_>, NamedError>>()?;
    let boundaries = request
        .source_boundaries
        .iter()
        .map(|value| *value as u32)
        .collect();
    let line_break_spans = request
        .line_break_spans
        .iter()
        .map(|span| {
            Ok(LineBreakSpan::new(
                text_range(span.start, span.end)?,
                LineBreakPolicy::ProgressiveTechnical,
            ))
        })
        .collect::<Result<Vec<_>, NamedError>>()?;
    let content = TiqianTextContent::new(
        &UString::from(request.text.as_str()),
        Some(spans),
        Some(boundaries),
        Some(line_break_spans),
        None,
    );
    let constraints = LayoutConstraints::new(request.max_width_px, None, None)
        .map_err(|error| NamedError(error.to_string()))?;
    let paragraph_style = ParagraphStyle::new(
        None,
        None,
        Some(request.line_height_px),
        Some(Ic::new(request.first_line_indent_ic)),
        None,
        None,
        Some(LineLengthGrid::new(Some(request.line_length_grid_enabled), None)),
        None,
        None,
        None,
    );
    let inline_boxes = request
        .inline_boxes
        .iter()
        .map(|inline_box| {
            Ok(InlineBoxSpan::new(
                text_range(inline_box.start, inline_box.end)?,
                Some(inline_box.inline_start),
                Some(inline_box.inline_end),
                Some(match inline_box.outer_spacing {
                    InlineBoxOuterSpacingCode::Narrow => InlineBoxOuterSpacing::Narrow,
                    InlineBoxOuterSpacingCode::Source => InlineBoxOuterSpacing::Source,
                }),
            ))
        })
        .collect::<Result<Vec<_>, NamedError>>()?;
    Ok(LayoutInput::new(
        content,
        Some(text_style),
        Some(paragraph_style),
        constraints,
        None,
        None,
        None,
        Some(inline_boxes),
        None,
    ))
}

/// Runs one paragraph request through the generated engine with `session`
/// and its capture window as the shaping and metrics components. Both stay
/// borrowed for the duration of the call. Errors are the named validation
/// issues of the request and the engine; the production path returns the
/// prepared-paragraph JSON read back into [`crate::plan::Plan`].
pub fn precompute_paragraph(
    session: &FontSession,
    evidence: &mut CaptureEvidence,
    request: &ParagraphRequest,
) -> Result<crate::plan::Plan, String> {
    request.validate().map_err(|error| error.0)?;
    // SAFETY: `precompute_paragraph` holds both borrows across the engine
    // call; see the obligation list on `SessionBackend`.
    let fault: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
    let mut engine = Engine::new(EngineComponents {
        // Both slots are P-1 interface handles (`Rc<RefCell<dyn Trait>>`):
        // the engine owns them for this call and never leaves the calling
        // thread, and the policy's final boundary forbids smuggling Arc/Mutex
        // in for a possible future threaded host (target-semantic-policy:43-56).
        // The two components point at the same session, capture window and
        // fault cell.
        text_shaper: Some(Rc::new(RefCell::new(unsafe {
            SessionBackend::new(session, evidence, Rc::clone(&fault))
        }))),
        font_metrics_resolver: Some(Rc::new(RefCell::new(unsafe {
            SessionBackend::new(session, evidence, Rc::clone(&fault))
        }))),
        ..EngineComponents::default()
    })
    .map_err(|error| error.0)?;
    let input = layout_input(request).map_err(|error| error.0)?;
    let layout = engine.layout(input).map_err(|error| error.0);
    // A metrics-resolution failure cannot travel through the generated trait;
    // report it as the call's error rather than hand back a plan built on the
    // stub metric (a check that could not be measured is a failure).
    if let Some(message) = fault.borrow_mut().take() {
        return Err(message);
    }
    let result = layout?;
    // The prepared-paragraph form keeps the emitter's default of no render
    // evidence (PreparedParagraph.toPreparedParagraphJson default): the
    // oracle plan carries no renderEvidence-only fields and the entry's
    // render artifact is produced by this lane's own lowering.
    let json =
        PreparedParagraphFns::prepared_paragraph_fns_to_prepared_paragraph_json(result, false)
            .map_err(|fault| format!("{fault:?}"))?;
    // The emitter returns the JSON as a Haxe string; the plan reader
    // takes the UTF-8 `&str` form.
    crate::plan::Plan::from_json_str(&json.to_utf8_lossy()).map_err(|error| error.0)
}

/// Kotlin `String.substring(start, end)`: UTF-16 code-unit offsets. A char
/// is kept when its UTF-16 units fall fully inside the range; the char that
/// a surrogate-split boundary cuts joins when its first unit sits inside.
fn utf16_substring(text: &str, start: u32, end: u32) -> String {
    let mut out = String::new();
    let mut position = 0u32;
    for character in text.chars() {
        let units = if character as u32 <= 0xffff { 1 } else { 2 };
        if position + units > start && position < end {
            out.push(character);
        }
        position += units;
    }
    out
}