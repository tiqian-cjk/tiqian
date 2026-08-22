//! Snapshot source semantics port of `snapshot-source.js` (ADR 0050): the
//! controlled inline semantics, the source artifact hashes and the DOM
//! projection of `snapshotSourceArtifactFromDom`. The js module stays the
//! parity oracle and the browser implementation.

use std::collections::HashSet;

use tiqian::NamedError;

use crate::js_compat::{
    cmp_utf16, js_int_to_number, js_number_string, js_to_number, js_trim, trunc_sat_i64,
};
use crate::json::Json;
use crate::schema::stable_stringify;

/// `SAFE_SEMANTIC_TAGS`: the inline tags the snapshot path can serialize.
pub const SAFE_SEMANTIC_TAGS: &[&str] = &[
    "a", "abbr", "b", "bdi", "bdo", "cite", "code", "data", "del", "dfn", "em", "i", "ins", "kbd",
    "mark", "q", "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var",
];

const INTERNAL_ATTRIBUTE_PREFIX: &str = "data-tq-";

/// One normalized inline semantic span (`normalizeSnapshotSemantics`).
#[derive(Debug, Clone, PartialEq)]
pub struct SemanticSpan {
    pub start: i64,
    pub end: i64,
    pub tag_name: String,
    pub attributes: Vec<(String, String)>,
}

/// One normalized live-DOM semantic span (`normalizeLiveSemantics`).
#[derive(Debug, Clone, PartialEq)]
pub struct LiveSemanticSpan {
    pub start: i64,
    pub end: i64,
    pub tag_name: String,
    pub source_index: i64,
}

/// The canonical source artifact of one paragraph: projected text plus the
/// normalized semantics.
#[derive(Debug, Clone, PartialEq)]
pub struct SourceArtifact {
    pub text: String,
    pub semantics: Vec<SemanticSpan>,
}

/// A minimal DOM tree for the HTML projection; `precompute-html` builds it
/// from parsed markup.
#[derive(Debug, Clone, PartialEq)]
pub enum DomNode {
    Text(String),
    Element {
        tag_name: String,
        attributes: Vec<(String, String)>,
        children: Vec<DomNode>,
    },
}

/// `normalizeSnapshotSemantics`: range, tag and attribute validation with the
/// js check order, then the hierarchy sort and the crossing check.
/// `None` input is the absent `value = []` default of the js signature.
pub fn normalize_snapshot_semantics(
    text: &str,
    value: Option<&Json>,
) -> Result<Vec<SemanticSpan>, NamedError> {
    normalize_semantic_ranges(text, value, false).map(|spans| {
        spans
            .into_iter()
            .map(|span| SemanticSpan {
                start: span.start,
                end: span.end,
                tag_name: span.tag_name,
                attributes: span.attributes,
            })
            .collect()
    })
}

/// `normalizeLiveSemantics`: structural ranges without attribute
/// serialization; the browser renderer clones the trusted source node.
pub fn normalize_live_semantics(
    text: &str,
    value: Option<&Json>,
) -> Result<Vec<LiveSemanticSpan>, NamedError> {
    normalize_semantic_ranges(text, value, true).map(|spans| {
        spans
            .into_iter()
            .map(|span| LiveSemanticSpan {
                start: span.start,
                end: span.end,
                tag_name: span.tag_name,
                source_index: span.source_index,
            })
            .collect()
    })
}

/// `snapshotSourceArtifact` and `snapshotSourceArtifactString`: the frozen
/// artifact object and its canonical serialization.
pub fn snapshot_source_artifact(
    text: &str,
    value: Option<&Json>,
) -> Result<SourceArtifact, NamedError> {
    let semantics = normalize_snapshot_semantics(text, value)?;
    Ok(SourceArtifact {
        text: text.to_string(),
        semantics,
    })
}

pub fn snapshot_source_artifact_string(
    text: &str,
    value: Option<&Json>,
) -> Result<String, NamedError> {
    Ok(stable_stringify(&artifact_json(
        text,
        &normalize_snapshot_semantics(text, value)?,
    )))
}

/// The artifact serialization over already-normalized spans. Feeding the
/// normalized form through the js function is idempotent, so the bytes match
/// `snapshotSourceArtifactString`.
pub fn source_artifact_string(text: &str, semantics: &[SemanticSpan]) -> String {
    stable_stringify(&artifact_json(text, semantics))
}

fn artifact_json(text: &str, semantics: &[SemanticSpan]) -> Json {
    Json::Obj(vec![
        ("text".to_string(), Json::str(text)),
        ("semantics".to_string(), semantics_json(semantics)),
    ])
}

