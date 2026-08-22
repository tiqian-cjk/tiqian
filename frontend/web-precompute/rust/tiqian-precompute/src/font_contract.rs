//! `requiredCjkDashContractInput` of `font-contract.js` (ADR 0050 parity
//! oracle): when a font-contract paragraph cannot be prepared, the `——` and
//! `⸺` runs it contained still need server shaping evidence, so every style
//! that owns one of those sequences contributes one minimal probe.

use std::collections::HashMap;

use crate::js_compat::js_int_to_number;
use crate::json::Json;
use crate::normalize::SnapshotTypography;
use crate::paragraph::utf16_length;
use crate::precomputer::PrepareInput;
use crate::snapshot_source::{js_number_value, js_string_value};

/// One resolved style of a dash run, in the js literal key order. The order
/// is the `JSON.stringify` signature order the js grouping reads.
#[derive(Clone, PartialEq)]
struct DashStyle {
    font_families: Vec<String>,
    font_size_px: f64,
    font_weight: f64,
    italic: Json,
    baseline_shift_px: f64,
}

impl DashStyle {
    fn to_json(&self) -> Json {
        Json::Obj(vec![
            (
                "fontFamilies".to_string(),
                Json::Arr(
                    self.font_families
                        .iter()
                        .map(|family| Json::str(family.clone()))
                        .collect(),
                ),
            ),
            ("fontSizePx".to_string(), Json::Num(self.font_size_px)),
            ("fontWeight".to_string(), Json::Num(self.font_weight)),
            ("italic".to_string(), self.italic.clone()),
            (
                "baselineShiftPx".to_string(),
                Json::Num(self.baseline_shift_px),
            ),
        ])
    }
}

/// `resolvedStyleAt`: the last raw span whose safe-integer range covers the
/// UTF-16 offset, otherwise the typography. Family strings are coerced, not
/// trimmed; the numbers use the loose `Number(...)` coercions of the js.
fn resolved_style_at(
    text_offset: f64,
    spans: &[Json],
    typography: &SnapshotTypography,
) -> DashStyle {
    let span = spans.iter().rev().find(|candidate| {
        // Number.isSafeInteger does not coerce: only JSON numbers pass.
        let (Some(Json::Num(start)), Some(Json::Num(end))) =
            (field(candidate, "start"), field(candidate, "end"))
        else {
            return false;
        };
        is_safe_integer(*start)
            && is_safe_integer(*end)
            && text_offset >= *start
            && text_offset < *end
    });
    DashStyle {
        font_families: match span.and_then(|span| field_non_null(Some(span), "fontFamilies")) {
            Some(Json::Arr(items)) => items.iter().map(js_string_value).collect(),
            _ => typography.font_families.clone(),
        },
        font_size_px: match field_non_null(span, "fontSizePx") {
            Some(value) => js_number_value(value),
            None => typography.font_size_px,
        },
        font_weight: match field_non_null(span, "fontWeight") {
            Some(value) => js_number_value(value),
            None => f64::from(typography.font_weight),
        },
        italic: match field_non_null(span, "italic") {
            Some(value) => value.clone(),
            None => Json::Bool(typography.italic),
        },
        baseline_shift_px: match field_non_null(span, "baselineShiftPx") {
            Some(value) => js_number_value(value),
            None => 0.0,
        },
    }
}

/// The minimal probe input for the dash retry, or `None` when the text owns
/// no `——` or `⸺` run. The result is a complete prepare input value: key,
/// probe text and one raw span per probe.
pub fn required_cjk_dash_contract_input(
    input: &PrepareInput,
    typography: &SnapshotTypography,
) -> Option<Json> {
    let text = input.text_string();
    let spans = match input.text_spans {
        Some(Json::Arr(items)) => items.clone(),
        _ => Vec::new(),
    };

    // matchAll(/——|⸺/gu): left to right, non overlapping, UTF-16 indices.
    // Groups keep first-seen order; each group dedupes its dash forms.
    let mut order: Vec<usize> = Vec::new();
    let mut signatures: HashMap<String, usize> = HashMap::new();
    let mut styles: Vec<DashStyle> = Vec::new();
    let mut dashes_per_group: Vec<Vec<&str>> = Vec::new();
    let mut offset = 0i64;
    let mut chars = text.chars().peekable();
    while let Some(current) = chars.next() {
        let dash = if current == '—' && chars.peek() == Some(&'—') {
            chars.next();
            Some("——")
        } else if current == '⸺' {
            Some("⸺")
        } else {
            None
        };
        if let Some(dash) = dash {
            let style = resolved_style_at(js_int_to_number(offset), &spans, typography);
            let signature = style.to_json().render();
            let index = match signatures.get(&signature) {
                Some(&index) => index,
                None => {
                    let index = styles.len();
                    signatures.insert(signature, index);
                    styles.push(style);
                    dashes_per_group.push(Vec::new());
                    order.push(index);
                    index
                }
            };
            if !dashes_per_group[index].contains(&dash) {
                dashes_per_group[index].push(dash);
            }
        }
        // Each char is one or two UTF-16 units; the bool step counts units
        // in i64.
        offset += match dash {
            Some(dash) => dash
                .chars()
                .map(|c| 1 + i64::from(c.len_utf16() == 2))
                .sum::<i64>(),
            None => 1 + i64::from(current.len_utf16() == 2),
        };
    }
    if styles.is_empty() {
        return None;
    }

    let mut probe_text = String::new();
    let mut text_spans: Vec<Json> = Vec::new();
    for index in order {
        for dash in &dashes_per_group[index] {
            let start = utf16_length(&probe_text);
            probe_text.push_str(dash);
            let end = utf16_length(&probe_text);
            let style = styles[index].to_json();
            let Json::Obj(style_fields) = &style else {
                unreachable!("dash style serializes as an object");
            };
            let mut fields = vec![
                ("start".to_string(), Json::Num(f64::from(start))),
                ("end".to_string(), Json::Num(f64::from(end))),
            ];
            fields.extend(style_fields.iter().cloned());
            text_spans.push(Json::Obj(fields));
        }
    }
    Some(Json::Obj(vec![
        ("key".to_string(), Json::str(input.key_string())),
        ("text".to_string(), Json::str(probe_text)),
        ("textSpans".to_string(), Json::Arr(text_spans)),
    ]))
}

