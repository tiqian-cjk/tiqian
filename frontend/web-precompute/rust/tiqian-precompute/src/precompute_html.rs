//! Port of `precompute-html.js` (ADR 0050 parity oracle): the framework
//! neutral server boundary that walks host HTML, snapshots conservative
//! plain paragraphs at a fixed measure and collects font contracts for the
//! rest. Host markup stays byte intact except for inserted snapshot keys.
//!
//! The tag scan runs on UTF-16 code units the way the js string methods do,
//! so insertion offsets stay comparable with js indices. Node file loading
//! and the projector callback belong to the host lane; this crate consumes
//! resolved face specs and an optional projection hook.

use std::collections::HashSet;

use tiqian::NamedError;

use crate::font_source::sha256_hex;
use crate::html_parse::{
    parse_compound_selector_list, parse_html_document, CompoundSelector, DomParser,
};
use crate::js_compat::{is_js_whitespace, js_int_to_number, js_trim, trunc_sat_usize};
use crate::json::{member, Json};
use crate::normalize::SnapshotTypography;
use std::sync::Arc;

use crate::precomputer::{create_precomputer, Precomputer, PrecomputerOptions, PrepareInput};
use crate::snapshot_bundle::{
    render_font_contract_bundle, render_snapshot_bundle, SnapshotBundle, SnapshotBundleOptions,
};
use crate::snapshot_source::{
    js_number_value, js_string_value, semantics_json, snapshot_source_artifact_from_dom, DomNode,
    SourceArtifact,
};

pub const DEFAULT_PARAGRAPH_SELECTOR: &str = "p, li";
pub const DEFAULT_SKIPPED_ANCESTOR_SELECTOR: &str =
    "[data-tiqian-skip], pre, table, .not-prose, .katex, .katex-display, .expressive-code";
const SOURCE_MAP_IGNORED_ANCESTOR_SELECTOR: &str =
    "iframe, noembed, noframes, noscript, plaintext, xmp";
const LIST_ITEM_CONTAINER_TAGS: [&str; 6] = ["p", "ul", "ol", "blockquote", "pre", "table"];
const RAW_TEXT_ELEMENTS: [&str; 9] = [
    "iframe", "noembed", "noframes", "noscript", "script", "style", "textarea", "title", "xmp",
];
/// The inert root the Node lane wraps host markup in.
const PREPARE_ROOT_MARKUP: &str = "<main data-tq-html-prepare-root>";

fn named(message: impl Into<String>) -> NamedError {
    NamedError(message.into())
}

/// `escapeAttribute` of the js module: ampersand, quote, and left angle in
/// that order, so the entities themselves stay literal.
fn escape_attribute(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
}

/// `selectedTagNames`: comma separated tag names only, trimmed and
/// lowercased.
pub fn selected_tag_names(selector: &str) -> Result<Vec<String>, NamedError> {
    let names: Vec<String> = selector
        .split(',')
        .map(|item| js_trim(item).to_lowercase())
        .collect();
    let valid = |name: &str| {
        let mut characters = name.chars();
        matches!(characters.next(), Some(first) if first.is_ascii_lowercase())
            && characters
                .all(|rest| rest.is_ascii_lowercase() || rest.is_ascii_digit() || rest == '-')
    };
    if names.iter().any(|name| !valid(name)) {
        return Err(named("UnsupportedHtmlParagraphSelector"));
    }
    Ok(names)
}

/// One located opening tag; `end` is the UTF-16 index of its `>`.
#[derive(Debug, Clone, PartialEq)]
pub struct HtmlOpeningTag {
    pub end: usize,
    pub source: String,
    pub tag_name: String,
}

