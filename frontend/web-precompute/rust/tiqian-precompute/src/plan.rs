//! Plan JSON deserialization (ADR 0050 amendment `PrecomputeInRust`).
//!
//! `toPreparedParagraphJson` in the Kotlin layout module is the single plan
//! producer. This module only reads the bytes back for Rust consumers; it
//! emits nothing. Field names and value shapes mirror the Kotlin emitter
//! one to one.

use crate::js_compat::{trunc_sat_i32, trunc_sat_i64};
use crate::json::{parse_json, Json};
use tiqian::NamedError;

/// `schema` of every plan this revision understands.
pub const PLAN_SCHEMA: i64 = 1;

/// `layoutRevision` of every plan this revision understands.
pub const PLAN_LAYOUT_REVISION: &str = "tiqian-layout-v2";

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub width: f64,
    pub height: f64,
    pub lines: Vec<PlanLine>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PlanLine {
    pub range_start: i32,
    pub range_end: i32,
    pub top: f64,
    pub bottom: f64,
    pub baseline: f64,
    pub indent: f64,
    pub visual_width: f64,
    pub hyphen_advance: f64,
    pub end_reason: PlanEndReason,
    pub cells: Vec<PlanCell>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanEndReason {
    AutoWrap,
    MandatoryBreak,
    ParagraphEnd,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PlanCell {
    pub range_start: i32,
    pub range_end: i32,
    pub source: String,
    pub display: String,
    pub draw_x: f64,
    pub natural_width: f64,
    pub leading_layout_advance: f64,
    /// Present only on multi-code-unit clusters; absent means false.
    pub shaping_boundary: bool,
    /// Present only when shaping applied OpenType features by policy.
    pub open_type_features: Vec<String>,
}

impl Plan {
    /// Deserializes one plan document. Schema and layout revision must match
    /// this revision's constants; failures carry named issues so callers can
    /// surface them the way engine errors surface.
    pub fn from_json_str(text: &str) -> Result<Plan, NamedError> {
        let value =
            parse_json(text).map_err(|error| NamedError(format!("InvalidPlanJson:{error}")))?;
        let fields = match value {
            Json::Obj(fields) => fields,
            _ => return Err(NamedError("InvalidPlanJson:not an object".to_string())),
        };
        let schema = number_field(&fields, "schema")
            .map_err(|_| NamedError("InvalidPlanSchema".to_string()))?;
        if trunc_sat_i64(schema) != PLAN_SCHEMA {
            return Err(NamedError("InvalidPlanSchema".to_string()));
        }
        let revision = string_field(&fields, "layoutRevision")
            .map_err(|_| NamedError("InvalidPlanLayoutRevision".to_string()))?;
        if revision != PLAN_LAYOUT_REVISION {
            return Err(NamedError("InvalidPlanLayoutRevision".to_string()));
        }
        // The js plan reader treats `width` as optional and no render path
        // reads it; hand-built plans without it must lower the same way.
        let width = match find(&fields, "width") {
            Some(_) => number_field(&fields, "width").map_err(field_error("width"))?,
            None => 0.0,
        };
        let height = number_field(&fields, "height").map_err(field_error("height"))?;
        let lines = array_field(&fields, "lines").map_err(field_error("lines"))?;
        let lines = lines
            .iter()
            .map(|line| PlanLine::from_json(line))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Plan {
            width,
            height,
            lines,
        })
    }
}

impl PlanLine {
    fn from_json(value: &Json) -> Result<PlanLine, NamedError> {
        let fields = object_value(value, "line")?;
        let end_reason = string_field(&fields, "endReason").map_err(field_error("endReason"))?;
        let cells = array_field(&fields, "cells").map_err(field_error("cells"))?;
        let cells = cells
            .iter()
            .map(|cell| PlanCell::from_json(cell))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(PlanLine {
            range_start: integer_field(&fields, "rangeStart").map_err(field_error("rangeStart"))?,
            range_end: integer_field(&fields, "rangeEnd").map_err(field_error("rangeEnd"))?,
            top: number_field(&fields, "top").map_err(field_error("top"))?,
            bottom: number_field(&fields, "bottom").map_err(field_error("bottom"))?,
            baseline: number_field(&fields, "baseline").map_err(field_error("baseline"))?,
            indent: number_field(&fields, "indent").map_err(field_error("indent"))?,
            visual_width: number_field(&fields, "visualWidth")
                .map_err(field_error("visualWidth"))?,
            hyphen_advance: number_field(&fields, "hyphenAdvance")
                .map_err(field_error("hyphenAdvance"))?,
            end_reason: match end_reason.as_str() {
                "AutoWrap" => PlanEndReason::AutoWrap,
                "MandatoryBreak" => PlanEndReason::MandatoryBreak,
                "ParagraphEnd" => PlanEndReason::ParagraphEnd,
                _ => return Err(NamedError("InvalidPlanEndReason".to_string())),
            },
            cells,
        })
    }
}

impl PlanCell {
    fn from_json(value: &Json) -> Result<PlanCell, NamedError> {
        let fields = object_value(value, "cell")?;
        let open_type_features = match find(&fields, "openTypeFeatures") {
            Some(Json::Arr(items)) => items
                .iter()
                .map(|item| match item {
                    Json::Str(text) => Ok(text.clone()),
                    _ => Err(NamedError(
                        "InvalidPlanJsonField:openTypeFeatures".to_string(),
                    )),
                })
                .collect::<Result<Vec<_>, _>>()?,
            Some(_) => {
                return Err(NamedError(
                    "InvalidPlanJsonField:openTypeFeatures".to_string(),
                ))
            }
            None => Vec::new(),
        };
        Ok(PlanCell {
            range_start: integer_field(&fields, "rangeStart").map_err(field_error("rangeStart"))?,
            range_end: integer_field(&fields, "rangeEnd").map_err(field_error("rangeEnd"))?,
            source: string_field(&fields, "source").map_err(field_error("source"))?,
            display: string_field(&fields, "display").map_err(field_error("display"))?,
            draw_x: number_field(&fields, "drawX").map_err(field_error("drawX"))?,
            natural_width: number_field(&fields, "naturalWidth")
                .map_err(field_error("naturalWidth"))?,
            leading_layout_advance: number_field(&fields, "leadingLayoutAdvance")
                .map_err(field_error("leadingLayoutAdvance"))?,
            shaping_boundary: match find(&fields, "shapingBoundary") {
                Some(Json::Bool(value)) => *value,
                Some(_) => {
                    return Err(NamedError(
                        "InvalidPlanJsonField:shapingBoundary".to_string(),
                    ))
                }
                None => false,
            },
            open_type_features,
        })
    }
}

fn find<'a>(fields: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    fields
        .iter()
        .find(|(name, _)| name == key)
        .map(|(_, value)| value)
}

