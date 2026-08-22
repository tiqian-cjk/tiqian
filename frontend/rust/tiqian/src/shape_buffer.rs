//! Packed shape-buffer encoding (ADR 0050 `PackedFfiCalls`).
//!
//! The Rust font session writes, the Kotlin engine reads. Offsets are
//! documented in `tiqian_font_backend.h`; this writer is the single Rust-side
//! encoder so every session path produces one byte layout.

use crate::font_backend::SHAPE_BUFFER_MAGIC;
use crate::NamedError;

const HEADER_BYTES: usize = 64;
const RECORD_BYTES: usize = 64;
const FIELD_BYTES: usize = 8;

/// Offsets of the header fields, kept beside the writer so layout edits stay
/// in one place.
mod offset {
    pub const MAGIC: usize = 0;
    pub const VERSION: usize = 4;
    pub const GLYPH_COUNT: usize = 8;
    pub const FEATURE_COUNT: usize = 12;
    pub const UNSAFE_BREAK_COUNT: usize = 16;
    pub const RESERVED: usize = 20;
    pub const TOTAL_ADVANCE: usize = 24;
    pub const FACE_ID: usize = 32;
    pub const INSTANCE_ID: usize = 40;
    pub const SCRIPT: usize = 48;
    pub const FEATURES: usize = 56;
}

/// One glyph as the engine consumes it: fixed 8-double record, ink bounds NaN
/// when the glyph has no extents.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ShapeGlyphRecord {
    pub id: u32,
    pub advance: f64,
    pub x: f64,
    pub y: f64,
    /// [left, top, right, bottom] in px.
    pub bounds: Option<[f64; 4]>,
}

/// Segment-level string evidence carried in the buffer's byte area.
#[derive(Debug, Clone, PartialEq)]
pub struct ShapeEvidence {
    pub face_id: String,
    pub instance_id: String,
    pub script: String,
    /// OpenType feature tags applied by policy, in application order.
    pub features: Vec<String>,
    pub total_advance: f64,
    pub unsafe_break_count: u32,
}

/// Byte size a buffer needs for these glyphs and evidence.
pub fn required_shape_buffer_size(glyphs: usize, evidence: &ShapeEvidence) -> usize {
    HEADER_BYTES + glyphs * RECORD_BYTES + string_area_size(evidence)
}

fn string_area_size(evidence: &ShapeEvidence) -> usize {
    evidence.face_id.len()
        + evidence.instance_id.len()
        + evidence.script.len()
        + joined_features(evidence).len()
}

fn joined_features(evidence: &ShapeEvidence) -> String {
    evidence.features.join("\u{001f}")
}

/// Writes the packed buffer. Fails with `ShapeBufferCapacity:<needed>` when
/// `out` is smaller than [`required_shape_buffer_size`] returned for the same
/// inputs; sessions probe with that function first, matching the engine's
/// capacity contract. Fails with `ShapeBufferTooLarge` when a count, offset,
/// or string length exceeds the u32 header fields.
pub fn write_shape_buffer(
    out: &mut [u8],
    glyphs: &[ShapeGlyphRecord],
    evidence: &ShapeEvidence,
) -> Result<(), NamedError> {
    let needed = required_shape_buffer_size(glyphs.len(), evidence);
    if out.len() < needed {
        return Err(NamedError(format!("ShapeBufferCapacity:{needed}")));
    }

    let features = joined_features(evidence);
    let string_area_start = HEADER_BYTES + glyphs.len() * RECORD_BYTES;

    write_u32(out, offset::MAGIC, SHAPE_BUFFER_MAGIC);
    write_u32(
        out,
        offset::VERSION,
        crate::font_backend::FONT_BACKEND_PROTOCOL_REVISION,
    );
    write_u32(out, offset::GLYPH_COUNT, header_u32(glyphs.len())?);
    write_u32(
        out,
        offset::FEATURE_COUNT,
        header_u32(evidence.features.len())?,
    );
    write_u32(out, offset::UNSAFE_BREAK_COUNT, evidence.unsafe_break_count);
    write_u32(out, offset::RESERVED, 0);
    write_f64(out, offset::TOTAL_ADVANCE, evidence.total_advance);

    let mut cursor = string_area_start;
    let mut put = |out: &mut [u8], field: usize, bytes: &[u8]| -> Result<(), NamedError> {
        out[cursor..cursor + bytes.len()].copy_from_slice(bytes);
        write_u32(out, field, header_u32(cursor)?);
        write_u32(out, field + 4, header_u32(bytes.len())?);
        cursor += bytes.len();
        Ok(())
    };
    let face_id = evidence.face_id.as_bytes();
    let instance_id = evidence.instance_id.as_bytes();
    let script = evidence.script.as_bytes();
    let features_bytes = features.as_bytes();
    put(out, offset::FACE_ID, face_id)?;
    put(out, offset::INSTANCE_ID, instance_id)?;
    put(out, offset::SCRIPT, script)?;
    put(out, offset::FEATURES, features_bytes)?;

    for (index, glyph) in glyphs.iter().enumerate() {
        let base = HEADER_BYTES + index * RECORD_BYTES;
        write_f64(out, base, f64::from(glyph.id));
        write_f64(out, base + FIELD_BYTES, glyph.advance);
        write_f64(out, base + FIELD_BYTES * 2, glyph.x);
        write_f64(out, base + FIELD_BYTES * 3, glyph.y);
        let bounds = glyph.bounds.unwrap_or([f64::NAN; 4]);
        for (edge, value) in bounds.iter().enumerate() {
            write_f64(out, base + FIELD_BYTES * 4 + edge * FIELD_BYTES, *value);
        }
    }
    Ok(())
}

