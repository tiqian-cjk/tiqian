//! Font session port of `createFontSession` in `precompute-fonts.js`
//! (ADR 0050 parity oracle): ordered face specs, per-call shape and metrics
//! with usage tracking, replay capture and evidence. The JS global backend
//! hands out integer handles into a registry; this port returns the values
//! directly, which is the surface the vtable protocol replays.

use crate::font_record::{FontFaceSpec, FontRecord, LoadRecordError};
use crate::font_record_cache::load_shared_record;
use crate::js_compat::{js_number_string, js_trim, trunc_sat_u32};
use crate::json::Json;
use crate::metrics::{resolve_metrics, select_metrics_face};
use crate::policy::normalize_base_features;
use crate::replay::{
    instance_axes, instance_id, metric_replay_key, normalized_replay_number, shape_replay_key,
};
use crate::selection::{render_families, select_face, select_shape_face};
use crate::shaping::{FontEngine, ShapeRecordResult};
use crate::source_boundaries::{
    source_boundaries_for_selected_face, BoundaryStyle, BoundaryTextSpan,
};

pub const BACKEND_REVISION: &str = "tiqian-shared-harfbuzz-v5";
pub const FONT_REPLAY_REVISION: &str = "tiqian-server-shaping-replay-v1";
const FAMILY_SEPARATOR: char = '\u{001f}';

/// Engine identity of the Rust stack; the JS session reports the wasm
/// HarfBuzz version here. The field is an exempt engine-identity output.
pub const HARFBUZZ_VERSION: &str = "harfrust-0.13.0";

/// Session-level failures; the Display strings match the JS throws.
#[derive(Debug, PartialEq)]
pub enum SessionError {
    MissingExplicitFontFaces,
    InvalidFontFaceSourceOrder {
        input_order: usize,
        source_order: String,
    },
    DuplicateFontFaceSourceOrder(u32),
    UnsupportedFontSessionBaseFeatures,
    Load(LoadRecordError),
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SessionError::MissingExplicitFontFaces => write!(f, "MissingExplicitFontFaces"),
            SessionError::InvalidFontFaceSourceOrder {
                input_order,
                source_order,
            } => {
                write!(
                    f,
                    "InvalidFontFaceSourceOrder:{}:{}",
                    input_order, source_order
                )
            }
            SessionError::DuplicateFontFaceSourceOrder(order) => {
                write!(f, "DuplicateFontFaceSourceOrder:{}", order)
            }
            SessionError::UnsupportedFontSessionBaseFeatures => {
                write!(f, "UnsupportedFontSessionBaseFeatures")
            }
            SessionError::Load(error) => write!(f, "{}", load_error_message(error)),
        }
    }
}

/// `loadRecord` error strings.
pub fn load_error_message(error: &LoadRecordError) -> String {
    match error {
        LoadRecordError::MissingFontFaceFamily => "MissingFontFaceFamily".to_string(),
        LoadRecordError::MissingPublicFontUrl(family) => {
            format!("MissingPublicFontUrl:{}", family)
        }
        LoadRecordError::UnsupportedFontCollection(family) => {
            format!("UnsupportedFontCollection:{}", family)
        }
        LoadRecordError::Woff2Decode(message) => format!("Woff2DecodeFailure:{}", message),
        LoadRecordError::UnsupportedFontFaceIndex { family, face_index } => {
            format!("UnsupportedFontFaceIndex:{}:{}", family, face_index)
        }
        LoadRecordError::InvalidOpenTypeFace(family) => format!("InvalidOpenTypeFace:{}", family),
        LoadRecordError::UnsupportedVariableFontAxes { family, axes } => {
            format!("UnsupportedVariableFontAxes:{}:{}", family, axes)
        }
        LoadRecordError::UnsupportedVariableFontMetrics(family) => {
            format!("UnsupportedVariableFontMetrics:{}", family)
        }
        LoadRecordError::InvalidFontFaceWeight => "InvalidFontFaceWeight".to_string(),
        LoadRecordError::UnsupportedFontFaceStyle { family, style } => {
            format!("UnsupportedFontFaceStyle:{}:{}", family, style)
        }
    }
}

