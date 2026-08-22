//! The context fingerprint of one precomputer (ADR 0052): the engine half of
//! every cache key. It is computed once at creation, in Rust, over the
//! revisions that shape artifact bytes, the shaping engine version, the
//! resolved face set and the normalized typography. Hosts treat it as opaque;
//! the combination into a store key stays in [`crate::canonical::store_key`].

use sha2::{Digest, Sha256};

use crate::normalize::SnapshotTypography;
use crate::schema::{
    FONT_BACKEND_REVISION, FONT_REPLAY_REVISION, FONT_REPLAY_TRANSPORT, FONT_SOURCE_POLICY,
    LAYOUT_REVISION, RENDER_REVISION, SNAPSHOT_SCHEMA,
};
use crate::session::{FaceInfo, HARFBUZZ_VERSION};

use crate::canonical::CANONICAL_VERSION;

/// Labeled section writing: every part of the fingerprint carries a tag and a
/// length, so equal bytes always mean equal parts.
struct FingerprintWriter {
    bytes: Vec<u8>,
}

impl FingerprintWriter {
    fn new() -> Self {
        FingerprintWriter { bytes: Vec::new() }
    }

    fn tag(&mut self, tag: u8) {
        self.bytes.push(tag);
    }

    fn str(&mut self, tag: u8, value: &str) {
        self.tag(tag);
        let bytes = value.as_bytes();
        self.bytes
            .extend_from_slice(&(u32::try_from(bytes.len()).unwrap_or(u32::MAX)).to_le_bytes());
        self.bytes.extend_from_slice(bytes);
    }

    fn u32(&mut self, tag: u8, value: u32) {
        self.tag(tag);
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn i64(&mut self, tag: u8, value: i64) {
        self.tag(tag);
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn f64(&mut self, tag: u8, value: f64) {
        self.tag(tag);
        // Normalized the canonical way: non-finite typography numbers cannot
        // occur after normalization, and both zero signs collapse.
        let normalized = if !value.is_finite() || value == 0.0 {
            0.0
        } else {
            value
        };
        self.bytes
            .extend_from_slice(&normalized.to_bits().to_le_bytes());
    }

    fn bool(&mut self, tag: u8, value: bool) {
        self.tag(tag);
        self.bytes.push(u8::from(value));
    }

    fn finish(self) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(self.bytes);
        let finished = hasher.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&finished);
        out
    }
}

fn encode_face(writer: &mut FingerprintWriter, face: &FaceInfo) {
    writer.str(0x20, &face.family);
    writer.str(0x21, face.style);
    writer.f64(0x22, face.weight[0]);
    writer.f64(0x23, face.weight[1]);
    writer.str(0x24, &face.unicode_range);
    writer.str(0x25, &face.public_url);
    writer.str(0x26, &face.source_sha256);
    writer.str(0x27, &face.sfnt_sha256);
    writer.f64(0x28, face.face_index);
    writer.u32(0x29, face.source_order);
    writer.tag(0x2a);
    writer.bytes_str_list(&face.axis_tags);
    writer.tag(0x2b);
    writer.bytes_str_list(&face.local_names);
}

impl FingerprintWriter {
    fn bytes_str_list(&mut self, values: &[String]) {
        self.bytes
            .extend_from_slice(&(u32::try_from(values.len()).unwrap_or(u32::MAX)).to_le_bytes());
        for value in values {
            let bytes = value.as_bytes();
            self.bytes
                .extend_from_slice(&(u32::try_from(bytes.len()).unwrap_or(u32::MAX)).to_le_bytes());
            self.bytes.extend_from_slice(bytes);
        }
    }
}

/// Computes the context fingerprint of a precomputer configuration. Two
/// precomputers produce compatible cache entries exactly when their
/// fingerprints agree.
pub fn context_fingerprint(typography: &SnapshotTypography, faces: &[FaceInfo]) -> [u8; 32] {
    let mut writer = FingerprintWriter::new();
    // Revisions that decide artifact bytes, then the bridge protocol.
    writer.u32(0x01, u32::try_from(SNAPSHOT_SCHEMA).unwrap_or(0));
    writer.str(0x02, LAYOUT_REVISION);
    writer.str(0x03, RENDER_REVISION);
    writer.str(0x04, FONT_BACKEND_REVISION);
    writer.str(0x05, FONT_REPLAY_REVISION);
    writer.str(0x06, FONT_REPLAY_TRANSPORT);
    writer.str(0x07, FONT_SOURCE_POLICY);
    writer.str(0x08, HARFBUZZ_VERSION);
    writer.u32(0x09, u32::from(CANONICAL_VERSION));
    // Normalized typography, in declaration order.
    writer.tag(0x10);
    writer.bytes_str_list(&typography.font_families);
    writer.f64(0x11, typography.font_size_px);
    writer.f64(0x12, typography.line_height_px);
    writer.str(0x13, &typography.locale);
    writer.i64(0x14, i64::from(typography.font_weight));
    writer.bool(0x15, typography.italic);
    writer.f64(0x16, typography.first_line_indent_ic);
    writer.bool(0x17, typography.line_length_grid_enabled);
    writer.f64(0x18, typography.letter_spacing_px);
    writer.str(0x19, typography.font_feature_settings);
    writer.str(0x1a, typography.font_variation_settings);
    writer.str(0x1b, &typography.font_variant_numeric);
    // The resolved face set, in fallback order.
    writer.u32(0x1c, u32::try_from(faces.len()).unwrap_or(u32::MAX));
    for face in faces {
        encode_face(&mut writer, face);
    }
    writer.finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::normalize::TypographyInput;

    fn typography() -> SnapshotTypography {
        let mut input = TypographyInput::default();
        input.font_families = Some(vec!["Tiqian Serif".to_string()]);
        input.font_size_px = Some(18.0);
        input.line_height_px = Some(30.0);
        crate::normalize::normalize_typography(input).expect("typography normalizes")
    }

    #[test]
    fn fingerprint_is_stable_for_equal_configuration() {
        let typography = typography();
        let faces = Vec::new();
        assert_eq!(
            context_fingerprint(&typography, &faces),
            context_fingerprint(&typography, &faces)
        );
    }

    #[test]
    fn typography_change_changes_the_fingerprint() {
        let base = typography();
        let mut changed = base.clone();
        changed.font_size_px += 1.0;
        assert_ne!(
            context_fingerprint(&base, &[]),
            context_fingerprint(&changed, &[])
        );
    }
}
