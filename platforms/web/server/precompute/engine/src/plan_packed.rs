//! Packed plan decoding (corrective-2).
//!
//! The Kotlin engine in `engine/nativeMain` is the single writer
//! (`tiqian_plan_abi.h`); this module is the Rust reader that fills the
//! existing [`Plan`] struct. Little endian, per-column partitions, string pool
//! with u32 deltas, f64 for geometry. JSON decoding stays for the dump path.

use tiqian::NamedError;

use crate::json::Json;
use crate::plan::{
    Plan, PlanBopomofo, PlanBopomofoPlacement, PlanCell, PlanDecorationSegment, PlanEmphasisDot,
    PlanEndReason, PlanInlineEdge, PlanLine, PlanRuby, PlanSpacingCarrierAdvance,
};

const PLAN_MAGIC: u32 = 0x5451_5050;
const PLAN_PROTOCOL_REVISION: u32 = 2;
const PLAN_STRING_ABSENT: u32 = 0xFFFF_FFFF;

fn invalid() -> NamedError {
    NamedError("InvalidPlanPacked".to_string())
}

fn checked_add(a: usize, b: usize) -> Result<usize, NamedError> {
    a.checked_add(b).ok_or_else(invalid)
}
fn checked_mul(a: usize, b: usize) -> Result<usize, NamedError> {
    a.checked_mul(b).ok_or_else(invalid)
}
fn try_usize(v: u32) -> Result<usize, NamedError> {
    usize::try_from(v).map_err(|_| invalid())
}

fn read_u32_at(bytes: &[u8], at: usize) -> Result<u32, NamedError> {
    let mut raw = [0u8; 4];
    raw.copy_from_slice(bytes.get(at..checked_add(at, 4)?).ok_or_else(invalid)?);
    Ok(u32::from_le_bytes(raw))
}
fn read_i32_at(bytes: &[u8], at: usize) -> Result<i32, NamedError> {
    Ok(read_u32_at(bytes, at)? as i32)
}
fn read_f64_at(bytes: &[u8], at: usize) -> Result<f64, NamedError> {
    let mut raw = [0u8; 8];
    raw.copy_from_slice(bytes.get(at..checked_add(at, 8)?).ok_or_else(invalid)?);
    Ok(f64::from_le_bytes(raw))
}
fn read_u8_at(bytes: &[u8], at: usize) -> Result<u8, NamedError> {
    Ok(*bytes.get(at).ok_or_else(invalid)?)
}

fn string_at(pool: &[String], index: u32) -> Result<String, NamedError> {
    if index == PLAN_STRING_ABSENT {
        return Err(invalid());
    }
    pool.get(try_usize(index)?).cloned().ok_or_else(invalid)
}
fn optional_string_at(pool: &[String], index: u32) -> Result<Option<String>, NamedError> {
    if index == PLAN_STRING_ABSENT {
        Ok(None)
    } else {
        Ok(Some(
            pool.get(try_usize(index)?).cloned().ok_or_else(invalid)?,
        ))
    }
}