/// `findHtmlOpeningTags`, the SourceFaithfulSnapshotKeyInsertion scan:
/// locate source opening tags without serializing the host's HTML. Browser
/// raw text containers and inert templates are skipped so a literal `<p>`
/// example never receives a live snapshot key. The scan reads UTF-16 code
/// units; markup inside quoted attribute values is not scanned because each
/// tag jumps past its own `>`.
pub fn find_html_opening_tags(html: &str, tag_names: &[&str]) -> Vec<HtmlOpeningTag> {
    let units: Vec<u16> = html.encode_utf16().collect();
    let lower: Vec<u16> = html.to_lowercase().encode_utf16().collect();
    let selected: HashSet<String> = tag_names.iter().map(|name| name.to_lowercase()).collect();
    let mut tags = Vec::new();
    let mut template_depth: i64 = 0;
    let mut cursor = utf16_find_str(&units, "<", 0);
    while let Some(start) = cursor {
        if utf16_starts_with(&units, "<!--", start) {
            let Some(comment_end) = utf16_find_str(&units, "-->", start + 4) else {
                break;
            };
            cursor = utf16_find_str(&units, "<", comment_end + 3);
            continue;
        }
        let mut end = start + 1;
        let mut quote: Option<u16> = None;
        while end < units.len() {
            let character = units[end];
            if let Some(open) = quote {
                if character == open {
                    quote = None;
                }
            } else if character == u16::from(b'"') || character == u16::from(b'\'') {
                quote = Some(character);
            } else if character == u16::from(b'>') {
                break;
            }
            end += 1;
        }
        if end >= units.len() {
            break;
        }
        let source = utf16_substring(&units, start, end + 1);
        let (closing, tag_name) = match parse_tag_source(&source) {
            Some(parsed) => parsed,
            None => {
                cursor = utf16_find_str(&units, "<", end + 1);
                continue;
            }
        };
        let self_closing = source.ends_with("/>");
        if !closing && tag_name == "plaintext" {
            break;
        }
        if !closing && RAW_TEXT_ELEMENTS.contains(&tag_name.as_str()) {
            let needle: Vec<u16> = format!("</{tag_name}").encode_utf16().collect();
            let Some(closing_start) = utf16_find(&lower, &needle, end + 1) else {
                break;
            };
            let Some(closing_end) = utf16_find_str(
                &units,
                ">",
                closing_start + tag_name.encode_utf16().count() + 2,
            ) else {
                break;
            };
            cursor = utf16_find_str(&units, "<", closing_end + 1);
            continue;
        }
        if tag_name == "template" {
            if closing {
                template_depth = (template_depth - 1).max(0);
            } else if !self_closing {
                template_depth += 1;
            }
        } else if !closing && selected.contains(&tag_name) && template_depth == 0 {
            tags.push(HtmlOpeningTag {
                end,
                source,
                tag_name,
            });
        }
        cursor = utf16_find_str(&units, "<", end + 1);
    }
    tags
}

/// `^<(\/)?([a-z][a-z0-9-]*)(?:\s|\/?>)` with the `i` flag. The name
/// cannot shorten under backtracking, so one greedy read suffices.
fn parse_tag_source(source: &str) -> Option<(bool, String)> {
    let characters: Vec<char> = source.chars().collect();
    if characters.first() != Some(&'<') {
        return None;
    }
    let mut position = 1;
    let closing = characters.get(position) == Some(&'/');
    if closing {
        position += 1;
    }
    let first = *characters.get(position)?;
    if !first.is_ascii_alphabetic() {
        return None;
    }
    position += 1;
    while let Some(&next) = characters.get(position) {
        if next.is_ascii_alphanumeric() || next == '-' {
            position += 1;
        } else {
            break;
        }
    }
    let tag_name: String = characters[usize::from(u8::from(closing)) + 1..position]
        .iter()
        .collect::<String>()
        .to_lowercase();
    match characters.get(position) {
        Some(follow) if is_js_whitespace(*follow) => Some((closing, tag_name)),
        Some('>') => Some((closing, tag_name)),
        Some('/') if characters.get(position + 1) == Some(&'>') => Some((closing, tag_name)),
        _ => None,
    }
}

/// A UTF-16 offset on the wire. The html cannot outgrow i64; the error arm
/// keeps the conversion total.
fn to_offset(value: usize) -> Result<i64, NamedError> {
    i64::try_from(value).map_err(|_| named("HtmlOffsetConversion"))
}

