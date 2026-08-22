//! OpenType BASE table reading for CJK ideographic metrics (ADR 0050: Rust
//! font session replicating `baseIdeoIdtp` in `precompute-fonts.js`).
//!
//! The parse walks raw bytes with the same offsets as the JS implementation.
//! Reads past the end of the table yield 0, matching typed-array reads of
//! `undefined` in JS; a missing table yields the empty result. Selection
//! order: script `hani`, else `DFLT`, else the first listed script.

/// Ideographic em-box metrics from the BASE table. `None` values mean the
/// table exposed no coordinate for that tag.
#[derive(Debug, PartialEq)]
pub struct BaseIdeoIdtp {
    pub ideo: Option<i16>,
    pub idtp: Option<i16>,
    /// Some BaseCoord records carry a variation device table (format 3);
    /// fonts using them are rejected at load because MVAR-style variation
    /// of metrics is out of scope.
    pub has_variation_index: bool,
}

impl BaseIdeoIdtp {
    fn empty() -> Self {
        BaseIdeoIdtp {
            ideo: None,
            idtp: None,
            has_variation_index: false,
        }
    }
}

fn u16_at(bytes: &[u8], offset: usize) -> u16 {
    let high = *bytes.get(offset).unwrap_or(&0);
    let low = *bytes.get(offset + 1).unwrap_or(&0);
    (u16::from(high) << 8) | u16::from(low)
}

fn s16_at(bytes: &[u8], offset: usize) -> i16 {
    i16::from_be_bytes(u16_at(bytes, offset).to_be_bytes())
}

/// Four-byte tag built from the bytes that exist; a tag cut short by the end
/// of the table never matches a lookup, same as a short JS string.
fn tag_at(bytes: &[u8], offset: usize) -> String {
    let raw: Vec<u8> = (0..4)
        .filter_map(|index| bytes.get(offset + index).copied())
        .collect();
    String::from_utf8_lossy(&raw).into_owned()
}

/// Reads the `ideo` and `idtp` BaseCoord values of the `hani` (or fallback)
/// script. Mirrors `baseIdeoIdtp`.
pub fn base_ideo_idtp(bytes: Option<&[u8]>) -> BaseIdeoIdtp {
    let bytes = match bytes {
        Some(bytes) if bytes.len() >= 6 => bytes,
        _ => return BaseIdeoIdtp::empty(),
    };
    let axis = usize::from(u16_at(bytes, 4));
    if axis == 0 {
        return BaseIdeoIdtp::empty();
    }
    let tag_list = axis + usize::from(u16_at(bytes, axis));
    let script_list = axis + usize::from(u16_at(bytes, axis + 2));
    let tag_count = usize::from(u16_at(bytes, tag_list));
    let tags: Vec<String> = (0..tag_count)
        .map(|index| tag_at(bytes, tag_list + 2 + index * 4))
        .collect();
    let script_count = u16_at(bytes, script_list);
    if script_count == 0 {
        return BaseIdeoIdtp::empty();
    }
    let scripts: Vec<(String, usize)> = (0..usize::from(script_count))
        .map(|index| {
            let record = script_list + 2 + index * 6;
            (
                tag_at(bytes, record),
                usize::from(u16_at(bytes, record + 4)),
            )
        })
        .collect();
    let selected = scripts
        .iter()
        .find(|(tag, _)| tag == "hani")
        .or_else(|| scripts.iter().find(|(tag, _)| tag == "DFLT"))
        .unwrap_or(&scripts[0]);
    let script = script_list + selected.1;
    let base_values_offset = u16_at(bytes, script);
    if base_values_offset == 0 {
        return BaseIdeoIdtp::empty();
    }
    let base_values = script + usize::from(base_values_offset);
    let coord_count = usize::from(u16_at(bytes, base_values + 2));
    let mut has_variation_index = false;
    let mut coord = |tag: &str| -> Option<i16> {
        let index = tags.iter().position(|candidate| candidate == tag)?;
        if index >= coord_count {
            return None;
        }
        let coordinate_offset = u16_at(bytes, base_values + 4 + index * 2);
        if coordinate_offset == 0 {
            return None;
        }
        let coordinate = base_values + usize::from(coordinate_offset);
        if u16_at(bytes, coordinate) == 3 {
            has_variation_index = true;
        }
        Some(s16_at(bytes, coordinate + 2))
    };
    let ideo = coord("ideo");
    let idtp = coord("idtp");
    BaseIdeoIdtp {
        ideo,
        idtp,
        has_variation_index,
    }
}

