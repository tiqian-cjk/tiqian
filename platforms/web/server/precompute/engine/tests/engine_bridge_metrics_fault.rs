//! The fault path of the host bridge's infallible metrics resolver (ADR 0050
//! Slice C).
//!
//! The generated `FontMetricsResolver::resolve` has no error channel, so
//! `SessionBackend::resolve` parks a `resolve_metrics` failure in the shared
//! fault cell and `precompute_paragraph` returns that message once layout
//! finishes. The substituted stub metric only keeps the layout it must throw
//! away well-formed; a plan computed from it must never reach the caller.
//!
//! The fixture is built in this file: two sfnt faces under one family, with
//! disjoint `unicode-range` coverage and different vertical metrics. Shaping
//! selects the face that covers the paragraph text and succeeds.
//! `resolve_metrics` then compares every weight-matched face of that family
//! and rejects the pair as non-uniform. That is the only shape the mechanism
//! exists for: a layout that would otherwise succeed on a substituted metric.
//!
//! The faces are synthesized here so the test needs no font file, no font
//! directory and no fontconfig: it runs the same way on a bare CI runner.

use tiqian_precompute::engine_bridge;
use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
use tiqian_precompute::paragraph::ParagraphRequest;
use tiqian_precompute::session::{
    create_font_session, CaptureEvidence, SessionFaceSpec, SessionOptions,
};

/// One family, two faces: the CJK face covers the paragraph text, the Latin
/// face supplies a conflicting metric set for the uniformity check.
const FAULT_FAMILY: &str = "Tq Metrics Fault Fixture";
const CJK_RANGE: &str = "U+4E00-9FFF";
const LATIN_RANGE: &str = "U+0020-007E";
/// 「中文文字排版段落」: every code point is mapped by the synthesized cmap.
const TEXT: &str = "中文文字排版段落";
const UPEM: u16 = 1000;
const ADVANCE: u16 = 600;

/// Minimal sfnt with the tables passed in, tags in the given order.
fn sfnt(tables: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&0x0001_0000u32.to_be_bytes());
    bytes.extend_from_slice(
        &u16::try_from(tables.len())
            .expect("fixture table count fits u16")
            .to_be_bytes(),
    );
    bytes.extend_from_slice(&0u16.to_be_bytes()); // searchRange
    bytes.extend_from_slice(&0u16.to_be_bytes()); // entrySelector
    bytes.extend_from_slice(&0u16.to_be_bytes()); // rangeShift
    let mut offset = 12 + tables.len() * 16;
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

fn head() -> Vec<u8> {
    let mut head = vec![0u8; 54];
    head[0..4].copy_from_slice(&0x0001_0000u32.to_be_bytes()); // version
    head[4..8].copy_from_slice(&0x0001_0000u32.to_be_bytes()); // fontRevision
    head[12..16].copy_from_slice(&0x5F0F_3CF5u32.to_be_bytes()); // magicNumber
    head[18..20].copy_from_slice(&UPEM.to_be_bytes());
    head[50..52].copy_from_slice(&0u16.to_be_bytes()); // indexToLocFormat
    head
}

fn hhea(ascender: i16, descender: i16, line_gap: i16, num_h_metrics: u16) -> Vec<u8> {
    let mut hhea = vec![0u8; 36];
    hhea[0..4].copy_from_slice(&0x0001_0000u32.to_be_bytes()); // version
    hhea[4..6].copy_from_slice(&ascender.to_be_bytes());
    hhea[6..8].copy_from_slice(&descender.to_be_bytes());
    hhea[8..10].copy_from_slice(&line_gap.to_be_bytes());
    hhea[10..12].copy_from_slice(&ADVANCE.to_be_bytes()); // advanceWidthMax
    hhea[18..20].copy_from_slice(&1u16.to_be_bytes()); // caretSlopeRise
    hhea[34..36].copy_from_slice(&num_h_metrics.to_be_bytes());
    hhea
}

fn maxp(num_glyphs: u16) -> Vec<u8> {
    let mut maxp = vec![0u8; 32];
    maxp[0..4].copy_from_slice(&0x0001_0000u32.to_be_bytes()); // version 1.0
    maxp[4..6].copy_from_slice(&num_glyphs.to_be_bytes());
    maxp
}