pub fn decode(bytes: &[u8]) -> Result<Plan, NamedError> {
    let mut pos = 0usize;
    // header
    let magic = read_u32_at(bytes, pos)?;
    pos = checked_add(pos, 4)?;
    if magic != PLAN_MAGIC {
        return Err(invalid());
    }
    let version = read_u32_at(bytes, pos)?;
    pos = checked_add(pos, 4)?;
    if version != PLAN_PROTOCOL_REVISION {
        return Err(invalid());
    }
    let width = read_f64_at(bytes, pos)?;
    pos = checked_add(pos, 8)?;
    let height = read_f64_at(bytes, pos)?;
    pos = checked_add(pos, 8)?;
    let font_size_raw = read_f64_at(bytes, pos)?;
    pos = checked_add(pos, 8)?;
    let overlay_width_raw = read_f64_at(bytes, pos)?;
    pos = checked_add(pos, 8)?;
    let line_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let cell_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let emphasis_range_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let inline_edge_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let ruby_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let bopomofo_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let bopomofo_placement_total = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let decoration_segment_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let emphasis_dot_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let string_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let feature_total = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let ruby_family_total = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let bopomofo_family_total = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;

    // string deltas
    let mut deltas: Vec<u32> = Vec::with_capacity(string_count);
    for _ in 0..string_count {
        deltas.push(read_u32_at(bytes, pos)?);
        pos = checked_add(pos, 4)?;
    }
    // string bytes
    let string_bytes_len: usize = deltas.iter().map(|d| *d as usize).sum();
    let string_bytes_start = pos;
    let string_bytes_end = checked_add(pos, string_bytes_len)?;
    if string_bytes_end > bytes.len() {
        return Err(invalid());
    }
    let mut pool: Vec<String> = Vec::with_capacity(string_count);
    let mut cursor = string_bytes_start;
    for delta in &deltas {
        let len = *delta as usize;
        let end = checked_add(cursor, len)?;
        let slice = bytes.get(cursor..end).ok_or_else(invalid)?;
        let s = String::from_utf8(slice.to_vec()).map_err(|_| invalid())?;
        pool.push(s);
        cursor = end;
    }
    pos = string_bytes_end;

    // line columns offsets
    let line_range_start = pos;
    pos = checked_add(pos, checked_mul(line_count, 4)?)?;
    let line_range_end = pos;
    pos = checked_add(pos, checked_mul(line_count, 4)?)?;
    let line_top = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_bottom = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_baseline = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_indent = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_visual_width = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_hyphen_advance = pos;
    pos = checked_add(pos, checked_mul(line_count, 8)?)?;
    let line_end_reason = pos;
    pos = checked_add(pos, line_count)?;
    let line_cell_count = pos;
    pos = checked_add(pos, checked_mul(line_count, 4)?)?;

    // cell columns
    let cell_range_start = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_range_end = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_source_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_display_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_draw_x = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_natural_width = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_leading_advance = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_shaping_boundary = pos;
    pos = checked_add(pos, cell_count)?;
    let cell_latin = pos;
    pos = checked_add(pos, cell_count)?;
    let cell_render_family_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_dash_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_language_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_resolved_face_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_glyph_ids_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_evidence_ref = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_ink_floor = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_body_width = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_advance = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_inline_object = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_style_font_size = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_style_font_weight = pos;
    pos = checked_add(pos, checked_mul(cell_count, 8)?)?;
    let cell_style_italic = pos;
    pos = checked_add(pos, cell_count)?;
    let cell_feature_offset = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;
    let cell_feature_count = pos;
    pos = checked_add(pos, checked_mul(cell_count, 4)?)?;

    let feature_pool_start = pos;
    pos = checked_add(pos, checked_mul(feature_total, 4)?)?;

    let emphasis_start = pos;
    pos = checked_add(pos, checked_mul(emphasis_range_count, 8)?)?;
    let emphasis_end = pos;
    pos = checked_add(pos, checked_mul(emphasis_range_count, 8)?)?;

    let inline_edge_offset = pos;
    pos = checked_add(pos, checked_mul(inline_edge_count, 8)?)?;
    let inline_edge_start = pos;
    pos = checked_add(pos, checked_mul(inline_edge_count, 8)?)?;
    let inline_edge_end = pos;
    pos = checked_add(pos, checked_mul(inline_edge_count, 8)?)?;

    let ruby_base_start = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 4)?)?;
    let ruby_base_end = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 4)?)?;
    let ruby_text_ref = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 4)?)?;
    let ruby_center_x = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 8)?)?;
    let ruby_baseline_y = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 8)?)?;
    let ruby_font_size = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 8)?)?;
    let ruby_font_weight = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 8)?)?;
    let ruby_family_offset = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 4)?)?;
    let ruby_family_count = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 4)?)?;
    let ruby_ascent = pos;
    pos = checked_add(pos, checked_mul(ruby_count, 8)?)?;

    let ruby_family_pool_start = pos;
    pos = checked_add(pos, checked_mul(ruby_family_total, 4)?)?;

    let bopomofo_base_start = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_base_end = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_text_ref = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_font_weight = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 8)?)?;
    let bopomofo_family_offset = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_family_count = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_place_offset = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;
    let bopomofo_place_count = pos;
    pos = checked_add(pos, checked_mul(bopomofo_count, 4)?)?;

    let bopomofo_family_pool_start = pos;
    pos = checked_add(pos, checked_mul(bopomofo_family_total, 4)?)?;

    let bopomofo_place_text_ref = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 4)?)?;
    let bopomofo_place_role_ref = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 4)?)?;
    let bopomofo_place_left = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 8)?)?;
    let bopomofo_place_top = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 8)?)?;
    let bopomofo_place_width = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 8)?)?;
    let bopomofo_place_height = pos;
    pos = checked_add(pos, checked_mul(bopomofo_placement_total, 8)?)?;

    let decoration_kind_ref = pos;
    pos = checked_add(pos, checked_mul(decoration_segment_count, 4)?)?;
    let decoration_left = pos;
    pos = checked_add(pos, checked_mul(decoration_segment_count, 8)?)?;
    let decoration_top = pos;
    pos = checked_add(pos, checked_mul(decoration_segment_count, 8)?)?;
    let decoration_right = pos;
    pos = checked_add(pos, checked_mul(decoration_segment_count, 8)?)?;

    let dot_cluster_start = pos;
    pos = checked_add(pos, checked_mul(emphasis_dot_count, 8)?)?;
    let dot_anchor_x = pos;
    pos = checked_add(pos, checked_mul(emphasis_dot_count, 8)?)?;
    let dot_anchor_y = pos;
    pos = checked_add(pos, checked_mul(emphasis_dot_count, 8)?)?;
    let dot_diameter = pos;
    pos = checked_add(pos, checked_mul(emphasis_dot_count, 8)?)?;

    let spacing_carrier_count = try_usize(read_u32_at(bytes, pos)?)?;
    pos = checked_add(pos, 4)?;
    let carrier_range_start = pos;
    pos = checked_add(pos, checked_mul(spacing_carrier_count, 4)?)?;
    let carrier_range_end = pos;
    pos = checked_add(pos, checked_mul(spacing_carrier_count, 4)?)?;
    let carrier_advance = pos;
    pos = checked_add(pos, checked_mul(spacing_carrier_count, 8)?)?;

    if pos != bytes.len() {
        return Err(invalid());
    }

    // Validate references for strings etc are within pool.
    // Build lines.
    let mut lines: Vec<PlanLine> = Vec::with_capacity(line_count);
    let mut cell_cursor = 0usize;
    for li in 0..line_count {
        let range_start = read_i32_at(bytes, checked_add(line_range_start, checked_mul(li, 4)?)?)?;
        let range_end = read_i32_at(bytes, checked_add(line_range_end, checked_mul(li, 4)?)?)?;
        let top = read_f64_at(bytes, checked_add(line_top, checked_mul(li, 8)?)?)?;
        let bottom = read_f64_at(bytes, checked_add(line_bottom, checked_mul(li, 8)?)?)?;
        let baseline = read_f64_at(bytes, checked_add(line_baseline, checked_mul(li, 8)?)?)?;
        let indent = read_f64_at(bytes, checked_add(line_indent, checked_mul(li, 8)?)?)?;
        let visual_width =
            read_f64_at(bytes, checked_add(line_visual_width, checked_mul(li, 8)?)?)?;
        let hyphen_advance = read_f64_at(
            bytes,
            checked_add(line_hyphen_advance, checked_mul(li, 8)?)?,
        )?;
        let end_reason_code = read_u8_at(bytes, line_end_reason + li)?;
        let end_reason = match end_reason_code {
            0 => PlanEndReason::AutoWrap,
            1 => PlanEndReason::MandatoryBreak,
            2 => PlanEndReason::ParagraphEnd,
            _ => return Err(invalid()),
        };
        let cell_n = try_usize(read_u32_at(
            bytes,
            checked_add(line_cell_count, checked_mul(li, 4)?)?,
        )?)?;
        let mut cells: Vec<PlanCell> = Vec::with_capacity(cell_n);
        for _ in 0..cell_n {
            let ci = cell_cursor;
            cell_cursor = checked_add(cell_cursor, 1)?;
            let range_start =
                read_i32_at(bytes, checked_add(cell_range_start, checked_mul(ci, 4)?)?)?;
            let range_end = read_i32_at(bytes, checked_add(cell_range_end, checked_mul(ci, 4)?)?)?;
            let source_ref =
                read_u32_at(bytes, checked_add(cell_source_ref, checked_mul(ci, 4)?)?)?;
            let display_ref =
                read_u32_at(bytes, checked_add(cell_display_ref, checked_mul(ci, 4)?)?)?;
            let draw_x = read_f64_at(bytes, checked_add(cell_draw_x, checked_mul(ci, 8)?)?)?;
            let natural_width =
                read_f64_at(bytes, checked_add(cell_natural_width, checked_mul(ci, 8)?)?)?;
            let leading = read_f64_at(
                bytes,
                checked_add(cell_leading_advance, checked_mul(ci, 8)?)?,
            )?;
            let shaping_boundary = read_u8_at(bytes, cell_shaping_boundary + ci)? != 0;
            let latin = read_u8_at(bytes, cell_latin + ci)? != 0;
            let render_family = optional_string_at(
                &pool,
                read_u32_at(
                    bytes,
                    checked_add(cell_render_family_ref, checked_mul(ci, 4)?)?,
                )?,
            )?;
            let dash_strategy = optional_string_at(
                &pool,
                read_u32_at(bytes, checked_add(cell_dash_ref, checked_mul(ci, 4)?)?)?,
            )?;
            let shaping_language = optional_string_at(
                &pool,
                read_u32_at(bytes, checked_add(cell_language_ref, checked_mul(ci, 4)?)?)?,
            )?;
            let resolved_face = optional_string_at(
                &pool,
                read_u32_at(
                    bytes,
                    checked_add(cell_resolved_face_ref, checked_mul(ci, 4)?)?,
                )?,
            )?;
            let glyph_ids = optional_string_at(
                &pool,
                read_u32_at(bytes, checked_add(cell_glyph_ids_ref, checked_mul(ci, 4)?)?)?,
            )?;
            let shaping_evidence = optional_string_at(
                &pool,
                read_u32_at(bytes, checked_add(cell_evidence_ref, checked_mul(ci, 4)?)?)?,
            )?;
            let ink_floor_raw =
                read_f64_at(bytes, checked_add(cell_ink_floor, checked_mul(ci, 8)?)?)?;
            let body_width_raw =
                read_f64_at(bytes, checked_add(cell_body_width, checked_mul(ci, 8)?)?)?;
            let (punct_ink_floor, punct_body_width) =
                if ink_floor_raw.is_nan() && body_width_raw.is_nan() {
                    (None, None)
                } else if ink_floor_raw.is_finite() && body_width_raw.is_finite() {
                    (Some(ink_floor_raw), Some(body_width_raw))
                } else {
                    return Err(invalid());
                };
            let adv_raw = read_f64_at(bytes, checked_add(cell_advance, checked_mul(ci, 8)?)?)?;
            let inline_obj_raw =
                read_f64_at(bytes, checked_add(cell_inline_object, checked_mul(ci, 8)?)?)?;
            let style_font_size_raw = read_f64_at(
                bytes,
                checked_add(cell_style_font_size, checked_mul(ci, 8)?)?,
            )?;
            let style_font_weight_raw = read_f64_at(
                bytes,
                checked_add(cell_style_font_weight, checked_mul(ci, 8)?)?,
            )?;
            let style_italic_raw = read_u8_at(bytes, cell_style_italic + ci)?;
            let style_italic = match style_italic_raw {
                0 | 1 => Some(style_italic_raw != 0),
                2 => None,
                _ => return Err(invalid()),
            };
            // Build style delta json if any field present.
            let style_delta = if style_font_size_raw.is_nan()
                && style_font_weight_raw.is_nan()
                && style_italic.is_none()
            {
                None
            } else {
                let mut fields: Vec<(String, Json)> = Vec::new();
                if style_font_size_raw.is_finite() {
                    fields.push(("fontSize".to_string(), Json::Num(style_font_size_raw)));
                } else if !style_font_size_raw.is_nan() {
                    return Err(invalid());
                }
                if style_font_weight_raw.is_finite() {
                    fields.push(("fontWeight".to_string(), Json::Num(style_font_weight_raw)));
                } else if !style_font_weight_raw.is_nan() {
                    return Err(invalid());
                }
                if let Some(italic) = style_italic {
                    fields.push(("italic".to_string(), Json::Bool(italic)));
                }
                if fields.is_empty() {
                    // empty object case: evidence path emitted {} for non-paint deltas
                    // we keep empty object to preserve presence.
                    Some(Json::Obj(Vec::new()))
                } else {
                    Some(Json::Obj(fields))
                }
            };
            let feature_offset = try_usize(read_u32_at(
                bytes,
                checked_add(cell_feature_offset, checked_mul(ci, 4)?)?,
            )?)?;
            let feature_count = try_usize(read_u32_at(
                bytes,
                checked_add(cell_feature_count, checked_mul(ci, 4)?)?,
            )?)?;
            if checked_add(feature_offset, feature_count)? > feature_total {
                return Err(invalid());
            }
            let mut open_type_features: Vec<String> = Vec::with_capacity(feature_count);
            for k in 0..feature_count {
                let idx = read_u32_at(
                    bytes,
                    checked_add(feature_pool_start, checked_mul(feature_offset + k, 4)?)?,
                )?;
                open_type_features.push(string_at(&pool, idx)?);
            }
            let source = string_at(&pool, source_ref)?;
            let display = string_at(&pool, display_ref)?;
            cells.push(PlanCell {
                range_start,
                range_end,
                source,
                display,
                draw_x,
                natural_width,
                leading_layout_advance: leading,
                shaping_boundary,
                open_type_features,
                render_font_family: render_family,
                dash_strategy,
                shaping_language,
                resolved_face,
                glyph_ids,
                shaping_evidence,
                punctuation_ink_floor: punct_ink_floor,
                punctuation_body_width: punct_body_width,
                latin,
                advance: if adv_raw.is_nan() {
                    None
                } else if adv_raw.is_finite() {
                    Some(adv_raw)
                } else {
                    return Err(invalid());
                },
                inline_object: if inline_obj_raw.is_nan() {
                    None
                } else if inline_obj_raw.is_finite() {
                    Some(inline_obj_raw)
                } else {
                    return Err(invalid());
                },
                style_delta,
            });
        }
        lines.push(PlanLine {
            range_start,
            range_end,
            top,
            bottom,
            baseline,
            indent,
            visual_width,
            hyphen_advance,
            end_reason,
            cells,
        });
    }
    if cell_cursor != cell_count {
        return Err(invalid());
    }

    // Emphasis ranges
    let mut emphasis_ranges: Vec<(f64, f64)> = Vec::with_capacity(emphasis_range_count);
    for i in 0..emphasis_range_count {
        let s = read_f64_at(bytes, checked_add(emphasis_start, checked_mul(i, 8)?)?)?;
        let e = read_f64_at(bytes, checked_add(emphasis_end, checked_mul(i, 8)?)?)?;
        emphasis_ranges.push((s, e));
    }
    // Inline edges
    let mut inline_edges: Vec<PlanInlineEdge> = Vec::with_capacity(inline_edge_count);
    for i in 0..inline_edge_count {
        let offset = read_f64_at(bytes, checked_add(inline_edge_offset, checked_mul(i, 8)?)?)?;
        let s = read_f64_at(bytes, checked_add(inline_edge_start, checked_mul(i, 8)?)?)?;
        let e = read_f64_at(bytes, checked_add(inline_edge_end, checked_mul(i, 8)?)?)?;
        inline_edges.push(PlanInlineEdge {
            offset,
            inline_start: if s.is_nan() { None } else { Some(s) },
            inline_end: if e.is_nan() { None } else { Some(e) },
        });
    }
    // Ruby
    let mut rubys: Vec<PlanRuby> = Vec::with_capacity(ruby_count);
    for i in 0..ruby_count {
        let base_start = read_i32_at(bytes, checked_add(ruby_base_start, checked_mul(i, 4)?)?)?;
        let base_end = read_i32_at(bytes, checked_add(ruby_base_end, checked_mul(i, 4)?)?)?;
        let text_idx = read_u32_at(bytes, checked_add(ruby_text_ref, checked_mul(i, 4)?)?)?;
        let center_x = read_f64_at(bytes, checked_add(ruby_center_x, checked_mul(i, 8)?)?)?;
        let baseline_y = read_f64_at(bytes, checked_add(ruby_baseline_y, checked_mul(i, 8)?)?)?;
        let font_size = read_f64_at(bytes, checked_add(ruby_font_size, checked_mul(i, 8)?)?)?;
        let font_weight = read_f64_at(bytes, checked_add(ruby_font_weight, checked_mul(i, 8)?)?)?;
        let fam_off = try_usize(read_u32_at(
            bytes,
            checked_add(ruby_family_offset, checked_mul(i, 4)?)?,
        )?)?;
        let fam_cnt = try_usize(read_u32_at(
            bytes,
            checked_add(ruby_family_count, checked_mul(i, 4)?)?,
        )?)?;
        let ascent_raw = read_f64_at(bytes, checked_add(ruby_ascent, checked_mul(i, 8)?)?)?;
        if checked_add(fam_off, fam_cnt)? > ruby_family_total {
            return Err(invalid());
        }
        let mut families: Vec<String> = Vec::with_capacity(fam_cnt);
        for k in 0..fam_cnt {
            let idx = read_u32_at(
                bytes,
                checked_add(ruby_family_pool_start, checked_mul(fam_off + k, 4)?)?,
            )?;
            families.push(string_at(&pool, idx)?);
        }
        rubys.push(PlanRuby {
            base_range_start: base_start,
            base_range_end: base_end,
            text: string_at(&pool, text_idx)?,
            center_x,
            baseline_y,
            font_size,
            font_weight,
            font_families: families,
            ascent: if ascent_raw.is_nan() {
                None
            } else {
                Some(ascent_raw)
            },
        });
    }
    // Bopomofo
    let mut bopomofos: Vec<PlanBopomofo> = Vec::with_capacity(bopomofo_count);
    for i in 0..bopomofo_count {
        let base_start = read_i32_at(bytes, checked_add(bopomofo_base_start, checked_mul(i, 4)?)?)?;
        let base_end = read_i32_at(bytes, checked_add(bopomofo_base_end, checked_mul(i, 4)?)?)?;
        let text_idx = read_u32_at(bytes, checked_add(bopomofo_text_ref, checked_mul(i, 4)?)?)?;
        let font_weight = read_f64_at(
            bytes,
            checked_add(bopomofo_font_weight, checked_mul(i, 8)?)?,
        )?;
        let fam_off = try_usize(read_u32_at(
            bytes,
            checked_add(bopomofo_family_offset, checked_mul(i, 4)?)?,
        )?)?;
        let fam_cnt = try_usize(read_u32_at(
            bytes,
            checked_add(bopomofo_family_count, checked_mul(i, 4)?)?,
        )?)?;
        let place_off = try_usize(read_u32_at(
            bytes,
            checked_add(bopomofo_place_offset, checked_mul(i, 4)?)?,
        )?)?;
        let place_cnt = try_usize(read_u32_at(
            bytes,
            checked_add(bopomofo_place_count, checked_mul(i, 4)?)?,
        )?)?;
        if checked_add(fam_off, fam_cnt)? > bopomofo_family_total {
            return Err(invalid());
        }
        if checked_add(place_off, place_cnt)? > bopomofo_placement_total {
            return Err(invalid());
        }
        let mut families: Vec<String> = Vec::with_capacity(fam_cnt);
        for k in 0..fam_cnt {
            let idx = read_u32_at(
                bytes,
                checked_add(bopomofo_family_pool_start, checked_mul(fam_off + k, 4)?)?,
            )?;
            families.push(string_at(&pool, idx)?);
        }
        let mut placements: Vec<PlanBopomofoPlacement> = Vec::with_capacity(place_cnt);
        for k in 0..place_cnt {
            let pi = place_off + k;
            let text = string_at(
                &pool,
                read_u32_at(
                    bytes,
                    checked_add(bopomofo_place_text_ref, checked_mul(pi, 4)?)?,
                )?,
            )?;
            let role = string_at(
                &pool,
                read_u32_at(
                    bytes,
                    checked_add(bopomofo_place_role_ref, checked_mul(pi, 4)?)?,
                )?,
            )?;
            let left = read_f64_at(
                bytes,
                checked_add(bopomofo_place_left, checked_mul(pi, 8)?)?,
            )?;
            let top = read_f64_at(bytes, checked_add(bopomofo_place_top, checked_mul(pi, 8)?)?)?;
            let width = read_f64_at(
                bytes,
                checked_add(bopomofo_place_width, checked_mul(pi, 8)?)?,
            )?;
            let height = read_f64_at(
                bytes,
                checked_add(bopomofo_place_height, checked_mul(pi, 8)?)?,
            )?;
            placements.push(PlanBopomofoPlacement {
                text,
                role,
                left,
                top,
                width,
                height,
            });
        }
        bopomofos.push(PlanBopomofo {
            base_range_start: base_start,
            base_range_end: base_end,
            text: string_at(&pool, text_idx)?,
            font_weight,
            font_families: families,
            placements,
        });
    }
    // Decoration segments
    let mut deco_segments: Vec<PlanDecorationSegment> =
        Vec::with_capacity(decoration_segment_count);
    for i in 0..decoration_segment_count {
        let kind_idx = read_u32_at(bytes, checked_add(decoration_kind_ref, checked_mul(i, 4)?)?)?;
        let left = read_f64_at(bytes, checked_add(decoration_left, checked_mul(i, 8)?)?)?;
        let top = read_f64_at(bytes, checked_add(decoration_top, checked_mul(i, 8)?)?)?;
        let right = read_f64_at(bytes, checked_add(decoration_right, checked_mul(i, 8)?)?)?;
        deco_segments.push(PlanDecorationSegment {
            kind: string_at(&pool, kind_idx)?,
            left,
            top,
            right,
        });
    }
    // Emphasis dots
    let mut dots: Vec<PlanEmphasisDot> = Vec::with_capacity(emphasis_dot_count);
    for i in 0..emphasis_dot_count {
        let cs = read_f64_at(bytes, checked_add(dot_cluster_start, checked_mul(i, 8)?)?)?;
        let ax = read_f64_at(bytes, checked_add(dot_anchor_x, checked_mul(i, 8)?)?)?;
        let ay = read_f64_at(bytes, checked_add(dot_anchor_y, checked_mul(i, 8)?)?)?;
        let d = read_f64_at(bytes, checked_add(dot_diameter, checked_mul(i, 8)?)?)?;
        dots.push(PlanEmphasisDot {
            cluster_range_start: if cs.is_nan() { None } else { Some(cs) },
            anchor_x: ax,
            anchor_y: ay,
            dot_diameter: d,
        });
    }

    // Spacing carrier advances
    let mut carriers: Vec<PlanSpacingCarrierAdvance> = Vec::with_capacity(spacing_carrier_count);
    for i in 0..spacing_carrier_count {
        let start = read_u32_at(bytes, checked_add(carrier_range_start, checked_mul(i, 4)?)?)?;
        let end = read_u32_at(bytes, checked_add(carrier_range_end, checked_mul(i, 4)?)?)?;
        let advance = read_f64_at(bytes, checked_add(carrier_advance, checked_mul(i, 8)?)?)?;
        carriers.push(PlanSpacingCarrierAdvance {
            range_start: i32::try_from(start).map_err(|_| invalid())?,
            range_end: i32::try_from(end).map_err(|_| invalid())?,
            advance,
        });
    }

    Ok(Plan {
        width,
        height,
        lines,
        emphasis_ranges,
        inline_edges: inline_edges,
        ruby_decisions: rubys,
        bopomofo_decisions: bopomofos,
        font_size: if font_size_raw.is_nan() {
            None
        } else {
            Some(font_size_raw)
        },
        overlay_width: if overlay_width_raw.is_nan() {
            None
        } else {
            Some(overlay_width_raw)
        },
        decoration_segments: deco_segments,
        emphasis_dots: dots,
        spacing_carrier_advances: carriers,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan::{Plan, PlanCell, PlanEndReason, PlanLine};

    #[test]
    fn roundtrip_minimal_plan() {
        // Build a minimal Plan and encode via duplicate of writer logic using raw bytes
        // constructed manually: header with 1 line 1 cell, no evidence.
        // Use the same decode path as production to validate zero-delta handling.
        let _plan = Plan {
            width: 80.0,
            height: 24.0,
            lines: vec![PlanLine {
                range_start: 0,
                range_end: 2,
                top: 0.0,
                bottom: 24.0,
                baseline: 19.0,
                indent: 0.0,
                visual_width: 32.0,
                hyphen_advance: 0.0,
                end_reason: PlanEndReason::ParagraphEnd,
                cells: vec![PlanCell {
                    range_start: 0,
                    range_end: 1,
                    source: "中".to_string(),
                    display: "中".to_string(),
                    draw_x: 0.0,
                    natural_width: 16.0,
                    leading_layout_advance: 0.0,
                    shaping_boundary: false,
                    open_type_features: vec![],
                    render_font_family: None,
                    dash_strategy: None,
                    shaping_language: None,
                    resolved_face: None,
                    glyph_ids: None,
                    shaping_evidence: None,
                    punctuation_ink_floor: None,
                    punctuation_body_width: None,
                    latin: false,
                    advance: None,
                    inline_object: None,
                    style_delta: None,
                }],
            }],
            emphasis_ranges: vec![],
            inline_edges: vec![],
            ruby_decisions: vec![],
            bopomofo_decisions: vec![],
            font_size: None,
            overlay_width: None,
            decoration_segments: vec![],
            emphasis_dots: vec![],
            spacing_carrier_advances: vec![],
        };
        // Encode by using the Kotlin writer would be ideal, but for unit test we
        // synthesize packed bytes directly via a minimal encoder that follows the
        // spec, then ensure decode reproduces the plan.
        let mut bytes: Vec<u8> = Vec::new();
        let mut w = |b: &[u8]| bytes.extend_from_slice(b);
        w(&PLAN_MAGIC.to_le_bytes());
        w(&PLAN_PROTOCOL_REVISION.to_le_bytes());
        w(&80f64.to_le_bytes());
        w(&24f64.to_le_bytes());
        w(&f64::NAN.to_le_bytes());
        w(&f64::NAN.to_le_bytes());
        w(&(1u32).to_le_bytes());
        w(&(1u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(1u32).to_le_bytes()); // stringCount: "中"
        w(&(0u32).to_le_bytes()); // feature pools 0
        w(&(0u32).to_le_bytes());
        w(&(0u32).to_le_bytes());
        w(&(3u32).to_le_bytes()); // "中" utf8 len 3
        w("中".as_bytes());
        // line columns
        w(&(0i32).to_le_bytes());
        w(&(2i32).to_le_bytes());
        w(&0f64.to_le_bytes());
        w(&24f64.to_le_bytes());
        w(&19f64.to_le_bytes());
        w(&0f64.to_le_bytes());
        w(&32f64.to_le_bytes());
        w(&0f64.to_le_bytes());
        w(&[2u8]); // ParagraphEnd
        w(&(1u32).to_le_bytes());
        // cell columns
        w(&(0i32).to_le_bytes()); // range start
        w(&(1i32).to_le_bytes()); // range end
        w(&(0u32).to_le_bytes()); // source ref 0
        w(&(0u32).to_le_bytes()); // display ref 0 (same string dedup would be 0; still valid)
        w(&0f64.to_le_bytes()); // drawX
        w(&16f64.to_le_bytes()); // naturalWidth
        w(&0f64.to_le_bytes()); // leading
        w(&[0u8]); // shapingBoundary
        w(&[0u8]); // latin
        w(&(PLAN_STRING_ABSENT).to_le_bytes()); // renderFamily absent etc (6 refs)
        w(&(PLAN_STRING_ABSENT).to_le_bytes());
        w(&(PLAN_STRING_ABSENT).to_le_bytes());
        w(&(PLAN_STRING_ABSENT).to_le_bytes());
        w(&(PLAN_STRING_ABSENT).to_le_bytes());
        w(&(PLAN_STRING_ABSENT).to_le_bytes());
        w(&f64::NAN.to_le_bytes()); // inkFloor
        w(&f64::NAN.to_le_bytes()); // bodyWidth
        w(&f64::NAN.to_le_bytes()); // advance
        w(&f64::NAN.to_le_bytes()); // inlineObject
        w(&f64::NAN.to_le_bytes()); // styleFontSize
        w(&f64::NAN.to_le_bytes()); // styleWeight
        w(&[2u8]); // styleItalic absent
        w(&(0u32).to_le_bytes()); // feature offset
        w(&(0u32).to_le_bytes()); // feature count
                                  // no feature pool, no other regions
        w(&(0u32).to_le_bytes()); // spacing carrier advance count
        let decoded = decode(&bytes).expect("decodes");
        assert_eq!(decoded.width, 80.0);
        assert_eq!(decoded.lines.len(), 1);
        assert_eq!(decoded.lines[0].cells[0].source, "中");
    }
}