/// `injectHtmlAttributes`: insertions sorted by descending UTF-16 offset,
/// each offset validated against the html as it grows. A missing offset
/// reads as NaN the way `Number(undefined)` does and fails the safe integer
/// gate; the comparator treats NaN as equal, so stable order keeps such
/// rows where they were.
pub fn inject_html_attributes(html: &str, insertions: Option<&Json>) -> Result<String, NamedError> {
    let mut units: Vec<u16> = html.encode_utf16().collect();
    let mut rows: Vec<(f64, String)> = match insertions {
        None | Some(Json::Null) => Vec::new(),
        Some(Json::Arr(items)) => items
            .iter()
            .map(|item| {
                let offset = member(item, "offset")
                    .filter(|value| !matches!(value, Json::Null))
                    .map(js_number_value)
                    .unwrap_or(f64::NAN);
                let attribute = match member(item, "attribute") {
                    Some(value) => js_string_value(value),
                    None => "undefined".to_string(),
                };
                (offset, attribute)
            })
            .collect(),
        Some(_) => Vec::new(),
    };
    rows.sort_by(|left, right| {
        right
            .0
            .partial_cmp(&left.0)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    for (offset, attribute) in rows {
        let safe_integer = offset.fract() == 0.0 && offset.abs() <= 9_007_199_254_740_991.0;
        let length = js_int_to_number(to_offset(units.len())?);
        if !safe_integer || offset < 0.0 || offset > length {
            return Err(named("InvalidHtmlAttributeInsertionOffset"));
        }
        // The checks above gate the value to a safe integer within the unit
        // vector.
        let at = trunc_sat_usize(offset);
        let attribute_units: Vec<u16> = attribute.encode_utf16().collect();
        units.splice(at..at, attribute_units);
    }
    Ok(String::from_utf16_lossy(&units))
}

/// `projectedTextOnly`: text content with `<br>` kept as a hard break and
/// every other whitespace run collapsed to one space. Offsets live in the
/// raw UTF-16 concatenation the way the js indices do.
pub fn projected_text_only(paragraph: &DomNode) -> String {
    let mut raw = String::new();
    let mut hard_break_offsets: HashSet<usize> = HashSet::new();
    append_projected_raw(paragraph, &mut raw, &mut hard_break_offsets);
    let mut output = String::new();
    let mut pending_whitespace = false;
    let mut offset = 0usize;
    for character in raw.chars() {
        if character == '\n' && hard_break_offsets.contains(&offset) {
            pending_whitespace = false;
            output.push('\n');
        } else if matches!(character, ' ' | '\t' | '\n' | '\r' | '\u{c}') {
            pending_whitespace = !output.is_empty() && !output.ends_with('\n');
        } else {
            if pending_whitespace {
                output.push(' ');
            }
            pending_whitespace = false;
            output.push(character);
        }
        offset += character.len_utf16();
    }
    output
}

fn append_projected_raw(node: &DomNode, raw: &mut String, hard_break_offsets: &mut HashSet<usize>) {
    match node {
        DomNode::Text(value) => raw.push_str(value),
        DomNode::Element { tag_name, .. } if tag_name == "br" => {
            hard_break_offsets.insert(raw.encode_utf16().count());
            raw.push('\n');
        }
        DomNode::Element { tag_name, .. }
            if matches!(tag_name.as_str(), "script" | "style" | "template") => {}
        DomNode::Element { children, .. } => {
            for child in children {
                append_projected_raw(child, raw, hard_break_offsets);
            }
        }
    }
}

/// `nestedListItem`: a list item that owns a block container keeps its
/// layout in the host.
fn nested_list_item(parser: &DomParser, element: usize) -> bool {
    parser.tag_name(element) == "li"
        && parser
            .element_children(element)
            .iter()
            .any(|child| LIST_ITEM_CONTAINER_TAGS.contains(&parser.tag_name(*child).as_str()))
}

/// The projection override a host returns from its callback. `None` fields
/// fall back to the source artifact semantics and empty lists, matching the
/// `??` defaults of the js wrapper.
pub struct SnapshotProjection {
    pub semantics: Option<Json>,
    pub text_spans: Option<Json>,
    pub inline_boxes: Option<Json>,
    pub source_boundaries: Option<Json>,
}

/// What `projectSnapshotParagraph` receives: the paragraph element, its
/// canonical source artifact, and the build typography.
pub struct HtmlProjectionContext<'a> {
    pub element: &'a DomNode,
    pub source_text: &'a str,
    pub source_semantics: Json,
    pub typography: &'a SnapshotTypography,
}

/// The host hook behind `projectSnapshotParagraph`. Returning `None`
/// declines the snapshot the way a null or false return value does. Stored
/// inside the preparer, so it must move across threads with it.
pub trait SnapshotParagraphProjector: Send {
    fn project(&mut self, context: HtmlProjectionContext) -> Option<SnapshotProjection>;
}

/// The combined projection one paragraph contributes.
struct ProjectedParagraph {
    text: String,
    semantics: Json,
    text_spans: Json,
    inline_boxes: Json,
    source_boundaries: Json,
}

/// `snapshotProjection`: the canonical artifact first, then either the host
/// projection or DefaultSnapshotPlainSemanticBoundary, the rule that a
/// paragraph with any inline semantics stays with the host unless a
/// projector vouches for it. Arbitrary host inline CSS cannot be
/// reconstructed on the server; plain text and explicit `<br>` are safe by
/// default and hosts opt richer semantics in through one named projection
/// callback. A `fromDom` failure declines the snapshot before the projector
/// ever runs.
fn snapshot_projection(
    element: &DomNode,
    typography: &SnapshotTypography,
    projector: Option<&mut (dyn SnapshotParagraphProjector + 'static)>,
) -> Option<ProjectedParagraph> {
    let source: SourceArtifact = snapshot_source_artifact_from_dom(element).ok()?;
    let source_semantics = semantics_json(&source.semantics);
    if let Some(projector) = projector {
        let projected = projector.project(HtmlProjectionContext {
            element,
            source_text: &source.text,
            source_semantics: source_semantics.clone(),
            typography,
        })?;
        return Some(ProjectedParagraph {
            text: source.text,
            semantics: projected.semantics.unwrap_or(source_semantics),
            text_spans: projected.text_spans.unwrap_or(Json::Arr(Vec::new())),
            inline_boxes: projected.inline_boxes.unwrap_or(Json::Arr(Vec::new())),
            source_boundaries: projected.source_boundaries.unwrap_or(Json::Arr(Vec::new())),
        });
    }
    if !source.semantics.is_empty() {
        return None;
    }
    Some(ProjectedParagraph {
        text: source.text,
        semantics: source_semantics,
        text_spans: Json::Arr(Vec::new()),
        inline_boxes: Json::Arr(Vec::new()),
        source_boundaries: Json::Arr(Vec::new()),
    })
}

/// `snapshotServerAssets`: the payload a server template inlines.
pub struct SnapshotServerAssets {
    pub id: String,
    pub initial_style: String,
    pub inert_template: String,
    pub font_preloads: Json,
}

pub fn snapshot_server_assets(bundle: Option<&SnapshotBundle>) -> Option<SnapshotServerAssets> {
    let bundle = bundle?;
    Some(SnapshotServerAssets {
        id: bundle.id.clone(),
        initial_style: bundle.initial_style.clone(),
        inert_template: bundle.inert_template.clone(),
        font_preloads: bundle.font_preloads.clone(),
    })
}

/// `renderSnapshotServerAssets`: preload links, the first paint style and
/// the inert template, concatenated.
pub fn render_snapshot_server_assets(assets: Option<&SnapshotServerAssets>) -> String {
    let Some(assets) = assets else {
        return String::new();
    };
    let preloads = match &assets.font_preloads {
        Json::Arr(items) => items
            .iter()
            .map(|href| {
                format!(
                    "<link rel=\"preload\" as=\"font\" type=\"font/woff2\" crossorigin href=\"{}\">",
                    escape_attribute(&js_string_value(href))
                )
            })
            .collect::<String>(),
        _ => String::new(),
    };
    format!(
        "{preloads}<style data-tq-initial-snapshot=\"{}\">{}</style>{}",
        escape_attribute(&assets.id),
        assets.initial_style,
        assets.inert_template
    )
}

/// `clientBundle`: the fields a client hydration path consumes.
fn client_bundle_json(bundle: &SnapshotBundle) -> Json {
    Json::Obj(vec![
        ("id".to_string(), Json::str(bundle.id.clone())),
        (
            "clientTemplate".to_string(),
            Json::str(bundle.client_template.clone()),
        ),
        (
            "initialStyle".to_string(),
            Json::str(bundle.initial_style.clone()),
        ),
        ("fontPreloads".to_string(), bundle.font_preloads.clone()),
    ])
}

/// The bundle in the js object literal field order.
pub fn bundle_json(bundle: &SnapshotBundle) -> Json {
    Json::Obj(vec![
        ("id".to_string(), Json::str(bundle.id.clone())),
        ("template".to_string(), Json::str(bundle.template.clone())),
        (
            "clientTemplate".to_string(),
            Json::str(bundle.client_template.clone()),
        ),
        (
            "inertTemplate".to_string(),
            Json::str(bundle.inert_template.clone()),
        ),
        (
            "initialStyle".to_string(),
            Json::str(bundle.initial_style.clone()),
        ),
        (
            "renderFontFamilies".to_string(),
            bundle.render_font_families.clone(),
        ),
        ("fontPreloads".to_string(), bundle.font_preloads.clone()),
        ("rootAttributes".to_string(), bundle.root_attributes.clone()),
        ("entries".to_string(), bundle.entries.clone()),
    ])
}

/// Options of one `prepare(html, options)` call. `snapshot_max_width_px`
/// carries `options.snapshot.maxWidthPx` raw; `None` and JSON null both
/// mean the width free lane.
pub struct HtmlPrepareOptions<'a> {
    pub id: Option<&'a str>,
    pub snapshot_max_width_px: Option<&'a Json>,
}

impl<'a> Default for HtmlPrepareOptions<'a> {
    fn default() -> Self {
        HtmlPrepareOptions {
            id: None,
            snapshot_max_width_px: None,
        }
    }
}

/// Options of [`create_html_preparer`]. `precomputer` reuses an open
/// session; several preparers may share one handle while the caller keeps
/// addressing it. Otherwise one is created from `create` and closed together
/// with the preparer. `shared_runtime_style` is the package stylesheet the
/// bundle inlines; the crate never reads files.
pub struct HtmlPreparerOptions<'a> {
    pub precomputer: Option<Arc<Precomputer>>,
    pub create: PrecomputerOptions<'a>,
    pub paragraph_selector: Option<&'a str>,
    pub skipped_ancestor_selector: Option<&'a str>,
    pub shared_runtime_style: &'a str,
    pub projector: Option<Box<dyn SnapshotParagraphProjector>>,
}

