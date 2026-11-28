//! Conversion from the precompute plan model to the generated shared prepared plan.

use crate::json::Json;
use crate::plan::{
    Plan, PlanBopomofo, PlanBopomofoPlacement, PlanCell, PlanDecorationSegment, PlanEmphasisDot,
    PlanInlineEdge, PlanLine, PlanRuby,
};
use tiqian_shared::org::tiqian::shared::prepared_dom::bopomofo_placement::BopomofoPlacement;
use tiqian_shared::org::tiqian::shared::prepared_dom::evidence_decoration_kind::EvidenceDecorationKind;
use tiqian_shared::org::tiqian::shared::prepared_dom::evidence_decoration_segment::EvidenceDecorationSegment;
use tiqian_shared::org::tiqian::shared::prepared_dom::evidence_emphasis_dot::EvidenceEmphasisDot;
use tiqian_shared::org::tiqian::shared::prepared_dom::inline_edge_entry::InlineEdgeEntry;
use tiqian_shared::org::tiqian::shared::prepared_dom::plan_bopomofo_zone::PlanBopomofoZone;
use tiqian_shared::org::tiqian::shared::prepared_dom::plan_ruby_annotation::PlanRubyAnnotation;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_emphasis_range::PreparedEmphasisRange;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_plan::PreparedPlan;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_plan_cell::PreparedPlanCell;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_plan_line::PreparedPlanLine;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_spacing_carrier_advance::PreparedSpacingCarrierAdvance;
use tiqian_shared::org::tiqian::shared::prepared_dom::style_delta::StyleDelta;
use tiqian_shared::runtime::u_string::UString;

fn shared(value: &str) -> UString {
    UString::from(value)
}

fn shared_vec(values: &[String]) -> Vec<UString> {
    values.iter().map(|value| shared(value)).collect()
}

pub fn end_reason_name(reason: crate::plan::PlanEndReason) -> &'static str {
    match reason {
        crate::plan::PlanEndReason::AutoWrap => "AutoWrap",
        crate::plan::PlanEndReason::MandatoryBreak => "MandatoryBreak",
        crate::plan::PlanEndReason::ParagraphEnd => "ParagraphEnd",
    }
}

pub fn to_prepared_plan(plan: &Plan) -> PreparedPlan {
    PreparedPlan {
        height: plan.height,
        lines: plan.lines.iter().map(to_line).collect(),
        emphasis_ranges: plan
            .emphasis_ranges
            .iter()
            .map(|(start, end)| PreparedEmphasisRange { start: *start, end: *end })
            .collect(),
        ruby_decisions: plan.ruby_decisions.iter().map(to_ruby).collect(),
        bopomofo_decisions: plan.bopomofo_decisions.iter().map(to_bopomofo).collect(),
        inline_edges: plan.inline_edges.iter().map(to_edge).collect(),
        decoration_segments: if plan.decoration_segments.is_empty() {
            None
        } else {
            Some(plan.decoration_segments.iter().map(to_decoration).collect())
        },
        emphasis_dots: if plan.emphasis_dots.is_empty() {
            None
        } else {
            Some(plan.emphasis_dots.iter().map(to_dot).collect())
        },
        spacing_carrier_advances: if plan.spacing_carrier_advances.is_empty() {
            None
        } else {
            Some(
                plan.spacing_carrier_advances
                    .iter()
                    .map(|entry| PreparedSpacingCarrierAdvance {
                        range_start: f64::from(entry.range_start),
                        range_end: f64::from(entry.range_end),
                        advance: entry.advance,
                    })
                    .collect(),
            )
        },
        font_size: plan.font_size.unwrap_or(0.0),
        overlay_width: plan.overlay_width.unwrap_or(0.0),
    }
}

fn to_line(line: &PlanLine) -> PreparedPlanLine {
    PreparedPlanLine {
        cells: line.cells.iter().map(to_cell).collect(),
        top: line.top,
        bottom: line.bottom,
        baseline: line.baseline,
        indent: line.indent,
        visual_width: line.visual_width,
        hyphen_advance: line.hyphen_advance,
        end_reason: shared(end_reason_name(line.end_reason)),
        range_start: f64::from(line.range_start),
        range_end: f64::from(line.range_end),
    }
}