/// Converts a usize value to the u32 header field; the error names the overflow.
fn header_u32(value: usize) -> Result<u32, NamedError> {
    u32::try_from(value).map_err(|_| NamedError("ShapeBufferTooLarge".to_string()))
}

fn write_u32(out: &mut [u8], offset: usize, value: u32) {
    out[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn write_f64(out: &mut [u8], offset: usize, value: f64) {
    out[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn evidence() -> ShapeEvidence {
        ShapeEvidence {
            face_id: "Source Han Sans CN|normal|400-400|abcd0123456789ab|0".to_string(),
            instance_id: "abcd0123456789ab:0:wght=400".to_string(),
            script: "hani".to_string(),
            features: vec!["fwid".to_string(), "palt".to_string()],
            total_advance: 18.5,
            unsafe_break_count: 1,
        }
    }

    fn glyphs() -> Vec<ShapeGlyphRecord> {
        vec![
            ShapeGlyphRecord {
                id: 111,
                advance: 10.5,
                x: 0.0,
                y: 0.25,
                bounds: Some([1.0, 2.0, 3.0, 4.0]),
            },
            ShapeGlyphRecord {
                id: 0,
                advance: 8.0,
                x: 10.5,
                y: -0.25,
                bounds: None,
            },
        ]
    }

    #[test]
    fn header_holds_the_documented_fields() {
        let evidence = evidence();
        let mut buffer = vec![0u8; required_shape_buffer_size(2, &evidence)];
        write_shape_buffer(&mut buffer, &glyphs(), &evidence)
            .expect("fixture strings and counts fit the u32 header fields");
        assert_eq!(read_u32(&buffer, 0), SHAPE_BUFFER_MAGIC);
        assert_eq!(read_u32(&buffer, 4), FONT_BACKEND_PROTOCOL_REVISION);
        assert_eq!(read_u32(&buffer, 8), 2);
        assert_eq!(read_u32(&buffer, 12), 2);
        assert_eq!(read_u32(&buffer, 16), 1);
        assert_eq!(read_u32(&buffer, 20), 0);
        assert_eq!(read_f64(&buffer, 24), 18.5);
    }

    #[test]
    fn glyph_records_are_fixed_width_little_endian() {
        let evidence = evidence();
        let mut buffer = vec![0u8; required_shape_buffer_size(2, &evidence)];
        write_shape_buffer(&mut buffer, &glyphs(), &evidence)
            .expect("fixture strings and counts fit the u32 header fields");
        assert_eq!(read_f64(&buffer, 64), 111.0);
        assert_eq!(read_f64(&buffer, 72), 10.5);
        assert_eq!(read_f64(&buffer, 80), 0.0);
        assert_eq!(read_f64(&buffer, 88), 0.25);
        assert_eq!(read_f64(&buffer, 96), 1.0);
        assert_eq!(read_f64(&buffer, 104), 2.0);
        assert_eq!(read_f64(&buffer, 112), 3.0);
        assert_eq!(read_f64(&buffer, 120), 4.0);
        // Second record: missing ink bounds encode as all-NaN.
        assert_eq!(read_f64(&buffer, 128 + 32).is_nan(), true);
        assert_eq!(read_f64(&buffer, 128 + 56).is_nan(), true);
    }

    #[test]
    fn string_offsets_are_absolute_from_buffer_start() {
        let evidence = evidence();
        let mut buffer = vec![0u8; required_shape_buffer_size(2, &evidence)];
        write_shape_buffer(&mut buffer, &glyphs(), &evidence)
            .expect("fixture strings and counts fit the u32 header fields");
        let face = read_string(&buffer, 32);
        assert_eq!(face, evidence.face_id);
        let instance = read_string(&buffer, 40);
        assert_eq!(instance, evidence.instance_id);
        let script = read_string(&buffer, 48);
        assert_eq!(script, "hani");
        let features = read_string(&buffer, 56);
        assert_eq!(features, "fwid\u{001f}palt");
        // The string area starts right after the last record.
        assert_eq!(read_u32(&buffer, 32), 192);
    }

    #[test]
    fn required_size_covers_the_whole_buffer() {
        let evidence = evidence();
        let needed = required_shape_buffer_size(2, &evidence);
        let mut buffer = vec![0u8; needed];
        write_shape_buffer(&mut buffer, &glyphs(), &evidence)
            .expect("fixture strings and counts fit the u32 header fields");
        // Every byte is accounted for: strings end exactly at the buffer end.
        let features_offset = read_u32(&buffer, 56);
        let features_length = read_u32(&buffer, 60);
        assert_eq!(
            u64::from(features_offset) + u64::from(features_length),
            u64::try_from(needed).expect("fixture buffer size fits u64")
        );
    }

    fn read_u32(buffer: &[u8], offset: usize) -> u32 {
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&buffer[offset..offset + 4]);
        u32::from_le_bytes(bytes)
    }

    fn read_f64(buffer: &[u8], offset: usize) -> f64 {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&buffer[offset..offset + 8]);
        f64::from_le_bytes(bytes)
    }

    fn read_string(buffer: &[u8], field: usize) -> String {
        let offset = usize::try_from(read_u32(buffer, field)).expect("string offset fits usize");
        let length =
            usize::try_from(read_u32(buffer, field + 4)).expect("string length fits usize");
        String::from_utf8(buffer[offset..offset + length].to_vec()).unwrap()
    }

    use crate::font_backend::FONT_BACKEND_PROTOCOL_REVISION;
}