/// `createHtmlPreparer`: validate the projection inputs in the js order,
/// the precomputer first.
pub fn create_html_preparer(options: HtmlPreparerOptions) -> Result<HtmlPreparer, NamedError> {
    let owns_precomputer = options.precomputer.is_none();
    let precomputer = match options.precomputer {
        Some(shared) => shared,
        None => Arc::new(create_precomputer(options.create)?),
    };
    let paragraph_selector = options
        .paragraph_selector
        .unwrap_or(DEFAULT_PARAGRAPH_SELECTOR);
    let tag_names = selected_tag_names(paragraph_selector)?;
    let skipped = options
        .skipped_ancestor_selector
        .unwrap_or(DEFAULT_SKIPPED_ANCESTOR_SELECTOR);
    Ok(HtmlPreparer {
        source_map_ignored: parse_compound_selector_list(SOURCE_MAP_IGNORED_ANCESTOR_SELECTOR)?,
        tag_names,
        skipped_ancestor_selector: parse_compound_selector_list(skipped)?,
        precomputer,
        owns_precomputer,
        shared_runtime_style: options.shared_runtime_style.to_string(),
        projector: options.projector,
        closed: false,
    })
}

pub struct HtmlPreparer {
    source_map_ignored: Vec<CompoundSelector>,
    tag_names: Vec<String>,
    skipped_ancestor_selector: Vec<CompoundSelector>,
    precomputer: Arc<Precomputer>,
    owns_precomputer: bool,
    shared_runtime_style: String,
    projector: Option<Box<dyn SnapshotParagraphProjector>>,
    closed: bool,
}