fn hmtx(num_glyphs: u16) -> Vec<u8> {
    let mut hmtx = Vec::with_capacity(usize::from(num_glyphs) * 4);
    for _ in 0..num_glyphs {
        hmtx.extend_from_slice(&ADVANCE.to_be_bytes());
        hmtx.extend_from_slice(&0i16.to_be_bytes()); // leftSideBearing
    }
    hmtx
}

fn os2(typo_ascender: i16, typo_descender: i16) -> Vec<u8> {
    let mut os2 = vec![0u8; 78];
    os2[0..2].copy_from_slice(&4u16.to_be_bytes()); // version
    os2[68..70].copy_from_slice(&typo_ascender.to_be_bytes());
    os2[70..72].copy_from_slice(&typo_descender.to_be_bytes());
    os2[74..76].copy_from_slice(&u16::try_from(typo_ascender).unwrap_or(0).to_be_bytes());
    os2[76..78].copy_from_slice(&u16::try_from(-typo_descender).unwrap_or(0).to_be_bytes());
    os2
}

/// A format 4 cmap mapping each distinct character of `TEXT` to glyph ids
/// 1..=n, with the mandatory 0xFFFF segment.
fn cmap() -> Vec<u8> {
    let mut chars: Vec<u16> = TEXT.chars().map(|c| c as u16).collect();
    chars.sort_unstable();
    chars.dedup();
    let seg_count = u16::try_from(chars.len() + 1).expect("fixture segment count fits u16");
    let seg_count_x2 = seg_count * 2;
    let mut entry_selector = 0u16;
    while (1u16 << (entry_selector + 1)) <= seg_count {
        entry_selector += 1;
    }
    let search_range = 2u16 << entry_selector;
    let range_shift = seg_count_x2 - search_range;

    let mut sub = Vec::new();
    sub.extend_from_slice(&4u16.to_be_bytes()); // format
    sub.extend_from_slice(&0u16.to_be_bytes()); // length, patched below
    sub.extend_from_slice(&0u16.to_be_bytes()); // language
    sub.extend_from_slice(&seg_count_x2.to_be_bytes());
    sub.extend_from_slice(&search_range.to_be_bytes());
    sub.extend_from_slice(&entry_selector.to_be_bytes());
    sub.extend_from_slice(&range_shift.to_be_bytes());
    for code in &chars {
        sub.extend_from_slice(&code.to_be_bytes()); // endCode
    }
    sub.extend_from_slice(&0xFFFFu16.to_be_bytes());
    sub.extend_from_slice(&0u16.to_be_bytes()); // reservedPad
    for code in &chars {
        sub.extend_from_slice(&code.to_be_bytes()); // startCode
    }
    sub.extend_from_slice(&0xFFFFu16.to_be_bytes());
    for (index, code) in chars.iter().enumerate() {
        let glyph = i32::try_from(index + 1).expect("fixture glyph id fits i32");
        let delta = (glyph - i32::from(*code)) as i16;
        sub.extend_from_slice(&delta.to_be_bytes()); // idDelta
    }
    sub.extend_from_slice(&1i16.to_be_bytes());
    for _ in 0..seg_count {
        sub.extend_from_slice(&0u16.to_be_bytes()); // idRangeOffset
    }
    let length = u16::try_from(sub.len()).expect("fixture cmap subtable fits u16");
    sub[2..4].copy_from_slice(&length.to_be_bytes());

    let mut table = Vec::new();
    table.extend_from_slice(&0u16.to_be_bytes()); // version
    table.extend_from_slice(&1u16.to_be_bytes()); // numTables
    table.extend_from_slice(&3u16.to_be_bytes()); // platformID: Windows
    table.extend_from_slice(&1u16.to_be_bytes()); // encodingID: Unicode BMP
    table.extend_from_slice(&12u32.to_be_bytes()); // subtable offset
    table.extend_from_slice(&sub);
    table
}

/// One synthesized face. The vertical metrics are the only difference between
/// the two faces of the fixture.
fn face(ascender: i16, descender: i16, line_gap: i16) -> Vec<u8> {
    let mut chars: Vec<u16> = TEXT.chars().map(|c| c as u16).collect();
    chars.sort_unstable();
    chars.dedup();
    let num_glyphs = u16::try_from(chars.len() + 1).expect("fixture glyph count fits u16");
    sfnt(&[
        (b"OS/2", os2(ascender, descender)),
        (b"cmap", cmap()),
        (b"head", head()),
        (b"hhea", hhea(ascender, descender, line_gap, num_glyphs)),
        (b"hmtx", hmtx(num_glyphs)),
        (b"maxp", maxp(num_glyphs)),
    ])
}

