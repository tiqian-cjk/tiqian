//! The session-backed engine bridge against a real font file (ADR 0050
//! Slice C). The fixture font is the system font the session parity harness
//! uses; the test skips with a reason when the file is absent.

#![cfg(tiqian_engine_link)]

use std::path::PathBuf;

use tiqian_precompute::engine_bridge;
use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
use tiqian_precompute::paragraph::ParagraphRequest;
use tiqian_precompute::plan::Plan;
use tiqian_precompute::session::{
    create_font_session, CaptureEvidence, SessionFaceSpec, SessionOptions,
};

fn dela_gothic_path() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home).join(".local/share/fonts/DelaGothicOne-Regular.ttf");
    path.is_file().then_some(path)
}

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
    let Some(font_path) = dela_gothic_path() else {
        eprintln!(
            "skipped: DelaGothicOne-Regular.ttf absent at {}",
            font_path_by_home().display()
        );
        return;
    };
    let bytes = std::fs::read(&font_path).expect("fixture font reads");
    let specs = vec![SessionFaceSpec {
        spec: FontFaceSpec {
            family: "Dela Gothic One",
            public_url: "/fonts/DelaGothicOne-Regular.ttf",
            source: &bytes,
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
    let plan_json =
        engine_bridge::precompute_paragraph(&mut session, &mut evidence_window, &request)
            .expect("engine precompute succeeds");
    let evidence = evidence_window.snapshot();

    let plan = Plan::from_json_str(&plan_json).expect("plan json parses");
    assert!(!plan.lines.is_empty(), "no lines");
    assert_eq!(
        plan.lines.last().unwrap().end_reason,
        tiqian_precompute::plan::PlanEndReason::ParagraphEnd,
        "last line must close the paragraph"
    );
    assert!(
        plan_json.contains("\"layoutRevision\":\"tiqian-layout-v2\""),
        "plan misses the layout revision: {plan_json}"
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

fn font_path_by_home() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join(".local/share/fonts/DelaGothicOne-Regular.ttf")
}