impl HtmlPreparer {
    pub fn typography(&self) -> SnapshotTypography {
        self.precomputer.typography().clone()
    }

    pub fn close(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        if self.owns_precomputer {
            self.precomputer.close();
        }
    }

    /// `prepare`: parse the wrapped markup, reconcile the DOM selection
    /// with the source tag scan, then snapshot or contract every remaining
    /// paragraph. Returns the frozen result object in the js field order.
    pub fn prepare(
        &mut self,
        html: &str,
        options: &HtmlPrepareOptions,
    ) -> Result<Json, NamedError> {
        if self.closed {
            return Err(named("HtmlPreparerClosed"));
        }
        let snapshot_width = options
            .snapshot_max_width_px
            .filter(|value| !matches!(value, Json::Null));
        if let Some(width) = snapshot_width {
            let number = js_number_value(width);
            if !number.is_finite() || number <= 0.0 {
                return Err(named("InvalidMaximumMeasure"));
            }
        }
        let id = match options.id {
            Some(id) => id.to_string(),
            None => {
                let mut digest = html.as_bytes().to_vec();
                digest.push(0);
                match snapshot_width {
                    None => digest.extend_from_slice(b"runtime"),
                    Some(width) => {
                        digest.extend_from_slice(js_string_value(width).as_bytes());
                    }
                }
                format!("tq-prose-{}", &sha256_hex(&digest)[..16])
            }
        };

        let parser = parse_html_document(&format!("{PREPARE_ROOT_MARKUP}{html}</main>"));
        let root = parser
            .descendants_by_tag(parser.document(), &["main".to_string()])
            .into_iter()
            .find(|element| {
                parser
                    .attributes(*element)
                    .iter()
                    .any(|(name, _)| name == "data-tq-html-prepare-root")
            })
            .ok_or_else(|| named("HtmlPrepareRootUnavailable"))?;
        let source_elements: Vec<usize> = parser
            .descendants_by_tag(root, &self.tag_names)
            .into_iter()
            .filter(|element| !parser.closest(*element, &self.source_map_ignored))
            .collect();
        let scan_names: Vec<&str> = self.tag_names.iter().map(String::as_str).collect();
        let opening_tags = find_html_opening_tags(html, &scan_names);
        if source_elements.len() != opening_tags.len() {
            return Err(named(format!(
                "HtmlParagraphSourceMapMismatch:{}:{}",
                source_elements.len(),
                opening_tags.len()
            )));
        }

        let HtmlPreparer {
            skipped_ancestor_selector,
            precomputer,
            shared_runtime_style,
            projector,
            ..
        } = self;
        // Phase one walks the document in order: the projector is mutable
        // state and the source order check reports by index, so validation
        // and projection stay sequential. The plans own their projected
        // values, which frees the shaping calls for the worker spread.
        let typography = precomputer.typography().clone();
        struct ElementPlan {
            index: usize,
            opening_tag_end: usize,
            snapshot: Option<ProjectedParagraph>,
            text: String,
        }
        let mut plans: Vec<ElementPlan> = Vec::new();
        for (index, element) in source_elements.iter().copied().enumerate() {
            let opening_tag = &opening_tags[index];
            if opening_tag.tag_name != parser.tag_name(element) {
                return Err(named(format!("HtmlParagraphSourceOrderMismatch:{index}")));
            }
            if parser.closest(element, skipped_ancestor_selector)
                || nested_list_item(&parser, element)
            {
                continue;
            }
            let element_node = parser.to_dom_node(element);
            let projected =
                snapshot_projection(&element_node, &typography, projector.as_deref_mut());
            let text = match &projected {
                Some(value) => value.text.clone(),
                None => projected_text_only(&element_node),
            };
            if js_trim(&text).is_empty() {
                continue;
            }
            plans.push(ElementPlan {
                index,
                opening_tag_end: opening_tag.end,
                snapshot: projected,
                text,
            });
        }

        // Phase two spreads one whole element sequence per worker: the
        // snapshot attempt runs first and the contract fallback runs after
        // it, so an element keeps the sequential lane's branching, issue
        // order, and error identity. The spread only interleaves elements,
        // and every paragraph owns its capture window.
        struct ElementOutcome {
            snapshot: Option<(Json, Json)>,
            contract: Option<Json>,
            issues: Vec<Json>,
        }
        let precomputer_ref: &Precomputer = precomputer.as_ref();
        let workers = crate::parallel::worker_count();
        let outcomes = crate::parallel::indexed_collect(plans.len(), workers, |slot| {
            let plan = &plans[slot];
            let mut issues: Vec<Json> = Vec::new();
            if let (Some(width), Some(projected)) = (snapshot_width, plan.snapshot.as_ref()) {
                let snapshot_key = format!("p-{}", plan.index);
                let key_value = Json::str(snapshot_key.clone());
                let text_value = Json::str(projected.text.clone());
                let width_number = Json::Num(js_number_value(width));
                let input = PrepareInput {
                    key: Some(&key_value),
                    text: Some(&text_value),
                    semantics: Some(&projected.semantics),
                    text_spans: Some(&projected.text_spans),
                    inline_boxes: Some(&projected.inline_boxes),
                    max_width_px: Some(&width_number),
                    source_boundaries: Some(&projected.source_boundaries),
                };
                let prepared = precomputer_ref.prepare_paragraph(&input)?;
                if entry_status(&prepared) == Some("prepared") {
                    return Ok(ElementOutcome {
                        snapshot: Some((
                            prepared,
                            Json::Obj(vec![
                                (
                                    "offset".to_string(),
                                    Json::Num(js_int_to_number(to_offset(plan.opening_tag_end)?)),
                                ),
                                (
                                    "attribute".to_string(),
                                    Json::str(format!(" data-tq-snapshot-key=\"{snapshot_key}\"")),
                                ),
                            ]),
                        )),
                        contract: None,
                        issues,
                    });
                }
                issues.push(issue_json(
                    plan.index,
                    &snapshot_key,
                    "snapshot",
                    &prepared,
                )?);
            }

            let contract_key = format!("f-{}", plan.index);
            let key_value = Json::str(contract_key.clone());
            let text_value = Json::str(plan.text.clone());
            let mut input = PrepareInput {
                key: Some(&key_value),
                text: Some(&text_value),
                ..Default::default()
            };
            if let Some(projected) = &plan.snapshot {
                input.semantics = Some(&projected.semantics);
                input.text_spans = Some(&projected.text_spans);
                input.inline_boxes = Some(&projected.inline_boxes);
                input.source_boundaries = Some(&projected.source_boundaries);
            }
            let contract = precomputer_ref.prepare_font_contract(&input)?;
            if entry_status(&contract) == Some("prepared") {
                return Ok(ElementOutcome {
                    snapshot: None,
                    contract: Some(contract),
                    issues,
                });
            }
            issues.push(issue_json(
                plan.index,
                &contract_key,
                "font-contract",
                &contract,
            )?);
            Ok(ElementOutcome {
                snapshot: None,
                contract: None,
                issues,
            })
        })?;

        // Phase three rebuilds the sequential arrays: every collection keeps
        // document order, and an element's snapshot issue stays ahead of its
        // contract issue.
        let mut prepared_paragraphs: Vec<Json> = Vec::new();
        let mut font_contracts: Vec<Json> = Vec::new();
        let mut insertions: Vec<Json> = Vec::new();
        let mut issues: Vec<Json> = Vec::new();
        for outcome in outcomes {
            if let Some((prepared, insertion)) = outcome.snapshot {
                prepared_paragraphs.push(prepared);
                insertions.push(insertion);
            }
            if let Some(contract) = outcome.contract {
                font_contracts.push(contract);
            }
            issues.extend(outcome.issues);
        }

        let bundle = if !prepared_paragraphs.is_empty() {
            let contract_array = Json::Arr(font_contracts);
            let options = SnapshotBundleOptions {
                id: Some(&id),
                paragraph_selector: None,
                font_contract_paragraphs: Some(&contract_array),
                shared_runtime_style: shared_runtime_style.as_str(),
                snapshot_tables: None,
            };
            Some(render_snapshot_bundle(
                Some(&Json::Arr(prepared_paragraphs)),
                &options,
            )?)
        } else if !font_contracts.is_empty() {
            let options = SnapshotBundleOptions {
                id: Some(&id),
                paragraph_selector: None,
                font_contract_paragraphs: None,
                shared_runtime_style: shared_runtime_style.as_str(),
                snapshot_tables: None,
            };
            Some(render_font_contract_bundle(
                Some(&Json::Arr(font_contracts)),
                &options,
            )?)
        } else {
            None
        };
        let prepared_html = inject_html_attributes(html, Some(&Json::Arr(insertions)))?;

        let result = vec![
            ("html".to_string(), Json::str(prepared_html)),
            (
                "rootAttributes".to_string(),
                match &bundle {
                    Some(bundle) => {
                        let mut fields =
                            vec![("snapshot-ref".to_string(), Json::str(bundle.id.clone()))];
                        if let Json::Obj(attributes) = &bundle.root_attributes {
                            fields.extend(attributes.iter().cloned());
                        }
                        Json::Obj(fields)
                    }
                    None => Json::Obj(Vec::new()),
                },
            ),
            (
                "bundle".to_string(),
                match &bundle {
                    Some(bundle) => bundle_json(bundle),
                    None => Json::Null,
                },
            ),
            (
                "clientBundle".to_string(),
                match &bundle {
                    Some(bundle) => client_bundle_json(bundle),
                    None => Json::Null,
                },
            ),
            (
                "serverAssets".to_string(),
                match &bundle {
                    Some(bundle) => Json::Obj(vec![
                        ("id".to_string(), Json::str(bundle.id.clone())),
                        (
                            "initialStyle".to_string(),
                            Json::str(bundle.initial_style.clone()),
                        ),
                        (
                            "inertTemplate".to_string(),
                            Json::str(bundle.inert_template.clone()),
                        ),
                        ("fontPreloads".to_string(), bundle.font_preloads.clone()),
                    ]),
                    None => Json::Null,
                },
            ),
            ("issues".to_string(), Json::Arr(issues)),
        ];
        Ok(Json::Obj(result))
    }
}

