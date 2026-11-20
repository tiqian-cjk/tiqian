//! Prepared DOM lowering of `renderPreparedParagraphArtifact` in
//! `prepared-dom.js` (ADR 0050). The js module stays the browser renderer and
//! the parity oracle; this port serves the Node orchestration with the same
//! html bytes and the same artifact tree.
//!
//! Damage to plan schema or revisions reports
//! `UnsupportedPreparedLayoutRevision`, damage to geometry reports
//! `InvalidPreparedParagraphGeometry`. The strict plan reader also funnels
//! malformed inner plan fields into the geometry error where js would render
//! undefined or throw a raw TypeError; the engine never emits those plans.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::js_compat::{
    cmp_utf16, js_int_to_number, js_max, js_min, js_number_string, js_trim, trunc_sat_i64,
};
use crate::json::{json_string, Json};
use crate::paragraph::utf16_length;
use crate::plan::{
    Plan, PlanBopomofo, PlanBopomofoPlacement, PlanCell, PlanEndReason, PlanInlineEdge, PlanLine,
    PlanRuby,
};
use crate::snapshot_source::{
    js_number_value, js_string_value, normalize_live_semantics, normalize_snapshot_semantics,
    LiveSemanticSpan, SemanticSpan,
};

const SPACING_EPSILON: f64 = 0.01;
// FloatDustSpacingZeroing: justification can leave real stretch of a few
// thousandths of a pixel per cluster boundary; zeroing those breaks the line
// flow identity once they accumulate. Only arithmetic dust zeroes here.
// SPACING_EPSILON still gates merge tolerance and carrier visibility.
const SPACING_DUST_EPSILON: f64 = 1e-6;
const RENDER_FLOW_EPSILON_PX: f64 = 0.01;
const LIVE_SEMANTIC_INDEX_ATTRIBUTE: &str = "data-tq-live-semantic-index";
/// Fallback annotation ascent ratio, mirroring the Kotlin no-metrics branch.
const RUBY_ASCENT_RATIO: f64 = 0.8;
const BOPOMOFO_LANG: &str = "zh-Hant-TW";
const BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE: f64 = 0.82;
const BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR: f64 = 0.404;
const BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD: f64 = 0.446;
const BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR: f64 = 0.644;
const BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD: f64 = 0.682;
const LINE_THICKNESS_EM: f64 = 0.08;
const WAVY_HALF_WAVE_EM: f64 = 0.2;
const WAVY_AMPLITUDE_EM: f64 = 0.06;
const WAVY_ENDPOINT_EPSILON_PX: f64 = 0.01;

/// One source element of the live replay path; the tag name carries the
/// validation the js renderer reads off the DOM node. Host capability checks
/// (`cloneNode`) stay with the js caller that owns the elements.
pub struct LiveSemanticSource {
    pub tag_name: String,
}

/// Options of `render_prepared_paragraph_artifact`. `None` and JSON null both
/// match the `??` defaults of the js signature.
pub struct PreparedRenderOptions<'a> {
    pub semantic_replay: Option<&'a str>,
    pub source_text: Option<&'a str>,
    pub semantics: Option<&'a Json>,
    pub live_semantic_elements: &'a [LiveSemanticSource],
    pub render_text_spans: Option<&'a Json>,
    pub inline_boxes: Option<&'a Json>,
    pub style_class_for: Option<&'a mut dyn FnMut(&str) -> String>,
    /// `options.cjkStrongSemantics`: entries `{start, end, weight}` matched by
    /// exact span equality; a snapshot strong span carrying an entry replays
    /// `data-tq-cjk-emphasis` and its font-weight.
    pub cjk_strong_semantics: Option<&'a Json>,
    /// `options.emphasisDotColor`: resolves an emphasis dot color from the
    /// dot's `clusterRangeStart`; null reads as currentColor like the js
    /// `?? null` default. Absent keeps the snapshot default.
    pub emphasis_dot_color: Option<&'a mut dyn FnMut(Option<f64>) -> Option<String>>,
}

impl<'a> PreparedRenderOptions<'a> {
    pub fn new() -> Self {
        PreparedRenderOptions {
            semantic_replay: None,
            source_text: None,
            semantics: None,
            live_semantic_elements: &[],
            render_text_spans: None,
            inline_boxes: None,
            style_class_for: None,
            cjk_strong_semantics: None,
            emphasis_dot_color: None,
        }
    }
}

impl Default for PreparedRenderOptions<'_> {
    fn default() -> Self {
        Self::new()
    }
}

/// The lowered paragraph: html for the snapshot template, the canonical
/// artifact tree for the render hash, and the counts the host checks.
pub struct PreparedParagraphRender {
    pub html: String,
    pub artifact: Json,
    pub live_semantic_count: usize,
    pub marker_count: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SpacingKind {
    None,
    Letter,
    Overlap,
    TrailingLetter,
}

#[derive(Clone)]
struct Spacing {
    kind: SpacingKind,
    px: f64,
}

struct CellRun {
    range_start: i32,
    range_end: i32,
    source: String,
    display: String,
    draw_x: f64,
    natural_width: f64,
    shaping_boundary: bool,
    open_type_features: Vec<String>,
    render_font_families: Vec<String>,
    trailing_gap: f64,
    spacing: Spacing,
    semantic_path: Vec<usize>,
    semantic_signature: String,
    dash_strategy: Option<String>,
    shaping_language: Option<String>,
    resolved_face: Option<String>,
    glyph_ids: Option<String>,
    shaping_evidence: Option<String>,
    punctuation_ink_floor: Option<f64>,
    punctuation_body_width: Option<f64>,
    evidence_render_font_family: Option<String>,
    /// `cell.inlineObject`: present on inline-object placeholder cells.
    inline_object_advance: Option<f64>,
    /// The flow slack the bopomofo annotation occupies when the base cell ends
    /// the line; zero when no annotation covers the cell.
    bopomofo_advance_width: f64,
    style_delta: Option<Json>,
    italic_effect: bool,
    style_signature: String,
    punctuation_signature: String,
}

/// The JS oracle's ordered line children: runs merge as before, but
/// inline-object cells and annotation boundaries flush the pending run so DOM
/// order is preserved. Ruby rides absolute positioning and takes no flow.
enum LineChild {
    Run(CellRun),
    InlineObject {
        cell: CellRun,
        carrier_margin: f64,
        semantic_path: Vec<usize>,
    },
    Ruby {
        ruby: PlanRuby,
        line_top: f64,
        semantic_path: Vec<usize>,
    },
    Bopomofo {
        z: PlanBopomofo,
        width: f64,
        line_top: f64,
        line_height: f64,
        semantic_path: Vec<usize>,
    },
}

impl LineChild {
    /// `child.run.naturalWidth + trailingGap`, `child.cell.naturalWidth +
    /// carrierMargin`, `child.width`, or zero for ruby.
    fn flow_width(&self) -> f64 {
        match self {
            LineChild::Run(run) => run.natural_width + run.trailing_gap,
            LineChild::InlineObject {
                cell,
                carrier_margin,
                ..
            } => {
                cell.natural_width
                    + if carrier_margin.abs() >= SPACING_EPSILON {
                        *carrier_margin
                    } else {
                        0.0
                    }
            }
            LineChild::Bopomofo { width, .. } => *width,
            LineChild::Ruby { .. } => 0.0,
        }
    }

    fn semantic_path(&self) -> &[usize] {
        match self {
            LineChild::Run(run) => &run.semantic_path,
            LineChild::InlineObject { semantic_path, .. }
            | LineChild::Ruby { semantic_path, .. }
            | LineChild::Bopomofo { semantic_path, .. } => semantic_path,
        }
    }
}

enum NodeDraft {
    Element {
        tag: String,
        entries: Vec<(String, Option<String>)>,
        children: Vec<usize>,
        void_element: bool,
    },
    Text(String),
}

const ROOT: usize = usize::MAX;

/// The draft tree of one lowering pass; indices address `nodes`, `ROOT`
/// addresses the paragraph root.
struct Draft {
    nodes: Vec<NodeDraft>,
    root_children: Vec<usize>,
    active_path: Vec<usize>,
    active_containers: Vec<usize>,
}

impl Draft {
    fn new() -> Self {
        Draft {
            nodes: Vec::new(),
            root_children: Vec::new(),
            active_path: Vec::new(),
            active_containers: Vec::new(),
        }
    }

    fn push_element(
        &mut self,
        tag: &str,
        entries: Vec<(String, Option<String>)>,
        void_element: bool,
    ) -> usize {
        self.nodes.push(NodeDraft::Element {
            tag: tag.to_string(),
            entries,
            children: Vec::new(),
            void_element,
        });
        self.nodes.len() - 1
    }

    fn push_text(&mut self, text: &str) -> usize {
        self.nodes.push(NodeDraft::Text(text.to_string()));
        self.nodes.len() - 1
    }

    fn append_child(&mut self, container: usize, child: usize) {
        if container == ROOT {
            self.root_children.push(child);
        } else {
            match &mut self.nodes[container] {
                NodeDraft::Element { children, .. } => children.push(child),
                NodeDraft::Text(_) => unreachable!("text nodes hold no children"),
            }
        }
    }

    /// The container `semanticContainerFor(activeSemantics)` resolves to: the
    /// deepest wrapper still open.
    fn current_container(&self) -> usize {
        self.active_containers.last().copied().unwrap_or(ROOT)
    }

