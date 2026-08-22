//! Face selection port of `precompute-fonts.js`: `faceCandidates`,
//! `findFace`, `faceCovers`, `selectFace`, `selectShapeFace`,
//! `renderFamiliesFor` (ADR 0050 parity oracle). Error strings match the JS
//! throws; the message builders live here so callers can embed them verbatim.

use std::sync::Arc;

use crate::font_face::{css_weight_matched, font_record_matches_family, unicode_range_contains};
use crate::font_record::FontRecord;
use crate::js_compat::js_number_string;
use crate::json::json_string;
use crate::shaping::FontEngine;
use crate::NamedError;

/// `NoExactFontFace:families=...;weight=...;italic=...;text=...`
pub fn no_exact_font_face_message(
    families: &[String],
    weight: f64,
    italic: bool,
    text: &str,
) -> String {
    format!(
        "NoExactFontFace:families={};weight={};italic={};text={}",
        families.join(","),
        js_number_string(weight),
        italic,
        json_string(text)
    )
}

/// `faceCovers`: every point inside the declared unicode-range and mapped by
/// the face's cmap. The coverage probe runs at the range's low weight, the
/// way `createFont(record, record.weightRange[0])` does. Fails with
/// `SfntDecode` when skrifa rejects the record bytes.
pub fn face_covers(record: &FontRecord, points: &[char]) -> Result<bool, NamedError> {
    if !points
        .iter()
        .all(|point| unicode_range_contains(&record.unicode_ranges, u32::from(*point)))
    {
        return Ok(false);
    }
    let engine = FontEngine::new(record, record.weight_range[0])?;
    Ok(points
        .iter()
        .all(|point| engine.nominal_glyph(*point).is_some()))
}

/// `faceCandidates`: first family with style and weight matches wins; the
/// matches keep session order.
pub fn face_candidates<'a>(
    records: &'a [Arc<FontRecord>],
    families: &[String],
    requested_weight: f64,
    italic: bool,
) -> Vec<&'a FontRecord> {
    let desired_style = if italic { "italic" } else { "normal" };
    for family in families {
        let family_matches: Vec<&FontRecord> = records
            .iter()
            .map(|record| record.as_ref())
            .filter(|record| {
                font_record_matches_family(record.family.as_str(), &record.local_names, family)
                    && record.style == desired_style
            })
            .collect();
        let matched = css_weight_matched(&family_matches, requested_weight, |record| {
            (record.weight_range[0], record.weight_range[1])
        });
        if !matched.is_empty() {
            return matched.into_iter().copied().collect();
        }
    }
    Vec::new()
}

/// `findFace`: like `faceCandidates`, but the candidate that covers all
/// points wins; composite faces prefer the later record. Fails with
/// `SfntDecode` when the coverage probe cannot decode a record.
pub fn find_face<'a>(
    records: &'a [Arc<FontRecord>],
    families: &[String],
    requested_weight: f64,
    italic: bool,
    text: &[char],
) -> Result<Option<&'a FontRecord>, String> {
    let desired_style = if italic { "italic" } else { "normal" };
    for family in families {
        let family_matches: Vec<&FontRecord> = records
            .iter()
            .map(|record| record.as_ref())
            .filter(|record| {
                font_record_matches_family(record.family.as_str(), &record.local_names, family)
                    && record.style == desired_style
            })
            .collect();
        let weight_matched = css_weight_matched(&family_matches, requested_weight, |record| {
            (record.weight_range[0], record.weight_range[1])
        });
        // CSS Fonts composite faces with the same descriptors use the later
        // @font-face rule for overlapping unicode-range coverage.
        for record in weight_matched.into_iter().rev() {
            if face_covers(record, text).map_err(|error| error.0)? {
                return Ok(Some(record));
            }
        }
    }
    Ok(None)
}

/// `selectFace`: `findFace` with the `NoExactFontFace` throw on a miss.
pub fn select_face<'a>(
    records: &'a [Arc<FontRecord>],
    families: &[String],
    requested_weight: f64,
    italic: bool,
    text: &[char],
) -> Result<&'a FontRecord, String> {
    find_face(records, families, requested_weight, italic, text)?.ok_or_else(|| {
        let joined: String = text.iter().collect();
        no_exact_font_face_message(families, requested_weight, italic, &joined)
    })
}

/// `selectShapeFace` (ExactDisplaySubstitutionCoverage): try the display
/// text, then the source text with `displayCovered: false`, then fail
/// through `selectFace`'s error.
pub fn select_shape_face<'a>(
    records: &'a [Arc<FontRecord>],
    families: &[String],
    requested_weight: f64,
    italic: bool,
    display_text: &[char],
    source_text: &[char],
) -> Result<(&'a FontRecord, bool), String> {
    if let Some(record) = find_face(records, families, requested_weight, italic, display_text)? {
        return Ok((record, true));
    }
    if source_text != display_text {
        if let Some(record) = find_face(records, families, requested_weight, italic, source_text)? {
            return Ok((record, false));
        }
    }
    let display: String = display_text.iter().collect();
    Err(no_exact_font_face_message(
        families,
        requested_weight,
        italic,
        &display,
    ))
}

/// `renderFamiliesFor`: host families backed by the corpus, in the host's
/// order, deduped per canonical family.
pub fn render_families(
    records: &[Arc<FontRecord>],
    requested_families: &[String],
) -> Result<Vec<String>, String> {
    let mut result: Vec<String> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for requested_family in requested_families {
        for record in records {
            if !font_record_matches_family(
                record.family.as_str(),
                &record.local_names,
                requested_family,
            ) {
                continue;
            }
            let canonical = record.family.trim().to_lowercase();
            if !seen.insert(canonical) {
                continue;
            }
            result.push(record.family.clone());
        }
    }
    if result.is_empty() {
        return Err(format!(
            "NoExactRenderFontFamily:families={}",
            requested_families.join(",")
        ));
    }
    Ok(result)
}