/// One `@font-face` input with its optional explicit `sourceOrder`.
#[derive(Clone)]
pub struct SessionFaceSpec<'a> {
    pub spec: FontFaceSpec<'a>,
    pub source_order: Option<f64>,
}

pub struct SessionOptions {
    pub session_prefix: String,
    pub base_features: Option<Vec<String>>,
}

impl Default for SessionOptions {
    fn default() -> Self {
        SessionOptions {
            session_prefix: "tq-font".to_string(),
            base_features: None,
        }
    }
}

/// A loaded face as `session.faces` reports it.
pub struct FaceInfo {
    pub family: String,
    pub style: &'static str,
    pub weight: [f64; 2],
    pub unicode_range: String,
    pub public_url: String,
    pub source_sha256: String,
    pub sfnt_sha256: String,
    pub face_index: f64,
    pub source_order: u32,
    pub axis_tags: Vec<String>,
    pub local_names: Vec<String>,
}

/// One used face in `captureEvidence`: the probe and its coverage.
#[derive(Clone)]
pub struct FaceUsage {
    pub family: String,
    pub style: &'static str,
    pub weight: [f64; 2],
    pub unicode_range: String,
    pub public_url: String,
    pub source_sha256: String,
    pub sfnt_sha256: String,
    pub face_index: f64,
    pub source_order: u32,
    pub axes: Vec<(String, f64)>,
    pub local_names: Vec<String>,
    pub coverage_text: Vec<char>,
    pub probe_text: String,
    pub probe_advance_px: f64,
    pub probe_font_size_px: f64,
    pub probe_font_weight: f64,
    pub probe_italic: bool,
    pub probe_script: String,
    pub probe_language: String,
    pub probe_features: Vec<String>,
}

/// One captured shape replay (em geometry, canonicalized).
#[derive(Clone)]
pub struct ShapeReplay {
    pub key: String,
    pub face_id: String,
    pub font_instance_id: String,
    pub script: String,
    pub features: Vec<String>,
    pub unsafe_break_count: usize,
    pub advance_em: Option<f64>,
    pub glyphs: Vec<ShapeReplayGlyph>,
}

#[derive(Clone)]
pub struct ShapeReplayGlyph {
    pub id: u32,
    pub advance_em: Option<f64>,
    pub x_em: Option<f64>,
    pub y_em: Option<f64>,
    pub bounds_em: Option<[Option<f64>; 4]>,
}

#[derive(Clone)]
pub struct MetricReplay {
    pub key: String,
    pub values_em: [Option<f64>; 5],
}

pub struct FontEvidence {
    pub backend_revision: &'static str,
    pub harfbuzz_version: &'static str,
    pub faces: Vec<FaceUsage>,
    pub replay_shapes: Vec<ShapeReplay>,
    pub replay_metrics: Vec<MetricReplay>,
}

/// The shape call inputs, mirroring the global backend's `shape(...)`.
pub struct ShapeInput<'a> {
    pub display_text: &'a str,
    pub serialized_families: &'a str,
    pub font_size: f64,
    pub font_weight: f64,
    pub italic: bool,
    pub locale: &'a str,
    pub role: Option<&'a str>,
    pub source_text: Option<&'a str>,
}

/// The metrics call inputs, mirroring `metrics(...)`.
pub struct MetricsInput<'a> {
    pub serialized_families: &'a str,
    pub font_size: f64,
    pub font_weight: f64,
    pub italic: bool,
    pub role: Option<&'a str>,
    pub face_selection_text: Option<&'a str>,
}

/// Global session counter backing `${prefix}-${nextSessionId++}`.
static NEXT_SESSION_ID: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(1);