/// Fixture writer shared by the BASE-table tests and the `font_record`
/// tests: a minimal table with one script and the given baseline tags.
/// Layout: header(6) + axis@6 { tagListOffset=4, scriptListOffset=14 }
/// + tagList@10 { count, tags } + scriptList@20 { count, records }
/// + script@28 { baseValuesOffset } + baseValues { default, count, offsets }
/// + coordinates.
#[cfg(test)]
pub(crate) fn base_table_bytes(tags: &[&str], script_tag: &str, coords: &[(u16, i16)]) -> Vec<u8> {
    let mut bytes = vec![0u8; 4];
    bytes.extend_from_slice(&6u16.to_be_bytes()); // header @4: axis table offset
    bytes.extend_from_slice(&4u16.to_be_bytes()); // axis + 0: tagList offset
    bytes.extend_from_slice(&14u16.to_be_bytes()); // axis + 2: scriptList offset
                                                   // tagList @ 10
    bytes.extend_from_slice(
        &u16::try_from(tags.len())
            .expect("fixture tag count fits u16")
            .to_be_bytes(),
    );
    for tag in tags {
        // tag records are fixed 4 bytes; pad shorter tags with NUL
        let mut record = [0u8; 4];
        record[..tag.len()].copy_from_slice(tag.as_bytes());
        bytes.extend_from_slice(&record);
    }
    while bytes.len() < 20 {
        bytes.push(0);
    }
    // scriptList @ 20
    bytes.extend_from_slice(&1u16.to_be_bytes());
    bytes.extend_from_slice(script_tag.as_bytes());
    bytes.extend_from_slice(&8u16.to_be_bytes()); // script record offset → script @ 28
    while bytes.len() < 28 {
        bytes.push(0);
    }
    // script @ 28: baseValuesOffset = 4 → baseValues @ 32
    bytes.extend_from_slice(&4u16.to_be_bytes());
    bytes.extend_from_slice(&0u16.to_be_bytes()); // defaultMinMax offset
                                                  // BaseValues @ 32: defaultIndex, coordCount, offsets
    bytes.extend_from_slice(&0u16.to_be_bytes());
    bytes.extend_from_slice(
        &u16::try_from(coords.len())
            .expect("fixture coord count fits u16")
            .to_be_bytes(),
    );
    let base_values = 32usize;
    let first_offset_slot = base_values + 4;
    let coordinates_start = first_offset_slot + coords.len() * 2;
    while bytes.len() < coordinates_start {
        bytes.push(0);
    }
    for (index, _) in coords.iter().enumerate() {
        let offset = u16::try_from(coordinates_start + index * 4 - base_values)
            .expect("fixture coord offset fits u16");
        let slot = first_offset_slot + index * 2;
        bytes[slot..slot + 2].copy_from_slice(&offset.to_be_bytes());
    }
    for (format, value) in coords {
        bytes.extend_from_slice(&format.to_be_bytes());
        bytes.extend_from_slice(&value.to_be_bytes());
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_ideo_and_idtp_coordinates() {
        let table = base_table_bytes(&["ideo", "idtp"], "hani", &[(1, 880), (1, -120)]);
        assert_eq!(
            base_ideo_idtp(Some(&table)),
            BaseIdeoIdtp {
                ideo: Some(880),
                idtp: Some(-120),
                has_variation_index: false,
            }
        );
    }

    #[test]
    fn format_three_sets_variation_flag_but_still_reports_value() {
        let table = base_table_bytes(&["ideo", "idtp"], "hani", &[(3, 500), (1, 500)]);
        assert_eq!(
            base_ideo_idtp(Some(&table)),
            BaseIdeoIdtp {
                ideo: Some(500),
                idtp: Some(500),
                has_variation_index: true,
            }
        );
    }

    #[test]
    fn missing_tag_yields_none_for_that_coord_only() {
        let table = base_table_bytes(&["ideo", "hang"], "hani", &[(1, 880), (1, 7)]);
        assert_eq!(
            base_ideo_idtp(Some(&table)),
            BaseIdeoIdtp {
                ideo: Some(880),
                idtp: None,
                has_variation_index: false,
            }
        );
    }

    #[test]
    fn script_falls_back_to_dflt_then_first() {
        let dflt = base_table_bytes(&["ideo"], "DFLT", &[(1, 42)]);
        assert_eq!(base_ideo_idtp(Some(&dflt)).ideo, Some(42));
        // "latn" is neither hani nor DFLT; the first script is used.
        let first = base_table_bytes(&["ideo"], "latn", &[(1, 17)]);
        assert_eq!(base_ideo_idtp(Some(&first)).ideo, Some(17));
    }

    #[test]
    fn empty_inputs_yield_empty_result() {
        assert_eq!(base_ideo_idtp(None), BaseIdeoIdtp::empty());
        assert_eq!(base_ideo_idtp(Some(&[0u8; 5])), BaseIdeoIdtp::empty());
        let mut short = vec![0u8; 6];
        short[4..6].copy_from_slice(&0u16.to_be_bytes()); // axis offset 0
        assert_eq!(base_ideo_idtp(Some(&short)), BaseIdeoIdtp::empty());
    }

    #[test]
    fn zero_base_values_offset_yields_empty_result() {
        let mut table = base_table_bytes(&["ideo"], "hani", &[(1, 880)]);
        table[28..30].copy_from_slice(&0u16.to_be_bytes());
        assert_eq!(base_ideo_idtp(Some(&table)), BaseIdeoIdtp::empty());
    }

    #[test]
    fn out_of_range_coord_index_yields_none() {
        // Tag exists at index 1, but coordCount is 1, so "idtp" is out of range.
        let table = base_table_bytes(&["ideo", "idtp"], "hani", &[(1, 880)]);
        assert_eq!(
            base_ideo_idtp(Some(&table)),
            BaseIdeoIdtp {
                ideo: Some(880),
                idtp: None,
                has_variation_index: false,
            }
        );
    }
}