/// The `semantics` array the prepared entry publishes. Field order and value
/// forms match the js object literal.
pub fn semantics_json(semantics: &[SemanticSpan]) -> Json {
    Json::Arr(
        semantics
            .iter()
            .map(|span| {
                Json::Obj(vec![
                    ("start".to_string(), Json::Num(js_int_to_number(span.start))),
                    ("end".to_string(), Json::Num(js_int_to_number(span.end))),
                    ("tagName".to_string(), Json::str(&span.tag_name)),
                    (
                        "attributes".to_string(),
                        Json::Arr(
                            span.attributes
                                .iter()
                                .map(|(name, value)| {
                                    Json::Arr(vec![
                                        Json::str(name.clone()),
                                        Json::str(value.clone()),
                                    ])
                                })
                                .collect(),
                        ),
                    ),
                ])
            })
            .collect(),
    )
}

/// `snapshotSemanticMetricContractIssue`: inline `code` publishes its metric
/// contract or the paragraph reports a capability issue.
pub fn snapshot_semantic_metric_contract_issue(
    semantics: &[SemanticSpan],
    text_spans: Option<&Json>,
    inline_boxes: Option<&Json>,
) -> Option<&'static str> {
    for semantic in semantics.iter().filter(|span| span.tag_name == "code") {
        let has_text_style = exact_range_contract(
            text_spans,
            semantic.start,
            semantic.end,
            |span| {
                matches!(field(span, "fontFamilies"), Some(Json::Arr(families)) if !families.is_empty())
                    && js_number_value_or(field(span, "fontSizePx"), f64::NAN).is_finite()
                    && field(span, "fontWeight").is_some_and(is_safe_integer_json)
                    && matches!(field(span, "italic"), Some(Json::Bool(_)))
                    && js_number_value_or(field(span, "baselineShiftPx"), f64::NAN).is_finite()
            },
        );
        if !has_text_style {
            return Some("InlineCodeFontContractUnavailable");
        }
        let has_inline_box =
            exact_range_contract(inline_boxes, semantic.start, semantic.end, |span| {
                js_number_value_or(field(span, "inlineStartPx"), f64::NAN).is_finite()
                    && js_number_value_or(field(span, "inlineEndPx"), f64::NAN).is_finite()
            });
        if !has_inline_box {
            return Some("InlineCodeBoxContractUnavailable");
        }
    }
    None
}

/// A collected span before the hierarchy sort; `source_index` is the array
/// position, `order` the sort key (`order` field or the array position).
struct RawSemantic {
    start: i64,
    end: i64,
    tag_name: String,
    attributes: Vec<(String, String)>,
    source_index: i64,
    order: i64,
}

fn normalize_semantic_ranges(
    text: &str,
    value: Option<&Json>,
    live: bool,
) -> Result<Vec<RawSemantic>, NamedError> {
    let text_length = to_offset(text.encode_utf16().count())?;
    const NO_SPANS: &[Json] = &[];
    let items = match value {
        None => NO_SPANS,
        Some(Json::Arr(items)) => items,
        Some(_) => return Err(named("InvalidSnapshotSemantics")),
    };
    let mut collected = Vec::with_capacity(items.len());
    for (source_index, span) in items.iter().enumerate() {
        let start = js_number_value_or(field(span, "start"), f64::NAN);
        let end = js_number_value_or(field(span, "end"), f64::NAN);
        let start = assert_utf16_boundary(text, text_length, start)?;
        let end = assert_utf16_boundary(text, text_length, end)?;
        if end <= start {
            return Err(named("InvalidSnapshotSemanticRange"));
        }
        // `span?.tagName ?? ""` maps an absent or null tag to the empty
        // string; every other value coerces through String().
        let raw_tag = match field(span, "tagName") {
            Some(Json::Null) | None => String::new(),
            Some(inner) => js_string_value(inner),
        };
        let tag_name = js_trim(&raw_tag).to_lowercase();
        // `Number.isSafeInteger(span?.order)` decides between the explicit
        // order field and the array position.
        let order = field(span, "order")
            .filter(|value| is_safe_integer_json(value))
            .map(|value| trunc_sat_i64(js_number_value(value)))
            .unwrap_or(to_offset(source_index)?);
        if live {
            if tag_name.is_empty() {
                return Err(named("InvalidLiveSemanticTag"));
            }
            let source_index = field(span, "sourceIndex")
                .filter(|value| is_safe_integer_json(value))
                .map(|value| trunc_sat_i64(js_number_value(value)))
                .unwrap_or(to_offset(source_index)?);
            collected.push(RawSemantic {
                start,
                end,
                tag_name,
                attributes: Vec::new(),
                source_index,
                order,
            });
        } else {
            if !SAFE_SEMANTIC_TAGS.contains(&tag_name.as_str()) {
                return Err(NamedError(format!(
                    "UnsupportedSnapshotSemanticTag:{tag_name}"
                )));
            }
            let attributes = normalized_attributes(field(span, "attributes"))?;
            collected.push(RawSemantic {
                start,
                end,
                tag_name,
                attributes,
                source_index: to_offset(source_index)?,
                order,
            });
        }
    }
    collected.sort_by(|left, right| {
        left.start
            .cmp(&right.start)
            .then_with(|| right.end.cmp(&left.end))
            .then_with(|| left.order.cmp(&right.order))
    });
    let mut stack: Vec<&RawSemantic> = Vec::new();
    for span in &collected {
        while let Some(top) = stack.last() {
            if span.start >= top.end {
                stack.pop();
            } else {
                break;
            }
        }
        if let Some(parent) = stack.last() {
            if span.end > parent.end {
                return Err(named("CrossingSnapshotSemanticRanges"));
            }
        }
        stack.push(span);
    }
    Ok(collected)
}

