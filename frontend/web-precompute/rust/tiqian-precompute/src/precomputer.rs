//! `createPrecomputer` of `precompute.js` (ADR 0050): one typography plus one
//! font session prepare paragraphs and font contracts. The port keeps the js
//! step order exactly, so the first named issue matches byte for byte; the
//! engine call exists only when build.rs linked the archive. Node file and
//! stylesheet loading stay with the host lane; this layer consumes resolved
//! face specs.

use tiqian::NamedError;

use crate::cache::{CacheAdapter, LayeredCacheStore, NoCache, WriteBudgetTier};
use crate::emit::evidence_json;
use crate::font_source::sha256_hex;
use crate::js_compat::{js_int_to_number, trunc_sat_i32};
use crate::json::{member, parse_json, Json};
use crate::normalize::{
    font_contract_capture_width, normalize_inline_boxes, normalize_text_spans,
    normalize_typography, paragraph_capability_issue, semantic_capability_issue,
    snapshot_plain_text_issue, InlineBoxRaw, SnapshotTypography, TextSpanRaw, TypographyInput,
};
use crate::paragraph::{
    utf16_length, InlineBoxInput, LineBreakPolicyCode, LineBreakSpanInput, ParagraphRequest,
    TextSpanInput,
};
use crate::prepared_dom::{render_prepared_paragraph_artifact, PreparedRenderOptions};
use crate::schema::{stable_stringify, LAYOUT_REVISION, RENDER_REVISION, SNAPSHOT_SCHEMA};
use crate::session::{create_font_session, FontSession, SessionFaceSpec, SessionOptions};
use crate::snapshot_source::{
    js_number_value, js_string_value, normalize_snapshot_semantics, semantics_json,
    snapshot_semantic_metric_contract_issue, SemanticSpan,
};
use crate::source_boundaries::{BoundaryStyle, BoundaryTextSpan};

/// The session prefix `createBuildFontSession` always passes.
const BUILD_SESSION_PREFIX: &str = "tq-build-font";

/// Options of [`create_precomputer`]. `faces` are the resolved build faces;
/// reading files and parsing stylesheets belongs to the host lane. A Rust
/// host plugs its persistence through `cache_adapter`; without one the bridge
/// drain queue serves as the write side.
pub struct PrecomputerOptions<'a> {
    pub typography: TypographyInput,
    pub faces: Vec<SessionFaceSpec<'a>>,
    pub session_prefix: String,
    pub cache_adapter: Option<Box<dyn CacheAdapter>>,
    /// The drain-queue write budget; `Normal` unless the host says otherwise.
    pub write_budget: WriteBudgetTier,
}

impl<'a> PrecomputerOptions<'a> {
    pub fn new(typography: TypographyInput, faces: Vec<SessionFaceSpec<'a>>) -> Self {
        PrecomputerOptions {
            typography,
            faces,
            session_prefix: BUILD_SESSION_PREFIX.to_string(),
            cache_adapter: None,
            write_budget: WriteBudgetTier::Normal,
        }
    }
}

/// `createPrecomputer`: normalize the typography, build the font session with
/// the `lining-nums` base feature and resolve the render families. Every
/// failure is the js throw of the same step.
pub fn create_precomputer(options: PrecomputerOptions) -> Result<Precomputer, NamedError> {
    let typography = normalize_typography(options.typography)?;
    let base_features = if typography.font_variant_numeric == "lining-nums" {
        vec!["lnum".to_string()]
    } else {
        Vec::new()
    };
    let session = create_font_session(
        options.faces,
        SessionOptions {
            session_prefix: options.session_prefix,
            base_features: Some(base_features),
        },
    )
    .map_err(|error| NamedError(error.to_string()))?;
    let mut precomputer = Precomputer {
        typography,
        render_font_families: Vec::new(),
        session,
        closed: std::sync::atomic::AtomicBool::new(false),
        cache: LayeredCacheStore::new([0; 32], Box::new(NoCache)),
        cache_owner: crate::renderer::next_job_owner(),
    };
    precomputer.render_font_families = precomputer
        .session
        .render_families(&precomputer.typography.font_families)
        .map_err(NamedError)?;
    // The context fingerprint covers the revisions, the shaping engine, the
    // resolved face set and the normalized typography; every cache key of
    // this precomputer derives from it (ADR 0052).
    let context =
        crate::context::context_fingerprint(&precomputer.typography, &precomputer.session.faces());
    precomputer.cache = match options.cache_adapter {
        Some(adapter) => LayeredCacheStore::new(context, adapter),
        None => LayeredCacheStore::with_drain_queue(context, options.write_budget).0,
    };
    Ok(precomputer)
}

