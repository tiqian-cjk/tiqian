//! CSS `@font-face` descriptor matching (ADR 0050: evidence duties of the CSS
//! font contract, replicated from `frontend/web/npm/font-face-boundaries.js`).
//!
//! Font fallback policy stays in the Kotlin `font` module; these functions only
//! decide which declared face owns a code point.

/// CSS Fonts weight-matching rank for one face descriptor range. Lower rank
/// wins; equal ranks keep every face (composite faces). Mirrors
/// `cssWeightPreference`: `(group, distance)` with `(inf, inf)` for malformed
/// ranges.
pub fn css_weight_preference(range: (f64, f64), requested: f64) -> (f64, f64) {
    let (low, high) = range;
    if !low.is_finite() || !high.is_finite() || high < low {
        return (f64::INFINITY, f64::INFINITY);
    }
    if (low..=high).contains(&requested) {
        return (0.0, 0.0);
    }
    if (400.0..=500.0).contains(&requested) {
        if low > requested && low <= 500.0 {
            return (1.0, low - requested);
        }
        if high < requested {
            return (2.0, requested - high);
        }
        return (3.0, low - 500.0);
    }
    if requested < 400.0 {
        if high < requested {
            return (1.0, requested - high);
        }
        return (2.0, low - requested);
    }
    if low > requested {
        return (1.0, low - requested);
    }
    (2.0, requested - high)
}

/// Faces sharing the best rank, in declaration order (stable sort, mirroring
/// `cssWeightMatched` including the `records.len() <= 1` short cut).
pub fn css_weight_matched<T>(
    records: &[T],
    requested: f64,
    range_of: impl Fn(&T) -> (f64, f64),
) -> Vec<&T> {
    if records.len() <= 1 {
        return records.iter().collect();
    }
    let mut ranked: Vec<(usize, (f64, f64))> = records
        .iter()
        .enumerate()
        .map(|(index, record)| (index, css_weight_preference(range_of(record), requested)))
        .collect();
    ranked.sort_by(|left, right| {
        left.1
             .0
            .total_cmp(&right.1 .0)
            .then_with(|| left.1 .1.total_cmp(&right.1 .1))
    });
    let best = ranked[0].1;
    ranked
        .into_iter()
        .filter(|(_, rank)| *rank == best)
        .map(|(index, _)| &records[index])
        .collect()
}

/// Parses a CSS `unicode-range` declaration into inclusive code point ranges.
/// `None` means the declaration covers everything (missing, blank, or no valid
/// token); invalid tokens are skipped, mirroring `parseUnicodeRange`.
pub fn parse_unicode_range(value: &str) -> Option<Vec<(u32, u32)>> {
    let serialized = value.trim();
    if serialized.is_empty() {
        return None;
    }
    let mut ranges = Vec::new();
    for item in serialized.split(',') {
        let token = item.trim().to_ascii_uppercase();
        let body = match token.strip_prefix("U+") {
            Some(body) => body,
            None => continue,
        };
        if body.len() <= 6
            && body.contains('?')
            && body.bytes().all(|b| b.is_ascii_hexdigit() || b == b'?')
        {
            let start = u32::from_str_radix(&body.replace('?', "0"), 16).ok();
            let end = u32::from_str_radix(&body.replace('?', "F"), 16).ok();
            if let (Some(start), Some(end)) = (start, end) {
                ranges.push((start, end));
            }
            continue;
        }
        let (start_text, end_text) = match body.split_once('-') {
            Some((start, end)) => (start, Some(end)),
            None => (body, None),
        };
        if !is_hex_1_6(start_text) {
            continue;
        }
        let end_text = end_text.unwrap_or(start_text);
        if !is_hex_1_6(end_text) {
            continue;
        }
        let start = u32::from_str_radix(start_text, 16).ok();
        let end = u32::from_str_radix(end_text, 16).ok();
        if let (Some(start), Some(end)) = (start, end) {
            ranges.push((start, end));
        }
    }
    Some(ranges)
}

fn is_hex_1_6(text: &str) -> bool {
    (1..=6).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_hexdigit())
}

/// A face covers a code point when no `unicode-range` was declared or one
/// declared range contains it.
pub fn unicode_range_contains(ranges: &Option<Vec<(u32, u32)>>, code_point: u32) -> bool {
    match ranges {
        None => true,
        Some(ranges) => ranges
            .iter()
            .any(|&(start, end)| code_point >= start && code_point <= end),
    }
}