/// `normalizedAttributes`: entries as pairs or object fields, name checks,
/// sort by name, duplicate rejection.
fn normalized_attributes(value: Option<&Json>) -> Result<Vec<(String, String)>, NamedError> {
    let entries: Vec<(Json, Json)> = match value {
        Some(Json::Arr(items)) => {
            let mut pairs = Vec::with_capacity(items.len());
            for item in items {
                match item {
                    Json::Arr(pair) if pair.len() == 2 => {
                        pairs.push((pair[0].clone(), pair[1].clone()));
                    }
                    _ => return Err(named("InvalidSnapshotSemanticAttributes")),
                }
            }
            pairs
        }
        Some(Json::Obj(fields)) => fields
            .iter()
            .map(|(key, value)| (Json::str(key.clone()), value.clone()))
            .collect(),
        _ => Vec::new(),
    };
    let mut attributes = Vec::with_capacity(entries.len());
    for (raw_name, raw_value) in entries {
        let name = js_trim(&js_string_value(&raw_name)).to_lowercase();
        let value = js_string_value(&raw_value);
        if !valid_attribute_name(&name)
            || name.starts_with("on")
            || name.starts_with(INTERNAL_ATTRIBUTE_PREFIX)
            || name == "style"
        {
            return Err(NamedError(format!(
                "UnsupportedSnapshotSemanticAttribute:{name}"
            )));
        }
        if name == "href" && unsafe_href(&value) {
            return Err(named("UnsafeSnapshotSemanticHref"));
        }
        attributes.push((name, value));
    }
    attributes.sort_by(|left, right| cmp_utf16(&left.0, &right.0));
    let mut seen = HashSet::new();
    if attributes
        .iter()
        .any(|(name, _)| !seen.insert(name.clone()))
    {
        return Err(named("DuplicateSnapshotSemanticAttribute"));
    }
    Ok(attributes)
}

/// `ATTRIBUTE_NAME`: one leading letter, underscore or colon, then letters,
/// digits, underscore, dot, colon or hyphen.
fn valid_attribute_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !(first.is_ascii_alphabetic() || first == '_' || first == ':') {
        return false;
    }
    chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | ':' | '-'))
}

/// `/^\s*javascript:/iu`: leading js whitespace, then the scheme under
/// case folding.
fn unsafe_href(value: &str) -> bool {
    let mut rest = value;
    while let Some(first) = rest.chars().next() {
        if js_regex_space(first) {
            rest = &rest[first.len_utf8()..];
        } else {
            break;
        }
    }
    let scheme = "javascript:";
    let lowered: String = rest
        .chars()
        .take(scheme.chars().count())
        .flat_map(|c| c.to_lowercase())
        .collect();
    lowered == scheme
}

/// The `\s` class of the js regex engine: the explicit ECMA set, which
/// differs from Unicode White_Space by excluding U+0085.
fn js_regex_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\u{000b}' | '\u{000c}' | '\r' | ' ' | '\u{00a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202f}'
                | '\u{205f}'
                | '\u{3000}'
                | '\u{feff}'
    )
}

/// `assertUtf16Boundary`: a safe integer inside the text, not splitting a
/// surrogate pair.
fn assert_utf16_boundary(text: &str, text_length: i64, offset: f64) -> Result<i64, NamedError> {
    if !is_safe_integer(offset) || offset < 0.0 || offset > js_int_to_number(text_length) {
        return Err(named("InvalidSnapshotSemanticRange"));
    }
    let offset = trunc_sat_i64(offset);
    if offset > 0 && offset < text_length {
        let units: Vec<u16> = text.encode_utf16().collect();
        let before = units[unit_index(offset - 1)?];
        let at = units[unit_index(offset)?];
        if (0xD800..0xDC00).contains(&before) && (0xDC00..0xE000).contains(&at) {
            return Err(named("SnapshotSemanticRangeSplitsSurrogatePair"));
        }
    }
    Ok(offset)
}

