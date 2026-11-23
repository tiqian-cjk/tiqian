//! Numeric OpenType features shared by native shaping and prepared DOM replay.

use tiqian::NamedError;

use crate::json::{member, Json};
use crate::paragraph::TextSpanInput;

const NUMERIC_FEATURES: [(&str, &str, u8); 8] = [
    ("lining-nums", "lnum", 1),
    ("oldstyle-nums", "onum", 1),
    ("proportional-nums", "pnum", 2),
    ("tabular-nums", "tnum", 2),
    ("diagonal-fractions", "frac", 4),
    ("stacked-fractions", "afrc", 4),
    ("ordinal", "ordn", 8),
    ("slashed-zero", "zero", 16),
];

/// A validated numeric override for one UTF-16 source range.
#[derive(Debug, Clone)]
pub(crate) struct NumericSpan {
    pub start: u32,
    pub end: u32,
    pub features: Vec<String>,
}

/// Resolve a complete CSS numeric variant, rejecting conflicting alternatives.
pub(crate) fn features(value: &str) -> Result<Vec<String>, NamedError> {
    if value == "normal" {
        return Ok(Vec::new());
    }

    // Each CSS alternative owns one group; incompatible values cannot coexist.
    let mut groups = 0;
    let mut selected = Vec::new();
    for token in value.split_whitespace() {
        let Some((_, tag, group)) = NUMERIC_FEATURES.iter().find(|(name, _, _)| *name == token)
        else {
            return Err(NamedError("UnsupportedFontVariantNumeric".into()));
        };

        // Repeated or conflicting alternatives must not reach HarfBuzz.
        if groups & group != 0 {
            return Err(NamedError("UnsupportedFontVariantNumeric".into()));
        }
        groups |= group;
        selected.push(*tag);
    }

    // Canonical feature order makes replay keys independent of CSS token order.
    if selected.is_empty() {
        return Err(NamedError("UnsupportedFontVariantNumeric".into()));
    }
    Ok(NUMERIC_FEATURES
        .iter()
        .filter(|(_, tag, _)| selected.contains(tag))
        .map(|(_, tag, _)| (*tag).to_string())
        .collect())
}

/// Read numeric styles after the ordinary text-span range checks have passed.
pub(crate) fn spans(
    value: Option<&Json>,
    normalized: &[TextSpanInput],
) -> Result<Vec<NumericSpan>, NamedError> {
    let Some(Json::Arr(items)) = value else {
        return Ok(Vec::new());
    };

    // The native text-span normalizer preserves source order and validated ranges.
    let mut spans = Vec::new();
    for (item, span) in items.iter().zip(normalized) {
        let selected = match member(item, "fontVariantNumeric") {
            None | Some(Json::Null) => continue,
            Some(Json::Str(value)) => features(value)?,
            _ => return Err(NamedError("UnsupportedFontVariantNumeric".into())),
        };

        // Numeric spans share the exact UTF-16 bounds of the corresponding style.
        spans.push(NumericSpan {
            start: span.start as u32,
            end: span.end as u32,
            features: selected,
        });
    }
    Ok(spans)
}

/// Decode the numeric prefix and validate the remaining punctuation features.
pub(crate) fn prepared_variant(features: &[String]) -> Result<Option<String>, ()> {
    let count = features
        .iter()
        .take_while(|tag| {
            tag.as_str() == "lnum=0" || NUMERIC_FEATURES.iter().any(|(_, name, _)| name == tag)
        })
        .count();

    // Punctuation keeps its own contextual feature suffix.
    let role = features[count..].join(",");
    if !matches!(role.as_str(), "" | "fwid" | "pwid,palt") {
        return Err(());
    }
    if count == 0 {
        return Ok(None);
    }
    if features[..count] == ["lnum=0"] {
        return Ok(Some("normal".into()));
    }

    // Reuse CSS validation so duplicate and mutually exclusive features fail closed.
    let value = features[..count]
        .iter()
        .map(|tag| {
            NUMERIC_FEATURES
                .iter()
                .find(|(_, name, _)| name == tag)
                .map(|(name, _, _)| *name)
                .ok_or(())
        })
        .collect::<Result<Vec<_>, _>>()?
        .join(" ");
    if self::features(&value).map_err(|_| ())? != features[..count] {
        return Err(());
    }
    Ok(Some(value))
}

/// Emit the same numeric and punctuation styles as the browser renderer.
pub(crate) fn prepared_styles(features: &[String]) -> Result<Vec<String>, NamedError> {
    let Some(variant) = prepared_variant(features)
        .map_err(|_| NamedError("UnsupportedPreparedOpenTypeFeatures".into()))?
    else {
        return Ok(Vec::new());
    };
    let proportional = features.ends_with(&["pwid".into(), "palt".into()]);
    let full_width = features.last().is_some_and(|tag| tag == "fwid");

    // CSS numeric and punctuation properties must be replayed together.
    let east_asian = if full_width {
        "full-width"
    } else if proportional {
        "proportional-width"
    } else {
        "normal"
    };

    // Match the browser renderer's explicit punctuation feature settings.
    let settings = if full_width {
        r#", "fwid" 1"#
    } else if proportional {
        r#", "pwid" 1"#
    } else {
        ""
    };

    // A complete numeric property resets inherited lining and width variants.
    Ok(vec![
        format!("font-variant-numeric:{variant}!important"),
        format!("font-variant-east-asian:{east_asian}!important"),
        format!(
            r#"font-feature-settings:"halt" 0, "chws" 0, "palt" {}{settings}!important"#,
            u8::from(proportional)
        ),
    ])
}

/// Append numeric overrides without changing canonical bytes for older inputs.
pub(crate) fn append_canonical(value: &Json, bytes: &mut Vec<u8>) -> Result<(), NamedError> {
    let Some(Json::Arr(spans)) = member(value, "textSpans") else {
        return Ok(());
    };
    let variants = spans
        .iter()
        .map(|span| match member(span, "fontVariantNumeric") {
            None | Some(Json::Null) => Ok(Json::Null),
            Some(Json::Str(value)) => Ok(Json::str(value)),
            _ => Err(NamedError("UnsupportedFontVariantNumeric".into())),
        })
        .collect::<Result<Vec<_>, _>>()?;

    // Keep legacy hash preimages unchanged when no numeric style is present.
    if variants.iter().all(|value| *value == Json::Null) {
        return Ok(());
    }
    let payload = Json::Arr(variants).render();
    let length =
        u32::try_from(payload.len()).map_err(|_| NamedError("InvalidCanonicalForm".into()))?;
    bytes.extend_from_slice(b"TQNV");
    bytes.extend_from_slice(&length.to_le_bytes());
    bytes.extend_from_slice(payload.as_bytes());
    Ok(())
}

/// Restore the optional numeric trailer after decoding the upstream span fields.
pub(crate) fn restore_canonical(spans: &mut Json, variants: Json) -> Result<(), NamedError> {
    let (Json::Arr(spans), Json::Arr(variants)) = (spans, variants) else {
        return Err(NamedError("InvalidCanonicalForm".into()));
    };
    if spans.len() != variants.len() {
        return Err(NamedError("InvalidCanonicalForm".into()));
    }
    for (span, variant) in spans.iter_mut().zip(variants) {
        if variant == Json::Null {
            continue;
        }
        let (Json::Obj(fields), Json::Str(value)) = (span, variant) else {
            return Err(NamedError("InvalidCanonicalForm".into()));
        };
        fields.push(("fontVariantNumeric".into(), Json::Str(value)));
    }
    Ok(())
}
