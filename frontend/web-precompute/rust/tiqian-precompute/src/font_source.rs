//! Font source decode (ADR 0050: Rust font session replicating
//! `frontend/web/npm/precompute-fonts.js`).
//!
//! Responsibilities here end at bytes: WOFF2 decompression, font-collection
//! rejection, and the two SHA-256 digests the face evidence carries. Face
//! parsing and validation live in `font_record`.

use sha2::{Digest, Sha256};

/// Lowercase hex SHA-256 of arbitrary bytes, matching `digest.js`.
pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut out = String::with_capacity(64);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

/// `77 4F 46 32` ("wOF2"). Mirrors `isWoff2`; wuff has no exported magic
/// check, so the four bytes are compared directly.
fn is_woff2(bytes: &[u8]) -> bool {
    bytes.len() >= 4 && bytes[0] == 0x77 && bytes[1] == 0x4f && bytes[2] == 0x46 && bytes[3] == 0x32
}

/// `74 74 63 66` ("ttcf"). Mirrors `isFontCollection`.
fn is_font_collection(bytes: &[u8]) -> bool {
    bytes.len() >= 4 && bytes[0] == 0x74 && bytes[1] == 0x74 && bytes[2] == 0x63 && bytes[3] == 0x66
}

/// Errors of the decode step. The record layer appends family context so the
/// message matches the JS side (`UnsupportedFontCollection:${family}`).
#[derive(Debug, PartialEq)]
pub enum FontSourceError {
    UnsupportedFontCollection,
    /// WOFF2 decompression failed; carries the decoder's reason. The JS side
    /// propagates the raw decompressor error the same way.
    Woff2Decode(String),
}

/// A decoded font source: WOFF2 inputs become sfnt bytes, raw sfnt inputs pass
/// through unchanged.
#[derive(Debug, PartialEq)]
pub struct DecodedFontSource {
    pub sfnt: Vec<u8>,
}

/// WOFF2 magic → decompress; collection flavor → reject. Everything else is
/// deferred to face parsing. Order mirrors `loadRecord`.
pub fn decode_font_source(source: &[u8]) -> Result<DecodedFontSource, FontSourceError> {
    let sfnt = if is_woff2(source) {
        wuff::decompress_woff2(source)
            .map_err(|error| FontSourceError::Woff2Decode(error.to_string()))?
    } else {
        source.to_vec()
    };
    if is_font_collection(&sfnt) {
        return Err(FontSourceError::UnsupportedFontCollection);
    }
    Ok(DecodedFontSource { sfnt })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_sfnt_passes_through() {
        let bytes = [0x00u8, 0x01, 0x00, 0x00, 7, 7, 7];
        let decoded = decode_font_source(&bytes).unwrap();
        assert_eq!(decoded.sfnt, bytes);
    }

    #[test]
    fn collection_magic_is_rejected() {
        let bytes = b"ttcf\x00\x00\x00\x02";
        assert_eq!(
            decode_font_source(bytes),
            Err(FontSourceError::UnsupportedFontCollection)
        );
    }

    #[test]
    fn woff2_magic_routes_to_decompressor() {
        // WOFF2 magic with a truncated body: decode must fail with the
        // decompressor's error, not pass the bytes through.
        let bytes = b"wOF2\x00";
        match decode_font_source(bytes) {
            Err(FontSourceError::Woff2Decode(_)) => {}
            other => panic!("expected Woff2Decode, got {other:?}"),
        }
    }

    #[test]
    fn sha256_hex_matches_known_vector() {
        // sha256("abc")
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
