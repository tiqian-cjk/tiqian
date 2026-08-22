//! Shaping port of `precompute-fonts.js` (`createFont`, `shapeRecord`) on the
//! adopted fontations stack: harfrust 0.13 for shaping, skrifa/read-fonts for
//! glyph extents, nominal glyphs and hhea (ADR 0050). The call sequence and
//! the extents dispatch are the ones the 1078/1078 differential verified
//! against the harfbuzzjs oracle.

use crate::font_record::FontRecord;
use crate::js_compat::{js_int_to_number, js_number_string, kotlin_to_float, round_sat_i32};
use crate::policy::shaping_policy_for_role;
use crate::NamedError;
use read_fonts::TableProvider;
use skrifa::instance::{Location, LocationRef, Size};
use skrifa::{MetadataProvider, OutlineGlyphCollection};

/// One shaped glyph in session coordinates: font-unit geometry scaled by
/// `fontSize/upem`, y flipped to screen-down.
#[derive(Debug, Clone, PartialEq)]
pub struct ShapeGlyph {
    pub id: u32,
    pub cluster: u32,
    /// Only the `UNSAFE_TO_BREAK` bit is observable through the session API
    /// (`unsafeBreakCount`), so the stored word keeps that bit alone.
    pub flags: u32,
    pub advance: f64,
    pub x: f64,
    pub y: f64,
    pub bounds: Option<[f64; 4]>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ShapeRecordResult {
    pub script: String,
    pub features: Vec<String>,
    pub probe_features: Vec<String>,
    pub display_text: String,
    pub glyphs: Vec<ShapeGlyph>,
    pub advance: f64,
    pub unsafe_break_count: usize,
    /// The JS result embeds its record; the session surface reads `faceId`
    /// and `instanceId(record, fontWeight)` back out of it.
    pub face_id: String,
    pub font_instance_id: String,
}

/// A shaping engine bound to one record and one requested weight, the way
/// `createFont` builds a fresh `hb.Font` per call.
pub struct FontEngine<'a> {
    record: &'a FontRecord,
    /// The decoded face; every table read below goes through it, so the
    /// decode runs once at construction and the methods stay total.
    font: skrifa::FontRef<'a>,
    /// Normalized variation coordinates; empty for static faces.
    location: Location,
    outlines: OutlineGlyphCollection<'a>,
    charmap: skrifa::charmap::Charmap<'a>,
    glyph_count: u32,
    glyf: Option<(
        read_fonts::tables::glyf::Glyf<'a>,
        read_fonts::tables::loca::Loca<'a>,
    )>,
}