    /// `semanticContainerFor`: closes wrappers down to the longest common
    /// prefix of the active path, then nests one wrapper per deeper span.
    fn semantic_container_for(
        &mut self,
        path: &[usize],
        wrapper: impl Fn(usize) -> (String, Vec<(String, Option<String>)>),
    ) -> usize {
        let common = self
            .active_path
            .iter()
            .zip(path)
            .take_while(|(active, next)| active == next)
            .count();
        self.active_path.truncate(common);
        self.active_containers.truncate(common);
        let mut container = self.active_containers.last().copied().unwrap_or(ROOT);
        for (depth, span_index) in path[common..].iter().enumerate() {
            let (tag, entries) = wrapper(*span_index);
            let child = self.push_element(&tag, entries, false);
            self.append_child(container, child);
            self.active_path.push(path[common + depth]);
            self.active_containers.push(child);
            container = child;
        }
        container
    }

    fn html(&self) -> String {
        let mut out = String::new();
        for child in &self.root_children {
            self.write_html(*child, &mut out);
        }
        out
    }

    fn write_html(&self, node: usize, out: &mut String) {
        match &self.nodes[node] {
            NodeDraft::Text(text) => out.push_str(&escape_text(text)),
            NodeDraft::Element {
                tag,
                entries,
                children,
                void_element,
            } => {
                out.push('<');
                out.push_str(tag);
                let serialized = serialize_entries(entries);
                if !serialized.is_empty() {
                    out.push(' ');
                    out.push_str(&serialized);
                }
                out.push('>');
                if !*void_element {
                    for child in children {
                        self.write_html(*child, out);
                    }
                    out.push_str("</");
                    out.push_str(tag);
                    out.push('>');
                }
            }
        }
    }

    fn artifact(&self) -> Json {
        Json::Arr(
            self.root_children
                .iter()
                .map(|child| self.artifact_of(*child))
                .collect(),
        )
    }

