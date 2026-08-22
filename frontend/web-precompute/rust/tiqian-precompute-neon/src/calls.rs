//! Exported functions. Flat arguments mirror the global backend protocol
//! (`shape(sessionId, displayText, families, ...)`); structured results are
//! JSON strings built by `tiqian_precompute::emit`, the same emitters the
//! parity harness byte-compares against the Kotlin/JS oracle.

use neon::prelude::*;
use neon::types::buffer::TypedArray;

use tiqian_precompute::emit;
use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
#[cfg(tiqian_engine_link)]
use tiqian_precompute::js_compat::trunc_sat_i32;
use tiqian_precompute::js_compat::trunc_sat_usize;
use tiqian_precompute::json::Json;
#[cfg(tiqian_engine_link)]
use tiqian_precompute::session::CaptureEvidence;
use tiqian_precompute::session::{
    create_font_session as create_session_impl, MetricsInput, SessionFaceSpec, SessionOptions,
    ShapeInput, BACKEND_REVISION, HARFBUZZ_VERSION,
};
use tiqian_precompute::source_boundaries::{BoundaryStyle, BoundaryTextSpan};

#[cfg(tiqian_engine_link)]
use tiqian_precompute::engine_bridge;
#[cfg(tiqian_engine_link)]
use tiqian_precompute::paragraph::{
    InlineBoxInput, InlineBoxOuterSpacingCode, LineBreakPolicyCode, LineBreakSpanInput,
    ParagraphRequest, TextSpanInput,
};

use crate::registry;

pub fn backend_revision(mut cx: FunctionContext) -> JsResult<JsString> {
    Ok(cx.string(BACKEND_REVISION))
}

pub fn harfbuzz_version(mut cx: FunctionContext) -> JsResult<JsString> {
    Ok(cx.string(HARFBUZZ_VERSION))
}

/// One face entry read from the `faces` array, with the font bytes it points
/// at held in the caller's `sources` list.
pub(crate) struct FaceSpecOwned {
    pub family: String,
    pub public_url: String,
    pub source_index: usize,
    pub face_index: Option<f64>,
    pub weight: FontWeightSpec,
    pub style: String,
    pub unicode_range: Option<String>,
    pub source_order: Option<f64>,
}

/// Capacity hint from a js array length. usize covers u32 on every neon
/// host; the zero fallback only guards narrower widths.
fn array_capacity(len: u32) -> usize {
    usize::try_from(len).unwrap_or(0)
}

/// Reads the `faces` and `sources` array pair of the create calls. Font
/// bytes are copied out of their buffers up front: the session outlives the
/// call, and the napi borrows end here.
pub(crate) fn read_face_arguments(
    cx: &mut FunctionContext,
    faces: &Handle<JsArray>,
    sources: &Handle<JsArray>,
) -> NeonResult<(Vec<FaceSpecOwned>, Vec<Vec<u8>>)> {
    let mut fonts: Vec<Vec<u8>> = Vec::with_capacity(array_capacity(sources.len(cx)));
    for value in sources.to_vec(cx)? {
        let buffer = value.downcast_or_throw::<JsBuffer, _>(cx)?;
        fonts.push(buffer.as_slice(cx).to_vec());
    }

    let mut owned: Vec<FaceSpecOwned> = Vec::with_capacity(array_capacity(faces.len(cx)));
    for value in faces.to_vec(cx)? {
        let face = value.downcast_or_throw::<JsObject, _>(cx)?;
        let source_index = trunc_sat_usize(face.prop(cx, "font").get::<f64>()?);
        if source_index >= fonts.len() {
            return cx.throw_error(format!("FontSourceOutOfRange:{source_index}"));
        }
        owned.push(FaceSpecOwned {
            family: face.prop(cx, "family").get::<String>()?,
            public_url: face.prop(cx, "publicUrl").get::<String>()?,
            source_index,
            face_index: face.prop(cx, "faceIndex").get::<Option<f64>>()?,
            weight: read_weight_spec(cx, &face)?,
            style: face
                .prop(cx, "style")
                .get::<Option<String>>()?
                .unwrap_or_else(|| "normal".to_string()),
            unicode_range: face.prop(cx, "unicodeRange").get::<Option<String>>()?,
            source_order: face.prop(cx, "sourceOrder").get::<Option<f64>>()?,
        });
    }
    Ok((owned, fonts))
}