pub struct FontSession {
    pub session_id: String,
    pub backend_revision: &'static str,
    pub harfbuzz_version: &'static str,
    records: Vec<std::sync::Arc<FontRecord>>,
    base_features: Vec<String>,
    /// Evidence of the standalone session lane; `begin_capture` clears it.
    /// The batch lanes keep one [`CaptureEvidence`] per paragraph instead,
    /// so concurrent paragraphs never mix their capture windows.
    evidence: std::sync::Mutex<CaptureEvidence>,
    /// Value cache keyed by metric selection. Every write stores the
    /// deterministic resolution of the same key, so the batch lanes may
    /// share it across workers.
    metric_cache: std::sync::Mutex<std::collections::HashMap<String, [f64; 5]>>,
}

/// One capture window: `beginCapture` clears it and every shape and metrics
/// call of the window records into it. A batch paragraph owns one for the
/// duration of its engine call.
pub struct CaptureEvidence {
    /// Insertion-ordered like the JS `Map`s; usage entries carry their key.
    used: Vec<(String, FaceUsage)>,
    replay_shapes: Vec<ShapeReplay>,
    replay_shape_keys: std::collections::HashSet<String>,
    replay_metrics: Vec<MetricReplay>,
    replay_metric_keys: std::collections::HashSet<String>,
}

impl CaptureEvidence {
    pub fn new() -> Self {
        CaptureEvidence {
            used: Vec::new(),
            replay_shapes: Vec::new(),
            replay_shape_keys: std::collections::HashSet::new(),
            replay_metrics: Vec::new(),
            replay_metric_keys: std::collections::HashSet::new(),
        }
    }

    fn clear(&mut self) {
        self.used.clear();
        self.replay_shapes.clear();
        self.replay_shape_keys.clear();
        self.replay_metrics.clear();
        self.replay_metric_keys.clear();
    }

    /// `captureEvidence`: the snapshot of the capture window.
    pub fn snapshot(&self) -> FontEvidence {
        FontEvidence {
            backend_revision: BACKEND_REVISION,
            harfbuzz_version: HARFBUZZ_VERSION,
            faces: self.used.iter().map(|(_, usage)| usage.clone()).collect(),
            replay_shapes: self.replay_shapes.clone(),
            replay_metrics: self.replay_metrics.clone(),
        }
    }

    /// Stores a shape replay when the key is new and the size gate passes; a
    /// rejected size leaves the key uncaptured, the way the JS early return
    /// does.
    fn store_shape_replay(&mut self, key: String, mut entry: ShapeReplay, font_size: f64) {
        if self.replay_shape_keys.contains(&key) {
            return;
        }
        if !font_size.is_finite() || font_size <= 0.0 {
            return;
        }
        self.replay_shape_keys.insert(key.clone());
        entry.key = key;
        self.replay_shapes.push(entry);
    }

    fn capture_metric_replay(&mut self, input: &MetricsInput, result: &[f64; 5]) {
        let key = metric_replay_key(
            input.serialized_families,
            input.font_weight,
            input.italic,
            input.role,
            input.face_selection_text,
        );
        if self.replay_metric_keys.contains(&key) {
            return;
        }
        if !input.font_size.is_finite() || input.font_size <= 0.0 {
            return;
        }
        let font_size = input.font_size;
        self.replay_metric_keys.insert(key.clone());
        self.replay_metrics.push(MetricReplay {
            key,
            values_em: result.map(|value| normalized_replay_number(value, font_size)),
        });
    }
}

impl Default for CaptureEvidence {
    fn default() -> Self {
        CaptureEvidence::new()
    }
}