    fn artifact_of(&self, node: usize) -> Json {
        match &self.nodes[node] {
            NodeDraft::Text(text) => Json::Arr(vec![Json::str("#"), Json::str(text.clone())]),
            NodeDraft::Element {
                tag,
                entries,
                children,
                ..
            } => Json::Arr(vec![
                Json::str(tag.clone()),
                entries_json(entries),
                Json::Arr(
                    children
                        .iter()
                        .map(|child| self.artifact_of(*child))
                        .collect(),
                ),
            ]),
        }
    }
}

/// `escapeText` and `escapeAttribute` of the js module.
pub fn escape_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

pub fn escape_attribute(value: &str) -> String {
    escape_text(value).replace('"', "&quot;")
}

/// `cssString`: a double-quoted CSS string.
pub fn css_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

/// `px`: canonical pixel length, `toFixed(5)` then `Number()` back to a js
/// number string.
pub fn px(value: f64) -> String {
    let normalized = if value.abs() < 0.000001 { 0.0 } else { value };
    let number: f64 = js_to_fixed5(normalized).parse().unwrap_or(0.0);
    format!("{}px", js_number_string(number))
}

/// `Number.prototype.toFixed(5)`: exact decimal expansion with ties resolved
/// to the larger integer, the ECMAScript rule. Dyadic ties such as 1/64
/// round up where half-even formatting would round down.
fn js_to_fixed5(value: f64) -> String {
    if value == 0.0 {
        return "0.00000".to_string();
    }
    let negative = value < 0.0;
    let magnitude = value.abs();
    let raw = magnitude.to_bits();
    // The sign bit is clear after abs, so reading the same bytes as i64 keeps
    // the field extraction in the signed type the arithmetic uses.
    let bits = i64::from_ne_bytes(raw.to_ne_bytes());
    let biased = (bits >> 52) & 0x7ff;
    let exponent = biased - 1075;
    let mantissa = if biased == 0 {
        bits & 0xf_ffff_ffff_ffff
    } else {
        (bits & 0xf_ffff_ffff_ffff) | 0x10_0000_0000_0000
    };
    // The scaled value is the dyadic rational mantissa * 5^5 over
    // 2^(-exponent - 5); round it to an integer with ties toward the larger
    // integer.
    let signed_scaled = i128::from(mantissa) * 3125;
    let power = exponent + 5;
    let n: i128 = if power >= 0 {
        if power > 40 {
            i128::MAX / 4
        } else {
            signed_scaled << power
        }
    } else {
        let d = -power;
        if d >= 120 {
            0
        } else {
            let divisor = 1i128 << d;
            let quotient = signed_scaled.div_euclid(divisor);
            let remainder = signed_scaled.rem_euclid(divisor);
            if 2 * remainder >= divisor {
                quotient + 1
            } else {
                quotient
            }
        }
    };
    let sign = if negative && n > 0 { "-" } else { "" };
    let digits = n.to_string();
    if digits.len() <= 5 {
        format!("{sign}0.{:0>5}", digits)
    } else {
        let split = digits.len() - 5;
        format!("{sign}{}.{}", &digits[..split], &digits[split..])
    }
}

/// `applyDynamicStyles`: fold dynamic declarations into a generated class or
/// an inline style attribute.
fn apply_dynamic_styles(
    attributes: &mut Vec<(String, Option<String>)>,
    styles: &[String],
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) {
    if styles.is_empty() {
        return;
    }
    let declaration = styles.join(";");
    if let Some(callback) = style_class_for.as_deref_mut() {
        let generated = callback(&declaration);
        match attributes.iter_mut().find(|(name, _)| name == "class") {
            Some((_, Some(existing))) => {
                *existing = format!("{existing} {generated}");
            }
            Some((_, value)) => *value = Some(generated),
            None => attributes.push(("class".to_string(), Some(generated))),
        }
    } else {
        attributes.push(("style".to_string(), Some(declaration)));
    }
}

/// `renderedElement`/`renderedContainer` entry serialization: drop null
/// values, sort by name, empty values render bare.
fn serialize_entries(entries: &[(String, Option<String>)]) -> String {
    sorted_entries(entries)
        .map(|(name, value)| {
            if value.is_empty() {
                name.to_string()
            } else {
                format!("{name}=\"{}\"", escape_attribute(value))
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn entries_json(entries: &[(String, Option<String>)]) -> Json {
    Json::Arr(
        sorted_entries(entries)
            .map(|(name, value)| Json::Arr(vec![Json::str(name), Json::str(value)]))
            .collect(),
    )
}

fn sorted_entries(entries: &[(String, Option<String>)]) -> impl Iterator<Item = (&str, &str)> {
    let mut pairs: Vec<(&str, &str)> = entries
        .iter()
        .filter_map(|(name, value)| value.as_ref().map(|value| (name.as_str(), value.as_str())))
        .collect();
    pairs.sort_by(|left, right| cmp_utf16(left.0, right.0));
    pairs.into_iter()
}

/// Object-assignment semantics for attribute entries: a key already present
/// keeps its position and takes the new value; a new key appends.
fn set_attribute(entries: &mut Vec<(String, Option<String>)>, name: &str, value: Option<String>) {
    match entries.iter_mut().find(|(existing, _)| existing == name) {
        Some((_, slot)) => *slot = value,
        None => entries.push((name.to_string(), value)),
    }
}

/// The semantic replay flavors with their per-flavor span shapes.
enum Semantics {
    Snapshot(Vec<SemanticSpan>),
    Live(Vec<LiveSemanticSpan>),
}

impl Semantics {
    /// `semanticSpansFor`: spans containing the whole range, in sorted order.
    fn path_for(&self, range_start: i32, range_end: i32) -> Vec<usize> {
        let (start, end) = (i64::from(range_start), i64::from(range_end));
        self.indices(|span_start, span_end| start >= span_start && end <= span_end)
    }

    /// `semanticSpansCrossing`: spans strictly containing the offset.
    fn crossing(&self, offset: i32) -> Vec<usize> {
        let offset = i64::from(offset);
        self.indices(|span_start, span_end| offset > span_start && offset < span_end)
    }

    fn indices(&self, covers: impl Fn(i64, i64) -> bool) -> Vec<usize> {
        let bounds: Vec<(i64, i64)> = match self {
            Semantics::Snapshot(spans) => spans.iter().map(|span| (span.start, span.end)).collect(),
            Semantics::Live(spans) => spans.iter().map(|span| (span.start, span.end)).collect(),
        };
        bounds
            .iter()
            .enumerate()
            .filter(|(_, &(start, end))| covers(start, end))
            .map(|(index, _)| index)
            .collect()
    }

    /// `JSON.stringify(cell.semanticPath)` over insertion-order span objects:
    /// `start`, `end`, `tagName`, then `attributes` or `sourceIndex`.
    fn signature(&self, path: &[usize]) -> String {
        let parts: Vec<String> = match self {
            Semantics::Snapshot(spans) => path
                .iter()
                .map(|&index| {
                    let span = &spans[index];
                    let attributes = span
                        .attributes
                        .iter()
                        .map(|(name, value)| {
                            format!("[{},{}]", json_string(name), json_string(value))
                        })
                        .collect::<Vec<_>>()
                        .join(",");
                    format!(
                        "{{\"start\":{},\"end\":{},\"tagName\":{},\"attributes\":[{}]}}",
                        js_number_string(js_int_to_number(span.start)),
                        js_number_string(js_int_to_number(span.end)),
                        json_string(&span.tag_name),
                        attributes
                    )
                })
                .collect(),
            Semantics::Live(spans) => path
                .iter()
                .map(|&index| {
                    let span = &spans[index];
                    format!(
                        "{{\"start\":{},\"end\":{},\"tagName\":{},\"sourceIndex\":{}}}",
                        js_number_string(js_int_to_number(span.start)),
                        js_number_string(js_int_to_number(span.end)),
                        json_string(&span.tag_name),
                        js_number_string(js_int_to_number(span.source_index))
                    )
                })
                .collect(),
        };
        format!("[{}]", parts.join(","))
    }

    fn wrapper(&self, index: usize) -> (String, Vec<(String, Option<String>)>) {
        match self {
            Semantics::Snapshot(spans) => {
                let semantic = &spans[index];
                let mut entries: Vec<(String, Option<String>)> = semantic
                    .attributes
                    .iter()
                    .map(|(name, value)| (name.clone(), Some(value.clone())))
                    .collect();
                entries.push((
                    "data-tq-source-semantic".to_string(),
                    Some("true".to_string()),
                ));
                (semantic.tag_name.clone(), entries)
            }
            Semantics::Live(spans) => (
                "span".to_string(),
                vec![(
                    LIVE_SEMANTIC_INDEX_ATTRIBUTE.to_string(),
                    Some(js_number_string(js_int_to_number(
                        spans[index].source_index,
                    ))),
                )],
            ),
        }
    }

    /// `wrapper` plus the `options.cjkStrongSemantics` replay: an entry whose
    /// `start`/`end` equal the span bounds adds `data-tq-cjk-emphasis` and the
    /// weight as an important font-weight, mirroring the js snapshot branch's
    /// object spread. The spread overwrites a key the span already carries at
    /// its original position, so the insert goes through `set_attribute`. The
    /// live branch never carries the attribute.
    fn wrapper_with_cjk(
        &self,
        index: usize,
        cjk_strong: &[CjkStrong],
    ) -> (String, Vec<(String, Option<String>)>) {
        let (tag, mut entries) = self.wrapper(index);
        let Semantics::Snapshot(spans) = self else {
            return (tag, entries);
        };
        let semantic = &spans[index];
        let matched = cjk_strong
            .iter()
            .find(|entry| semantic.start as f64 == entry.start && semantic.end as f64 == entry.end);
        if let Some(matched) = matched {
            set_attribute(
                &mut entries,
                "data-tq-cjk-emphasis",
                Some("true".to_string()),
            );
            set_attribute(
                &mut entries,
                "style",
                Some(format!(
                    "font-weight:{}!important",
                    js_number_string(matched.weight)
                )),
            );
        }
        (tag, entries)
    }

    fn is_live(&self) -> bool {
        matches!(self, Semantics::Live(_))
    }

    fn len(&self) -> usize {
        match self {
            Semantics::Snapshot(spans) => spans.len(),
            Semantics::Live(spans) => spans.len(),
        }
    }
}

/// `renderPreparedParagraphArtifact`: the plan JSON plus options lower to the
/// sparse DOM wire shared by build-time snapshots and browser rendering.
pub fn render_prepared_paragraph_artifact(
    plan_json: &str,
    locale: &str,
    options: &mut PreparedRenderOptions,
) -> Result<PreparedParagraphRender, NamedError> {
    let plan = Plan::from_json_str(plan_json).map_err(|error| match error.name() {
        "InvalidPlanSchema" | "InvalidPlanLayoutRevision" => {
            NamedError("UnsupportedPreparedLayoutRevision".to_string())
        }
        _ => NamedError("InvalidPreparedParagraphGeometry".to_string()),
    })?;
    render_prepared_paragraph_artifact_from_plan(&plan, locale, options)
}

pub fn render_prepared_paragraph_artifact_from_plan(
    plan: &Plan,
    locale: &str,
    options: &mut PreparedRenderOptions,
) -> Result<PreparedParagraphRender, NamedError> {
    if !plan.height.is_finite() || plan.height < 0.0 {
        return Err(NamedError("InvalidPreparedParagraphGeometry".to_string()));
    }
    let source_text: String = plan
        .lines
        .iter()
        .flat_map(|line| line.cells.iter())
        .map(|cell| cell.source.as_str())
        .collect();
    let semantics_json = match options.semantics {
        None | Some(Json::Null) => None,
        Some(value) => Some(value),
    };
    let live = match options.semantic_replay {
        None | Some("snapshot-safe") => false,
        Some("live-source") => true,
        Some(other) => {
            return Err(NamedError(format!(
                "UnsupportedPreparedSemanticReplay:{other}"
            )))
        }
    };
    let text_for_semantics = options.source_text.unwrap_or(&source_text).to_string();
    let semantics = if live {
        Semantics::Live(normalize_live_semantics(
            &text_for_semantics,
            semantics_json,
        )?)
    } else {
        Semantics::Snapshot(normalize_snapshot_semantics(
            &text_for_semantics,
            semantics_json,
        )?)
    };
    if live {
        validate_live_semantic_elements(options)?;
    }
    let render_text_spans = read_render_text_spans(options.render_text_spans, &text_for_semantics)?;
    let cjk_strong_semantics = read_cjk_strong_semantics(options.cjk_strong_semantics);
    let (inline_start_by_offset, inline_end_by_offset) =
        read_inline_box_edges(&plan.inline_edges, options.inline_boxes);
    let ruby_by_base_end: HashMap<i64, PlanRuby> = plan
        .ruby_decisions
        .iter()
        .map(|ruby| (normalized_key(f64::from(ruby.base_range_end)), ruby.clone()))
        .collect();
    let mut bopomofo_by_base_end: HashMap<i64, Vec<PlanBopomofo>> = HashMap::new();
    for z in &plan.bopomofo_decisions {
        bopomofo_by_base_end
            .entry(normalized_key(f64::from(z.base_range_end)))
            .or_default()
            .push(z.clone());
    }
    let mut style_class_for = options.style_class_for.take();
    let mut emphasis_dot_color = options.emphasis_dot_color.take();
    let lowered = render_plan(
        &plan,
        locale,
        &semantics,
        &render_text_spans,
        &cjk_strong_semantics,
        &inline_start_by_offset,
        &inline_end_by_offset,
        &ruby_by_base_end,
        &bopomofo_by_base_end,
        &mut style_class_for,
        &mut emphasis_dot_color,
    );
    options.style_class_for = style_class_for;
    options.emphasis_dot_color = emphasis_dot_color;
    lowered
}

fn validate_live_semantic_elements(options: &PreparedRenderOptions) -> Result<(), NamedError> {
    let text = options.source_text.map(str::to_string).unwrap_or_default();
    // Normalization already ran in the entry; damage surfaces there first.
    let semantics = normalize_live_semantics(&text, options.semantics)?;
    let mut seen: Vec<i64> = Vec::new();
    for semantic in &semantics {
        // A negative source index selects no element; the mismatch error
        // follows.
        let source = match usize::try_from(semantic.source_index) {
            Ok(index) => options.live_semantic_elements.get(index),
            Err(_) => None,
        };
        let matches =
            source.is_some_and(|element| element.tag_name.to_lowercase() == semantic.tag_name);
        if !matches {
            return Err(NamedError(format!(
                "LiveSemanticSourceMismatch:{}:{}",
                semantic.source_index, semantic.tag_name
            )));
        }
        if seen.contains(&semantic.source_index) {
            return Err(NamedError(format!(
                "DuplicateLiveSemanticSource:{}",
                semantic.source_index
            )));
        }
        seen.push(semantic.source_index);
    }
    Ok(())
}

struct RenderTextSpan {
    start: i64,
    end: i64,
    font_families: Vec<String>,
}

/// One `options.cjkStrongSemantics` entry. Range members use the js `Number()`
/// coercion and the weight formats with the js `String(number)` template rule.
struct CjkStrong {
    start: f64,
    end: f64,
    weight: f64,
}

/// `Array.from(options.cjkStrongSemantics ?? [])`: each entry reads `start`,
/// `end` and `weight` with `Number(entry?.field)`, so absent members are NaN
/// exactly like the js find predicate's comparison.
fn read_cjk_strong_semantics(value: Option<&Json>) -> Vec<CjkStrong> {
    let items = match value {
        Some(Json::Arr(items)) => items,
        _ => return Vec::new(),
    };
    items
        .iter()
        .map(|item| CjkStrong {
            start: number_of_field(item, "start"),
            end: number_of_field(item, "end"),
            weight: number_of_field(item, "weight"),
        })
        .collect()
}

/// `renderTextSpans`: exact-range font projections with js coercion and
/// validation.
fn read_render_text_spans(
    value: Option<&Json>,
    source_text: &str,
) -> Result<Vec<RenderTextSpan>, NamedError> {
    let mut spans = Vec::new();
    let items = match value {
        Some(Json::Arr(items)) => items,
        _ => return Ok(spans),
    };
    let source_length = f64::from(utf16_length(source_text));
    for item in items {
        let start = number_of_field(item, "start");
        let end = number_of_field(item, "end");
        let mut families = Vec::new();
        match item_field(item, "fontFamilies") {
            Some(Json::Arr(list)) => {
                for family in list {
                    let text = match family {
                        Json::Str(inner) => inner.clone(),
                        other => js_string_value(other),
                    };
                    let trimmed = js_trim(&text);
                    if !trimmed.is_empty() {
                        families.push(trimmed.to_string());
                    }
                }
            }
            // `Array.from` also spreads strings by code point.
            Some(Json::Str(raw)) => {
                for family in raw.chars() {
                    let text = family.to_string();
                    let trimmed = js_trim(&text);
                    if !trimmed.is_empty() {
                        families.push(trimmed.to_string());
                    }
                }
            }
            _ => {}
        }
        if !is_safe_integer(start)
            || !is_safe_integer(end)
            || start < 0.0
            || end <= start
            || end > source_length
            || families.is_empty()
        {
            return Err(NamedError("InvalidPreparedRenderTextSpan".to_string()));
        }
        spans.push(RenderTextSpan {
            start: trunc_sat_i64(start),
            end: trunc_sat_i64(end),
            font_families: families,
        });
    }
    Ok(spans)
}

/// The inline-box edge sums keyed by offset. The JS oracle's precedence: plan
/// `inlineEdges` win when present, `options.inlineBoxes` remain the fallback.
/// `Number()` semantics feed the sums so missing boxes produce NaN like the js
/// map.
fn read_inline_box_edges(
    plan_inline_edges: &[PlanInlineEdge],
    options_inline_boxes: Option<&Json>,
) -> (HashMap<i64, f64>, HashMap<i64, f64>) {
    let mut starts: HashMap<i64, f64> = HashMap::new();
    let mut ends: HashMap<i64, f64> = HashMap::new();
    if !plan_inline_edges.is_empty() {
        for edge in plan_inline_edges {
            if let Some(inline_start) = edge.inline_start {
                *starts.entry(normalized_key(edge.offset)).or_insert(0.0) += inline_start;
            }
            if let Some(inline_end) = edge.inline_end {
                *ends.entry(normalized_key(edge.offset)).or_insert(0.0) += inline_end;
            }
        }
    } else if let Some(Json::Arr(items)) = options_inline_boxes {
        for item in items {
            let (Some(Json::Num(start_key)), Some(Json::Num(end_key))) =
                (item_field(item, "start"), item_field(item, "end"))
            else {
                continue;
            };
            *starts.entry(normalized_key(*start_key)).or_insert(0.0) +=
                number_of_field(item, "inlineStartPx");
            *ends.entry(normalized_key(*end_key)).or_insert(0.0) +=
                number_of_field(item, "inlineEndPx");
        }
    }
    (starts, ends)
}

/// Map keys use SameValueZero; `-0` and `0` share one entry.
fn normalized_key(value: f64) -> i64 {
    if value == 0.0 {
        0
    } else {
        i64::from_ne_bytes(value.to_bits().to_ne_bytes())
    }
}

fn edge_at(map: &HashMap<i64, f64>, offset: i32) -> f64 {
    map.get(&normalized_key(f64::from(offset)))
        .copied()
        .unwrap_or(0.0)
}

fn item_field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

/// `Number(span?.field)`: the absent field is NaN.
fn number_of_field(item: &Json, key: &str) -> f64 {
    match item_field(item, key) {
        Some(value) => js_number_value(value),
        None => f64::NAN,
    }
}

fn is_safe_integer(value: f64) -> bool {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    value.fract() == 0.0 && value.abs() <= MAX_SAFE_INTEGER
}

fn prepared_spacing(display: &str, natural_width: f64, trailing_gap: f64) -> Spacing {
    if trailing_gap.abs() < SPACING_DUST_EPSILON {
        return Spacing {
            kind: SpacingKind::None,
            px: 0.0,
        };
    }
    // NegativeSingleCellFlowAdvance: browsers clamp the border-box width of a
    // one-character inline span at zero when negative letter-spacing exceeds
    // the glyph advance. Preserve the selectable source glyph at its natural
    // width and carry the overtake in margin-right.
    if utf16_length(display) == 1 && natural_width + trailing_gap >= 0.0 {
        return Spacing {
            kind: SpacingKind::Letter,
            px: trailing_gap,
        };
    }
    if trailing_gap < 0.0 {
        return Spacing {
            kind: SpacingKind::Overlap,
            px: trailing_gap,
        };
    }
    // MultiCharacterSelectableGapCarrier: the gap follows the whole shaping
    // cluster. A dedicated selectable carrier owns the full flow advance;
    // splitting off the final grapheme would break kerning.
    Spacing {
        kind: SpacingKind::TrailingLetter,
        px: trailing_gap,
    }
}

fn feature_signature(run: &CellRun) -> String {
    run.open_type_features.join(",")
}

fn render_font_signature(run: &CellRun) -> String {
    run.render_font_families.join("\u{1f}")
}

fn can_merge_prepared_run(left: &CellRun, right: &CellRun) -> bool {
    if left.range_end != right.range_start
        || left.semantic_signature != right.semantic_signature
        || left.shaping_boundary
        || right.shaping_boundary
        || feature_signature(left) != feature_signature(right)
        || render_font_signature(left) != render_font_signature(right)
        || left.dash_strategy.is_some()
        || right.dash_strategy.is_some()
        || left.style_signature != right.style_signature
        || left.punctuation_signature != right.punctuation_signature
        || left.italic_effect != right.italic_effect
        || left.evidence_render_font_family != right.evidence_render_font_family
    {
        return false;
    }
    if left.spacing.kind == SpacingKind::None && right.spacing.kind == SpacingKind::None {
        return true;
    }
    left.spacing.kind == SpacingKind::Letter
        && right.spacing.kind == SpacingKind::Letter
        && (left.spacing.px - right.spacing.px).abs() < SPACING_EPSILON
}

fn merge_prepared_run(left: &mut CellRun, right: &CellRun) {
    left.range_end = right.range_end;
    left.source.push_str(&right.source);
    left.display.push_str(&right.display);
    left.natural_width += right.natural_width;
    left.trailing_gap += right.trailing_gap;
}

fn end_reason_name(reason: PlanEndReason) -> &'static str {
    match reason {
        PlanEndReason::AutoWrap => "AutoWrap",
        PlanEndReason::MandatoryBreak => "MandatoryBreak",
        PlanEndReason::ParagraphEnd => "ParagraphEnd",
    }
}

#[allow(clippy::too_many_arguments)]
fn render_plan(
    plan: &Plan,
    locale: &str,
    semantics: &Semantics,
    render_text_spans: &[RenderTextSpan],
    cjk_strong_semantics: &[CjkStrong],
    inline_start_by_offset: &HashMap<i64, f64>,
    inline_end_by_offset: &HashMap<i64, f64>,
    ruby_by_base_end: &HashMap<i64, PlanRuby>,
    bopomofo_by_base_end: &HashMap<i64, Vec<PlanBopomofo>>,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
    emphasis_dot_color: &mut Option<&mut dyn FnMut(Option<f64>) -> Option<String>>,
) -> Result<PreparedParagraphRender, NamedError> {
    let mut draft = Draft::new();
    // The counter runs in i64 because the marker attributes carry the line
    // number as a JS number; the iterator removes any narrowing.
    let mut lines = (0i64..).zip(&plan.lines).peekable();
    while let Some((line_index, line)) = lines.next() {
        render_line(
            &mut draft,
            line,
            line_index,
            lines.peek().is_some(),
            plan.height,
            locale,
            semantics,
            render_text_spans,
            cjk_strong_semantics,
            inline_start_by_offset,
            inline_end_by_offset,
            &plan.emphasis_ranges,
            ruby_by_base_end,
            bopomofo_by_base_end,
            &mut *style_class_for,
        )?;
    }
    draft.semantic_container_for(&[], |_| unreachable!("the empty path opens nothing"));
    if !plan.lines.is_empty() {
        // ParagraphSelectionEndSentinel mirrors the runtime DOM renderer. The
        // zero-width character keeps Chromium's cross-block selection
        // terminator outside compressed closing-punctuation letter spacing.
        let sentinel = draft.push_element(
            "span",
            vec![
                ("aria-hidden".to_string(), Some("true".to_string())),
                ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
                (
                    "data-tq-selection-end".to_string(),
                    Some("true".to_string()),
                ),
            ],
            false,
        );
        let text = draft.push_text("\u{200B}");
        draft.append_child(sentinel, text);
        draft.append_child(ROOT, sentinel);
    }
    append_evidence_overlays(&mut draft, plan, emphasis_dot_color)?;
    Ok(PreparedParagraphRender {
        html: draft.html(),
        artifact: draft.artifact(),
        live_semantic_count: semantics.is_live().then(|| semantics.len()).unwrap_or(0),
        marker_count: plan.lines.len(),
    })
}

#[allow(clippy::too_many_arguments)]
fn render_line(
    draft: &mut Draft,
    line: &PlanLine,
    line_index: i64,
    has_following: bool,
    paragraph_height: f64,
    locale: &str,
    semantics: &Semantics,
    render_text_spans: &[RenderTextSpan],
    cjk_strong_semantics: &[CjkStrong],
    inline_start_by_offset: &HashMap<i64, f64>,
    inline_end_by_offset: &HashMap<i64, f64>,
    emphasis_ranges: &[(f64, f64)],
    ruby_by_base_end: &HashMap<i64, PlanRuby>,
    bopomofo_by_base_end: &HashMap<i64, Vec<PlanBopomofo>>,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) -> Result<(), NamedError> {
    let height = line.bottom - line.top;
    let first = line.cells.first();
    let flow_start = first
        .map(|cell| cell.draw_x - cell.leading_layout_advance)
        .unwrap_or(0.0);
    let first_inline_start = first
        .map(|cell| edge_at(inline_start_by_offset, cell.range_start))
        .unwrap_or(0.0);
    if let Some(cell) = first {
        if (cell.leading_layout_advance - first_inline_start).abs() > RENDER_FLOW_EPSILON_PX {
            return Err(NamedError(format!(
                "SnapshotRenderFlowMismatch:line={line_index};leading-layout-advance"
            )));
        }
    }
    let mut cells: Vec<CellRun> = Vec::with_capacity(line.cells.len());
    for (index, cell) in line.cells.iter().enumerate() {
        cells.push(prepared_cell(
            line,
            index,
            cell,
            semantics,
            render_text_spans,
            inline_start_by_offset,
            inline_end_by_offset,
            emphasis_ranges,
            bopomofo_by_base_end,
        )?);
    }
    for cell in &mut cells {
        cell.semantic_signature = semantics.signature(&cell.semantic_path);
    }
    let mut children: Vec<LineChild> = Vec::new();
    let mut pending_run: Option<CellRun> = None;
    for cell in cells {
        let range_end = cell.range_end;
        let bopomofo_advance_width = cell.bopomofo_advance_width;
        let semantic_path = cell.semantic_path.clone();
        if cell.inline_object_advance.is_some() {
            if let Some(run) = pending_run.take() {
                children.push(LineChild::Run(run));
            }
            children.push(LineChild::InlineObject {
                carrier_margin: cell.trailing_gap,
                semantic_path,
                cell,
            });
            continue;
        }
        let mut merged = false;
        if let Some(pending) = pending_run.as_mut() {
            if can_merge_prepared_run(pending, &cell) {
                merge_prepared_run(pending, &cell);
                merged = true;
            }
        }
        if !merged {
            if let Some(run) = pending_run.take() {
                children.push(LineChild::Run(run));
            }
            pending_run = Some(cell);
        }
        let ruby_at_end = ruby_by_base_end.get(&normalized_key(f64::from(range_end)));
        let bopomofo_at_end = bopomofo_by_base_end.get(&normalized_key(f64::from(range_end)));
        if ruby_at_end.is_some() || bopomofo_at_end.is_some() {
            if let Some(run) = pending_run.take() {
                children.push(LineChild::Run(run));
            }
        }
        if let Some(ruby) = ruby_at_end {
            children.push(LineChild::Ruby {
                ruby: ruby.clone(),
                line_top: line.top,
                semantic_path: semantic_path.clone(),
            });
        }
        for z in bopomofo_at_end.iter().flat_map(|list| list.iter()) {
            children.push(LineChild::Bopomofo {
                z: z.clone(),
                width: bopomofo_advance_width,
                line_top: line.top,
                line_height: height,
                semantic_path: semantic_path.clone(),
            });
        }
    }
    if let Some(run) = pending_run.take() {
        children.push(LineChild::Run(run));
    }
    let last = line.cells.last();
    let flow_end = last
        .map(|cell| {
            cell.draw_x + cell.natural_width + edge_at(inline_end_by_offset, cell.range_end)
        })
        .unwrap_or(0.0);
    let hyphen_leading_gap = if line.hyphen_advance > 0.0 {
        line.indent + line.visual_width - flow_end
    } else {
        0.0
    };
    let inline_edge_width: f64 = line
        .cells
        .iter()
        .map(|cell| {
            edge_at(inline_start_by_offset, cell.range_start)
                + edge_at(inline_end_by_offset, cell.range_end)
        })
        .sum();
    let children_flow: f64 = children.iter().map(LineChild::flow_width).sum();
    let expected_flow_width =
        flow_start + inline_edge_width + children_flow + hyphen_leading_gap + line.hyphen_advance;
    let core_line_width = line.indent + line.visual_width + line.hyphen_advance;
    if (expected_flow_width - core_line_width).abs() > RENDER_FLOW_EPSILON_PX {
        return Err(NamedError(format!(
            "SnapshotRenderFlowMismatch:line={line_index}"
        )));
    }
    let mut marker_styles = vec![
        format!("--tq-line-height:{}!important", px(height)),
        format!(
            "--tq-line-baseline-offset:{}!important",
            px(-(line.bottom - line.baseline))
        ),
    ];
    if flow_start.abs() >= SPACING_EPSILON {
        marker_styles.push(format!("--tq-line-flow-start:{}!important", px(flow_start)));
    }
    let end_reason = end_reason_name(line.end_reason);
    let mut marker_attributes: Vec<(String, Option<String>)> = vec![
        ("aria-hidden".to_string(), Some("true".to_string())),
        ("class".to_string(), Some("tq-line".to_string())),
        ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        (
            "data-tq-line-empty".to_string(),
            Some((line.cells.is_empty()).to_string()),
        ),
        ("data-tq-line-end".to_string(), Some(end_reason.to_string())),
        (
            "data-tq-line-top".to_string(),
            Some(js_number_string(line.top)),
        ),
        (
            "data-tq-line-bottom".to_string(),
            Some(js_number_string(line.bottom)),
        ),
        (
            "data-tq-line-baseline".to_string(),
            Some(js_number_string(line.baseline)),
        ),
        (
            "data-tq-line-flow-width".to_string(),
            Some(js_number_string(expected_flow_width)),
        ),
        (
            "data-tq-line-index".to_string(),
            Some(js_number_string(js_int_to_number(line_index))),
        ),
        (
            "data-tq-line-range".to_string(),
            Some(format!("{}-{}", line.range_start, line.range_end)),
        ),
        (
            "data-tq-line-shift".to_string(),
            (flow_start.abs() >= SPACING_EPSILON).then(|| "true".to_string()),
        ),
        (
            "data-tq-line-width".to_string(),
            Some(js_number_string(core_line_width)),
        ),
        (
            "data-tq-paragraph-height".to_string(),
            Some(js_number_string(paragraph_height)),
        ),
    ];
    apply_dynamic_styles(&mut marker_attributes, &marker_styles, style_class_for);
    let marker_container = draft.current_container();
    let marker = draft.push_element("span", marker_attributes, false);
    draft.append_child(marker_container, marker);

    for child in &children {
        let path = child.semantic_path().to_vec();
        let node = match child {
            LineChild::Run(run) => render_run(draft, run, style_class_for)?,
            LineChild::InlineObject {
                cell,
                carrier_margin,
                ..
            } => inline_object_placeholder(draft, cell, *carrier_margin, style_class_for),
            LineChild::Ruby { ruby, line_top, .. } => {
                ruby_annotation_span(draft, ruby, *line_top, style_class_for)
            }
            LineChild::Bopomofo {
                z,
                width,
                line_top,
                line_height,
                ..
            } => {
                bopomofo_annotation_span(draft, z, *width, *line_top, *line_height, style_class_for)
            }
        };
        let container = draft.semantic_container_for(&path, |index| {
            semantics.wrapper_with_cjk(index, cjk_strong_semantics)
        });
        draft.append_child(container, node);
    }

    if line.hyphen_advance > 0.0 {
        let mut hyphen_attributes: Vec<(String, Option<String>)> = vec![
            ("aria-hidden".to_string(), Some("true".to_string())),
            (
                "data-tq-advance".to_string(),
                Some(js_number_string(line.hyphen_advance)),
            ),
            ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
            (
                "data-tq-engine-hyphen".to_string(),
                Some("true".to_string()),
            ),
            ("data-tq-geometry".to_string(), Some("true".to_string())),
            (
                "data-tq-x".to_string(),
                Some(js_number_string(line.indent + line.visual_width)),
            ),
            ("lang".to_string(), Some(locale.to_string())),
        ];
        let styles = if hyphen_leading_gap.abs() >= SPACING_EPSILON {
            vec![format!("margin-left:{}!important", px(hyphen_leading_gap))]
        } else {
            Vec::new()
        };
        apply_dynamic_styles(&mut hyphen_attributes, &styles, style_class_for);
        let hyphen_container = draft.current_container();
        let hyphen = draft.push_element("span", hyphen_attributes, false);
        let text = draft.push_text("-");
        draft.append_child(hyphen, text);
        draft.append_child(hyphen_container, hyphen);
    }
    let crossing = semantics.crossing(line.range_end);
    let boundary = draft.semantic_container_for(&crossing, |index| {
        semantics.wrapper_with_cjk(index, cjk_strong_semantics)
    });
    let sentinel = draft.push_element(
        "span",
        vec![
            ("aria-hidden".to_string(), Some("true".to_string())),
            ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
            ("data-tq-geometry".to_string(), Some("true".to_string())),
            (
                "data-tq-line-end-sentinel".to_string(),
                Some(js_number_string(js_int_to_number(line_index))),
            ),
        ],
        false,
    );
    draft.append_child(boundary, sentinel);
    if line.end_reason == PlanEndReason::MandatoryBreak {
        let hard_break = draft.push_element(
            "span",
            vec![
                ("data-tq-geometry".to_string(), Some("true".to_string())),
                ("data-tq-hard-break".to_string(), Some("true".to_string())),
                ("data-tq-src".to_string(), Some("\n".to_string())),
            ],
            false,
        );
        draft.append_child(boundary, hard_break);
    }
    if has_following {
        let mut break_attributes: Vec<(String, Option<String>)> = vec![(
            "data-tq-engine-break".to_string(),
            Some(end_reason.to_string()),
        )];
        if line.end_reason != PlanEndReason::MandatoryBreak {
            // AccessibilitySoftWrapExclusion: only MandatoryBreak represents a
            // source newline. Other BRs replay visual geometry and stay out of
            // AX and source-faithful copy semantics.
            break_attributes.push(("aria-hidden".to_string(), Some("true".to_string())));
            break_attributes.push(("data-tq-copy-ignore".to_string(), Some("true".to_string())));
        }
        let br = draft.push_element("br", break_attributes, true);
        draft.append_child(boundary, br);
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn prepared_cell(
    line: &PlanLine,
    index: usize,
    cell: &PlanCell,
    semantics: &Semantics,
    render_text_spans: &[RenderTextSpan],
    inline_start_by_offset: &HashMap<i64, f64>,
    inline_end_by_offset: &HashMap<i64, f64>,
    emphasis_ranges: &[(f64, f64)],
    bopomofo_by_base_end: &HashMap<i64, Vec<PlanBopomofo>>,
) -> Result<CellRun, NamedError> {
    let next = line.cells.get(index + 1);
    let trailing_inline_edge = edge_at(inline_end_by_offset, cell.range_end);
    let next_leading_inline_edge = next
        .map(|next| edge_at(inline_start_by_offset, next.range_start))
        .unwrap_or(0.0);
    let raw_trailing_gap = match next {
        Some(next) => {
            next.draw_x
                - cell.draw_x
                - cell.natural_width
                - trailing_inline_edge
                - next_leading_inline_edge
        }
        None if line.hyphen_advance > 0.0 => 0.0,
        None => {
            line.indent + line.visual_width
                - cell.draw_x
                - cell.natural_width
                - trailing_inline_edge
        }
    };
    let layout_trailing_gap = if raw_trailing_gap.abs() < SPACING_DUST_EPSILON {
        0.0
    } else {
        raw_trailing_gap
    };
    let bopomofo_at_end = bopomofo_by_base_end.get(&normalized_key(f64::from(cell.range_end)));
    let bopomofo_advance_width = match bopomofo_at_end {
        None => 0.0,
        Some(_) if next.is_some() => js_max(layout_trailing_gap, 0.0),
        Some(_) => js_max(
            cell.advance.unwrap_or(cell.natural_width) - cell.natural_width - trailing_inline_edge,
            0.0,
        ),
    };
    let trailing_gap = if bopomofo_at_end.is_some() {
        0.0
    } else {
        layout_trailing_gap
    };
    let render_font_families =
        render_font_families_for(render_text_spans, cell.range_start, cell.range_end)?;
    let style_italic = style_member_bool(&cell.style_delta, "italic");
    let italic_effect = style_italic == Some(true)
        || (cell.latin
            && emphasis_ranges.iter().any(|&(start, end)| {
                f64::from(cell.range_start) >= start && f64::from(cell.range_start) < end
            }));
    Ok(CellRun {
        range_start: cell.range_start,
        range_end: cell.range_end,
        source: cell.source.clone(),
        display: cell.display.clone(),
        draw_x: cell.draw_x,
        natural_width: cell.natural_width,
        shaping_boundary: cell.shaping_boundary,
        open_type_features: cell.open_type_features.clone(),
        render_font_families,
        trailing_gap,
        spacing: prepared_spacing(&cell.display, cell.natural_width, trailing_gap),
        semantic_path: semantics.path_for(cell.range_start, cell.range_end),
        semantic_signature: String::new(),
        dash_strategy: cell.dash_strategy.clone(),
        shaping_language: cell.shaping_language.clone(),
        resolved_face: cell.resolved_face.clone(),
        glyph_ids: cell.glyph_ids.clone(),
        shaping_evidence: cell.shaping_evidence.clone(),
        punctuation_ink_floor: cell.punctuation_ink_floor,
        punctuation_body_width: cell.punctuation_body_width,
        evidence_render_font_family: cell.render_font_family.clone(),
        inline_object_advance: cell.inline_object,
        bopomofo_advance_width,
        style_delta: cell.style_delta.clone(),
        italic_effect,
        style_signature: style_signature(cell),
        punctuation_signature: punctuation_signature(cell),
    })
}

/// `JSON.stringify(cell.style ?? null)`: the parsed delta object re-renders
/// with insertion order and ECMAScript numbers, absent is `null`.
fn style_signature(cell: &PlanCell) -> String {
    match &cell.style_delta {
        Some(style) => style.render(),
        None => "null".to_string(),
    }
}

/// `JSON.stringify([cell.punctuationInkFloor ?? null, cell.punctuationBodyWidth ?? null])`.
fn punctuation_signature(cell: &PlanCell) -> String {
    let floor = match cell.punctuation_ink_floor {
        Some(value) => js_number_string(value),
        None => "null".to_string(),
    };
    let body = match cell.punctuation_body_width {
        Some(value) => js_number_string(value),
        None => "null".to_string(),
    };
    format!("[{floor},{body}]")
}

/// `cell.style?.<key>` for the paint-relevant members: only an object's
/// matching member reads, mirroring the js optional chain.
fn style_member_bool(style: &Option<Json>, key: &str) -> Option<bool> {
    let Json::Obj(fields) = style.as_ref()? else {
        return None;
    };
    match fields.iter().find(|(name, _)| name == key) {
        Some((_, Json::Bool(value))) => Some(*value),
        _ => None,
    }
}

fn style_member_number(style: &Option<Json>, key: &str) -> Option<f64> {
    let Json::Obj(fields) = style.as_ref()? else {
        return None;
    };
    match fields.iter().find(|(name, _)| name == key) {
        Some((_, Json::Num(value))) => Some(*value),
        _ => None,
    }
}

/// `renderFontFamiliesFor`: owners covering the range must agree on families.
fn render_font_families_for(
    render_text_spans: &[RenderTextSpan],
    range_start: i32,
    range_end: i32,
) -> Result<Vec<String>, NamedError> {
    let owners: Vec<&RenderTextSpan> = render_text_spans
        .iter()
        .filter(|span| i64::from(range_start) >= span.start && i64::from(range_end) <= span.end)
        .collect();
    let Some(first) = owners.first() else {
        return Ok(Vec::new());
    };
    if owners
        .iter()
        .any(|span| span.font_families != first.font_families)
    {
        return Err(NamedError("ConflictingPreparedRenderTextSpan".to_string()));
    }
    Ok(first.font_families.clone())
}

/// `renderRun`: a bare text node or a span carrying geometry and projection
/// attributes; the trailing-letter carrier owns the selectable gap.
fn render_run(
    draft: &mut Draft,
    run: &CellRun,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) -> Result<usize, NamedError> {
    let feature_signature = feature_signature(run);
    let render_font_families = &run.render_font_families;
    let needs_element = run.shaping_boundary
        || !feature_signature.is_empty()
        || !render_font_families.is_empty()
        || run.source != run.display
        || run.spacing.kind != SpacingKind::None
        || run.style_delta.is_some()
        || run.italic_effect
        || run.evidence_render_font_family.is_some()
        || run.dash_strategy.is_some()
        || run.punctuation_ink_floor.is_some();
    if !needs_element {
        return Ok(draft.push_text(&run.display));
    }
    let advance = if run.spacing.kind == SpacingKind::Letter
        || run.spacing.kind == SpacingKind::TrailingLetter
    {
        run.natural_width + run.trailing_gap
    } else {
        run.natural_width
    };
    let mut attributes: Vec<(String, Option<String>)> = vec![
        (
            "data-tq-advance".to_string(),
            Some(js_number_string(advance)),
        ),
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        ("data-tq-x".to_string(), Some(js_number_string(run.draw_x))),
    ];
    if run.shaping_boundary || !feature_signature.is_empty() {
        attributes.push(("data-tq-shaping-boundary".to_string(), Some(String::new())));
    }
    if !feature_signature.is_empty() {
        // Numeric overrides and contextual punctuation must have exact CSS replay.
        // Reject unknown feature sets instead of painting different glyph advances.
        if crate::numeric::prepared_variant(&run.open_type_features).is_err() {
            return Err(NamedError(format!(
                "UnsupportedPreparedOpenTypeFeatures: {feature_signature}"
            )));
        }
        attributes.push((
            "data-tq-open-type-features".to_string(),
            Some(feature_signature),
        ));
    }
    if run.source != run.display {
        attributes.push(("data-tq-src".to_string(), Some(run.source.clone())));
    }
    if let Some(strategy) = &run.dash_strategy {
        attributes.push(("data-tq-dash-strategy".to_string(), Some(strategy.clone())));
        attributes.push((
            "data-tq-dash-advance".to_string(),
            Some(js_number_string(run.natural_width)),
        ));
        if let Some(family) = &run.evidence_render_font_family {
            attributes.push(("data-tq-dash-font-family".to_string(), Some(family.clone())));
        }
        if let Some(face) = &run.resolved_face {
            attributes.push(("data-tq-dash-face".to_string(), Some(face.clone())));
        }
        if let Some(ids) = &run.glyph_ids {
            attributes.push(("data-tq-dash-glyph-ids".to_string(), Some(ids.clone())));
        }
        if let Some(evidence) = &run.shaping_evidence {
            attributes.push(("data-tq-dash-evidence".to_string(), Some(evidence.clone())));
        }
        if let Some(language) = &run.shaping_language {
            attributes.push(("lang".to_string(), Some(language.clone())));
        }
    }
    if let Some(floor) = run.punctuation_ink_floor {
        attributes.push((
            "data-tq-punctuation-ink-floor".to_string(),
            Some(js_number_string(floor)),
        ));
        if let Some(width) = run.punctuation_body_width {
            attributes.push((
                "data-tq-punctuation-body-width".to_string(),
                Some(js_number_string(width)),
            ));
        }
    }
    let mut styles = crate::numeric::prepared_styles(&run.open_type_features)?;
    if !render_font_families.is_empty() || run.evidence_render_font_family.is_some() {
        attributes.push((
            "data-tq-render-font-projection".to_string(),
            Some("true".to_string()),
        ));
    }
    if !render_font_families.is_empty() {
        styles.push(format!(
            "font-family:{}!important",
            render_font_families
                .iter()
                .map(|family| css_string(family))
                .collect::<Vec<_>>()
                .join(",")
        ));
    }
    if let Some(family) = &run.evidence_render_font_family {
        styles.push(format!("font-family:{}!important", css_string(family)));
    }
    if run.italic_effect && style_member_bool(&run.style_delta, "italic") != Some(true) {
        styles.push("font-style:italic!important".to_string());
    }
    if let Some(font_size) = style_member_number(&run.style_delta, "fontSize") {
        styles.push(format!("font-size:{}!important", px(font_size)));
    }
    if let Some(font_weight) = style_member_number(&run.style_delta, "fontWeight") {
        styles.push(format!(
            "font-weight:{}!important",
            js_number_string(font_weight)
        ));
    }
    match style_member_bool(&run.style_delta, "italic") {
        Some(true) => styles.push("font-style:italic!important".to_string()),
        Some(false) => styles.push("font-style:normal!important".to_string()),
        None => {}
    }
    match run.spacing.kind {
        SpacingKind::Letter => {
            styles.push(format!("letter-spacing:{}!important", px(run.spacing.px)))
        }
        SpacingKind::Overlap => {
            styles.push(format!("margin-right:{}!important", px(run.spacing.px)))
        }
        _ => {}
    }
    apply_dynamic_styles(&mut attributes, &styles, &mut *style_class_for);
    if run.spacing.kind == SpacingKind::TrailingLetter {
        let container = draft.push_element("span", attributes, false);
        let text = draft.push_text(&run.display);
        draft.append_child(container, text);
        let mut carrier_attributes: Vec<(String, Option<String>)> = vec![
            ("aria-hidden".to_string(), Some("true".to_string())),
            ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
            ("data-tq-geometry".to_string(), Some("true".to_string())),
            (
                "data-tq-spacing-carrier".to_string(),
                Some("true".to_string()),
            ),
        ];
        apply_dynamic_styles(
            &mut carrier_attributes,
            &[
                "display:inline-block!important".to_string(),
                format!("inline-size:{}!important", px(run.spacing.px)),
                "height:0!important".to_string(),
                "line-height:0!important".to_string(),
                format!("letter-spacing:{}!important", px(run.spacing.px)),
                "overflow:hidden!important".to_string(),
                "vertical-align:baseline!important".to_string(),
                "white-space:pre!important".to_string(),
            ],
            &mut *style_class_for,
        );
        let carrier = draft.push_element("span", carrier_attributes, false);
        let carrier_text = draft.push_text("\u{A0}");
        draft.append_child(carrier, carrier_text);
        draft.append_child(container, carrier);
        return Ok(container);
    }
    let element = draft.push_element("span", attributes, false);
    let text = draft.push_text(&run.display);
    draft.append_child(element, text);
    Ok(element)
}

/// `inlineObjectPlaceholder`: the pending placeholder carries the layout-owned
/// trailing gap as an attribute so the live-DOM swap can rebuild the
/// renderer's margin without parsing serialized CSS.
fn inline_object_placeholder(
    draft: &mut Draft,
    cell: &CellRun,
    trailing_gap: f64,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) -> usize {
    let carries_trailing_margin = trailing_gap.abs() >= SPACING_EPSILON;
    let mut attributes: Vec<(String, Option<String>)> = vec![
        (
            "data-tq-advance".to_string(),
            Some(js_number_string(cell.natural_width)),
        ),
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        (
            "data-tq-inline-object".to_string(),
            Some("pending".to_string()),
        ),
        (
            "data-tq-object-range".to_string(),
            Some(format!("{}-{}", cell.range_start, cell.range_end)),
        ),
        (
            "data-tq-object-trailing-margin".to_string(),
            carries_trailing_margin.then(|| js_number_string(trailing_gap)),
        ),
        ("data-tq-x".to_string(), Some(js_number_string(cell.draw_x))),
    ];
    let mut styles = vec![
        "display:inline-block!important".to_string(),
        "box-sizing:border-box!important".to_string(),
        format!("inline-size:{}!important", px(cell.natural_width)),
    ];
    if carries_trailing_margin {
        styles.push(format!("margin-right:{}!important", px(trailing_gap)));
    }
    apply_dynamic_styles(&mut attributes, &styles, style_class_for);
    draft.push_element("span", attributes, false)
}

/// `rubyAnnotationSpan`: the measured plan ascent joins when the plan carries
/// it (RubyPlanAscent), otherwise the ratio-ascent fallback covers pre-ascent
/// plans. Matches the js `Number(ruby.ascent)` finite check: absent and
/// non-finite values read as the ratio fallback.
fn ruby_annotation_span(
    draft: &mut Draft,
    ruby: &PlanRuby,
    line_top: f64,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) -> usize {
    let font_size = ruby.font_size;
    let ascent = ruby
        .ascent
        .filter(|value| value.is_finite())
        .unwrap_or(font_size * RUBY_ASCENT_RATIO);
    let families = &ruby.font_families;
    let mut attributes: Vec<(String, Option<String>)> = vec![
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        (
            "data-tq-src".to_string(),
            Some(format!("（{}）", ruby.text)),
        ),
    ];
    let mut styles = vec!["color:currentColor!important".to_string()];
    if !families.is_empty() {
        styles.push(format!(
            "font-family:{}!important",
            families
                .iter()
                .map(|family| css_string(family))
                .collect::<Vec<_>>()
                .join(",")
        ));
    }
    styles.push(format!("font-size:{}!important", px(font_size)));
    styles.push(format!(
        "font-weight:{}!important",
        js_number_string(ruby.font_weight)
    ));
    styles.push(format!("left:{}!important", px(ruby.center_x)));
    styles.push("line-height:1!important".to_string());
    styles.push("position:absolute!important".to_string());
    styles.push(format!(
        "top:{}!important",
        px(ruby.baseline_y - line_top - ascent)
    ));
    styles.push("transform:translateX(-50%)!important".to_string());
    styles.push("white-space:pre!important".to_string());
    apply_dynamic_styles(&mut attributes, &styles, style_class_for);
    let span = draft.push_element("span", attributes, false);
    let text = draft.push_text(&ruby.text);
    draft.append_child(span, text);
    span
}

struct BopomofoPlacementCss {
    left: f64,
    top: f64,
    font_size: f64,
    line_height: f64,
}

/// `bopomofoToneInkWidthEm`: interpolates the tone ink width between the
/// regular and semibold em widths by the normalized weight.
fn bopomofo_tone_ink_width_em(text: &str, font_weight: f64) -> f64 {
    let (regular, semibold) = if text == "\u{2c7}" {
        (
            BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR,
            BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD,
        )
    } else {
        (
            BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR,
            BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD,
        )
    };
    let t = js_min(js_max((font_weight - 400.0) / 300.0, 0.0), 1.0);
    regular + (semibold - regular) * t
}

/// `bopomofoCssPlacement`: Symbol paints at the box, Neutral centers the box
/// width, every other role is a tone glyph scaled to the target ink width.
fn bopomofo_css_placement(
    text: &str,
    role: &str,
    font_weight: f64,
    box_left: f64,
    box_top: f64,
    box_width: f64,
    box_height: f64,
) -> BopomofoPlacementCss {
    if role == "Symbol" {
        return BopomofoPlacementCss {
            left: box_left,
            top: box_top,
            font_size: box_height,
            line_height: box_width,
        };
    }
    if role == "Neutral" {
        let font_size = box_width;
        return BopomofoPlacementCss {
            left: box_left,
            top: box_top + (box_height - font_size) / 2.0,
            font_size,
            line_height: box_width,
        };
    }
    let ink_width_em = js_max(bopomofo_tone_ink_width_em(text, font_weight), 0.1);
    let font_size = box_width * BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE / ink_width_em;
    BopomofoPlacementCss {
        left: box_left,
        top: box_top + (box_height - font_size) / 2.0,
        font_size,
        line_height: box_width,
    }
}

/// `bopomofoZoneLeft`: the symbol zone edge, or the minimum placement left.
fn bopomofo_zone_left(placements: &[PlanBopomofoPlacement]) -> f64 {
    let symbol = placements
        .iter()
        .find(|placement| placement.role == "Symbol");
    if let Some(symbol) = symbol {
        return symbol.left - symbol.width / 9.0;
    }
    if placements.is_empty() {
        return 0.0;
    }
    placements
        .iter()
        .map(|placement| placement.left)
        .fold(f64::INFINITY, js_min)
}

/// `bopomofoAnnotationSpan`: an inline-block that occupies the consumed flow
/// slack and positions each glyph in vertical-rl writing mode.
fn bopomofo_annotation_span(
    draft: &mut Draft,
    z: &PlanBopomofo,
    width: f64,
    line_top: f64,
    line_height: f64,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
) -> usize {
    let font_weight = z.font_weight;
    let families = &z.font_families;
    let placements = &z.placements;
    let mut attributes: Vec<(String, Option<String>)> = vec![
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        ("data-tq-src".to_string(), Some(format!("（{}）", z.text))),
        ("lang".to_string(), Some(BOPOMOFO_LANG.to_string())),
    ];
    let styles = vec![
        "box-sizing:border-box!important".to_string(),
        "display:inline-block!important".to_string(),
        format!("height:{}!important", px(line_height)),
        format!("line-height:{}!important", px(line_height)),
        "overflow:visible!important".to_string(),
        "position:relative!important".to_string(),
        "user-select:all!important".to_string(),
        "vertical-align:top!important".to_string(),
        "-webkit-user-select:all!important".to_string(),
        "white-space:pre!important".to_string(),
        format!("width:{}!important", px(width)),
    ];
    apply_dynamic_styles(&mut attributes, &styles, style_class_for);
    let container = draft.push_element("span", attributes, false);
    let zone_left = bopomofo_zone_left(placements);
    for placement in placements {
        let css = bopomofo_css_placement(
            &placement.text,
            &placement.role,
            font_weight,
            placement.left,
            placement.top,
            placement.width,
            placement.height,
        );
        let mut glyph_attributes: Vec<(String, Option<String>)> = vec![
            ("data-tq-geometry".to_string(), Some("true".to_string())),
            ("lang".to_string(), Some(BOPOMOFO_LANG.to_string())),
        ];
        let mut glyph_styles = vec!["color:currentColor!important".to_string()];
        if !families.is_empty() {
            glyph_styles.push(format!(
                "font-family:{}!important",
                families
                    .iter()
                    .map(|family| css_string(family))
                    .collect::<Vec<_>>()
                    .join(",")
            ));
        }
        glyph_styles.push("font-feature-settings:'vert' 1, 'vrt2' 1!important".to_string());
        glyph_styles.push(format!("font-size:{}!important", px(css.font_size)));
        glyph_styles.push("font-style:normal!important".to_string());
        glyph_styles.push(format!(
            "font-weight:{}!important",
            js_number_string(font_weight)
        ));
        glyph_styles.push(format!("left:{}!important", px(css.left - zone_left)));
        glyph_styles.push(format!("line-height:{}!important", px(css.line_height)));
        glyph_styles.push("overflow:visible!important".to_string());
        glyph_styles.push("pointer-events:none!important".to_string());
        glyph_styles.push("position:absolute!important".to_string());
        glyph_styles.push(format!("top:{}!important", px(css.top - line_top)));
        glyph_styles.push("white-space:pre!important".to_string());
        glyph_styles.push("display:inline-block!important".to_string());
        glyph_styles.push("text-orientation:upright!important".to_string());
        glyph_styles.push("writing-mode:vertical-rl!important".to_string());
        apply_dynamic_styles(&mut glyph_attributes, &glyph_styles, style_class_for);
        let glyph = draft.push_element("span", glyph_attributes, false);
        let glyph_text = draft.push_text(&placement.text);
        draft.append_child(glyph, glyph_text);
        draft.append_child(container, glyph);
    }
    container
}

/// `overlayAttributes`: the shared SVG overlay container attributes; the width
/// and height use `px` like every CSS length on the wire.
fn overlay_attributes(width: f64, height: f64) -> Vec<(String, Option<String>)> {
    vec![
        ("aria-hidden".to_string(), Some("true".to_string())),
        ("data-tq-copy-ignore".to_string(), Some("true".to_string())),
        ("data-tq-geometry".to_string(), Some("true".to_string())),
        (
            "style".to_string(),
            Some(format!(
                "--tq-overlay-width:{};--tq-overlay-height:{}",
                px(width),
                px(height)
            )),
        ),
    ]
}

/// `wavyLinePath`: the BookTitle wave. The half wave and amplitude scale from
/// the paragraph font size, and the loop walks the span in half-wave steps
/// snapping the final segment to `right`. Every coordinate serializes with the
/// `String(number)` form, so the js arithmetic and this port share one f64
/// sequence.
fn wavy_line_path(left: f64, right: f64, y: f64, font_size: f64) -> String {
    let half_wave = js_max(font_size * WAVY_HALF_WAVE_EM, 1.0);
    let amplitude = font_size * WAVY_AMPLITUDE_EM;
    let mut path = format!("M {} {}", js_number_string(left), js_number_string(y));
    let mut x = left;
    let mut up = true;
    while x < right - WAVY_ENDPOINT_EPSILON_PX {
        let raw_next_x = x + half_wave;
        let next_x = if raw_next_x >= right - WAVY_ENDPOINT_EPSILON_PX {
            right
        } else {
            raw_next_x
        };
        let control_y = if up {
            y - amplitude * 2.0
        } else {
            y + amplitude * 2.0
        };
        path.push_str(&format!(
            " Q {} {} {} {}",
            js_number_string((x + next_x) / 2.0),
            js_number_string(control_y),
            js_number_string(next_x),
            js_number_string(y)
        ));
        x = next_x;
        up = !up;
    }
    path
}

/// `appendEvidenceOverlays`: the engine-owned interlinear decoration and
/// emphasis dot SVG overlays, appended after the flow content. Geometry gates
/// exactly like the js: the segments branch reads `fontSize`/`overlayWidth`/
/// `height`, the dots branch reads `overlayWidth`/`height`, and any non-finite
/// value is `InvalidPreparedOverlayGeometry`.
fn append_evidence_overlays(
    draft: &mut Draft,
    plan: &Plan,
    emphasis_dot_color: &mut Option<&mut dyn FnMut(Option<f64>) -> Option<String>>,
) -> Result<(), NamedError> {
    let segments = &plan.decoration_segments;
    let dots = &plan.emphasis_dots;
    if !segments.is_empty() {
        let font_size = plan.font_size.unwrap_or(f64::NAN);
        let width = plan.overlay_width.unwrap_or(f64::NAN);
        let height = plan.height;
        if !font_size.is_finite() || !width.is_finite() || !height.is_finite() {
            return Err(NamedError("InvalidPreparedOverlayGeometry".to_string()));
        }
        let stroke_width = font_size * LINE_THICKNESS_EM;
        let svg = draft.push_element("svg", overlay_attributes(width, height), false);
        for segment in segments {
            let style = format!(
                "--tq-decoration-color:currentColor;--tq-decoration-stroke-width:{}",
                px(stroke_width)
            );
            let (tag, attributes) = match segment.kind.as_str() {
                "ProperNoun" => (
                    "line",
                    vec![
                        (
                            "data-tq-decoration-line".to_string(),
                            Some("true".to_string()),
                        ),
                        ("stroke".to_string(), Some("currentColor".to_string())),
                        ("stroke-linecap".to_string(), Some("butt".to_string())),
                        (
                            "stroke-width".to_string(),
                            Some(js_number_string(stroke_width)),
                        ),
                        ("style".to_string(), Some(style)),
                        ("x1".to_string(), Some(js_number_string(segment.left))),
                        ("x2".to_string(), Some(js_number_string(segment.right))),
                        ("y1".to_string(), Some(js_number_string(segment.top))),
                        ("y2".to_string(), Some(js_number_string(segment.top))),
                    ],
                ),
                "BookTitle" => (
                    "path",
                    vec![
                        (
                            "d".to_string(),
                            Some(wavy_line_path(
                                segment.left,
                                segment.right,
                                segment.top,
                                font_size,
                            )),
                        ),
                        (
                            "data-tq-decoration-wave".to_string(),
                            Some("true".to_string()),
                        ),
                        ("fill".to_string(), Some("none".to_string())),
                        ("stroke".to_string(), Some("currentColor".to_string())),
                        ("stroke-linecap".to_string(), Some("butt".to_string())),
                        ("stroke-linejoin".to_string(), Some("round".to_string())),
                        (
                            "stroke-width".to_string(),
                            Some(js_number_string(stroke_width)),
                        ),
                        ("style".to_string(), Some(style)),
                    ],
                ),
                other => {
                    return Err(NamedError(format!(
                        "UnsupportedPreparedDecorationSegment:{other}"
                    )))
                }
            };
            let child = draft.push_element(tag, attributes, false);
            draft.append_child(svg, child);
        }
        draft.append_child(ROOT, svg);
    }
    if !dots.is_empty() {
        let width = plan.overlay_width.unwrap_or(f64::NAN);
        let height = plan.height;
        if !width.is_finite() || !height.is_finite() {
            return Err(NamedError("InvalidPreparedOverlayGeometry".to_string()));
        }
        let svg = draft.push_element("svg", overlay_attributes(width, height), false);
        for dot in dots {
            let color = emphasis_dot_color
                .as_mut()
                .and_then(|callback| callback(dot.cluster_range_start))
                .filter(|color| !color.is_empty());
            let dot_color = color.unwrap_or_else(|| "currentColor".to_string());
            let circle = draft.push_element(
                "circle",
                vec![
                    ("cx".to_string(), Some(js_number_string(dot.anchor_x))),
                    ("cy".to_string(), Some(js_number_string(dot.anchor_y))),
                    (
                        "data-tq-decoration-dot".to_string(),
                        Some("true".to_string()),
                    ),
                    ("fill".to_string(), Some(dot_color.clone())),
                    (
                        "r".to_string(),
                        Some(js_number_string(dot.dot_diameter / 2.0)),
                    ),
                    (
                        "style".to_string(),
                        Some(format!("--tq-decoration-color:{dot_color}")),
                    ),
                ],
                false,
            );
            draft.append_child(svg, circle);
        }
        draft.append_child(ROOT, svg);
    }
    Ok(())
}