/// Builds the borrowed face specs the library consumes.
pub(crate) fn session_face_specs<'a>(
    owned: &'a [FaceSpecOwned],
    fonts: &'a [Vec<u8>],
) -> Vec<SessionFaceSpec<'a>> {
    owned
        .iter()
        .map(|face| SessionFaceSpec {
            spec: FontFaceSpec {
                family: face.family.as_str(),
                public_url: face.public_url.as_str(),
                source: &fonts[face.source_index],
                face_index: face.face_index,
                weight: face.weight.clone(),
                style: face.style.as_str(),
                unicode_range: face.unicode_range.as_deref(),
                source_order: 0,
            },
            source_order: face.source_order,
        })
        .collect()
}

pub fn create_font_session(mut cx: FunctionContext) -> JsResult<JsString> {
    let faces = cx.argument::<JsArray>(0)?;
    let sources = cx.argument::<JsArray>(1)?;
    let options = cx.argument::<JsObject>(2)?;

    let (owned, fonts) = read_face_arguments(&mut cx, &faces, &sources)?;
    let specs = session_face_specs(&owned, &fonts);

    let session_prefix = options
        .prop(&mut cx, "sessionPrefix")
        .get::<Option<String>>()?
        .unwrap_or_else(|| "tq-font".to_string());
    let base_features = match options
        .prop(&mut cx, "baseFeatures")
        .get::<Option<Handle<JsArray>>>()?
    {
        Some(array) => Some(read_string_elements(&mut cx, &array)?),
        None => None,
    };

    match create_session_impl(
        specs,
        SessionOptions {
            session_prefix,
            base_features,
        },
    ) {
        Ok(session) => Ok(cx.string(registry::insert(session))),
        Err(error) => cx.throw_error(error.to_string()),
    }
}

pub(crate) fn read_weight_spec(
    cx: &mut FunctionContext,
    face: &Handle<JsObject>,
) -> NeonResult<FontWeightSpec> {
    let value = face.prop(&mut *cx, "weight").get::<Handle<JsValue>>()?;
    if value.is_a::<JsArray, _>(cx) {
        let array = value.downcast_or_throw::<JsArray, _>(cx)?;
        let items = array.to_vec(cx)?;
        if items.len() != 2 {
            return cx.throw_error("InvalidFontFaceWeight");
        }
        let low = items[0].downcast_or_throw::<JsNumber, _>(cx)?.value(cx);
        let high = items[1].downcast_or_throw::<JsNumber, _>(cx)?.value(cx);
        Ok(FontWeightSpec::Range(low, high))
    } else if value.is_a::<JsNumber, _>(cx) {
        let weight = value.downcast_or_throw::<JsNumber, _>(cx)?.value(cx);
        Ok(FontWeightSpec::Single(Some(weight)))
    } else {
        Ok(FontWeightSpec::Single(None))
    }
}

pub fn session_faces(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_session(&session_id, |session| {
        Json::Arr(session.faces().iter().map(emit::face_info_json).collect())
    }) {
        Ok(json) => Ok(cx.string(json.render())),
        Err(error) => cx.throw_error(error),
    }
}

/// `shape(sessionId, displayText, families, fontSize, fontWeight, italic,
/// locale, role, sourceText)` in the global backend protocol; `families` is
/// pre-joined with U+001F by the JS wrapper.
pub fn shape(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    let display_text = cx.argument::<JsString>(1)?.value(&mut cx);
    let families = cx.argument::<JsString>(2)?.value(&mut cx);
    let font_size = cx.argument::<JsNumber>(3)?.value(&mut cx);
    let font_weight = cx.argument::<JsNumber>(4)?.value(&mut cx);
    let italic = cx.argument::<JsBoolean>(5)?.value(&mut cx);
    let locale = cx.argument::<JsString>(6)?.value(&mut cx);
    let role = optional_string(&mut cx, 7)?;
    let source_text = optional_string(&mut cx, 8)?;

    let input = ShapeInput {
        display_text: &display_text,
        serialized_families: &families,
        font_size,
        font_weight,
        italic,
        locale: &locale,
        role: role.as_deref(),
        source_text: source_text.as_deref(),
    };
    match registry::with_session(&session_id, |session| session.shape(&input)) {
        Ok(Ok(result)) => match emit::shape_result_json(&result) {
            Ok(json) => Ok(cx.string(json.render())),
            Err(error) => cx.throw_error(error.0),
        },
        Ok(Err(error)) => cx.throw_error(error),
        Err(error) => cx.throw_error(error),
    }
}