/// `exactRangeContract`: some span sits exactly on the semantic range and
/// passes the predicate.
fn exact_range_contract(
    spans: Option<&Json>,
    start: i64,
    end: i64,
    predicate: impl Fn(&Json) -> bool,
) -> bool {
    let Some(Json::Arr(items)) = spans else {
        return false;
    };
    items.iter().any(|span| {
        js_number_value_or(field(span, "start"), f64::NAN) == js_int_to_number(start)
            && js_number_value_or(field(span, "end"), f64::NAN) == js_int_to_number(end)
            && predicate(span)
    })
}

/// A span collected from the DOM walk, before the normal-flow projection.
struct DomSpan {
    start: i64,
    end: i64,
    tag_name: String,
    attributes: Vec<(String, String)>,
    order: i64,
}

/// `snapshotSourceArtifactFromDom`: collects text, `<br>` hard breaks and
/// safe semantic elements, projects normal-flow whitespace, then normalizes.
pub fn snapshot_source_artifact_from_dom(
    paragraph: &DomNode,
) -> Result<SourceArtifact, NamedError> {
    let mut text = String::new();
    let mut spans: Vec<DomSpan> = Vec::new();
    let mut hard_break_offsets: HashSet<usize> = HashSet::new();
    let mut order = 0i64;
    // The paragraph itself stays outside the walk; js iterates its children.
    if let DomNode::Element { children, .. } = paragraph {
        for child in children {
            append_dom_node(
                child,
                &mut text,
                &mut spans,
                &mut hard_break_offsets,
                &mut order,
            )?;
        }
    }
    projected_normal_flow(&text, &spans, &hard_break_offsets)
}

fn append_dom_node(
    node: &DomNode,
    text: &mut String,
    spans: &mut Vec<DomSpan>,
    hard_break_offsets: &mut HashSet<usize>,
    order: &mut i64,
) -> Result<(), NamedError> {
    match node {
        DomNode::Text(value) => {
            text.push_str(value);
        }
        DomNode::Element {
            tag_name,
            attributes,
            children,
        } => {
            let tag_name = tag_name.to_lowercase();
            if tag_name == "br" {
                hard_break_offsets.insert(text.encode_utf16().count());
                text.push('\n');
                return Ok(());
            }
            if !SAFE_SEMANTIC_TAGS.contains(&tag_name.as_str()) {
                return Err(NamedError(format!(
                    "UnsupportedSnapshotSemanticTag:{tag_name}"
                )));
            }
            let start = to_offset(text.encode_utf16().count())?;
            let source_order = *order;
            *order += 1;
            for child in children {
                append_dom_node(child, text, spans, hard_break_offsets, order)?;
            }
            let end = to_offset(text.encode_utf16().count())?;
            if end > start {
                spans.push(DomSpan {
                    start,
                    end,
                    tag_name,
                    attributes: attributes.clone(),
                    order: source_order,
                });
            }
        }
    }
    Ok(())
}