pub struct Precomputer {
    typography: SnapshotTypography,
    render_font_families: Vec<String>,
    session: FontSession,
    closed: std::sync::atomic::AtomicBool,
    pub(crate) cache: LayeredCacheStore,
    /// Instance identity for renderer-pool dedup; see [`crate::renderer`].
    pub(crate) cache_owner: u64,
}

/// One `prepare(input, snapshotCandidate)` call. Every field is the loose js
/// object member; `from_json` reads the wire form and the dash retry builds
/// the same shape.
#[derive(Default)]
pub struct PrepareInput<'a> {
    pub key: Option<&'a Json>,
    pub text: Option<&'a Json>,
    pub semantics: Option<&'a Json>,
    pub text_spans: Option<&'a Json>,
    pub inline_boxes: Option<&'a Json>,
    pub max_width_px: Option<&'a Json>,
    pub source_boundaries: Option<&'a Json>,
}

impl<'a> PrepareInput<'a> {
    pub fn new() -> Self {
        PrepareInput::default()
    }

    pub fn from_json(value: &'a Json) -> Self {
        PrepareInput {
            key: member(value, "key"),
            text: member(value, "text"),
            semantics: member(value, "semantics"),
            text_spans: member(value, "textSpans"),
            inline_boxes: member(value, "inlineBoxes"),
            max_width_px: member(value, "maxWidthPx"),
            source_boundaries: member(value, "sourceBoundaries"),
        }
    }

    /// `String(input.key ?? "")`.
    pub fn key_string(&self) -> String {
        coalesce(self.key).map(js_string_value).unwrap_or_default()
    }

    /// `String(input.text ?? "")`.
    pub fn text_string(&self) -> String {
        coalesce(self.text).map(js_string_value).unwrap_or_default()
    }
}

impl Precomputer {
    pub fn typography(&self) -> &SnapshotTypography {
        &self.typography
    }

    pub fn render_font_families(&self) -> &[String] {
        &self.render_font_families
    }

    pub fn session_id(&self) -> &str {
        &self.session.session_id
    }

    /// `prepareParagraph`: the snapshot path with the plain-text gate and the
    /// caller's measure.
    pub fn prepare_paragraph(&self, input: &PrepareInput) -> Result<Json, NamedError> {
        self.prepare(input, true)
    }

    /// `prepareParagraphs`: the batch snapshot lane. The items spread over
    /// the configured workers; entries come back in input order and the
    /// reported error is the one of the lowest failing index, the sequential
    /// loop's `?` order. Every paragraph owns its capture window, so the
    /// entries match the singular lane exactly.
    pub fn prepare_paragraphs(&self, inputs: &[PrepareInput]) -> Result<Vec<Json>, NamedError> {
        let workers = crate::parallel::worker_count();
        crate::parallel::indexed_collect(inputs.len(), workers, |index| {
            self.prepare_paragraph(&inputs[index])
        })
    }

    /// `prepareFontContract`: the wide capture measure, and when the source
    /// cannot be prepared at all, one retry over the CJK dash probes it owns.
    pub fn prepare_font_contract(&self, input: &PrepareInput) -> Result<Json, NamedError> {
        let prepared = self.prepare(input, false)?;
        if entry_status(&prepared) == Some("prepared") {
            return Ok(prepared);
        }
        let Some(probe) =
            crate::font_contract::required_cjk_dash_contract_input(input, &self.typography)
        else {
            return Ok(prepared);
        };
        let replay = PrepareInput::from_json(&probe);
        self.prepare(&replay, false)
    }

    /// `prepareFontContracts`: the batch contract lane. The items spread
    /// over the configured workers with the same guarantees as the snapshot
    /// batch: entries come back in input order and the reported error is the
    /// one of the lowest failing index, the sequential loop's `?` order.
    /// Every item owns its capture window and its CJK dash retry, so the
    /// entries match the singular lane exactly.
    pub fn prepare_font_contracts(&self, inputs: &[PrepareInput]) -> Result<Vec<Json>, NamedError> {
        let workers = crate::parallel::worker_count();
        crate::parallel::indexed_collect(inputs.len(), workers, |index| {
            self.prepare_font_contract(&inputs[index])
        })
    }

