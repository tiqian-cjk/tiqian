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

use crate::js_compat::{cmp_utf16, js_int_to_number, js_number_string, js_trim, trunc_sat_i64};
use crate::json::{json_string, Json};
use crate::paragraph::utf16_length;
use crate::plan::{Plan, PlanCell, PlanEndReason, PlanLine};
use crate::snapshot_source::{
    js_number_value, js_string_value, normalize_live_semantics, normalize_snapshot_semantics,
    LiveSemanticSpan, SemanticSpan,
};

const SPACING_EPSILON: f64 = 0.01;
const RENDER_FLOW_EPSILON_PX: f64 = 0.01;
const LIVE_SEMANTIC_INDEX_ATTRIBUTE: &str = "data-tq-live-semantic-index";

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
    let (inline_start_by_offset, inline_end_by_offset) =
        read_inline_box_edges(options.inline_boxes);
    let mut style_class_for = options.style_class_for.take();
    let lowered = render_plan(
        &plan,
        locale,
        &semantics,
        &render_text_spans,
        &inline_start_by_offset,
        &inline_end_by_offset,
        &mut style_class_for,
    );
    options.style_class_for = style_class_for;
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

/// The inline-box edge sums keyed by offset; `Number()` semantics feed the
/// sums so missing boxes produce NaN like the js map.
fn read_inline_box_edges(value: Option<&Json>) -> (HashMap<i64, f64>, HashMap<i64, f64>) {
    let mut starts: HashMap<i64, f64> = HashMap::new();
    let mut ends: HashMap<i64, f64> = HashMap::new();
    if let Some(Json::Arr(items)) = value {
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
    if trailing_gap.abs() < SPACING_EPSILON {
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
    inline_start_by_offset: &HashMap<i64, f64>,
    inline_end_by_offset: &HashMap<i64, f64>,
    style_class_for: &mut Option<&mut dyn FnMut(&str) -> String>,
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
            inline_start_by_offset,
            inline_end_by_offset,
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
    inline_start_by_offset: &HashMap<i64, f64>,
    inline_end_by_offset: &HashMap<i64, f64>,
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
        )?);
    }
    for cell in &mut cells {
        cell.semantic_signature = semantics.signature(&cell.semantic_path);
    }
    let mut runs: Vec<CellRun> = Vec::new();
    for cell in cells {
        match runs.last_mut() {
            Some(pending) if can_merge_prepared_run(pending, &cell) => {
                merge_prepared_run(pending, &cell)
            }
            _ => runs.push(cell),
        }
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
    let run_flow: f64 = runs
        .iter()
        .map(|run| run.natural_width + run.trailing_gap)
        .sum();
    let expected_flow_width =
        flow_start + inline_edge_width + run_flow + hyphen_leading_gap + line.hyphen_advance;
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

    for run in &runs {
        let node = render_run(draft, run, style_class_for)?;
        let path = run.semantic_path.clone();
        let container = draft.semantic_container_for(&path, |index| semantics.wrapper(index));
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
    let boundary = draft.semantic_container_for(&crossing, |index| semantics.wrapper(index));
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
) -> Result<CellRun, NamedError> {
    let next = line.cells.get(index + 1);
    let trailing_inline_edge = edge_at(inline_end_by_offset, cell.range_end);
    let next_leading_inline_edge = next
        .map(|next| edge_at(inline_start_by_offset, next.range_start))
        .unwrap_or(0.0);
    let trailing_gap = match next {
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
    let render_font_families =
        render_font_families_for(render_text_spans, cell.range_start, cell.range_end)?;
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
    })
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
        || run.spacing.kind != SpacingKind::None;
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
        // The renderer replays exactly the feature sets the engine emits:
        // Latin curly quotes shape proportional (pwid,palt), CJK-context
        // curly quotes shape full-width (fwid,
        // CjkContextCurlyQuoteFullWidthVariant). Any other signature has no
        // CSS replay rule and must not be silently painted.
        if feature_signature != "pwid,palt" && feature_signature != "fwid" {
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
    let mut styles = Vec::new();
    if !render_font_families.is_empty() {
        attributes.push((
            "data-tq-render-font-projection".to_string(),
            Some("true".to_string()),
        ));
        styles.push(format!(
            "font-family:{}!important",
            render_font_families
                .iter()
                .map(|family| css_string(family))
                .collect::<Vec<_>>()
                .join(",")
        ));
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
