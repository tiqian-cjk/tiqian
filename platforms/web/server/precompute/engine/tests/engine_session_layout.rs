//! The session-backed engine bridge against a real font file (ADR 0050
//! Slice C). The fixture font is vendored under `tests/fixtures` and embedded
//! with `include_bytes!`, so the test runs on a bare runner without a font
//! directory.

#[path = "support/font_fixture.rs"]
mod font_fixture;

use tiqian_precompute::engine_bridge;
use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
use tiqian_precompute::paragraph::ParagraphRequest;
use tiqian_precompute::session::{
    create_font_session, CaptureEvidence, SessionFaceSpec, SessionOptions,
};

/// 「中文文字排版段落」 keeps every code point inside the coverage of the
/// fixture font, so the run exercises real glyph ids and advances.
fn request(session_id: &str) -> ParagraphRequest {
    ParagraphRequest {
        font_session_id: session_id.to_string(),
        text: "中文文字排版段落".to_string(),
        max_width_px: 144.0,
        font_families: vec!["Dela Gothic One".to_string()],
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

#[test]
fn session_lends_the_engine_a_real_font_backend() {
    let bytes = font_fixture::DELA_GOTHIC_ONE;
    let specs = vec![SessionFaceSpec {
        spec: FontFaceSpec {
            family: font_fixture::FAMILY,
            public_url: font_fixture::PUBLIC_URL,
            source: bytes,
            face_index: None,
            weight: FontWeightSpec::Single(Some(400.0)),
            style: "normal",
            unicode_range: None,
            source_order: 0,
        },
        source_order: Some(0.0),
    }];
    let mut session =
        create_font_session(specs, SessionOptions::default()).expect("fixture session builds");

    let request = request(&session.session_id);
    let mut evidence_window = CaptureEvidence::new();
    let plan = engine_bridge::precompute_paragraph(&mut session, &mut evidence_window, &request)
        .expect("engine precompute succeeds");
    let evidence = evidence_window.snapshot();

    assert!(!plan.lines.is_empty(), "no lines");
    assert_eq!(
        plan.lines.last().unwrap().end_reason,
        tiqian_precompute::plan::PlanEndReason::ParagraphEnd,
        "last line must close the paragraph"
    );
    assert_eq!(
        tiqian_precompute::plan::PLAN_LAYOUT_REVISION.as_str(),
        "tiqian-layout-v2",
        "layout revision constant diverged"
    );
    assert!(
        !evidence.replay_shapes.is_empty(),
        "the engine never shaped through the session"
    );
    assert!(
        evidence
            .replay_shapes
            .iter()
            .all(|shape| !shape.glyphs.is_empty()),
        "a replayed shape carries no glyphs"
    );
}