pub fn metrics(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    let families = cx.argument::<JsString>(1)?.value(&mut cx);
    let font_size = cx.argument::<JsNumber>(2)?.value(&mut cx);
    let font_weight = cx.argument::<JsNumber>(3)?.value(&mut cx);
    let italic = cx.argument::<JsBoolean>(4)?.value(&mut cx);
    let role = optional_string(&mut cx, 5)?;
    let face_selection_text = optional_string(&mut cx, 6)?;

    let input = MetricsInput {
        serialized_families: &families,
        font_size,
        font_weight,
        italic,
        role: role.as_deref(),
        face_selection_text: face_selection_text.as_deref(),
    };
    match registry::with_session(&session_id, |session| session.metrics(&input)) {
        Ok(Ok(values)) => {
            Ok(cx
                .string(Json::Arr(values.iter().map(|value| Json::Num(*value)).collect()).render()))
        }
        Ok(Err(error)) => cx.throw_error(error),
        Err(error) => cx.throw_error(error),
    }
}

pub fn render_families(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    let requested = cx.argument::<JsArray>(1)?;
    let names = read_string_elements(&mut cx, &requested)?;
    match registry::with_session(&session_id, |session| session.render_families(&names)) {
        Ok(Ok(families)) => Ok(cx.string(
            Json::Arr(
                families
                    .iter()
                    .map(|name| Json::str(name.clone()))
                    .collect(),
            )
            .render(),
        )),
        Ok(Err(error)) => cx.throw_error(error),
        Err(error) => cx.throw_error(error),
    }
}

/// `sourceBoundaries(sessionId, text, baseStyle, textSpans)`.
pub fn source_boundaries(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    let text = cx.argument::<JsString>(1)?.value(&mut cx);
    let base_style = cx.argument::<JsObject>(2)?;
    let spans = cx.argument::<JsArray>(3)?;

    let base = read_boundary_style(&mut cx, &base_style)?;
    let mut parsed: Vec<BoundaryTextSpan> = Vec::with_capacity(array_capacity(spans.len(&mut cx)));
    for value in spans.to_vec(&mut cx)? {
        let span = value.downcast_or_throw::<JsObject, _>(&mut cx)?;
        let style_value = span.prop(&mut cx, "style").get::<Handle<JsValue>>()?;
        let style = style_value.downcast_or_throw::<JsObject, _>(&mut cx)?;
        parsed.push(BoundaryTextSpan {
            start: span.prop(&mut cx, "start").get::<f64>()?,
            end: span.prop(&mut cx, "end").get::<f64>()?,
            style: read_boundary_style(&mut cx, &style)?,
        });
    }

    match registry::with_session(&session_id, |session| {
        session.source_boundaries(&text, &base, &parsed)
    }) {
        Ok(Ok(boundaries)) => {
            Ok(cx.string(Json::Arr(boundaries.iter().map(|v| Json::Num(*v)).collect()).render()))
        }
        Ok(Err(error)) => cx.throw_error(error),
        Err(error) => cx.throw_error(error),
    }
}

fn read_boundary_style(
    cx: &mut FunctionContext,
    style: &Handle<JsObject>,
) -> NeonResult<BoundaryStyle> {
    Ok(BoundaryStyle {
        font_families: read_property_string_array(cx, style, "fontFamilies")?,
        font_size_px: style.prop(&mut *cx, "fontSizePx").get::<f64>()?,
        font_weight: style.prop(&mut *cx, "fontWeight").get::<f64>()?,
        italic: style.prop(&mut *cx, "italic").get::<bool>()?,
        baseline_shift_px: style
            .prop(&mut *cx, "baselineShiftPx")
            .get::<Option<f64>>()?,
    })
}