/// One `{ index, key, stage, issue }` issues row.
fn issue_json(index: usize, key: &str, stage: &str, entry: &Json) -> Result<Json, NamedError> {
    let issue = match entry {
        Json::Obj(fields) => fields
            .iter()
            .find(|(name, _)| name == "issue")
            .map(|(_, value)| value.clone())
            .unwrap_or(Json::Null),
        _ => Json::Null,
    };
    Ok(Json::Obj(vec![
        (
            "index".to_string(),
            Json::Num(js_int_to_number(to_offset(index)?)),
        ),
        ("key".to_string(), Json::str(key)),
        ("stage".to_string(), Json::str(stage)),
        ("issue".to_string(), issue),
    ]))
}

/// `entry.status` of a prepare result.
fn entry_status(entry: &Json) -> Option<&str> {
    match entry {
        Json::Obj(fields) => match fields.iter().find(|(name, _)| name == "status") {
            Some((_, Json::Str(status))) => Some(status.as_str()),
            _ => None,
        },
        _ => None,
    }
}

fn utf16_find(units: &[u16], needle: &[u16], from: usize) -> Option<usize> {
    if needle.is_empty() {
        return Some(from.min(units.len()));
    }
    if units.len() < needle.len() {
        return None;
    }
    (from..=units.len() - needle.len())
        .find(|start| units[*start..*start + needle.len()] == needle[..])
}

fn utf16_find_str(units: &[u16], needle: &str, from: usize) -> Option<usize> {
    utf16_find(units, &needle.encode_utf16().collect::<Vec<u16>>(), from)
}

fn utf16_starts_with(units: &[u16], prefix: &str, at: usize) -> bool {
    let prefix: Vec<u16> = prefix.encode_utf16().collect();
    at + prefix.len() <= units.len() && units[at..at + prefix.len()] == prefix[..]
}

fn utf16_substring(units: &[u16], start: usize, end: usize) -> String {
    String::from_utf16_lossy(&units[start..end])
}