/// `orderedFaceSpecs`: resolve `sourceOrder` (defaulting to the input
/// position), validate, dedupe, sort by (sourceOrder, inputOrder). Returns
/// the processing order as input indices with their resolved orders.
fn ordered_face_specs(specs: &[SessionFaceSpec]) -> Result<Vec<(usize, u32)>, SessionError> {
    let mut seen = std::collections::HashSet::new();
    let mut resolved: Vec<(usize, u32)> = Vec::new();
    // The js default sourceOrder is the input index held as a Number.
    let mut input_order_number = 0.0_f64;
    for (input_order, entry) in specs.iter().enumerate() {
        let source_order = entry.source_order.unwrap_or(input_order_number);
        let is_safe_integer =
            source_order.fract() == 0.0 && source_order.abs() <= 9_007_199_254_740_992.0;
        if !is_safe_integer || source_order < 0.0 {
            return Err(SessionError::InvalidFontFaceSourceOrder {
                input_order,
                source_order: js_number_string(source_order),
            });
        }
        let order = trunc_sat_u32(source_order);
        if !seen.insert(order) {
            return Err(SessionError::DuplicateFontFaceSourceOrder(order));
        }
        resolved.push((input_order, order));
        input_order_number += 1.0;
    }
    resolved.sort_by(|left, right| left.1.cmp(&right.1).then_with(|| left.0.cmp(&right.0)));
    Ok(resolved)
}

/// `createFontSession`.
pub fn create_font_session(
    specs: Vec<SessionFaceSpec>,
    options: SessionOptions,
) -> Result<FontSession, SessionError> {
    if specs.is_empty() {
        return Err(SessionError::MissingExplicitFontFaces);
    }
    let ordered = ordered_face_specs(&specs)?;
    // The records spread over the configured workers; SharedFontRecordCache
    // serves already-decoded faces, and the first load error by processing
    // order wins, the sequential loop's `?` order.
    let workers = crate::parallel::worker_count();
    let records = crate::parallel::indexed_collect(ordered.len(), workers, |position| {
        let (input_index, order) = ordered[position];
        let mut spec = specs[input_index].spec.clone();
        spec.source_order = order;
        load_shared_record(&spec).map_err(SessionError::Load)
    })?;
    let prefix = {
        let trimmed = js_trim(&options.session_prefix);
        if trimmed.is_empty() {
            "tq-font"
        } else {
            trimmed
        }
    };
    // The JS reads the counter before the session literal normalizes
    // baseFeatures, so a session rejected for UnsupportedFontSessionBaseFeatures
    // still consumes an id; later session numbers reflect that.
    let session_id = format!(
        "{}-{}",
        prefix,
        NEXT_SESSION_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst)
    );
    let base_features = normalize_base_features(options.base_features.as_deref())
        .map_err(|_| SessionError::UnsupportedFontSessionBaseFeatures)?;
    Ok(FontSession {
        session_id,
        backend_revision: BACKEND_REVISION,
        harfbuzz_version: HARFBUZZ_VERSION,
        records,
        base_features,
        evidence: std::sync::Mutex::new(CaptureEvidence::new()),
        metric_cache: std::sync::Mutex::new(std::collections::HashMap::new()),
    })
}

impl FontSession {
    /// `session.faces`.
    pub fn faces(&self) -> Vec<FaceInfo> {
        self.records
            .iter()
            .map(|record| {
                let mut axis_tags: Vec<String> = record
                    .axis_infos
                    .iter()
                    .map(|axis| axis.tag.clone())
                    .collect();
                // JS `.sort()` compares UTF-16 code units.
                axis_tags.sort_by(|left, right| crate::js_compat::cmp_utf16(left, right));
                FaceInfo {
                    family: record.family.clone(),
                    style: record.style,
                    weight: record.weight_range,
                    unicode_range: record.unicode_range.clone(),
                    public_url: record.public_url.clone(),
                    source_sha256: record.source_sha256.clone(),
                    sfnt_sha256: record.sfnt_sha256.clone(),
                    face_index: record.face_index,
                    source_order: record.source_order,
                    axis_tags,
                    local_names: record.local_names.clone(),
                }
            })
            .collect()
    }

    pub fn records(&self) -> &[std::sync::Arc<FontRecord>] {
        &self.records
    }

    /// `session.renderFamilies`.
    pub fn render_families(&self, requested: &[String]) -> Result<Vec<String>, String> {
        render_families(&self.records, requested)
    }