/// `precomputeParagraph(sessionId, text, maxWidthPx, families, fontSizePx,
/// lineHeightPx, locale, fontWeight, italic, firstLineIndentIc,
/// lineLengthGridEnabled, sourceBoundaries, textSpans, inlineBoxes,
/// lineBreakSpans)`: the structured form of the js facade call. Arrays and
/// span objects arrive as themselves; the delimiter wire encoding stays on
/// the js side. Returns the plan JSON. The engine link is a build time
/// property; an addon built without the archive reports `EngineNotLinked`.
pub fn precompute_paragraph(mut cx: FunctionContext) -> JsResult<JsString> {
    #[cfg(not(tiqian_engine_link))]
    {
        return cx.throw_error("EngineNotLinked");
    }
    #[cfg(tiqian_engine_link)]
    {
        let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
        let request = read_paragraph_request(&mut cx, session_id.clone())?;
        match registry::with_session(&session_id, |session| {
            // One capture window per call. The singular entries keep this
            // shape.
            let mut evidence_window = CaptureEvidence::new();
            engine_bridge::precompute_paragraph(session, &mut evidence_window, &request)
        }) {
            Ok(Ok(plan)) => Ok(cx.string(plan)),
            Ok(Err(error)) => cx.throw_error(error),
            Err(error) => cx.throw_error(error),
        }
    }
}

#[cfg(tiqian_engine_link)]
fn read_paragraph_request(
    cx: &mut FunctionContext,
    session_id: String,
) -> NeonResult<ParagraphRequest> {
    let text = cx.argument::<JsString>(1)?.value(&mut *cx);
    let max_width_px = cx.argument::<JsNumber>(2)?.value(&mut *cx);
    let families = cx.argument::<JsArray>(3)?;
    let font_size_px = cx.argument::<JsNumber>(4)?.value(&mut *cx);
    let line_height_px = cx.argument::<JsNumber>(5)?.value(&mut *cx);
    let locale = cx.argument::<JsString>(6)?.value(&mut *cx);
    let font_weight = trunc_sat_i32(cx.argument::<JsNumber>(7)?.value(&mut *cx));
    let italic = cx.argument::<JsBoolean>(8)?.value(&mut *cx);
    let first_line_indent_ic = cx.argument::<JsNumber>(9)?.value(&mut *cx);
    let line_length_grid_enabled = cx.argument::<JsBoolean>(10)?.value(&mut *cx);
    let source_boundaries = cx.argument::<JsArray>(11)?;
    let text_spans = cx.argument::<JsArray>(12)?;
    let inline_boxes = cx.argument::<JsArray>(13)?;
    let line_break_spans = cx.argument::<JsArray>(14)?;

    Ok(ParagraphRequest {
        font_session_id: session_id,
        text,
        max_width_px,
        font_families: read_string_elements(&mut *cx, &families)?,
        font_size_px,
        line_height_px,
        locale,
        font_weight,
        italic,
        first_line_indent_ic,
        line_length_grid_enabled,
        source_boundaries: read_int_elements(&mut *cx, &source_boundaries)?,
        text_spans: read_text_spans(&mut *cx, &text_spans)?,
        line_break_spans: read_line_break_spans(&mut *cx, &line_break_spans)?,
        inline_boxes: read_inline_boxes(&mut *cx, &inline_boxes)?,
    })
}

/// Index and boundary values are integers on the js side. The conversion
/// truncates toward zero, maps NaN to 0, and saturates at the i32 bounds.
#[cfg(tiqian_engine_link)]
fn read_int_elements(cx: &mut FunctionContext, array: &Handle<JsArray>) -> NeonResult<Vec<i32>> {
    let mut items = Vec::with_capacity(array_capacity(array.len(&mut *cx)));
    for value in array.to_vec(&mut *cx)? {
        let number = value
            .downcast_or_throw::<JsNumber, _>(&mut *cx)?
            .value(&mut *cx);
        items.push(trunc_sat_i32(number));
    }
    Ok(items)
}

#[cfg(tiqian_engine_link)]
fn read_text_spans(
    cx: &mut FunctionContext,
    spans: &Handle<JsArray>,
) -> NeonResult<Vec<TextSpanInput>> {
    let mut parsed = Vec::with_capacity(array_capacity(spans.len(&mut *cx)));
    for value in spans.to_vec(&mut *cx)? {
        let span = value.downcast_or_throw::<JsObject, _>(&mut *cx)?;
        let families = span.prop(&mut *cx, "families").get::<Handle<JsArray>>()?;
        parsed.push(TextSpanInput {
            start: trunc_sat_i32(span.prop(&mut *cx, "start").get::<f64>()?),
            end: trunc_sat_i32(span.prop(&mut *cx, "end").get::<f64>()?),
            families: read_string_elements(&mut *cx, &families)?,
            font_size_px: span.prop(&mut *cx, "fontSizePx").get::<f64>()?,
            font_weight: trunc_sat_i32(span.prop(&mut *cx, "fontWeight").get::<f64>()?),
            italic: span.prop(&mut *cx, "italic").get::<bool>()?,
            baseline_shift: span.prop(&mut *cx, "baselineShiftPx").get::<f64>()?,
        });
    }
    Ok(parsed)
}