    pub fn close(&self) {
        if self.closed.swap(true, std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        self.session.close();
    }

    /// The `prepare` closure of the js. Returns the frozen entry value:
    /// `status: "prepared"` with the nineteen fields, or `status:
    /// "unsupported"` with the classified issue.
    fn prepare(&self, input: &PrepareInput, snapshot_candidate: bool) -> Result<Json, NamedError> {
        let Precomputer {
            typography,
            render_font_families,
            session,
            ..
        } = self;
        if self.closed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(named("PrecomputerClosed"));
        }
        let key = input.key_string().trim().to_string();
        if key.is_empty() {
            return Err(named("MissingSnapshotKey"));
        }
        let text = input.text_string();

        let semantics = match normalize_snapshot_semantics(&text, coalesce(input.semantics)) {
            Ok(spans) => spans,
            Err(error) => {
                return match semantic_capability_issue(&error.0) {
                    Some(issue) => Ok(unsupported_paragraph(&key, issue, Some(&error.0))),
                    None => Err(error),
                };
            }
        };
        if let Some(issue) = snapshot_semantic_metric_contract_issue(
            &semantics,
            input.text_spans,
            input.inline_boxes,
        ) {
            return Ok(unsupported_paragraph(&key, issue, None));
        }
        let text_spans =
            normalize_text_spans(&text, text_spans_raw(input.text_spans)?, typography)?;
        let mut render_text_spans: Vec<(i32, i32, Vec<String>)> = Vec::new();
        for span in &text_spans {
            let families = session
                .render_families(&span.families)
                .map_err(NamedError)?;
            if families == *render_font_families {
                continue;
            }
            render_text_spans.push((span.start, span.end, families));
        }
        let inline_boxes = normalize_inline_boxes(&text, inline_boxes_raw(input.inline_boxes)?)?;
        if snapshot_candidate {
            if let Some(issue) = snapshot_plain_text_issue(&text) {
                return Ok(unsupported_paragraph(&key, issue, None));
            }
        }
        let max_width_px = if snapshot_candidate {
            input.max_width_px.map(js_number_value).unwrap_or(f64::NAN)
        } else {
            font_contract_capture_width(
                utf16_length(&text),
                &text_spans,
                &inline_boxes,
                typography.font_size_px,
            )
        };
        if !max_width_px.is_finite() || max_width_px <= 0.0 {
            return Err(named("InvalidMaximumMeasure"));
        }

        let captured = capture(
            session,
            input,
            &text,
            typography,
            &semantics,
            &text_spans,
            &inline_boxes,
            max_width_px,
        );
        let (plan_json, evidence) = match classify_paragraph(&key, captured)? {
            Ok(value) => value,
            Err(unsupported) => return Ok(unsupported),
        };

        let typography_json = typography_value_json(typography);
        let typography_sha256 = sha256_hex(stable_stringify(&typography_json).as_bytes());
        let render_text_spans_json = render_text_spans_value(&render_text_spans);
        let inline_boxes_json = inline_boxes_value(&inline_boxes);
        let semantics_value = semantics_json(&semantics);
        let mut render_options = PreparedRenderOptions::new();
        render_options.semantics = Some(&semantics_value);
        render_options.inline_boxes = Some(&inline_boxes_json);
        render_options.render_text_spans = Some(&render_text_spans_json);
        render_options.source_text = Some(&text);
        let rendered = match render_prepared_paragraph_artifact(
            &plan_json,
            &typography.locale,
            &mut render_options,
        ) {
            Ok(rendered) => rendered,
            Err(error) => {
                return match paragraph_capability_issue(&error.0) {
                    Some(issue) => Ok(unsupported_paragraph(&key, issue, Some(&error.0))),
                    None => Err(error),
                };
            }
        };

        Ok(Json::Obj(vec![
            ("status".to_string(), Json::str("prepared")),
            (
                "schema".to_string(),
                Json::Num(js_int_to_number(SNAPSHOT_SCHEMA)),
            ),
            ("layoutRevision".to_string(), Json::str(LAYOUT_REVISION)),
            ("renderRevision".to_string(), Json::str(RENDER_REVISION)),
            ("key".to_string(), Json::str(key)),
            ("sourceText".to_string(), Json::str(text.clone())),
            (
                "sourceSha256".to_string(),
                Json::str(sha256_hex(text.as_bytes())),
            ),
            (
                "sourceArtifactSha256".to_string(),
                Json::str(sha256_hex(
                    crate::snapshot_source::source_artifact_string(&text, &semantics).as_bytes(),
                )),
            ),
            ("semantics".to_string(), semantics_value),
            ("inlineBoxes".to_string(), inline_boxes_json),
            ("renderTextSpans".to_string(), render_text_spans_json),
            ("typography".to_string(), typography_json),
            (
                "renderFontFamilies".to_string(),
                Json::Arr(
                    render_font_families
                        .iter()
                        .map(|family| Json::str(family.clone()))
                        .collect(),
                ),
            ),
            ("typographySha256".to_string(), Json::str(typography_sha256)),
            ("maxWidthPx".to_string(), Json::Num(max_width_px)),
            ("fontEvidence".to_string(), evidence_json(&evidence)?),
            (
                "plan".to_string(),
                parse_json(&plan_json).map_err(|_| named("InvalidPlanJson"))?,
            ),
            ("html".to_string(), Json::str(rendered.html)),
            (
                "renderArtifactSha256".to_string(),
                Json::str(sha256_hex(stable_stringify(&rendered.artifact).as_bytes())),
            ),
        ]))
    }
}