impl<'a> FontEngine<'a> {
    /// Builds the engine for `requested_weight`. Faces with a `wght` axis
    /// clamp the weight into the axis range and carry variation coordinates;
    /// static faces carry none. Fails with `SfntDecode` when skrifa rejects
    /// the record bytes; the load path validates them with this crate's own
    /// parser, and the two may disagree.
    pub fn new(
        record: &'a FontRecord,
        requested_weight: f64,
    ) -> Result<FontEngine<'a>, NamedError> {
        let font =
            skrifa::FontRef::new(&record.sfnt).map_err(|_| NamedError("SfntDecode".to_string()))?;
        let location = match variation_weight(record, requested_weight) {
            Some(weight) => font.axes().location([("wght", weight)]),
            None => font.axes().location(Vec::<(&str, f32)>::new()),
        };
        let glyf = match (font.glyf(), font.loca(None)) {
            (Ok(glyf), Ok(loca)) => Some((glyf, loca)),
            _ => None,
        };
        let outlines = font.outline_glyphs();
        let charmap = skrifa::charmap::Charmap::new(&font);
        let glyph_count = font
            .maxp()
            .map(|table| u32::from(table.num_glyphs()))
            // A face without maxp claims no glyphs, so every extents probe
            // reports out of range; hb reports the same through its face
            // count of zero, while shaping still works off the cmap.
            .unwrap_or(0);
        Ok(FontEngine {
            record,
            font,
            location,
            outlines,
            charmap,
            glyph_count,
            glyf,
        })
    }

    pub fn record(&self) -> &FontRecord {
        self.record
    }

    /// `font.nominalGlyph(point) != null`.
    pub fn nominal_glyph(&self, point: char) -> Option<u32> {
        self.charmap.map(point).map(|g| g.to_u32())
    }

    /// `font.glyphExtents(gid)` in HB convention: `[xBearing, yBearing,
    /// width, height]`, `height` negative. Static TrueType glyphs read the
    /// `glyf` header box; CFF outlines and varied coordinates draw the
    /// control bounds. A valid glyph with no outline reports `[0; 4]`; a gid
    /// outside the font reports `None`.
    pub fn glyph_extents(&self, gid: u32) -> Option<[i32; 4]> {
        if self.location.coords().is_empty() {
            if let Some((glyf, loca)) = &self.glyf {
                return match loca.get_glyf(read_fonts::types::GlyphId::new(gid), glyf) {
                    Ok(None) => Some([0, 0, 0, 0]),
                    Ok(Some(glyph)) => Some([
                        i32::from(glyph.x_min()),
                        i32::from(glyph.y_max()),
                        i32::from(glyph.x_max() - glyph.x_min()),
                        i32::from(glyph.y_min() - glyph.y_max()),
                    ]),
                    Err(_) => None,
                };
            }
        }
        let glyph = match self.outlines.get(skrifa::GlyphId::new(gid)) {
            Some(glyph) => glyph,
            None => {
                return if gid < self.glyph_count {
                    Some([0, 0, 0, 0])
                } else {
                    None
                }
            }
        };
        let mut pen = read_fonts::model::pen::ControlBoundsPen::new();
        let coords = self.location.coords();
        let settings =
            skrifa::outline::DrawSettings::unhinted(Size::unscaled(), LocationRef::new(coords));
        glyph.draw(settings, &mut pen).ok()?;
        match pen.bounding_box() {
            None => Some([0, 0, 0, 0]),
            Some(bb) => {
                let (x0, y1) = (round_sat_i32(bb.x_min), round_sat_i32(bb.y_max));
                let (x1, y0) = (round_sat_i32(bb.x_max), round_sat_i32(bb.y_min));
                Some([x0, y1, x1 - x0, y0 - y1])
            }
        }
    }

    /// `font.hExtents()`: hhea values in font units (`setScale(upem, upem)`
    /// is identity). Faces the parity corpus covers all carry hhea; a face
    /// without one reads as zeroes here, the oracle behavior.
    pub fn h_extents(&self) -> (i32, i32, i32) {
        match self.font.hhea() {
            Ok(hhea) => (
                i32::from(hhea.ascender().to_i16()),
                i32::from(hhea.descender().to_i16()),
                i32::from(hhea.line_gap().to_i16()),
            ),
            Err(_) => (0, 0, 0),
        }
    }

    /// `shapeRecord`: shape `display_text` at `font_size`/`font_weight` under
    /// `locale` and `role`, with the session's base features folded in.
    /// Fails with `SfntDecode` when harfrust rejects the record bytes.
    pub fn shape_record(
        &self,
        display_text: &str,
        font_size: f64,
        font_weight: f64,
        locale: &str,
        role: Option<&str>,
        base_features: &[String],
    ) -> Result<ShapeRecordResult, NamedError> {
        let (script, policy_features) = shaping_policy_for_role(role, display_text);
        let mut applied: Vec<String> = base_features.to_vec();
        for tag in &policy_features {
            if !applied.iter().any(|base| base == tag) {
                applied.push((*tag).to_string());
            }
        }

        let font = harfrust::FontRef::new(&self.record.sfnt)
            .map_err(|_| NamedError("SfntDecode".to_string()))?;
        let data = harfrust::ShaperData::new(&font);
        let instance = variation_weight(self.record, font_weight).map(|weight| {
            harfrust::ShaperInstance::from_variations(
                &font,
                [harfrust::Variation {
                    tag: harfrust::Tag::new(b"wght"),
                    value: weight,
                }],
            )
        });
        let shaper = data.shaper(&font).instance(instance.as_ref()).build();

        let mut buffer = harfrust::UnicodeBuffer::new();
        buffer.push_str(display_text);
        buffer.guess_segment_properties();
        buffer.set_direction(harfrust::Direction::LeftToRight);
        if let Ok(language) = locale.parse() {
            buffer.set_language(language);
        } else if let Ok(fallback) = "c".parse() {
            // "c" never fails to parse; the guard exists for the Result type.
            buffer.set_language(fallback);
        }
        buffer.set_script(
            harfrust::Script::from_iso15924_tag(harfrust::Tag::new(&tag_bytes(script)))
                .unwrap_or(harfrust::script::UNKNOWN),
        );
        let features: Vec<harfrust::Feature> = applied
            .iter()
            .map(|tag| harfrust::Feature::new(harfrust::Tag::new(&tag_bytes(tag)), 1, ..))
            .collect();
        let out = shaper.shape(buffer, harfrust::ShapeOptions::new().features(&features));

        let infos = out.glyph_infos();
        let positions = out.glyph_positions();
        let scale = font_size / f64::from(self.record.upem);
        let mut glyphs: Vec<ShapeGlyph> = Vec::with_capacity(infos.len());
        let mut cursor_x: i64 = 0;
        for (info, position) in infos.iter().zip(positions.iter()) {
            let extents = self.glyph_extents(info.glyph_id);
            let origin_x = cursor_x + i64::from(position.x_offset);
            let bounds = extents.map(|[xb, yb, w, h]| {
                [
                    f64::from(xb) * scale,
                    -f64::from(yb) * scale,
                    f64::from(xb + w) * scale,
                    -(f64::from(yb + h) * scale),
                ]
            });
            let unsafe_to_break = info.unsafe_to_break();
            glyphs.push(ShapeGlyph {
                id: info.glyph_id,
                cluster: info.cluster, // UTF-8 byte offset; remapped below
                flags: if unsafe_to_break { 1 } else { 0 },
                advance: f64::from(position.x_advance) * scale,
                x: js_int_to_number(origin_x) * scale,
                y: -f64::from(position.y_offset) * scale,
                bounds,
            });
            cursor_x += i64::from(position.x_advance);
        }
        remap_clusters_to_utf16(&mut glyphs, display_text);
        let unsafe_break_count = glyphs.iter().filter(|glyph| glyph.flags & 1 != 0).count();
        Ok(ShapeRecordResult {
            script: script.to_string(),
            features: policy_features
                .iter()
                .map(|tag| (*tag).to_string())
                .collect(),
            probe_features: applied,
            display_text: display_text.to_string(),
            advance: js_int_to_number(cursor_x) * scale,
            unsafe_break_count,
            font_instance_id: crate::replay::instance_id(self.record, font_weight),
            face_id: self.record.face_id.clone(),
            glyphs,
        })
    }
}