    /// `session.sourceBoundaries(text, baseStyle, textSpans)`: exact-face run
    /// boundaries over the session's records, keyed on `faceId`.
    pub fn source_boundaries(
        &self,
        text: &str,
        base_style: &BoundaryStyle,
        spans: &[BoundaryTextSpan],
    ) -> Result<Vec<f64>, String> {
        source_boundaries_for_selected_face(text, base_style, spans, |style, point| {
            let record = select_face(
                &self.records,
                &style.font_families,
                style.font_weight,
                style.italic,
                &[point],
            )?;
            Ok(record.face_id.clone())
        })
    }

    /// `beginCapture`.
    pub fn begin_capture(&self) {
        crate::parallel::recover(self.evidence.lock()).clear();
    }

    /// `close`.
    pub fn close(&self) {
        self.begin_capture();
        crate::parallel::recover(self.metric_cache.lock()).clear();
    }

    /// The `shape(...)` backend call of the standalone session lane; the
    /// evidence lock serializes the window the way the js single thread did.
    pub fn shape(&self, input: &ShapeInput) -> Result<ShapeRecordResult, String> {
        let mut evidence = crate::parallel::recover(self.evidence.lock());
        self.shape_into(&mut evidence, input)
    }

    /// The shape call recording into an explicit capture window. The engine
    /// callbacks of a batch paragraph pass their per-paragraph window here.
    pub fn shape_into(
        &self,
        evidence: &mut CaptureEvidence,
        input: &ShapeInput,
    ) -> Result<ShapeRecordResult, String> {
        let families = split_families(input.serialized_families);
        let display_chars: Vec<char> = input.display_text.chars().collect();
        let source_text = input.source_text.unwrap_or(input.display_text);
        let source_chars: Vec<char> = source_text.chars().collect();
        let (record, display_covered) = select_shape_face(
            &self.records,
            &families,
            input.font_weight,
            input.italic,
            &display_chars,
            &source_chars,
        )?;
        let engine = FontEngine::new(record, input.font_weight).map_err(|error| error.0)?;
        let mut result = engine
            .shape_record(
                input.display_text,
                input.font_size,
                input.font_weight,
                input.locale,
                input.role,
                &self.base_features,
            )
            .map_err(|error| error.0)?;
        if !display_covered {
            // The exact CSS face contract rejected the display codepoint even
            // if the raw sfnt happens to retain an unreachable glyph; the
            // probe reports missing so the common engine re-shapes the source.
            for glyph in &mut result.glyphs {
                glyph.id = 0;
            }
        }
        let missing_glyph = result.glyphs.iter().any(|glyph| glyph.id == 0);
        if missing_glyph && source_text == input.display_text {
            return Err(format!(
                "MissingGlyph:face={};text={}",
                record.face_id,
                Json::str(input.display_text).render()
            ));
        }
        // Everything derived from `record` is built before the mutable
        // session updates; the JS order is throw check, replay capture,
        // then usage.
        let replay_key = shape_replay_key(
            input.display_text,
            input.serialized_families,
            input.font_weight,
            input.italic,
            input.locale,
            input.role,
            input.source_text.unwrap_or(input.display_text),
        );
        let replay_entry = build_shape_replay(input, &result, record);
        let key = usage_key(record, input, &result);
        let usage = FaceUsage {
            family: record.family.clone(),
            style: record.style,
            weight: record.weight_range,
            unicode_range: record.unicode_range.clone(),
            public_url: record.public_url.clone(),
            source_sha256: record.source_sha256.clone(),
            sfnt_sha256: record.sfnt_sha256.clone(),
            face_index: record.face_index,
            source_order: record.source_order,
            axes: instance_axes(record, input.font_weight),
            local_names: record.local_names.clone(),
            coverage_text: {
                // The js seeds `coverageText` as a Set of the display text,
                // so a repeated code point counts once even on first use.
                let mut seen = std::collections::HashSet::new();
                display_chars
                    .iter()
                    .copied()
                    .filter(|point| seen.insert(*point))
                    .collect()
            },
            probe_text: input.display_text.to_string(),
            probe_advance_px: result.advance,
            probe_font_size_px: input.font_size,
            probe_font_weight: input.font_weight,
            probe_italic: input.italic,
            probe_script: result.script.clone(),
            probe_language: input.locale.to_string(),
            probe_features: result.probe_features.clone(),
        };
        evidence.store_shape_replay(replay_key, replay_entry, input.font_size);
        if missing_glyph {
            return Ok(result);
        }
        if let Some((_, existing)) = evidence
            .used
            .iter_mut()
            .find(|(candidate, _)| *candidate == key)
        {
            let mut seen: std::collections::HashSet<char> =
                existing.coverage_text.iter().copied().collect();
            for point in &display_chars {
                if seen.insert(*point) {
                    existing.coverage_text.push(*point);
                }
            }
        } else {
            evidence.used.push((key, usage));
        }
        Ok(result)
    }