/// The capture and engine phase of `prepare`: open the capture window,
/// gather the source boundary set, run the engine and read the evidence.
/// Every error here reaches the `paragraphCapabilityIssue` classifier.
type Captured = Result<(String, crate::session::FontEvidence), NamedError>;

fn capture(
    session: &FontSession,
    input: &PrepareInput,
    text: &str,
    typography: &SnapshotTypography,
    semantics: &[SemanticSpan],
    text_spans: &[TextSpanInput],
    inline_boxes: &[InlineBoxInput],
    max_width_px: f64,
) -> Captured {
    // One capture window per paragraph; engine callbacks reach it through
    // the thread-local lend, so a batch paragraph never sees another
    // paragraph's evidence.
    let mut evidence_window = crate::session::CaptureEvidence::new();
    let text_length = utf16_length(text);
    let mut boundaries: Vec<f64> = Vec::new();
    if let Some(Json::Arr(items)) = input.source_boundaries {
        for item in items {
            push_boundary(&mut boundaries, js_number_value(item));
        }
    }
    for span in semantics {
        push_boundary(&mut boundaries, js_int_to_number(span.start));
        push_boundary(&mut boundaries, js_int_to_number(span.end));
    }
    for span in text_spans {
        push_boundary(&mut boundaries, f64::from(span.start));
        push_boundary(&mut boundaries, f64::from(span.end));
    }
    for inline_box in inline_boxes {
        push_boundary(&mut boundaries, f64::from(inline_box.start));
        push_boundary(&mut boundaries, f64::from(inline_box.end));
    }
    let base_style = BoundaryStyle {
        font_families: typography.font_families.clone(),
        font_size_px: typography.font_size_px,
        font_weight: f64::from(typography.font_weight),
        italic: typography.italic,
        baseline_shift_px: Some(0.0),
    };
    let boundary_spans: Vec<BoundaryTextSpan> = text_spans
        .iter()
        .map(|span| BoundaryTextSpan {
            start: f64::from(span.start),
            end: f64::from(span.end),
            style: BoundaryStyle {
                font_families: span.families.clone(),
                font_size_px: span.font_size_px,
                font_weight: f64::from(span.font_weight),
                italic: span.italic,
                baseline_shift_px: Some(span.baseline_shift),
            },
        })
        .collect();
    let session_boundaries = session
        .source_boundaries(text, &base_style, &boundary_spans)
        .map_err(NamedError)?;
    for value in session_boundaries {
        push_boundary(&mut boundaries, value);
    }
    for value in &boundaries {
        if !is_safe_integer(*value) || *value < 0.0 || *value > f64::from(text_length) {
            return Err(named("InvalidSourceBoundary"));
        }
    }
    // The gate above passed every boundary as a safe integer, so partial_cmp
    // is total; Equal covers a NaN that cannot occur.
    boundaries.sort_by(|left, right| left.partial_cmp(right).unwrap_or(std::cmp::Ordering::Equal));

    let line_break_spans: Vec<LineBreakSpanInput> = semantics
        .iter()
        .filter(|span| {
            let tag = span.tag_name.to_lowercase();
            tag == "a" || tag == "code"
        })
        .map(|span| {
            // Offsets were validated against the text length; the error arm
            // keeps the conversion total.
            Ok(LineBreakSpanInput {
                start: i32::try_from(span.start)
                    .map_err(|_| named("InvalidSnapshotSemanticRange"))?,
                end: i32::try_from(span.end).map_err(|_| named("InvalidSnapshotSemanticRange"))?,
                policy: LineBreakPolicyCode::ProgressiveTechnical,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let request = ParagraphRequest {
        font_session_id: session.session_id.clone(),
        text: text.to_string(),
        max_width_px,
        font_families: typography.font_families.clone(),
        font_size_px: typography.font_size_px,
        line_height_px: typography.line_height_px,
        locale: typography.locale.clone(),
        font_weight: typography.font_weight,
        italic: typography.italic,
        first_line_indent_ic: typography.first_line_indent_ic,
        line_length_grid_enabled: typography.line_length_grid_enabled,
        source_boundaries: boundaries
            .iter()
            .map(|value| trunc_sat_i32(*value))
            .collect(),
        text_spans: text_spans.to_vec(),
        line_break_spans,
        inline_boxes: inline_boxes.to_vec(),
    };
    let plan_json = engine_call(session, &mut evidence_window, &request)?;
    let evidence = evidence_window.snapshot();
    if evidence.faces.is_empty() {
        return Err(named("MissingShapingFontEvidence"));
    }
    Ok((plan_json, evidence))
}

/// `runtime.precomputeParagraph`: the engine runs with the session and the
/// paragraph's capture window as its font backend. Without the linked
/// archive no paragraph can be prepared.
#[cfg(tiqian_engine_link)]
fn engine_call(
    session: &FontSession,
    evidence: &mut crate::session::CaptureEvidence,
    request: &ParagraphRequest,
) -> Result<String, NamedError> {
    crate::engine_bridge::precompute_paragraph(session, evidence, request).map_err(NamedError)
}

#[cfg(not(tiqian_engine_link))]
fn engine_call(
    _session: &FontSession,
    _evidence: &mut crate::session::CaptureEvidence,
    _request: &ParagraphRequest,
) -> Result<String, NamedError> {
    Err(named("PrecomputeEngineNotLinked"))
}

/// The catch of the js try blocks: a listed capability issue lowers to an
/// unsupported entry carrying the message as detail; anything else is a hard
/// error.
fn classify_paragraph<T>(
    key: &str,
    result: Result<T, NamedError>,
) -> Result<Result<T, Json>, NamedError> {
    match result {
        Ok(value) => Ok(Ok(value)),
        Err(error) => match paragraph_capability_issue(&error.0) {
            Some(issue) => Ok(Err(unsupported_paragraph(key, issue, Some(&error.0)))),
            None => Err(error),
        },
    }
}

/// `unsupportedParagraph(key, issue, error)`: detail only with a non-empty
/// message.
fn unsupported_paragraph(key: &str, issue: &str, detail: Option<&str>) -> Json {
    let mut fields = vec![
        ("status".to_string(), Json::str("unsupported")),
        ("key".to_string(), Json::str(key)),
        ("issue".to_string(), Json::str(issue)),
    ];
    if let Some(detail) = detail.filter(|detail| !detail.is_empty()) {
        fields.push(("detail".to_string(), Json::str(detail)));
    }
    Json::Obj(fields)
}

fn entry_status(entry: &Json) -> Option<&str> {
    let Json::Obj(fields) = entry else {
        return None;
    };
    match fields.iter().find(|(key, _)| key == "status") {
        Some((_, Json::Str(status))) => Some(status),
        _ => None,
    }
}

/// The wire typography of the prepared entry; `stableStringify` of this form
/// feeds `typographySha256`.
pub fn typography_value_json(typography: &SnapshotTypography) -> Json {
    Json::Obj(vec![
        (
            "fontFamilies".to_string(),
            Json::Arr(
                typography
                    .font_families
                    .iter()
                    .map(|family| Json::str(family.clone()))
                    .collect(),
            ),
        ),
        ("fontSizePx".to_string(), Json::Num(typography.font_size_px)),
        (
            "lineHeightPx".to_string(),
            Json::Num(typography.line_height_px),
        ),
        ("locale".to_string(), Json::str(typography.locale.clone())),
        (
            "fontWeight".to_string(),
            Json::Num(f64::from(typography.font_weight)),
        ),
        ("italic".to_string(), Json::Bool(typography.italic)),
        (
            "firstLineIndentIc".to_string(),
            Json::Num(typography.first_line_indent_ic),
        ),
        (
            "lineLengthGridEnabled".to_string(),
            Json::Bool(typography.line_length_grid_enabled),
        ),
        (
            "letterSpacingPx".to_string(),
            Json::Num(typography.letter_spacing_px),
        ),
        (
            "fontFeatureSettings".to_string(),
            Json::str(typography.font_feature_settings),
        ),
        (
            "fontVariationSettings".to_string(),
            Json::str(typography.font_variation_settings),
        ),
        (
            "fontVariantNumeric".to_string(),
            Json::str(typography.font_variant_numeric.clone()),
        ),
    ])
}

fn render_text_spans_value(spans: &[(i32, i32, Vec<String>)]) -> Json {
    Json::Arr(
        spans
            .iter()
            .map(|(start, end, families)| {
                Json::Obj(vec![
                    ("start".to_string(), Json::Num(f64::from(*start))),
                    ("end".to_string(), Json::Num(f64::from(*end))),
                    (
                        "fontFamilies".to_string(),
                        Json::Arr(
                            families
                                .iter()
                                .map(|family| Json::str(family.clone()))
                                .collect(),
                        ),
                    ),
                ])
            })
            .collect(),
    )
}

fn inline_boxes_value(inline_boxes: &[InlineBoxInput]) -> Json {
    Json::Arr(
        inline_boxes
            .iter()
            .map(|inline_box| {
                Json::Obj(vec![
                    ("start".to_string(), Json::Num(f64::from(inline_box.start))),
                    ("end".to_string(), Json::Num(f64::from(inline_box.end))),
                    (
                        "inlineStartPx".to_string(),
                        Json::Num(inline_box.inline_start),
                    ),
                    ("inlineEndPx".to_string(), Json::Num(inline_box.inline_end)),
                    (
                        "outerSpacing".to_string(),
                        Json::str(match inline_box.outer_spacing {
                            crate::paragraph::InlineBoxOuterSpacingCode::Narrow => "Narrow",
                            crate::paragraph::InlineBoxOuterSpacingCode::Source => "Source",
                        }),
                    ),
                ])
            })
            .collect::<Vec<_>>(),
    )
}

fn text_spans_raw(value: Option<&Json>) -> Result<Option<Vec<TextSpanRaw>>, NamedError> {
    let Some(value) = coalesce(value) else {
        return Ok(None);
    };
    let Json::Arr(items) = value else {
        return Err(named("InvalidSnapshotTextSpans"));
    };
    Ok(Some(
        items
            .iter()
            .map(|item| TextSpanRaw {
                start: number_member(item, "start"),
                end: number_member(item, "end"),
                font_families: match coalesce(member(item, "fontFamilies")) {
                    Some(Json::Arr(list)) => {
                        Some(list.iter().map(js_string_value).collect::<Vec<_>>())
                    }
                    _ => None,
                },
                font_size_px: number_member(item, "fontSizePx"),
                font_weight: number_member(item, "fontWeight"),
                italic: match coalesce(member(item, "italic")) {
                    Some(Json::Bool(value)) => Some(*value),
                    _ => None,
                },
                baseline_shift_px: number_member(item, "baselineShiftPx"),
            })
            .collect(),
    ))
}

fn inline_boxes_raw(value: Option<&Json>) -> Result<Option<Vec<InlineBoxRaw>>, NamedError> {
    let Some(value) = coalesce(value) else {
        return Ok(None);
    };
    let Json::Arr(items) = value else {
        return Err(named("InvalidSnapshotInlineBoxes"));
    };
    Ok(Some(
        items
            .iter()
            .map(|item| InlineBoxRaw {
                start: number_member(item, "start"),
                end: number_member(item, "end"),
                inline_start_px: number_member(item, "inlineStartPx"),
                inline_end_px: number_member(item, "inlineEndPx"),
                outer_spacing: coalesce(member(item, "outerSpacing")).map(js_string_value),
            })
            .collect(),
    ))
}

/// A member of a wire object, whatever its value.
/// The `??` step: absent and null both read as absent.
fn coalesce(value: Option<&Json>) -> Option<&Json> {
    value.filter(|value| !matches!(value, Json::Null))
}

/// `Number(member)`: present, non-null values coerce loosely.
fn number_member(value: &Json, name: &str) -> Option<f64> {
    coalesce(member(value, name)).map(js_number_value)
}

/// The js `Set` insert of the boundary union.
fn push_boundary(boundaries: &mut Vec<f64>, value: f64) {
    if !boundaries.contains(&value) {
        boundaries.push(value);
    }
}

/// `Number.isSafeInteger`.
fn is_safe_integer(value: f64) -> bool {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    value.fract() == 0.0 && value.abs() <= MAX_SAFE_INTEGER
}

fn named(name: &str) -> NamedError {
    NamedError(name.to_string())
}