#[cfg(tiqian_engine_link)]
fn read_inline_boxes(
    cx: &mut FunctionContext,
    boxes: &Handle<JsArray>,
) -> NeonResult<Vec<InlineBoxInput>> {
    let mut parsed = Vec::with_capacity(array_capacity(boxes.len(&mut *cx)));
    for value in boxes.to_vec(&mut *cx)? {
        let inline_box = value.downcast_or_throw::<JsObject, _>(&mut *cx)?;
        let outer_spacing = inline_box
            .prop(&mut *cx, "outerSpacing")
            .get::<Option<String>>()?;
        parsed.push(InlineBoxInput {
            start: trunc_sat_i32(inline_box.prop(&mut *cx, "start").get::<f64>()?),
            end: trunc_sat_i32(inline_box.prop(&mut *cx, "end").get::<f64>()?),
            inline_start: inline_box.prop(&mut *cx, "inlineStartPx").get::<f64>()?,
            inline_end: inline_box.prop(&mut *cx, "inlineEndPx").get::<f64>()?,
            outer_spacing: match outer_spacing.as_deref() {
                None | Some("Narrow") => InlineBoxOuterSpacingCode::Narrow,
                Some("Source") => InlineBoxOuterSpacingCode::Source,
                Some(_) => return cx.throw_error("InvalidInlineBoxOuterSpacing"),
            },
        });
    }
    Ok(parsed)
}

#[cfg(tiqian_engine_link)]
fn read_line_break_spans(
    cx: &mut FunctionContext,
    spans: &Handle<JsArray>,
) -> NeonResult<Vec<LineBreakSpanInput>> {
    let mut parsed = Vec::with_capacity(array_capacity(spans.len(&mut *cx)));
    for value in spans.to_vec(&mut *cx)? {
        let span = value.downcast_or_throw::<JsObject, _>(&mut *cx)?;
        let policy = span.prop(&mut *cx, "policy").get::<String>()?;
        parsed.push(LineBreakSpanInput {
            start: trunc_sat_i32(span.prop(&mut *cx, "start").get::<f64>()?),
            end: trunc_sat_i32(span.prop(&mut *cx, "end").get::<f64>()?),
            policy: match policy.as_str() {
                "ProgressiveTechnical" => LineBreakPolicyCode::ProgressiveTechnical,
                _ => return cx.throw_error("InvalidLineBreakPolicy"),
            },
        });
    }
    Ok(parsed)
}

pub fn begin_capture(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_session(&session_id, |session| session.begin_capture()) {
        Ok(()) => Ok(cx.undefined()),
        Err(error) => cx.throw_error(error),
    }
}

pub fn capture_evidence(mut cx: FunctionContext) -> JsResult<JsString> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_session(&session_id, |session| {
        emit::evidence_json(&session.capture_evidence())
    }) {
        Ok(Ok(json)) => Ok(cx.string(json.render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

pub fn close_session(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let session_id = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_session(&session_id, |session| session.close()) {
        Ok(()) => Ok(cx.undefined()),
        Err(error) => cx.throw_error(error),
    }
}

pub(crate) fn optional_string(
    cx: &mut FunctionContext,
    index: usize,
) -> NeonResult<Option<String>> {
    let Some(value) = cx.argument_opt(index) else {
        return Ok(None);
    };
    if value.is_a::<JsNull, _>(cx) || value.is_a::<JsUndefined, _>(cx) {
        return Ok(None);
    }
    Ok(Some(value.downcast_or_throw::<JsString, _>(cx)?.value(cx)))
}

pub(crate) fn read_string_elements(
    cx: &mut FunctionContext,
    array: &Handle<JsArray>,
) -> NeonResult<Vec<String>> {
    let mut items = Vec::with_capacity(array_capacity(array.len(&mut *cx)));
    for value in array.to_vec(&mut *cx)? {
        items.push(value.downcast_or_throw::<JsString, _>(cx)?.value(cx));
    }
    Ok(items)
}

fn read_property_string_array(
    cx: &mut FunctionContext,
    object: &Handle<JsObject>,
    key: &str,
) -> NeonResult<Vec<String>> {
    let array = object.prop(&mut *cx, key).get::<Handle<JsArray>>()?;
    read_string_elements(cx, &array)
}
