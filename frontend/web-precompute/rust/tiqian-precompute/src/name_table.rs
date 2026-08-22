//! OpenType `name` table reading for face-local names, replicating the
//! `faceLocalNames` → `listNames`/`getName` path of `precompute-fonts.js`
//! (ADR 0050 parity oracle).
//!
//! HarfBuzz lists a name record when its encoding has a score in the table
//! below and its language resolves to a known tag (Windows LCID, Mac code,
//! or `ltag` entry). Per `(nameID, language)` pair only the best-scoring
//! record is fetched; strings decode as UTF-16BE (Unicode platforms) or
//! ASCII with U+FFFD for bytes ≥ 0x80 (Mac Latin). A `name` table whose
//! records or string storage run past its bounds is rejected whole, the
//! same way the HarfBuzz sanitizer nulls it out.

use crate::js_compat::{cmp_utf16, js_trim};
use crate::name_language::{mac_language, ms_language};

/// Name IDs kept by `LOCAL_FONT_NAME_IDS`: family (1), full name (4),
/// PostScript name (6), typographic family (16), WWS family (21).
const LOCAL_NAME_IDS: [u16; 5] = [1, 4, 6, 16, 21];

/// Mirrors `NameRecord::score` in HarfBuzz: lower wins, `None` drops the
/// record (UNSUPPORTED encoding).
fn record_score(platform: u16, encoding: u16) -> Option<u16> {
    match (platform, encoding) {
        (3, 10) => Some(0),
        (0, 6) => Some(1),
        (0, 4) => Some(2),
        (3, 1) => Some(3),
        (0, 3) => Some(4),
        (0, 2) => Some(5),
        (0, 1) => Some(6),
        (0, 0) => Some(7),
        (3, 0) => Some(8),
        // HarfBuzz treats Mac Latin as ASCII-only.
        (1, 0) => Some(10),
        _ => None,
    }
}

fn u16_at(bytes: &[u8], offset: usize) -> Option<u16> {
    let high = *bytes.get(offset)?;
    let low = *bytes.get(offset + 1)?;
    Some((u16::from(high) << 8) | u16::from(low))
}

fn u32_at(bytes: &[u8], offset: usize) -> Option<u32> {
    Some((u32::from(u16_at(bytes, offset)?) << 16) | u32::from(u16_at(bytes, offset + 2)?))
}

/// HarfBuzz sanitizer gate for `ltag`: version ≥ 1, the range array and all
/// strings inside the table. A failed gate nulls the whole table, and every
/// platform-0 record stays language-invalid.
fn ltag_valid(table: &[u8]) -> bool {
    let Some(version) = u32_at(table, 0) else {
        return false;
    };
    if version < 1 {
        return false;
    }
    let Some(count) = u32_at(table, 8) else {
        return false;
    };
    let Some(count) = usize::try_from(count).ok() else {
        return false;
    };
    let Some(ranges_end) = 12usize.checked_add(count.saturating_mul(4)) else {
        return false;
    };
    if ranges_end > table.len() {
        return false;
    }
    for index in 0..count {
        let record = 12 + index * 4;
        let offset = usize::from(u16_at(table, record).unwrap_or(u16::MAX));
        let length = usize::from(u16_at(table, record + 2).unwrap_or(u16::MAX));
        let Some(end) = offset.checked_add(length) else {
            return false;
        };
        if end > table.len() {
            return false;
        }
    }
    true
}

/// Reads the `ltag` string for a platform-0 language index; a missing table
/// or index leaves the record language-invalid. Layout: version u32, flags
/// u32, count u32, then {offset, length} u16 pairs at 12 + index*4, offsets
/// absolute from the table start.
fn ltag_language(ltag: Option<&[u8]>, index: u16) -> Option<String> {
    let table = ltag?;
    let count = usize::try_from(u32_at(table, 8)?).ok()?;
    if usize::from(index) >= count {
        return None;
    }
    let record = 12 + usize::from(index) * 4;
    let offset = usize::from(u16_at(table, record)?);
    let length = usize::from(u16_at(table, record + 2)?);
    let end = offset.checked_add(length)?;
    Some(String::from_utf8_lossy(table.get(offset..end)?).into_owned())
}

/// Canonicalizes like `hb_language_from_string`: lowercase, `_` → `-`.
fn canonical_language(tag: &str) -> String {
    tag.to_lowercase().replace('_', "-")
}

/// Resolves a record's language; `None` drops it from listings.
fn record_language(platform: u16, language_id: u16, ltag: Option<&[u8]>) -> Option<String> {
    match platform {
        3 => ms_language(language_id).map(canonical_language),
        1 => mac_language(language_id).map(canonical_language),
        0 => ltag_language(ltag, language_id).map(|tag| canonical_language(&tag)),
        _ => None,
    }
}

