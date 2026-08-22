//! Raw sfnt table-directory access shared by the font-record reader.
//! Collections are rejected earlier in `font_source`; this module only
//! walks the directory of a single-font sfnt.

use crate::js_compat::kotlin_to_float;

fn u16_at(bytes: &[u8], offset: usize) -> u16 {
    let high = *bytes.get(offset).unwrap_or(&0);
    let low = *bytes.get(offset + 1).unwrap_or(&0);
    (u16::from(high) << 8) | u16::from(low)
}

fn u32_at(bytes: &[u8], offset: usize) -> u32 {
    (u32::from(u16_at(bytes, offset)) << 16) | u32::from(u16_at(bytes, offset + 2))
}

/// Returns a table's bytes, or `None` when the tag is absent or the record's
/// range falls outside the file. An out-of-range table resolves to the same
/// missing-table behavior as `hb_face_reference_table` returning an empty
/// blob.
pub fn table<'a>(sfnt: &'a [u8], tag: &[u8; 4]) -> Option<&'a [u8]> {
    if sfnt.len() < 12 {
        return None;
    }
    let count = usize::from(u16_at(sfnt, 4));
    for index in 0..count {
        let record = 12 + index * 16;
        if sfnt.get(record..record + 4)? != tag {
            continue;
        }
        let offset = usize::try_from(u32_at(sfnt, record + 8)).ok()?;
        let length = usize::try_from(u32_at(sfnt, record + 12)).ok()?;
        let end = offset.checked_add(length)?;
        return sfnt.get(offset..end);
    }
    None
}

/// Signed 16-bit read inside a table, 0 past the end (same convention as the
/// BASE-table reader).
pub fn s16_at(bytes: &[u8], offset: usize) -> i16 {
    i16::from_be_bytes(u16_at(bytes, offset).to_be_bytes())
}

/// head.unitsPerEm with HarfBuzz's coercion: values outside 16..=16384 (and
/// missing or truncated tables, where the sanitizer nulls the whole table)
/// fall back to 1000. `get_upem` in hb-ot-head-table.hh; head is 54 bytes.
pub fn units_per_em(sfnt: &[u8]) -> u32 {
    let raw = table(sfnt, b"head").and_then(|head| {
        if head.len() >= 54 {
            Some(u16_at(head, 18))
        } else {
            None
        }
    });
    match raw {
        Some(upem) if (16..=16384).contains(&upem) => u32::from(upem),
        _ => 1000,
    }
}

/// One fvar axis; min/default/max carry the Fixed-to-float conversion of
/// `hb_ot_var_get_axis_infos`.
#[derive(Debug, PartialEq)]
pub struct AxisInfo {
    pub tag: String,
    pub min: f64,
    pub default: f64,
    pub max: f64,
}

fn fixed_at(bytes: &[u8], offset: usize) -> f64 {
    let raw = i32::from_be_bytes(u32_at(bytes, offset).to_be_bytes());
    // kotlin_to_float narrows with round-to-nearest-even to binary32. The
    // name documents the Kotlin parity use; the HarfBuzz Fixed 16.16 read
    // narrows the same way before the division by 65536.
    f64::from(kotlin_to_float(f64::from(raw)) / 65536.0)
}