fn field<'a>(value: &'a Json, name: &str) -> Option<&'a Json> {
    let Json::Obj(fields) = value else {
        return None;
    };
    fields
        .iter()
        .find(|(key, _)| key == name)
        .map(|(_, inner)| inner)
}

/// A field after the `??` step: absent and null both read as absent.
fn field_non_null<'a>(value: Option<&'a Json>, name: &str) -> Option<&'a Json> {
    field(value?, name).filter(|inner| !matches!(inner, Json::Null))
}

/// `Number.isSafeInteger`.
fn is_safe_integer(value: f64) -> bool {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    value.fract() == 0.0 && value.abs() <= MAX_SAFE_INTEGER
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::parse_json;
    use crate::normalize::{normalize_typography, TypographyInput};

    fn typography() -> SnapshotTypography {
        normalize_typography(TypographyInput {
            font_families: Some(vec!["Dela Gothic One".to_string()]),
            font_size_px: Some(18.0),
            line_height_px: Some(27.0),
            ..Default::default()
        })
        .expect("typography normalizes")
    }

    fn run(input_json: &str) -> Option<String> {
        let value = parse_json(input_json).expect("input parses");
        let input = PrepareInput::from_json(&value);
        required_cjk_dash_contract_input(&input, &typography()).map(|probe| probe.render())
    }

    #[test]
    fn text_without_a_dash_returns_none() {
        assert_eq!(run(r###"{"key":"p1","text":"正文段落"}"###), None);
        assert_eq!(
            run(r###"{"key":"p1","text":"a—b"}"###),
            None,
            "a lone em dash is not a dash run"
        );
    }

    #[test]
    fn one_dash_group_produces_one_probe_span() {
        assert_eq!(
            run(r###"{"key":"p1","text":"前——后——尾"}"###),
            Some(r###"{"key":"p1","text":"——","textSpans":[{"start":0,"end":2,"fontFamilies":["Dela Gothic One"],"fontSizePx":18,"fontWeight":400,"italic":false,"baselineShiftPx":0}]}"###.to_string())
        );
    }

    #[test]
    fn two_styled_dash_runs_group_by_style() {
        let input = r###"{"key":"p1","text":"前——中⸺尾——末","textSpans":[{"start":0,"end":3,"fontFamilies":["F B"]},{"start":3,"end":9,"fontSizePx":22,"italic":true}]}"###;
        assert_eq!(
            run(input),
            Some(r###"{"key":"p1","text":"——⸺——","textSpans":[{"start":0,"end":2,"fontFamilies":["F B"],"fontSizePx":18,"fontWeight":400,"italic":false,"baselineShiftPx":0},{"start":2,"end":3,"fontFamilies":["Dela Gothic One"],"fontSizePx":22,"fontWeight":400,"italic":true,"baselineShiftPx":0},{"start":3,"end":5,"fontFamilies":["Dela Gothic One"],"fontSizePx":22,"fontWeight":400,"italic":true,"baselineShiftPx":0}]}"###.to_string())
        );
    }

    #[test]
    fn later_spans_win_and_loose_values_coerce() {
        let input = r###"{"key":7,"text":"——","textSpans":[{"start":0,"end":2,"fontSizePx":9},{"start":0,"end":2,"fontFamilies":["A","B"],"fontSizePx":"20","fontWeight":"500","baselineShiftPx":"1.5"}]}"###;
        assert_eq!(
            run(input),
            Some(r###"{"key":"7","text":"——","textSpans":[{"start":0,"end":2,"fontFamilies":["A","B"],"fontSizePx":20,"fontWeight":500,"italic":false,"baselineShiftPx":1.5}]}"###.to_string())
        );
    }

    #[test]
    fn unsafe_span_ranges_never_own_a_dash() {
        let input = r###"{"key":"p1","text":"——","textSpans":[{"start":"0","end":2,"fontFamilies":["A"]},{"start":0.5,"end":2,"fontFamilies":["B"]},{"end":2,"fontFamilies":["C"]}]}"###;
        assert_eq!(
            run(input),
            Some(r###"{"key":"p1","text":"——","textSpans":[{"start":0,"end":2,"fontFamilies":["Dela Gothic One"],"fontSizePx":18,"fontWeight":400,"italic":false,"baselineShiftPx":0}]}"###.to_string()),
            "every candidate fails the safe-integer range check, so the typography owns the dash"
        );
    }
}