/// `projectedNormalFlow`: collapsible whitespace runs become one space,
/// explicit hard breaks stay, semantic ranges map through the projection.
fn projected_normal_flow(
    text: &str,
    spans: &[DomSpan],
    hard_break_offsets: &HashSet<usize>,
) -> Result<SourceArtifact, NamedError> {
    let units: Vec<u16> = text.encode_utf16().collect();
    let mut boundary_map: Vec<i64> = vec![0; units.len() + 1];
    let mut projected: Vec<u16> = Vec::new();
    let mut pending_start: i64 = -1;
    let mut pending_end: i64 = -1;

    fn resolve_pending(
        projected: &mut Vec<u16>,
        boundary_map: &mut [i64],
        emit: bool,
        pending_start: &mut i64,
        pending_end: &mut i64,
    ) -> Result<(), NamedError> {
        if *pending_start < 0 {
            return Ok(());
        }
        let before = to_offset(projected.len())?;
        if emit && projected.last().is_some_and(|last| *last != 0x0A) {
            projected.push(u16::from(b' '));
        }
        let after = to_offset(projected.len())?;
        boundary_map[unit_index(*pending_start)?] = before;
        for boundary in (*pending_start + 1)..=*pending_end {
            boundary_map[unit_index(boundary)?] = after;
        }
        *pending_start = -1;
        *pending_end = -1;
        Ok(())
    }

    for index in 0..units.len() {
        let character = units[index];
        if character == 0x0A && hard_break_offsets.contains(&index) {
            resolve_pending(
                &mut projected,
                &mut boundary_map,
                false,
                &mut pending_start,
                &mut pending_end,
            )?;
            boundary_map[index] = to_offset(projected.len())?;
            projected.push(character);
            boundary_map[index + 1] = to_offset(projected.len())?;
        } else if matches!(character, 0x20 | 0x09 | 0x0A | 0x0D | 0x0C) {
            if pending_start < 0 {
                pending_start = to_offset(index)?;
                boundary_map[index] = to_offset(projected.len())?;
            }
            pending_end = to_offset(index)? + 1;
        } else {
            resolve_pending(
                &mut projected,
                &mut boundary_map,
                true,
                &mut pending_start,
                &mut pending_end,
            )?;
            boundary_map[index] = to_offset(projected.len())?;
            projected.push(character);
            boundary_map[index + 1] = to_offset(projected.len())?;
        }
    }
    resolve_pending(
        &mut projected,
        &mut boundary_map,
        false,
        &mut pending_start,
        &mut pending_end,
    )?;
    boundary_map[units.len()] = to_offset(projected.len())?;

    // The projection never splits surrogate pairs, so the decode cannot fail.
    let projected_text =
        String::from_utf16(&projected).map_err(|_| named("SnapshotSourceProjectionUtf16"))?;
    let mut mapped: Vec<Json> = Vec::new();
    for span in spans {
        let start = boundary_map[unit_index(span.start)?];
        let end = boundary_map[unit_index(span.end)?];
        if end <= start {
            continue;
        }
        mapped.push(Json::Obj(vec![
            ("start".to_string(), Json::Num(js_int_to_number(start))),
            ("end".to_string(), Json::Num(js_int_to_number(end))),
            ("tagName".to_string(), Json::str(&span.tag_name)),
            (
                "attributes".to_string(),
                Json::Arr(
                    span.attributes
                        .iter()
                        .map(|(name, value)| Json::Arr(vec![Json::str(name), Json::str(value)]))
                        .collect(),
                ),
            ),
            ("order".to_string(), Json::Num(js_int_to_number(span.order))),
        ]));
    }
    snapshot_source_artifact(&projected_text, Some(&Json::Arr(mapped)))
}

/// `Number(value)` over a wire value; the absent field is `undefined`, which
/// coerces to NaN.
fn js_number_value_or(value: Option<&Json>, fallback: f64) -> f64 {
    match value {
        Some(inner) => js_number_value(inner),
        None => fallback,
    }
}

pub(crate) fn js_number_value(value: &Json) -> f64 {
    match value {
        Json::Num(inner) => *inner,
        Json::Str(inner) => js_to_number(inner),
        Json::Bool(inner) => {
            if *inner {
                1.0
            } else {
                0.0
            }
        }
        Json::Null => 0.0,
        Json::Arr(_) | Json::Obj(_) => js_to_number(&js_string_value(value)),
    }
}

/// `String(value)` over a wire value.
pub fn js_string_value(value: &Json) -> String {
    match value {
        Json::Str(inner) => inner.clone(),
        Json::Num(inner) => js_number_string(*inner),
        Json::Bool(inner) => inner.to_string(),
        Json::Null => "null".to_string(),
        Json::Arr(items) => items
            .iter()
            .map(|item| match item {
                Json::Null => String::new(),
                inner => js_string_value(inner),
            })
            .collect::<Vec<_>>()
            .join(","),
        Json::Obj(_) => "[object Object]".to_string(),
    }
}

/// `Number.isSafeInteger` on a wire value: the value must be a JSON number.
fn is_safe_integer_json(value: &Json) -> bool {
    match value {
        Json::Num(inner) => is_safe_integer(*inner),
        _ => false,
    }
}

fn is_safe_integer(value: f64) -> bool {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    value.fract() == 0.0 && value.abs() <= MAX_SAFE_INTEGER
}

/// Converts a length or index of in-memory data to the offset form the js
/// functions use. The conversion fails only when a length exceeds i64.
fn to_offset(value: usize) -> Result<i64, NamedError> {
    i64::try_from(value).map_err(|_| named("SnapshotSourceOffsetConversion"))
}

/// Converts an offset already validated against the text length to a unit
/// index. A negative offset fails.
fn unit_index(offset: i64) -> Result<usize, NamedError> {
    usize::try_from(offset).map_err(|_| named("SnapshotSourceIndexConversion"))
}

fn field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