    /// The `metrics(...)` backend call of the standalone session lane.
    pub fn metrics(&self, input: &MetricsInput) -> Result<[f64; 5], String> {
        let mut evidence = crate::parallel::recover(self.evidence.lock());
        self.metrics_into(&mut evidence, input)
    }

    /// The metrics call recording into an explicit capture window. The cache
    /// lock spans the get-or-compute step, so concurrent batch paragraphs
    /// resolve one selection once, the value the sequential loop stored.
    pub fn metrics_into(
        &self,
        evidence: &mut CaptureEvidence,
        input: &MetricsInput,
    ) -> Result<[f64; 5], String> {
        let families = split_families(input.serialized_families);
        let selection = select_metrics_face(
            &self.records,
            &families,
            input.font_size,
            input.font_weight,
            input.italic,
            input.face_selection_text,
        )?;
        let mut cache = crate::parallel::recover(self.metric_cache.lock());
        let result = match cache.get(&selection.cache_key) {
            Some(cached) => *cached,
            None => {
                let computed = resolve_metrics(
                    selection.record,
                    &self.records,
                    input.font_size,
                    input.font_weight,
                )?;
                cache.insert(selection.cache_key.clone(), computed);
                computed
            }
        };
        drop(cache);
        evidence.capture_metric_replay(input, &result);
        Ok(result)
    }

    /// `captureEvidence`.
    pub fn capture_evidence(&self) -> FontEvidence {
        crate::parallel::recover(self.evidence.lock()).snapshot()
    }
}

fn split_families(serialized: &str) -> Vec<String> {
    serialized
        .split(FAMILY_SEPARATOR)
        .filter(|family| !family.is_empty())
        .map(|family| family.to_string())
        .collect()
}

/// The `captureShapeReplay` entry: em geometry canonicalized to 12 decimals.
fn build_shape_replay(
    input: &ShapeInput,
    result: &ShapeRecordResult,
    record: &FontRecord,
) -> ShapeReplay {
    let font_size = input.font_size;
    ShapeReplay {
        key: String::new(),
        face_id: record.face_id.clone(),
        font_instance_id: instance_id(record, input.font_weight),
        script: result.script.clone(),
        features: result.features.clone(),
        unsafe_break_count: result.unsafe_break_count,
        advance_em: normalized_replay_number(result.advance, font_size),
        glyphs: result
            .glyphs
            .iter()
            .map(|glyph| ShapeReplayGlyph {
                id: glyph.id,
                advance_em: normalized_replay_number(glyph.advance, font_size),
                x_em: normalized_replay_number(glyph.x, font_size),
                y_em: normalized_replay_number(glyph.y, font_size),
                bounds_em: glyph
                    .bounds
                    .as_ref()
                    .map(|bounds| bounds.map(|value| normalized_replay_number(value, font_size))),
            })
            .collect(),
    }
}

fn usage_key(record: &FontRecord, input: &ShapeInput, result: &ShapeRecordResult) -> String {
    [
        instance_id(record, input.font_weight),
        record.family.clone(),
        record.style.to_string(),
        format!(
            "{}-{}",
            js_number_string(record.weight_range[0]),
            js_number_string(record.weight_range[1])
        ),
        record.unicode_range.clone(),
        record.public_url.clone(),
        result.probe_features.join(","),
    ]
    .join("|")
}
