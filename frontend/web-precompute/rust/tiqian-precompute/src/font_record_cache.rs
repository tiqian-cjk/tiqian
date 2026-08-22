//! SharedFontRecordCache: a process-global registry of loaded font records.
//! Hosts that create one precomputer per typography decode the same font
//! sources once per instance; the registry hands every session over the same
//! `Arc<FontRecord>` instead. The key covers every spec field `load_record`
//! reads, so equal keys imply equal records; different spellings of one face
//! (raw vs trimmed family, `400` vs a `400-400` range) miss and decode again,
//! which only costs time. Cache behavior never changes output bytes.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::font_record::{load_record, FontFaceSpec, FontRecord, FontWeightSpec, LoadRecordError};
use crate::font_source::sha256_hex;
use crate::js_compat::js_number_string;

/// Entry cap. Real corpora sit well below it (the larger host uses 216
/// faces); a host beyond the cap still runs, its extra faces simply skip
/// the registry.
const SHARED_FONT_RECORD_CACHE_MAX_RECORDS: usize = 512;

static SHARED_FONT_RECORD_CACHE: OnceLock<Mutex<HashMap<String, Arc<FontRecord>>>> =
    OnceLock::new();

fn cache() -> &'static Mutex<HashMap<String, Arc<FontRecord>>> {
    SHARED_FONT_RECORD_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn weight_key(spec: &FontWeightSpec) -> String {
    match spec {
        FontWeightSpec::Range(low, high) => {
            format!("{}-{}", js_number_string(*low), js_number_string(*high))
        }
        FontWeightSpec::Single(None) => "default".to_string(),
        FontWeightSpec::Single(Some(value)) => js_number_string(*value).to_string(),
    }
}

/// The registry key: the raw spec fields in a fixed order, joined on the
/// unit separator the session families also use.
pub fn shared_record_key(spec: &FontFaceSpec) -> String {
    [
        spec.family.to_string(),
        spec.public_url.to_string(),
        sha256_hex(spec.source),
        weight_key(&spec.weight),
        spec.style.to_string(),
        spec.unicode_range.unwrap_or("").to_string(),
        js_number_string(spec.face_index.unwrap_or(0.0)),
        spec.source_order.to_string(),
    ]
    .join("\u{001f}")
}

/// Loads one record through the registry: a hit clones the `Arc`, a miss
/// decodes outside the lock and inserts. Concurrent first loads of the same
/// spec may both decode; the loser's entry is dropped on insert, so the
/// records stay identical either way.
pub fn load_shared_record(spec: &FontFaceSpec) -> Result<Arc<FontRecord>, LoadRecordError> {
    let key = shared_record_key(spec);
    if let Some(record) = crate::parallel::recover(cache().lock()).get(&key) {
        return Ok(Arc::clone(record));
    }
    let record = Arc::new(load_record(spec)?);
    let mut entries = crate::parallel::recover(cache().lock());
    if entries.len() < SHARED_FONT_RECORD_CACHE_MAX_RECORDS || entries.contains_key(&key) {
        entries.insert(key, Arc::clone(&record));
    }
    Ok(record)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec<'a>(family: &'a str, source: &'a [u8], source_order: u32) -> FontFaceSpec<'a> {
        FontFaceSpec {
            family,
            public_url: "/fonts/body.woff2",
            source,
            face_index: None,
            weight: FontWeightSpec::Single(Some(400.0)),
            style: "normal",
            unicode_range: Some("U+4E00-9FFF"),
            source_order,
        }
    }

    #[test]
    fn same_spec_returns_one_record() {
        let source = b"not a font at all";
        let first = load_shared_record(&spec("SharedA", source, 0)).unwrap();
        let second = load_shared_record(&spec("SharedA", source, 0)).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
    }

    #[test]
    fn distinct_specs_return_distinct_records() {
        let source = b"not a font at all";
        let base = load_shared_record(&spec("SharedB", source, 0)).unwrap();
        let other_order = load_shared_record(&spec("SharedB", source, 1)).unwrap();
        let other_bytes = load_shared_record(&spec("SharedB", b"other", 0)).unwrap();
        let other_family = load_shared_record(&spec("SharedC", source, 0)).unwrap();
        assert!(!Arc::ptr_eq(&base, &other_order));
        assert!(!Arc::ptr_eq(&base, &other_bytes));
        assert!(!Arc::ptr_eq(&base, &other_family));
    }

    #[test]
    fn key_covers_every_load_record_input() {
        let source = b"bytes";
        let base = shared_record_key(&spec("SharedD", source, 0));
        let variants = [
            shared_record_key(&spec("SharedE", source, 0)), // family
            shared_record_key(&spec("SharedD", b"other", 0)), // source bytes
            shared_record_key(&spec("SharedD", source, 3)), // source order
        ];
        for variant in variants {
            assert_ne!(base, variant);
        }
        let mut other_url = spec("SharedD", source, 0);
        other_url.public_url = "/fonts/other.woff2";
        assert_ne!(base, shared_record_key(&other_url));
        let mut other_weight = spec("SharedD", source, 0);
        other_weight.weight = FontWeightSpec::Range(300.0, 700.0);
        assert_ne!(base, shared_record_key(&other_weight));
        let mut other_style = spec("SharedD", source, 0);
        other_style.style = "italic";
        assert_ne!(base, shared_record_key(&other_style));
        let mut other_range = spec("SharedD", source, 0);
        other_range.unicode_range = Some("U+0000-00FF");
        assert_ne!(base, shared_record_key(&other_range));
        let mut other_index = spec("SharedD", source, 0);
        other_index.face_index = Some(0.0);
        assert_eq!(base, shared_record_key(&other_index)); // defaulted
    }
}