fn request(session_id: &str) -> ParagraphRequest {
    ParagraphRequest {
        font_session_id: session_id.to_string(),
        text: TEXT.to_string(),
        max_width_px: 144.0,
        font_families: vec![FAULT_FAMILY.to_string()],
        font_size_px: 18.0,
        line_height_px: 27.0,
        locale: "zh-Hans".to_string(),
        font_weight: 400,
        italic: false,
        first_line_indent_ic: 0.0,
        line_length_grid_enabled: true,
        source_boundaries: Vec::new(),
        text_spans: Vec::new(),
        line_break_spans: Vec::new(),
        inline_boxes: Vec::new(),
    }
}

fn face_specs<'a>(
    cjk_bytes: &'a [u8],
    latin_bytes: Option<&'a [u8]>,
) -> Vec<SessionFaceSpec<'a>> {
    let mut specs = vec![SessionFaceSpec {
        spec: FontFaceSpec {
            family: FAULT_FAMILY,
            public_url: "/fonts/tq-metrics-fault-cjk.ttf",
            source: cjk_bytes,
            face_index: None,
            weight: FontWeightSpec::Single(Some(400.0)),
            style: "normal",
            unicode_range: Some(CJK_RANGE),
            source_order: 0,
        },
        source_order: Some(0.0),
    }];
    if let Some(latin_bytes) = latin_bytes {
        specs.push(SessionFaceSpec {
            spec: FontFaceSpec {
                family: FAULT_FAMILY,
                public_url: "/fonts/tq-metrics-fault-latin.ttf",
                source: latin_bytes,
                face_index: None,
                weight: FontWeightSpec::Single(Some(400.0)),
                style: "normal",
                unicode_range: Some(LATIN_RANGE),
                source_order: 1,
            },
            source_order: Some(1.0),
        });
    }
    specs
}

/// `resolve_metrics` rejects the pair because both faces are weight-matched
/// members of the selected family and their vertical metrics differ.
fn expected_metrics_message() -> String {
    format!("NonUniformUnicodeRangeMetrics:family={FAULT_FAMILY};weight=400")
}

#[test]
fn metrics_resolution_failure_is_reported_instead_of_a_stub_metric_plan() {
    let cjk_bytes = face(880, -120, 0);
    let latin_bytes = face(1000, -200, 100);
    let session = create_font_session(
        face_specs(&cjk_bytes, Some(&latin_bytes)),
        SessionOptions::default(),
    )
    .expect("conflicting-metrics session builds");
    let request = request(&session.session_id);
    let mut evidence = CaptureEvidence::new();

    let outcome = engine_bridge::precompute_paragraph(&session, &mut evidence, &request);
    // Shaping succeeds on the CJK face, so without the fault check this call
    // would return Ok with a plan laid out on the stub metric.
    let error = match outcome {
        Ok(plan) => panic!(
            "a plan built on the substituted stub metric escaped: {} lines",
            plan.lines.len()
        ),
        Err(message) => message,
    };
    assert_eq!(
        error,
        expected_metrics_message(),
        "the call must report the metrics resolution failure, not a shape or \
         layout error"
    );
    assert!(
        error.starts_with("NonUniformUnicodeRangeMetrics:"),
        "the error must carry the resolve_metrics message, got {error:?}"
    );
}

/// Control: the same request and the same CJK face lay out successfully when
/// the conflicting face is absent. The failing call above therefore fails
/// because of the metrics fault, not because the request cannot be laid out.
#[test]
fn the_same_layout_succeeds_when_the_metric_conflict_is_absent() {
    let cjk_bytes = face(880, -120, 0);
    let session = create_font_session(face_specs(&cjk_bytes, None), SessionOptions::default())
        .expect("single-face session builds");
    let request = request(&session.session_id);
    let mut evidence = CaptureEvidence::new();

    let plan = engine_bridge::precompute_paragraph(&session, &mut evidence, &request)
        .expect("the control layout succeeds");
    assert!(!plan.lines.is_empty(), "the control layout produced no lines");
}