/// A face is matched by the same family name or an OpenType local name exposed
/// by the host. Comparison trims and lowercases, mirroring
/// `fontRecordMatchesFamily`.
pub fn font_record_matches_family(
    family: &str,
    local_names: &[String],
    requested_family: &str,
) -> bool {
    let requested = requested_family.trim().to_lowercase();
    if requested.is_empty() {
        return false;
    }
    if family.to_lowercase() == requested {
        return true;
    }
    local_names
        .iter()
        .any(|name| name.trim().to_lowercase() == requested)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weight_inside_range_ranks_first() {
        assert_eq!(css_weight_preference((400.0, 400.0), 400.0), (0.0, 0.0));
        assert_eq!(css_weight_preference((300.0, 700.0), 450.0), (0.0, 0.0));
    }

    #[test]
    fn weight_400_to_500_uses_css_special_ranks() {
        // Requesting 400: a 500 face beats a 300 face (CSS Fonts 400/500 rule).
        assert_eq!(css_weight_preference((500.0, 500.0), 400.0), (1.0, 100.0));
        assert_eq!(css_weight_preference((300.0, 300.0), 400.0), (2.0, 100.0));
        // Requesting 450: a higher low end up to 500 still ranks group 1.
        assert_eq!(css_weight_preference((460.0, 600.0), 450.0), (1.0, 10.0));
        // A face entirely above 500 falls to group 3.
        assert_eq!(css_weight_preference((550.0, 700.0), 450.0), (3.0, 50.0));
        assert_eq!(css_weight_preference((100.0, 440.0), 450.0), (2.0, 10.0));
    }

    #[test]
    fn weight_outside_400_to_500_prefers_nearest() {
        assert_eq!(css_weight_preference((600.0, 600.0), 300.0), (2.0, 300.0));
        assert_eq!(css_weight_preference((100.0, 200.0), 300.0), (1.0, 100.0));
        assert_eq!(css_weight_preference((800.0, 900.0), 700.0), (1.0, 100.0));
    }

    #[test]
    fn malformed_range_ranks_last() {
        assert_eq!(
            css_weight_preference((500.0, 400.0), 400.0),
            (f64::INFINITY, f64::INFINITY)
        );
    }

    #[test]
    fn matched_keeps_all_best_rank_faces_in_order() {
        let records = [
            ("a", (300.0, 300.0)),
            ("b", (500.0, 500.0)),
            ("c", (500.0, 700.0)),
            ("d", (600.0, 600.0)),
        ];
        let matched = css_weight_matched(&records, 400.0, |record| record.1);
        let names: Vec<&str> = matched.iter().map(|record| record.0).collect();
        assert_eq!(names, vec!["b", "c"]);
    }

    #[test]
    fn matched_short_cuts_single_record() {
        let records = [("only", (100.0, 100.0))];
        let matched = css_weight_matched(&records, 900.0, |record| record.1);
        assert_eq!(matched.len(), 1);
    }

    #[test]
    fn unicode_range_parses_wildcard_range_and_single() {
        assert_eq!(
            parse_unicode_range("U+4E00-9FFF, U+F900"),
            Some(vec![(0x4E00, 0x9FFF), (0xF900, 0xF900)])
        );
        assert_eq!(parse_unicode_range("u+30??"), Some(vec![(0x3000, 0x30FF)]));
        assert_eq!(parse_unicode_range("U+0-7F"), Some(vec![(0x0, 0x7F)]));
    }

    #[test]
    fn unicode_range_skips_invalid_tokens() {
        assert_eq!(parse_unicode_range("nope, U+41"), Some(vec![(0x41, 0x41)]));
        assert_eq!(parse_unicode_range("U+1234567"), Some(vec![]));
        assert_eq!(parse_unicode_range(""), None);
        assert_eq!(parse_unicode_range("   "), None);
    }

    #[test]
    fn unicode_range_contains_matches_declared_ranges() {
        let ranges = parse_unicode_range("U+4E00-9FFF");
        assert!(unicode_range_contains(&ranges, 0x4E00));
        assert!(unicode_range_contains(&ranges, 0x9FFF));
        assert!(!unicode_range_contains(&ranges, 0x9FFF + 1));
        assert!(unicode_range_contains(&None, 0x10FFFF));
    }

    #[test]
    fn family_matches_by_declared_or_local_name() {
        assert!(font_record_matches_family(
            "Source Han Sans CN",
            &[],
            "source han sans cn"
        ));
        assert!(font_record_matches_family(
            "Source Han Sans CN",
            &["思源黑体".to_string()],
            "思源黑体"
        ));
        // The requested family is trimmed; the record family is not.
        assert!(font_record_matches_family("Serif", &[], "serif "));
        assert!(!font_record_matches_family(" Serif", &[], "serif"));
        assert!(!font_record_matches_family("Serif", &[], ""));
    }
}