/// The `wght` variation value for a requested weight, replicating
/// `createFont`: clamp into the axis range, format the way template
/// interpolation does, parse back — harfbuzzjs stores the value as f32.
/// Weights that do not survive the round trip drop the variation, the way a
/// failed `Variation.fromString` leaves `variations` empty.
fn variation_weight(record: &FontRecord, requested_weight: f64) -> Option<f32> {
    let axis = record.wght_axis()?;
    let clamped = crate::js_compat::js_max(
        axis.min,
        crate::js_compat::js_min(axis.max, requested_weight),
    );
    if !clamped.is_finite() {
        return None;
    }
    let text = js_number_string(clamped);
    text.parse::<f64>().ok().map(kotlin_to_float)
}

fn tag_bytes(tag: &str) -> [u8; 4] {
    let mut bytes = [b' '; 4];
    for (slot, byte) in bytes.iter_mut().zip(tag.bytes()) {
        *slot = byte;
    }
    bytes
}

/// harfbuzzjs feeds UTF-16 so clusters are UTF-16 code-unit offsets; harfrust
/// clusters by UTF-8 bytes. Remap in place.
fn remap_clusters_to_utf16(glyphs: &mut [ShapeGlyph], text: &str) {
    // Byte and UTF-16 offsets stay u32 to match the u32 cluster domain.
    let mut map = std::collections::HashMap::new();
    let mut byte_position = 0u32;
    let mut u16_position = 0u32;
    for ch in text.chars() {
        map.insert(byte_position, u16_position);
        byte_position += match ch {
            '\0'..='\u{7f}' => 1,
            '\u{80}'..='\u{7ff}' => 2,
            '\u{800}'..='\u{ffff}' => 3,
            _ => 4,
        };
        u16_position += match ch {
            '\0'..='\u{ffff}' => 1,
            _ => 2,
        };
    }
    for glyph in glyphs.iter_mut() {
        if let Some(&u16_offset) = map.get(&glyph.cluster) {
            glyph.cluster = u16_offset;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feature_tags_pad_to_four_bytes() {
        assert_eq!(&tag_bytes("lnum"), b"lnum");
        assert_eq!(&tag_bytes("ab"), b"ab  ");
    }

    #[test]
    fn utf16_cluster_remap_handles_astral_text() {
        let mut glyphs = vec![
            ShapeGlyph {
                id: 1,
                cluster: 0,
                flags: 0,
                advance: 0.0,
                x: 0.0,
                y: 0.0,
                bounds: None,
            },
            ShapeGlyph {
                id: 2,
                cluster: 1,
                flags: 0,
                advance: 0.0,
                x: 0.0,
                y: 0.0,
                bounds: None,
            },
            ShapeGlyph {
                id: 3,
                cluster: 5,
                flags: 0,
                advance: 0.0,
                x: 0.0,
                y: 0.0,
                bounds: None,
            },
        ];
        // "a😀你" → byte offsets 0, 1, 5; UTF-16 offsets 0, 1, 3.
        remap_clusters_to_utf16(&mut glyphs, "a\u{1f600}你");
        assert_eq!(glyphs[0].cluster, 0);
        assert_eq!(glyphs[1].cluster, 1);
        assert_eq!(glyphs[2].cluster, 3);
    }

    #[test]
    fn variation_weight_clamps_and_round_trips_through_string() {
        let mut record = crate::font_record::FontRecord {
            sfnt: Vec::new(),
            upem: 1000,
            face_index: 0.0,
            source_order: 0,
            family: "F".into(),
            style: "normal",
            weight_range: [400.0, 400.0],
            unicode_range: String::new(),
            unicode_ranges: None,
            public_url: "/f".into(),
            source_sha256: String::new(),
            sfnt_sha256: String::new(),
            axis_infos: vec![crate::sfnt::AxisInfo {
                tag: "wght".into(),
                min: 100.0,
                default: 400.0,
                max: 900.0,
            }],
            local_names: Vec::new(),
            table_metrics: crate::font_record::TableMetrics {
                typo_ascender: None,
                typo_descender: None,
                base_ideo: None,
                base_idtp: None,
                base_has_variation_index: false,
            },
            face_id: "F".into(),
        };
        assert_eq!(variation_weight(&record, 350.0), Some(350.0));
        assert_eq!(variation_weight(&record, 50.0), Some(100.0));
        assert_eq!(variation_weight(&record, 950.0), Some(900.0));
        assert_eq!(variation_weight(&record, 400.5), Some(400.5));
        assert!(variation_weight(&record, f64::NAN).is_none());
        record.axis_infos.clear();
        assert_eq!(variation_weight(&record, 700.0), None);
    }
}