fn field_error(field: &str) -> impl Fn(NamedError) -> NamedError {
    let field = field.to_string();
    move |_| NamedError(format!("InvalidPlanJsonField:{field}"))
}

fn object_value<'a>(value: &'a Json, what: &str) -> Result<&'a [(String, Json)], NamedError> {
    match value {
        Json::Obj(fields) => Ok(fields),
        _ => Err(NamedError(format!("InvalidPlanJsonField:{what}"))),
    }
}

fn number_field(fields: &[(String, Json)], key: &str) -> Result<f64, NamedError> {
    match find(fields, key) {
        Some(Json::Num(value)) => Ok(*value),
        _ => Err(NamedError(format!("InvalidPlanJsonField:{key}"))),
    }
}

fn integer_field(fields: &[(String, Json)], key: &str) -> Result<i32, NamedError> {
    let value = number_field(fields, key)?;
    if value.fract() != 0.0 || !(f64::from(i32::MIN)..=f64::from(i32::MAX)).contains(&value) {
        return Err(NamedError(format!("InvalidPlanJsonField:{key}")));
    }
    Ok(trunc_sat_i32(value))
}

fn string_field(fields: &[(String, Json)], key: &str) -> Result<String, NamedError> {
    match find(fields, key) {
        Some(Json::Str(value)) => Ok(value.clone()),
        _ => Err(NamedError(format!("InvalidPlanJsonField:{key}"))),
    }
}