/// Decodes a kept record's string bytes per its score: UTF-16BE with lone
/// surrogates replaced (Unicode platforms), ASCII with U+FFFD for high
/// bytes (Mac Latin).
fn decode_string(score: u16, bytes: &[u8]) -> String {
    if score < 10 {
        let units: Vec<u16> = bytes
            .chunks_exact(2)
            .map(|pair| (u16::from(pair[0]) << 8) | u16::from(pair[1]))
            .collect();
        return String::from_utf16_lossy(&units);
    }
    bytes
        .iter()
        .map(|byte| {
            if *byte < 0x80 {
                char::from(*byte)
            } else {
                '\u{fffd}'
            }
        })
        .collect()
}

/// Collects face-local names the way `faceLocalNames` does: decode the
/// listed records for the kept name IDs, trim, drop empty strings, dedupe,
/// sort by UTF-16 code units.
pub fn local_names(name: Option<&[u8]>, ltag: Option<&[u8]>) -> Vec<String> {
    let table = match name {
        Some(bytes) if bytes.len() >= 6 => bytes,
        _ => return Vec::new(),
    };
    let ltag = ltag.filter(|table| ltag_valid(table));
    let format = u16_at(table, 0).unwrap_or(0);
    if format > 1 {
        return Vec::new();
    }
    let count = usize::from(u16_at(table, 2).unwrap_or(0));
    let storage_offset = usize::from(u16_at(table, 4).unwrap_or(0));
    if storage_offset > table.len() || 6 + count * 12 > table.len() {
        return Vec::new();
    }
    // (nameID, language, score, index, byte range) for kept records.
    let mut candidates: Vec<(u16, String, u16, usize, usize, usize)> = Vec::new();
    for index in 0..count {
        let record = 6 + index * 12;
        let platform = u16_at(table, record).unwrap_or(0);
        let encoding = u16_at(table, record + 2).unwrap_or(0);
        let language_id = u16_at(table, record + 4).unwrap_or(0);
        let name_id = u16_at(table, record + 6).unwrap_or(0);
        let length = usize::from(u16_at(table, record + 8).unwrap_or(0));
        let offset = usize::from(u16_at(table, record + 10).unwrap_or(0));
        // A record whose string runs past the table's storage nulls the
        // whole table in the HarfBuzz sanitizer.
        let start = storage_offset + offset;
        if start
            .checked_add(length)
            .map_or(true, |end| end > table.len())
        {
            return Vec::new();
        }
        let Some(score) = record_score(platform, encoding) else {
            continue;
        };
        let Some(language) = record_language(platform, language_id, ltag) else {
            continue;
        };
        if !LOCAL_NAME_IDS.contains(&name_id) {
            continue;
        }
        candidates.push((name_id, language, score, index, start, length));
    }
    // HarfBuzz fetches, per (nameID, language), the first record in
    // (nameID, language, score, index) order.
    candidates.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
            .then_with(|| left.3.cmp(&right.3))
    });
    candidates.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
    let mut names: Vec<String> = Vec::new();
    let mut seen: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for (_, _, score, _, start, length) in candidates {
        let decoded = decode_string(score, &table[start..start + length]);
        let trimmed = js_trim(&decoded).to_string();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed.clone()) {
            names.push(trimmed);
        }
    }
    names.sort_by(|left, right| cmp_utf16(left, right));
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utf16(text: &str) -> Vec<u8> {
        text.encode_utf16()
            .flat_map(|unit| unit.to_be_bytes())
            .collect()
    }

    struct NameTableBuilder {
        records: Vec<(u16, u16, u16, u16, Vec<u8>)>,
    }

    impl NameTableBuilder {
        fn new() -> NameTableBuilder {
            NameTableBuilder {
                records: Vec::new(),
            }
        }

        /// (platform, encoding, languageID, nameID, string bytes)
        fn record(
            mut self,
            platform: u16,
            encoding: u16,
            language: u16,
            name_id: u16,
            bytes: &[u8],
        ) -> Self {
            self.records
                .push((platform, encoding, language, name_id, bytes.to_vec()));
            self
        }

        fn build(self) -> Vec<u8> {
            let storage_start = 6 + self.records.len() * 12;
            let mut bytes = Vec::new();
            bytes.extend_from_slice(&0u16.to_be_bytes()); // format
            bytes.extend_from_slice(
                &u16::try_from(self.records.len())
                    .expect("fixture record count fits u16")
                    .to_be_bytes(),
            );
            bytes.extend_from_slice(
                &u16::try_from(storage_start)
                    .expect("fixture storage offset fits u16")
                    .to_be_bytes(),
            );
            let mut storage = Vec::new();
            for (platform, encoding, language, name_id, string) in &self.records {
                let offset = storage.len();
                bytes.extend_from_slice(&platform.to_be_bytes());
                bytes.extend_from_slice(&encoding.to_be_bytes());
                bytes.extend_from_slice(&language.to_be_bytes());
                bytes.extend_from_slice(&name_id.to_be_bytes());
                bytes.extend_from_slice(
                    &u16::try_from(string.len())
                        .expect("fixture string size fits u16")
                        .to_be_bytes(),
                );
                bytes.extend_from_slice(
                    &u16::try_from(offset)
                        .expect("fixture storage offset fits u16")
                        .to_be_bytes(),
                );
                storage.extend_from_slice(string);
            }
            bytes.extend_from_slice(&storage);
            bytes
        }
    }

    #[test]
    fn empty_or_short_table_yields_no_names() {
        assert!(local_names(Some(&[0, 0, 0, 0, 0, 0]), None).is_empty());
        assert!(local_names(None, None).is_empty());
        assert!(local_names(Some(&[0, 1]), None).is_empty());
    }

    #[test]
    fn windows_names_decode_and_dedupe() {
        let table = NameTableBuilder::new()
            .record(3, 1, 0x0409, 1, &utf16("Source Han Sans SC"))
            .record(3, 1, 0x0409, 4, &utf16("Source Han Sans SC"))
            .record(3, 1, 0x0409, 6, &utf16("SourceHanSansSC-Regular"))
            .record(3, 1, 0x0409, 2, &utf16("ignored id")) // nameID 2 filtered
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec![
                "Source Han Sans SC".to_string(),
                "SourceHanSansSC-Regular".to_string(),
            ]
        );
    }

    #[test]
    fn mac_record_loses_to_windows_record_of_same_language() {
        let table = NameTableBuilder::new()
            .record(3, 1, 0x0409, 1, &utf16("Windows Family"))
            .record(1, 0, 0, 1, b"Mac Family")
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec!["Windows Family".to_string()]
        );
    }

    #[test]
    fn mac_only_names_decode_as_ascii_with_replacement() {
        let table = NameTableBuilder::new()
            .record(1, 0, 0, 1, b"caf\xe9")
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec!["caf\u{fffd}".to_string()]
        );
    }

    #[test]
    fn unknown_language_code_drops_record() {
        let table = NameTableBuilder::new()
            .record(3, 1, 0x04ff, 1, &utf16("Unknown LCID"))
            .record(3, 1, 0x0804, 1, &utf16("思源黑体"))
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec!["思源黑体".to_string()]
        );
    }

    #[test]
    fn unsupported_encoding_drops_record() {
        let table = NameTableBuilder::new()
            .record(3, 2, 0x0409, 1, &utf16("not a listed encoding"))
            .build();
        assert!(local_names(Some(&table), None).is_empty());
    }

    #[test]
    fn platform_zero_resolves_language_through_ltag() {
        let table = NameTableBuilder::new()
            .record(0, 4, 0, 1, &utf16("Ltag Family"))
            .build();
        // ltag: version u32 1, flags u32 0, count u32 1, one range
        // {offset 16, length 2} pointing at "en" (absolute table offset).
        let ltag: Vec<u8> = [1u32, 0u32, 1u32]
            .iter()
            .flat_map(|value| value.to_be_bytes())
            .chain([16u16, 2u16].iter().flat_map(|value| value.to_be_bytes()))
            .chain(b"en".iter().copied())
            .collect();
        assert_eq!(
            local_names(Some(&table), Some(&ltag)),
            vec!["Ltag Family".to_string()]
        );
        // Without ltag the record has no language and is dropped.
        assert!(local_names(Some(&table), None).is_empty());
    }

    #[test]
    fn malformed_ltag_nulls_platform_zero_languages() {
        let table = NameTableBuilder::new()
            .record(0, 4, 0, 1, &utf16("Ltag Family"))
            .build();
        // The range string runs past the table; the sanitizer gate nulls ltag.
        let mut ltag: Vec<u8> = vec![0u8; 16];
        ltag[0..4].copy_from_slice(&1u32.to_be_bytes());
        ltag[8..12].copy_from_slice(&1u32.to_be_bytes());
        ltag[12..14].copy_from_slice(&16u16.to_be_bytes());
        ltag[14..16].copy_from_slice(&100u16.to_be_bytes());
        assert!(local_names(Some(&table), Some(&ltag)).is_empty());
        // A version below 1 fails the gate the same way.
        let mut zero_version = ltag;
        zero_version[0..4].copy_from_slice(&0u32.to_be_bytes());
        assert!(local_names(Some(&table), Some(&zero_version)).is_empty());
    }

    #[test]
    fn blank_strings_are_skipped_after_trim() {
        let table = NameTableBuilder::new()
            .record(3, 1, 0x0409, 1, &utf16("   "))
            .record(3, 1, 0x0409, 4, &utf16("Real Name"))
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec!["Real Name".to_string()]
        );
    }

    #[test]
    fn record_string_past_table_nulls_whole_table() {
        let mut table = NameTableBuilder::new()
            .record(3, 1, 0x0409, 1, &utf16("Family"))
            .build();
        // Inflate the record's length field to run past the table end.
        table[6 + 8] = 0xff;
        table[6 + 9] = 0xff;
        assert!(local_names(Some(&table), None).is_empty());
    }

    #[test]
    fn sort_follows_utf16_code_units() {
        let table = NameTableBuilder::new()
            .record(3, 1, 0x0409, 1, &utf16("\u{fffd} after surrogates"))
            .record(3, 1, 0x0804, 1, &utf16("\u{10000} surrogate pair first"))
            .build();
        assert_eq!(
            local_names(Some(&table), None),
            vec![
                "\u{10000} surrogate pair first".to_string(),
                "\u{fffd} after surrogates".to_string(),
            ]
        );
    }
}