fn named(name: &str) -> NamedError {
    NamedError(name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::parse_json;

    fn json(text: &str) -> Json {
        parse_json(text).expect("test json parses")
    }

    #[test]
    fn snapshot_semantics_nest_deterministically() {
        let semantics = normalize_snapshot_semantics(
            "前链接后",
            Some(&json(
                "[{\"start\":1,\"end\":3,\"tagName\":\"a\",\"attributes\":{\"title\":\"入口\",\"href\":\"/first\"}},{\"start\":1,\"end\":3,\"tagName\":\"strong\",\"attributes\":{}}]",
            )),
        )
        .unwrap();
        assert_eq!(
            semantics
                .iter()
                .map(|span| span.tag_name.as_str())
                .collect::<Vec<_>>(),
            vec!["a", "strong"]
        );
        // attributes sort by name: href before title
        assert_eq!(
            semantics[0].attributes,
            vec![
                ("href".to_string(), "/first".to_string()),
                ("title".to_string(), "入口".to_string())
            ]
        );
    }

    #[test]
    fn artifact_strings_distinguish_attribute_values() {
        let first = snapshot_source_artifact_string(
            "前链接后",
            Some(&json(
                "[{\"start\":1,\"end\":3,\"tagName\":\"a\",\"attributes\":{\"title\":\"入口\",\"href\":\"/first\"}},{\"start\":1,\"end\":3,\"tagName\":\"strong\",\"attributes\":{}}]",
            )),
        )
        .unwrap();
        let second = snapshot_source_artifact_string(
            "前链接后",
            Some(&json(
                "[{\"start\":1,\"end\":3,\"tagName\":\"a\",\"attributes\":{\"title\":\"入口\",\"href\":\"/second\"}},{\"start\":1,\"end\":3,\"tagName\":\"strong\",\"attributes\":{}}]",
            )),
        )
        .unwrap();
        assert_ne!(first, second);
        assert_eq!(
            first,
            "{\"semantics\":[{\"attributes\":[[\"href\",\"/first\"],[\"title\",\"入口\"]],\"end\":3,\"start\":1,\"tagName\":\"a\"},{\"attributes\":[],\"end\":3,\"start\":1,\"tagName\":\"strong\"}],\"text\":\"前链接后\"}"
        );
    }

    #[test]
    fn artifact_string_of_normalized_spans_matches_the_raw_form() {
        let raw = json(
            "[{\"start\":1,\"end\":3,\"tagName\":\"a\",\"attributes\":{\"href\":\"/first\"}}]",
        );
        let normalized = normalize_snapshot_semantics("前链接后", Some(&raw)).unwrap();
        assert_eq!(
            snapshot_source_artifact_string("前链接后", Some(&raw)).unwrap(),
            source_artifact_string("前链接后", &normalized)
        );
    }

    #[test]
    fn crossing_ranges_and_active_attributes_are_rejected() {
        let crossing = json(
            "[{\"start\":0,\"end\":3,\"tagName\":\"a\",\"attributes\":{\"href\":\"/a\"}},{\"start\":2,\"end\":4,\"tagName\":\"em\",\"attributes\":{}}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("中文正文", Some(&crossing))
                .unwrap_err()
                .0,
            "CrossingSnapshotSemanticRanges"
        );
        let active = json(
            "[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{\"onclick\":\"alert(1)\"}}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&active))
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticAttribute:onclick"
        );
        let style =
            json("[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{\"style\":\"x\"}}]");
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&style))
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticAttribute:style"
        );
        let internal = json(
            "[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{\"data-tq-x\":\"1\"}}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&internal))
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticAttribute:data-tq-x"
        );
        let unsafe_href = json(
            "[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{\"href\":\"JavaScript:alert(1)\"}}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&unsafe_href))
                .unwrap_err()
                .0,
            "UnsafeSnapshotSemanticHref"
        );
    }

    #[test]
    fn attribute_shapes_and_names_validate() {
        let pairs = json(
            "[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":[[\" href \",\"/x\"],[\"HREF\",\"/y\"]]}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&pairs))
                .unwrap_err()
                .0,
            "DuplicateSnapshotSemanticAttribute"
        );
        let malformed =
            json("[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":[[\"href\"]]}]");
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&malformed))
                .unwrap_err()
                .0,
            "InvalidSnapshotSemanticAttributes"
        );
        let bad_name =
            json("[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{\"1bad\":\"x\"}}]");
        assert_eq!(
            normalize_snapshot_semantics("链接", Some(&bad_name))
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticAttribute:1bad"
        );
    }

    #[test]
    fn ranges_validate_boundaries_and_surrogate_pairs() {
        let split = json("[{\"start\":1,\"end\":3,\"tagName\":\"a\",\"attributes\":{}}]");
        assert_eq!(
            normalize_snapshot_semantics("😀字", Some(&split))
                .unwrap_err()
                .0,
            "SnapshotSemanticRangeSplitsSurrogatePair"
        );
        let emoji_only = json("[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{}}]");
        assert_eq!(
            normalize_snapshot_semantics("😀字", Some(&emoji_only)).unwrap()[0].end,
            2
        );
        let whole = json("[{\"start\":0,\"end\":3,\"tagName\":\"a\",\"attributes\":{}}]");
        // "😀字" is three UTF-16 units, so 0..3 covers the whole text.
        let normalized = normalize_snapshot_semantics("😀字", Some(&whole)).unwrap();
        assert_eq!((normalized[0].start, normalized[0].end), (0, 3));
        let out_of_range = json("[{\"start\":0,\"end\":4,\"tagName\":\"a\",\"attributes\":{}}]");
        assert_eq!(
            normalize_snapshot_semantics("😀字", Some(&out_of_range))
                .unwrap_err()
                .0,
            "InvalidSnapshotSemanticRange"
        );
        let astral_ok = json("[{\"start\":0,\"end\":2,\"tagName\":\"a\",\"attributes\":{}}]");
        let normalized = normalize_snapshot_semantics("😀", Some(&astral_ok)).unwrap();
        assert_eq!((normalized[0].start, normalized[0].end), (0, 2));
        let not_array = json("{}");
        assert_eq!(
            normalize_snapshot_semantics("中文", Some(&not_array))
                .unwrap_err()
                .0,
            "InvalidSnapshotSemantics"
        );
        assert_eq!(
            normalize_snapshot_semantics("中文", Some(&Json::Null))
                .unwrap_err()
                .0,
            "InvalidSnapshotSemantics"
        );
    }

    #[test]
    fn snapshot_tags_are_whitelisted_and_live_tags_are_not() {
        let spoiler = json(
            "[{\"start\":1,\"end\":3,\"tagName\":\"spoiler\",\"attributes\":{\"style\":\"padding:4px\",\"onclick\":\"reveal()\"}}]",
        );
        assert_eq!(
            normalize_snapshot_semantics("前秘密后", Some(&spoiler))
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticTag:spoiler"
        );
        let live = normalize_live_semantics("前秘密后", Some(&spoiler)).unwrap();
        assert_eq!(
            live,
            vec![LiveSemanticSpan {
                start: 1,
                end: 3,
                tag_name: "spoiler".to_string(),
                source_index: 0,
            }]
        );
        let crossing = json(
            "[{\"start\":0,\"end\":3,\"tagName\":\"spoiler\"},{\"start\":2,\"end\":4,\"tagName\":\"span\"}]",
        );
        assert_eq!(
            normalize_live_semantics("中文正文", Some(&crossing))
                .unwrap_err()
                .0,
            "CrossingSnapshotSemanticRanges"
        );
        let empty_tag = json("[{\"start\":0,\"end\":2,\"tagName\":\"\"}]");
        assert_eq!(
            normalize_live_semantics("中文", Some(&empty_tag))
                .unwrap_err()
                .0,
            "InvalidLiveSemanticTag"
        );
    }

    #[test]
    fn live_semantics_keep_hierarchy_order_separate_from_source_indices() {
        let spans = json(
            "[{\"start\":0,\"end\":2,\"tagName\":\"em\",\"sourceIndex\":0,\"order\":1},{\"start\":0,\"end\":2,\"tagName\":\"spoiler\",\"sourceIndex\":1,\"order\":0}]",
        );
        let live = normalize_live_semantics("秘密", Some(&spans)).unwrap();
        assert_eq!(live[0].tag_name, "spoiler");
        assert_eq!(live[0].source_index, 1);
        assert_eq!(live[1].tag_name, "em");
        assert_eq!(live[1].source_index, 0);
    }

    #[test]
    fn inline_code_requires_the_full_metric_contract() {
        let semantics = normalize_snapshot_semantics(
            "中code文",
            Some(&json(
                "[{\"start\":1,\"end\":5,\"tagName\":\"code\",\"attributes\":{}}]",
            )),
        )
        .unwrap();
        assert_eq!(
            snapshot_semantic_metric_contract_issue(
                &semantics,
                Some(&json("[]")),
                Some(&json("[]"))
            ),
            Some("InlineCodeFontContractUnavailable")
        );
        let text_spans = json(
            "[{\"start\":1,\"end\":5,\"fontFamilies\":[\"Host Exact Mono\"],\"fontSizePx\":14,\"fontWeight\":400,\"italic\":false,\"baselineShiftPx\":0}]",
        );
        assert_eq!(
            snapshot_semantic_metric_contract_issue(
                &semantics,
                Some(&text_spans),
                Some(&json("[]"))
            ),
            Some("InlineCodeBoxContractUnavailable")
        );
        let boxes = json("[{\"start\":1,\"end\":5,\"inlineStartPx\":5.6,\"inlineEndPx\":5.6}]");
        assert_eq!(
            snapshot_semantic_metric_contract_issue(&semantics, Some(&text_spans), Some(&boxes)),
            None
        );
        // non-code semantics never require the contract
        let plain = normalize_snapshot_semantics(
            "中code文",
            Some(&json(
                "[{\"start\":1,\"end\":5,\"tagName\":\"em\",\"attributes\":{}}]",
            )),
        )
        .unwrap();
        assert_eq!(
            snapshot_semantic_metric_contract_issue(&plain, None, None),
            None
        );
        // undefined span inputs fail the exact-range contract
        assert_eq!(
            snapshot_semantic_metric_contract_issue(&semantics, None, None),
            Some("InlineCodeFontContractUnavailable")
        );
    }

    #[test]
    fn dom_artifact_projects_whitespace_and_hard_breaks() {
        let paragraph = DomNode::Element {
            tag_name: "p".to_string(),
            attributes: Vec::new(),
            children: vec![
                DomNode::Text("  正文 ".to_string()),
                DomNode::Element {
                    tag_name: "br".to_string(),
                    attributes: Vec::new(),
                    children: Vec::new(),
                },
                DomNode::Text(" 续　行 ".to_string()),
                DomNode::Element {
                    tag_name: "em".to_string(),
                    attributes: Vec::new(),
                    children: vec![DomNode::Text("强调".to_string())],
                },
            ],
        };
        let artifact = snapshot_source_artifact_from_dom(&paragraph).unwrap();
        // The ideographic space is not collapsible whitespace; only the ASCII
        // run around it collapses.
        assert_eq!(artifact.text, "正文\n续\u{3000}行 强调");
        assert_eq!(artifact.semantics.len(), 1);
        let emphasis = &artifact.semantics[0];
        assert_eq!((emphasis.start, emphasis.end), (7, 9));
        assert_eq!(emphasis.tag_name, "em");
    }

    #[test]
    fn dom_artifact_rejects_unsafe_tags_and_maps_nested_ranges() {
        let paragraph = DomNode::Element {
            tag_name: "p".to_string(),
            attributes: Vec::new(),
            children: vec![
                DomNode::Text("前".to_string()),
                DomNode::Element {
                    tag_name: "a".to_string(),
                    attributes: vec![("href".to_string(), "/x".to_string())],
                    children: vec![DomNode::Text("链接".to_string())],
                },
                DomNode::Text("后".to_string()),
            ],
        };
        let artifact = snapshot_source_artifact_from_dom(&paragraph).unwrap();
        assert_eq!(artifact.text, "前链接后");
        assert_eq!(artifact.semantics.len(), 1);
        assert_eq!(
            source_artifact_string(&artifact.text, &artifact.semantics),
            "{\"semantics\":[{\"attributes\":[[\"href\",\"/x\"]],\"end\":3,\"start\":1,\"tagName\":\"a\"}],\"text\":\"前链接后\"}"
        );
        let unsafe_paragraph = DomNode::Element {
            tag_name: "p".to_string(),
            attributes: Vec::new(),
            children: vec![DomNode::Element {
                tag_name: "ruby".to_string(),
                attributes: Vec::new(),
                children: vec![DomNode::Text("字".to_string())],
            }],
        };
        assert_eq!(
            snapshot_source_artifact_from_dom(&unsafe_paragraph)
                .unwrap_err()
                .0,
            "UnsupportedSnapshotSemanticTag:ruby"
        );
    }

    #[test]
    fn dom_artifact_keeps_whitespace_semantics_that_materialize_a_space() {
        let paragraph = DomNode::Element {
            tag_name: "p".to_string(),
            attributes: Vec::new(),
            children: vec![
                DomNode::Text("文".to_string()),
                DomNode::Element {
                    tag_name: "em".to_string(),
                    attributes: Vec::new(),
                    children: vec![DomNode::Text(" ".to_string())],
                },
                DomNode::Text("字".to_string()),
            ],
        };
        let artifact = snapshot_source_artifact_from_dom(&paragraph).unwrap();
        assert_eq!(artifact.text, "文 字");
        // The whitespace-only span survives: its projected range owns the
        // materialized space.
        assert_eq!(artifact.semantics.len(), 1);
        assert_eq!(
            (artifact.semantics[0].start, artifact.semantics[0].end),
            (1, 2)
        );
        let leading = DomNode::Element {
            tag_name: "p".to_string(),
            attributes: Vec::new(),
            children: vec![
                DomNode::Element {
                    tag_name: "em".to_string(),
                    attributes: Vec::new(),
                    children: vec![DomNode::Text(" ".to_string())],
                },
                DomNode::Text("文".to_string()),
            ],
        };
        // A leading whitespace span collapses to nothing; the projected range
        // is empty and the span drops.
        let artifact = snapshot_source_artifact_from_dom(&leading).unwrap();
        assert_eq!(artifact.text, "文");
        assert!(artifact.semantics.is_empty());
    }
}
