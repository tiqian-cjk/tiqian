//! Shaping policy port of `precompute-fonts.js`: `scriptForText`,
//! `shapingPolicyForRole`, `normalizeBaseFeatures` (ADR 0050 parity oracle).

/// `scriptForText`: Han wins over Latin wins over common.
pub fn script_for_text(text: &str) -> &'static str {
    let is_han = |point: u32| {
        (0x2e80..=0x2fdf).contains(&point)
            || point == 0x3005
            || point == 0x3007
            || (0x3021..=0x3029).contains(&point)
            || (0x3038..=0x303b).contains(&point)
            || (0x31c0..=0x31ef).contains(&point)
            || (0x3400..=0x4dbf).contains(&point)
            || (0x4e00..=0x9fff).contains(&point)
            || (0xf900..=0xfaff).contains(&point)
            || (0x16fe2..=0x16fe3).contains(&point)
            || (0x20000..=0x2ee5f).contains(&point)
            || (0x2f800..=0x2fa1f).contains(&point)
            || (0x30000..=0x323af).contains(&point)
    };
    // Array.from(text) iterates code points, so astral Han ranges work.
    if text.chars().any(|c| is_han(u32::from(c))) {
        return "Hani";
    }
    // /[A-Za-zÀ-ɏ]/u
    if text
        .chars()
        .any(|c| c.is_ascii_alphabetic() || ('\u{00c0}'..='\u{024f}').contains(&c))
    {
        return "Latn";
    }
    "Zyyy"
}

/// `SHARED_CURLY_QUOTE` = /[‘-”]/u
pub fn has_curly_quote(text: &str) -> bool {
    text.chars().any(|c| ('\u{2018}'..='\u{201d}').contains(&c))
}

/// `shapingPolicyForRole`: the role resolves to a script and a feature set
/// (ContextualSharedQuoteShaping).
pub fn shaping_policy_for_role(
    role: Option<&str>,
    display_text: &str,
) -> (&'static str, Vec<&'static str>) {
    let role = role.unwrap_or("");
    match role {
        "LatinText" => (
            "Latn",
            if has_curly_quote(display_text) {
                vec!["pwid", "palt"]
            } else {
                Vec::new()
            },
        ),
        "CjkPunctuation" => (
            "Hani",
            if has_curly_quote(display_text) {
                vec!["fwid"]
            } else {
                Vec::new()
            },
        ),
        "CjkText" => ("Hani", Vec::new()),
        _ => (script_for_text(display_text), Vec::new()),
    }
}

/// `normalizeBaseFeatures`: `null` means none; only `lnum` is supported and
/// duplicates collapse preserving first occurrence.
pub fn normalize_base_features(value: Option<&[String]>) -> Result<Vec<String>, ()> {
    let Some(features) = value else {
        return Ok(Vec::new());
    };
    for feature in features {
        if feature != "lnum" {
            return Err(());
        }
    }
    let mut seen = std::collections::HashSet::new();
    Ok(features
        .iter()
        .filter(|feature| seen.insert((*feature).clone()))
        .cloned()
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn han_ranges_decide_the_script() {
        assert_eq!(script_for_text("你好"), "Hani");
        assert_eq!(script_for_text("\u{2e80}\u{2fdf}"), "Hani");
        assert_eq!(script_for_text("\u{3005}\u{3007}\u{3021}"), "Hani");
        assert_eq!(script_for_text("\u{2ee5f}\u{2f800}"), "Hani");
        assert_eq!(script_for_text("\u{323af}"), "Hani");
        // Just outside the ranges: CJK punctuation is not Han.
        assert_eq!(script_for_text("、。"), "Zyyy");
    }

    #[test]
    fn latin_detection_includes_extended_letters() {
        assert_eq!(script_for_text("Hello"), "Latn");
        assert_eq!(script_for_text("Étàlé"), "Latn");
        assert_eq!(script_for_text("123 .。"), "Zyyy");
    }

    #[test]
    fn roles_map_to_script_and_features() {
        let (script, features) = shaping_policy_for_role(Some("LatinText"), "plain");
        assert_eq!((script, features.as_slice()), ("Latn", &[] as &[&str]));
        let (script, features) = shaping_policy_for_role(Some("LatinText"), "‘x’");
        assert_eq!(
            (script, features.as_slice()),
            ("Latn", ["pwid", "palt"].as_slice())
        );
        let (script, features) = shaping_policy_for_role(Some("CjkPunctuation"), "“”");
        assert_eq!((script, features.as_slice()), ("Hani", ["fwid"].as_slice()));
        let (script, features) = shaping_policy_for_role(Some("CjkText"), "‘x’");
        assert_eq!((script, features.as_slice()), ("Hani", &[] as &[&str]));
        let (script, features) = shaping_policy_for_role(None, "你好");
        assert_eq!((script, features.as_slice()), ("Hani", &[] as &[&str]));
        let (script, features) = shaping_policy_for_role(Some("Unknown"), "Hi");
        assert_eq!((script, features.as_slice()), ("Latn", &[] as &[&str]));
    }

    #[test]
    fn base_features_validate_and_dedupe() {
        assert_eq!(normalize_base_features(None), Ok(Vec::new()));
        assert_eq!(
            normalize_base_features(Some(&["lnum".to_string(), "lnum".to_string()])),
            Ok(vec!["lnum".to_string()])
        );
        assert_eq!(
            normalize_base_features(Some(&["kern".to_string()])),
            Err(())
        );
    }
}
