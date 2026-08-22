//! Font metrics port of `precompute-fonts.js` (`normalizedMetrics`, the
//! `metricsFor` body) split at the cache boundary the JS code checks:
//! selection and cache key first, uniformity and scaling only on a miss
//! (ADR 0050 parity oracle).

use std::sync::Arc;

use crate::font_face::css_weight_matched;
use crate::font_record::FontRecord;
use crate::js_compat::js_number_string;
use crate::selection::{face_candidates, find_face, no_exact_font_face_message};
use crate::shaping::FontEngine;
use crate::NamedError;

/// The face a metrics call resolves to, plus the `metricsFor` cache key.
pub struct MetricSelection<'a> {
    pub record: &'a FontRecord,
    pub cache_key: String,
}

/// Face selection of `metricsFor`: `faceSelectionText` goes through
/// `selectFace`, an absent or empty text takes the first `faceCandidates`
/// entry.
pub fn select_metrics_face<'a>(
    records: &'a [Arc<FontRecord>],
    families: &[String],
    font_size: f64,
    font_weight: f64,
    italic: bool,
    face_selection_text: Option<&str>,
) -> Result<MetricSelection<'a>, String> {
    let selected: &FontRecord = match face_selection_text.filter(|text| !text.is_empty()) {
        Some(text) => {
            let points: Vec<char> = text.chars().collect();
            find_face(records, families, font_weight, italic, &points)?
                .ok_or_else(|| no_exact_font_face_message(families, font_weight, italic, text))?
        }
        None => face_candidates(records, families, font_weight, italic)
            .into_iter()
            .next()
            .ok_or_else(|| {
                format!(
                    "NoExactMetricFace:families={};weight={};italic={}",
                    families.join(","),
                    js_number_string(font_weight),
                    italic
                )
            })?,
    };
    let cache_key = format!(
        "{}|{}|{}|{}",
        selected.family,
        selected.style,
        js_number_string(font_weight),
        js_number_string(font_size)
    );
    Ok(MetricSelection {
        record: selected,
        cache_key,
    })
}

/// `normalizedMetrics`: font units over the em. The typo metrics cross-
/// assigned from BASE read as NaN when the table exposes no coordinate.
/// Fails with `SfntDecode` when skrifa rejects the record bytes.
pub fn normalized_metrics(record: &FontRecord, font_weight: f64) -> Result<[f64; 5], NamedError> {
    let engine = FontEngine::new(record, font_weight)?;
    let (ascender, descender, line_gap) = engine.h_extents();
    let upem = f64::from(record.upem);
    let typo_ascender = match record.table_metrics.typo_ascender {
        Some(value) => f64::from(value) / upem,
        None => f64::NAN,
    };
    let typo_descender = match record.table_metrics.typo_descender {
        Some(value) => -f64::from(value) / upem,
        None => f64::NAN,
    };
    Ok([
        f64::from(ascender) / upem,
        -f64::from(descender) / upem,
        f64::from(line_gap) / upem,
        typo_ascender,
        typo_descender,
    ])
}

/// `metricsEqual`: NaN pairs count as equal, everything else within 1e-6.
pub fn metrics_equal(left: &[f64; 5], right: &[f64; 5]) -> bool {
    left.iter()
        .zip(right.iter())
        .all(|(l, r)| (l.is_nan() && r.is_nan()) || (l - r).abs() <= 1e-6)
}

/// The uniformity check and scaling half of `metricsFor`, run on a cache
/// miss. Every weight-matched face of the selected family must agree within
/// 1e-6 em units.
pub fn resolve_metrics(
    selected: &FontRecord,
    records: &[Arc<FontRecord>],
    font_size: f64,
    font_weight: f64,
) -> Result<[f64; 5], String> {
    let selected_lower = selected.family.to_lowercase();
    let family_candidates: Vec<&FontRecord> = records
        .iter()
        .map(|record| record.as_ref())
        .filter(|record| {
            record.family.to_lowercase() == selected_lower && record.style == selected.style
        })
        .collect();
    let candidates = css_weight_matched(&family_candidates, font_weight, |record| {
        (record.weight_range[0], record.weight_range[1])
    });
    let selected_metrics = normalized_metrics(selected, font_weight).map_err(|error| error.0)?;
    for record in &candidates {
        let record_metrics = normalized_metrics(record, font_weight).map_err(|error| error.0)?;
        if !metrics_equal(&selected_metrics, &record_metrics) {
            return Err(format!(
                "NonUniformUnicodeRangeMetrics:family={};weight={}",
                selected.family,
                js_number_string(font_weight)
            ));
        }
    }
    Ok(selected_metrics.map(|value| {
        if value.is_nan() {
            value
        } else {
            value * font_size
        }
    }))
}