fn array_field<'a>(fields: &'a [(String, Json)], key: &str) -> Result<&'a [Json], NamedError> {
    match find(fields, key) {
        Some(Json::Arr(items)) => Ok(items),
        _ => Err(NamedError(format!("InvalidPlanJsonField:{key}"))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn two_line_plan() -> String {
        "{\"schema\":1,\"layoutRevision\":\"tiqian-layout-v2\",\"width\":80.0,\"height\":48.0,\
\"lines\":[\
{\"rangeStart\":0,\"rangeEnd\":5,\"top\":0.0,\"bottom\":24.0,\"baseline\":19.0,\"indent\":32.0,\
\"visualWidth\":80.0,\"hyphenAdvance\":0.0,\"endReason\":\"AutoWrap\",\"cells\":[\
{\"rangeStart\":0,\"rangeEnd\":1,\"source\":\"字\",\"display\":\"字\",\"drawX\":0.0,\
\"naturalWidth\":16.0,\"leadingLayoutAdvance\":16.0},\
{\"rangeStart\":4,\"rangeEnd\":5,\"source\":\"字\",\"display\":\"字\",\"drawX\":64.0,\
\"naturalWidth\":16.0,\"leadingLayoutAdvance\":16.0,\"shapingBoundary\":true,\
\"openTypeFeatures\":[\"fwid\"]}]}\
,{\"rangeStart\":5,\"rangeEnd\":10,\"top\":24.0,\"bottom\":48.0,\"baseline\":43.0,\"indent\":0.0,\
\"visualWidth\":80.0,\"hyphenAdvance\":0.0,\"endReason\":\"ParagraphEnd\",\"cells\":[]}]}"
            .to_string()
    }

    #[test]
    fn reads_every_field_the_emitter_writes() {
        let plan = Plan::from_json_str(&two_line_plan()).unwrap();
        assert_eq!(plan.width, 80.0);
        assert_eq!(plan.height, 48.0);
        assert_eq!(plan.lines.len(), 2);
        let first = &plan.lines[0];
        assert_eq!((first.range_start, first.range_end), (0, 5));
        assert_eq!(first.indent, 32.0);
        assert_eq!(first.end_reason, PlanEndReason::AutoWrap);
        assert_eq!(first.cells[0].source, "字");
        assert!(!first.cells[0].shaping_boundary);
        assert!(first.cells[0].open_type_features.is_empty());
        assert!(first.cells[1].shaping_boundary);
        assert_eq!(first.cells[1].open_type_features, vec!["fwid".to_string()]);
        assert_eq!(plan.lines[1].end_reason, PlanEndReason::ParagraphEnd);
    }

    #[test]
    fn rejects_schema_and_revision_damage() {
        let plan = two_line_plan();
        assert_eq!(
            Plan::from_json_str(&plan.replace("\"schema\":1", "\"schema\":2"))
                .unwrap_err()
                .name(),
            "InvalidPlanSchema"
        );
        assert_eq!(
            Plan::from_json_str(&plan.replace("tiqian-layout-v2", "other"))
                .unwrap_err()
                .name(),
            "InvalidPlanLayoutRevision"
        );
    }

    #[test]
    fn rejects_structural_damage_with_field_names() {
        let plan = two_line_plan();
        let error =
            Plan::from_json_str(&plan.replace("\"width\":80.0", "\"width\":\"80\"")).unwrap_err();
        assert_eq!(error.name(), "InvalidPlanJsonField:width");
        let error = Plan::from_json_str(
            &plan.replace("\"endReason\":\"AutoWrap\"", "\"endReason\":\"New\""),
        )
        .unwrap_err();
        assert_eq!(error.name(), "InvalidPlanEndReason");
        let error = Plan::from_json_str("{").unwrap_err();
        assert!(error.name().starts_with("InvalidPlanJson"));
    }

    #[test]
    fn reads_plans_without_width() {
        let plan = Plan::from_json_str(&two_line_plan().replace("\"width\":80.0,", "")).unwrap();
        assert_eq!(plan.width, 0.0);
        assert_eq!(plan.height, 48.0);
        assert_eq!(plan.lines.len(), 2);
    }
}