/// fvar axes in table order. Validation mirrors the HarfBuzz sanitizer:
/// major version 1, 16-byte header, axisSize exactly 20, axes and instance
/// arrays inside the table. `get_coordinates` clamps min/max around the
/// default, which `hb_ot_var_get_axis_infos` reports. Malformed or missing
/// tables yield an empty list.
pub fn fvar_axes(sfnt: &[u8]) -> Vec<AxisInfo> {
    let Some(fvar) = table(sfnt, b"fvar") else {
        return Vec::new();
    };
    if fvar.len() < 16 || u16_at(fvar, 0) != 1 {
        return Vec::new();
    }
    let data_offset = usize::from(u16_at(fvar, 4));
    let count = usize::from(u16_at(fvar, 8));
    let axis_size = usize::from(u16_at(fvar, 10));
    let instance_count = usize::from(u16_at(fvar, 12));
    let instance_size = usize::from(u16_at(fvar, 14));
    if axis_size != 20 || instance_size < count * 4 + 4 {
        return Vec::new();
    }
    let Some(axes_end) = data_offset.checked_add(count * 20) else {
        return Vec::new();
    };
    let Some(instances_end) = axes_end.checked_add(instance_count * instance_size) else {
        return Vec::new();
    };
    if axes_end > fvar.len() || instances_end > fvar.len() {
        return Vec::new();
    }
    let mut axes = Vec::with_capacity(count);
    for index in 0..count {
        let axis = data_offset + index * 20;
        let tag = String::from_utf8_lossy(&fvar[axis..axis + 4]).into_owned();
        let default = fixed_at(fvar, axis + 8);
        axes.push(AxisInfo {
            tag,
            min: default.min(fixed_at(fvar, axis + 4)),
            default,
            max: default.max(fixed_at(fvar, axis + 12)),
        });
    }
    axes
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal sfnt with the tables passed in, tags in given order.
    fn sfnt_with(tables: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&0x00010000u32.to_be_bytes());
        bytes.extend_from_slice(
            &u16::try_from(tables.len())
                .expect("fixture table count fits u16")
                .to_be_bytes(),
        );
        bytes.extend_from_slice(&0u16.to_be_bytes()); // searchRange
        bytes.extend_from_slice(&0u16.to_be_bytes()); // entrySelector
        bytes.extend_from_slice(&0u16.to_be_bytes()); // rangeShift
        let directory_end = 12 + tables.len() * 16;
        let mut offset = directory_end;
        let mut body = Vec::new();
        for (tag, data) in tables {
            bytes.extend_from_slice(tag.as_slice());
            bytes.extend_from_slice(&0u32.to_be_bytes()); // checksum
            bytes.extend_from_slice(
                &u32::try_from(offset)
                    .expect("fixture offset fits u32")
                    .to_be_bytes(),
            );
            bytes.extend_from_slice(
                &u32::try_from(data.len())
                    .expect("fixture table size fits u32")
                    .to_be_bytes(),
            );
            body.extend_from_slice(data);
            offset += data.len();
        }
        bytes.extend_from_slice(&body);
        bytes
    }

    fn head(upem: u16) -> Vec<u8> {
        let mut head = vec![0u8; 54];
        head[18..20].copy_from_slice(&upem.to_be_bytes());
        head
    }

    #[test]
    fn table_lookup_returns_slice_and_none() {
        let sfnt = sfnt_with(&[(b"head", head(1000)), (b"OS/2", vec![7u8; 72])]);
        assert_eq!(table(&sfnt, b"head").unwrap().len(), 54);
        assert_eq!(table(&sfnt, b"OS/2").unwrap().len(), 72);
        assert!(table(&sfnt, b"BASE").is_none());
        assert!(table(&sfnt, b"name").is_none());
    }

    #[test]
    fn table_record_past_file_end_is_missing() {
        let mut sfnt = sfnt_with(&[(b"head", head(1000))]);
        // point the head record 4 GiB away
        let record = 12;
        sfnt[record + 8..record + 12].copy_from_slice(&0xffff_ffffu32.to_be_bytes());
        assert!(table(&sfnt, b"head").is_none());
    }

    #[test]
    fn upem_uses_head_value_inside_valid_range() {
        for upem in [16u16, 1000, 2048, 16384] {
            let sfnt = sfnt_with(&[(b"head", head(upem))]);
            assert_eq!(units_per_em(&sfnt), u32::from(upem));
        }
    }

    #[test]
    fn upem_outside_range_or_missing_falls_back_to_1000() {
        for upem in [0u16, 15, 16385, 65535] {
            let sfnt = sfnt_with(&[(b"head", head(upem))]);
            assert_eq!(units_per_em(&sfnt), 1000);
        }
        let sfnt = sfnt_with(&[]);
        assert_eq!(units_per_em(&sfnt), 1000);
    }

    #[test]
    fn fvar_axes_read_in_order_with_fixed_values() {
        // wght 100..900 default 400, wdth 100..200 default 100
        let mut fvar = Vec::new();
        fvar.extend_from_slice(&1u16.to_be_bytes()); // major version
        fvar.extend_from_slice(&0u16.to_be_bytes()); // minor version
        fvar.extend_from_slice(&16u16.to_be_bytes()); // firstAxis offset
        fvar.extend_from_slice(&2u16.to_be_bytes()); // countSizePairs (reserved)
        fvar.extend_from_slice(&2u16.to_be_bytes()); // axisCount
        fvar.extend_from_slice(&20u16.to_be_bytes()); // axisSize
        fvar.extend_from_slice(&0u16.to_be_bytes()); // instanceCount
        fvar.extend_from_slice(&12u16.to_be_bytes()); // instanceSize
        for (tag, min, default, max) in
            [(b"wght", 100i32, 400i32, 900i32), (b"wdth", 100, 100, 200)]
        {
            fvar.extend_from_slice(tag.as_slice());
            fvar.extend_from_slice(&(min << 16).to_be_bytes());
            fvar.extend_from_slice(&(default << 16).to_be_bytes());
            fvar.extend_from_slice(&(max << 16).to_be_bytes());
            fvar.extend_from_slice(&0u16.to_be_bytes()); // flags
            fvar.extend_from_slice(&0u16.to_be_bytes()); // nameID
        }
        let sfnt = sfnt_with(&[(b"fvar", fvar)]);
        assert_eq!(
            fvar_axes(&sfnt),
            vec![
                AxisInfo {
                    tag: "wght".into(),
                    min: 100.0,
                    default: 400.0,
                    max: 900.0
                },
                AxisInfo {
                    tag: "wdth".into(),
                    min: 100.0,
                    default: 100.0,
                    max: 200.0
                },
            ]
        );
    }

    #[test]
    fn fvar_min_max_clamp_around_default() {
        // reversed min/max must still report default-ordered triple
        let mut fvar = Vec::new();
        fvar.extend_from_slice(&[0u8, 1, 0, 0]); // version 1.0
        fvar.extend_from_slice(&16u16.to_be_bytes()); // firstAxis
        fvar.extend_from_slice(&2u16.to_be_bytes()); // reserved
        fvar.extend_from_slice(&1u16.to_be_bytes()); // axisCount
        fvar.extend_from_slice(&20u16.to_be_bytes()); // axisSize
        fvar.extend_from_slice(&0u16.to_be_bytes()); // instanceCount
        fvar.extend_from_slice(&8u16.to_be_bytes()); // instanceSize
        fvar.extend_from_slice(b"wght");
        fvar.extend_from_slice(&(900i32 << 16).to_be_bytes()); // min above default
        fvar.extend_from_slice(&(400i32 << 16).to_be_bytes()); // default
        fvar.extend_from_slice(&(100i32 << 16).to_be_bytes()); // max below default
        fvar.extend_from_slice(&0u16.to_be_bytes());
        fvar.extend_from_slice(&0u16.to_be_bytes());
        let sfnt = sfnt_with(&[(b"fvar", fvar)]);
        assert_eq!(
            fvar_axes(&sfnt),
            vec![AxisInfo {
                tag: "wght".into(),
                min: 400.0,
                default: 400.0,
                max: 400.0
            }]
        );
    }

    #[test]
    fn fvar_wrong_version_or_missing_yields_empty() {
        let mut fvar = vec![0u8; 10];
        fvar[0..2].copy_from_slice(&2u16.to_be_bytes());
        let sfnt = sfnt_with(&[(b"fvar", fvar)]);
        assert!(fvar_axes(&sfnt).is_empty());
        assert!(fvar_axes(&sfnt_with(&[])).is_empty());
    }
}