fn to_cell(cell: &PlanCell) -> PreparedPlanCell {
    PreparedPlanCell {
        range_start: f64::from(cell.range_start),
        range_end: f64::from(cell.range_end),
        source: shared(&cell.source),
        display: shared(&cell.display),
        draw_x: cell.draw_x,
        natural_width: cell.natural_width,
        leading_layout_advance: cell.leading_layout_advance,
        advance: cell.advance,
        shaping_boundary: cell.shaping_boundary,
        open_type_features: if cell.open_type_features.is_empty() {
            None
        } else {
            Some(shared_vec(&cell.open_type_features))
        },
        style: style_delta(&cell.style_delta),
        style_signature: shared(&style_signature(cell)),
        punctuation_signature: shared(&punctuation_signature(cell)),
        latin: cell.latin,
        dash_strategy: cell.dash_strategy.as_deref().map(shared),
        shaping_language: cell.shaping_language.as_deref().map(shared),
        resolved_face: cell.resolved_face.as_deref().map(shared),
        glyph_ids: cell.glyph_ids.as_deref().map(shared),
        shaping_evidence: cell.shaping_evidence.as_deref().map(shared),
        punctuation_ink_floor: cell.punctuation_ink_floor,
        punctuation_body_width: cell.punctuation_body_width,
        render_font_family: cell.render_font_family.as_deref().map(shared),
        inline_object: cell.inline_object,
    }
}

fn style_delta(value: &Option<Json>) -> Option<StyleDelta> {
    let Some(Json::Obj(fields)) = value else {
        return None;
    };
    let number = |name: &str| {
        fields.iter().find(|(key, _)| key == name).and_then(|(_, value)| match value {
            Json::Num(number) => Some(*number),
            _ => None,
        })
    };
    let boolean = |name: &str| {
        fields.iter().find(|(key, _)| key == name).and_then(|(_, value)| match value {
            Json::Bool(flag) => Some(*flag),
            _ => None,
        })
    };
    Some(StyleDelta {
        font_size: number("fontSize"),
        font_weight: number("fontWeight"),
        italic: boolean("italic"),
    })
}

fn to_ruby(ruby: &PlanRuby) -> PlanRubyAnnotation {
    PlanRubyAnnotation {
        font_size: ruby.font_size,
        ascent: ruby.ascent.unwrap_or(0.0),
        font_families: shared_vec(&ruby.font_families),
        text: shared(&ruby.text),
        font_weight: ruby.font_weight,
        center_x: ruby.center_x,
        baseline_y: ruby.baseline_y,
        base_range_end: f64::from(ruby.base_range_end),
    }
}

fn to_bopomofo(zone: &PlanBopomofo) -> PlanBopomofoZone {
    PlanBopomofoZone {
        text: shared(&zone.text),
        font_weight: zone.font_weight,
        font_families: shared_vec(&zone.font_families),
        placements: zone.placements.iter().map(to_placement).collect(),
        base_range_end: f64::from(zone.base_range_end),
    }
}

fn to_placement(placement: &PlanBopomofoPlacement) -> BopomofoPlacement {
    BopomofoPlacement {
        text: shared(&placement.text),
        role: shared(&placement.role),
        left: placement.left,
        top: placement.top,
        width: placement.width,
        height: placement.height,
    }
}

fn to_edge(edge: &PlanInlineEdge) -> InlineEdgeEntry {
    InlineEdgeEntry {
        offset: edge.offset,
        inline_start: edge.inline_start,
        inline_end: edge.inline_end,
    }
}

fn to_decoration(segment: &PlanDecorationSegment) -> EvidenceDecorationSegment {
    EvidenceDecorationSegment {
        left: segment.left,
        top: segment.top,
        right: segment.right,
        kind: decoration_kind(&segment.kind),
    }
}

fn decoration_kind(kind: &str) -> EvidenceDecorationKind {
    match kind {
        "BookTitle" => EvidenceDecorationKind::BookTitle,
        _ => EvidenceDecorationKind::ProperNoun,
    }
}

fn to_dot(dot: &PlanEmphasisDot) -> EvidenceEmphasisDot {
    EvidenceEmphasisDot {
        cluster_range_start: dot.cluster_range_start.unwrap_or(0.0),
        anchor_x: dot.anchor_x,
        anchor_y: dot.anchor_y,
        dot_diameter: dot.dot_diameter,
    }
}

fn style_signature(cell: &PlanCell) -> String {
    match &cell.style_delta {
        Some(style) => style.render(),
        None => "null".to_string(),
    }
}

fn punctuation_signature(cell: &PlanCell) -> String {
    let floor = match cell.punctuation_ink_floor {
        Some(value) => crate::js_compat::js_number_string(value),
        None => "null".to_string(),
    };
    let body = match cell.punctuation_body_width {
        Some(value) => crate::js_compat::js_number_string(value),
        None => "null".to_string(),
    };
    format!("[{floor},{body}]")
}
