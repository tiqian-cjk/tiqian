//! Plan parity harness: the native lane against the js oracle (ADR 0050
//! amendment Verification).
//!
//! Both lanes run the same Kotlin engine over the same deterministic fixture
//! font backend, and plan JSON numbers are canonicalized in commonMain
//! (`appendJsonNumber`), so the two dumps are expected to match byte for
//! byte. The corpus and the fixture numbers mirror
//! `frontend/web-precompute/scripts/plan-parity-oracle.mjs` one to one; the
//! oracle dump is produced by that Node script and compared byte for byte.
//!
//! The engine link and the fixture backend make this test meaningless without
//! `TIQIAN_NATIVE_LIB_DIR`; the whole file compiles out in pure builds. The
//! comparison skips with a reason when the oracle dump is absent and still
//! writes the native dump, so a first divergence can be diffed by hand.
//!
//! The fixture callbacks below traverse the same C ABI as the production
//! backend; their `unsafe` obligations are listed in
//! docs/rust-unsafe-inventory.md, section "plan_parity.rs".

#![cfg(tiqian_engine_link)]

use std::ffi::{c_char, CStr};
use std::path::PathBuf;
use std::sync::Once;

use tiqian::font_backend::{FontBackendVtable, InstallOutcome, FONT_BACKEND_PROTOCOL_REVISION};
use tiqian::layout_request::{InlineBoxOuterSpacingCode, LineBreakPolicyCode};
use tiqian::shape_buffer::{
    required_shape_buffer_size, write_shape_buffer, ShapeEvidence, ShapeGlyphRecord,
};
use tiqian_precompute::js_compat::js_int_to_number;
use tiqian_precompute::json::Json;
use tiqian_precompute::paragraph::{
    InlineBoxInput, LineBreakSpanInput, ParagraphRequest, TextSpanInput,
};
use tiqian_precompute::plan::{Plan, PlanEndReason};

const FIXTURE_FACE_ID: &str = "Fixture CJK";
const FIXTURE_INSTANCE_ID: &str = "fixture-sha:0:wght=400";
const FIXTURE_SCRIPT: &str = "Hani";

static INSTALL: Once = Once::new();

fn install_fixture_backend() {
    INSTALL.call_once(|| {
        // The engine keeps the pointer for the process lifetime, so the
        // vtable lives in static storage; get_or_init runs the conversion
        // outside a const context.
        static VTABLE: std::sync::OnceLock<FontBackendVtable> = std::sync::OnceLock::new();
        let vtable = VTABLE.get_or_init(|| FontBackendVtable {
            size: u32::try_from(std::mem::size_of::<FontBackendVtable>())
                .expect("vtable size fits u32"),
            protocol_revision: FONT_BACKEND_PROTOCOL_REVISION,
            shape: Some(fixture_shape),
            metrics: Some(fixture_metrics),
            release_string: Some(fixture_release_string),
        });
        assert_eq!(
            tiqian::engine::install_font_backend(vtable),
            InstallOutcome::Installed
        );
    });
}

/// Mirrors the fixture backend of `PrecomputeExportsTest.kt` and
/// `plan-parity-oracle.mjs`: one glyph per code point, advance and x scaled
/// by the font size, glyph id 0 marks a missing glyph. The `unsafe` marker is
/// part of the signature shared with the production backend; obligations:
/// docs/rust-unsafe-inventory.md.
unsafe extern "C" fn fixture_shape(
    _session_id: *const c_char,
    display_text: *const c_char,
    _serialized_families: *const c_char,
    font_size: f64,
    _font_weight: i32,
    _italic: i32,
    _locale: *const c_char,
    _role: *const c_char,
    _source_text: *const c_char,
    buffer: *mut u8,
    capacity: u64,
    _error_out: *mut *mut c_char,
) -> i64 {
    // SAFETY: engine arguments are NUL-terminated strings per the ABI.
    let text = match display_text.is_null() {
        true => return -1,
        false => unsafe { CStr::from_ptr(display_text).to_string_lossy().into_owned() },
    };
    let missing = text.contains('⋯');
    let glyphs: Vec<ShapeGlyphRecord> = text
        .chars()
        .enumerate()
        .map(|(index, _)| ShapeGlyphRecord {
            id: if missing {
                0
            } else {
                100 + u32::try_from(index).expect("fixture glyph index fits u32")
            },
            advance: font_size,
            x: js_int_to_number(i64::try_from(index).expect("fixture glyph index fits i64"))
                * font_size,
            y: 0.0,
            bounds: Some([0.0, -font_size * 0.88, font_size, font_size * 0.12]),
        })
        .collect();
    let evidence = ShapeEvidence {
        face_id: FIXTURE_FACE_ID.to_string(),
        instance_id: FIXTURE_INSTANCE_ID.to_string(),
        script: FIXTURE_SCRIPT.to_string(),
        features: Vec::new(),
        total_advance: js_int_to_number(
            i64::try_from(glyphs.len()).expect("fixture glyph count fits i64"),
        ) * font_size,
        unsafe_break_count: 0,
    };
    let needed = required_shape_buffer_size(glyphs.len(), &evidence);
    let capacity = usize::try_from(capacity).expect("shape buffer capacity fits usize");
    if buffer.is_null() || capacity < needed {
        return i64::try_from(needed).expect("shape buffer size fits i64");
    }
    // SAFETY: the engine passes `capacity` live bytes at `buffer`.
    let out = unsafe { std::slice::from_raw_parts_mut(buffer, needed) };
    write_shape_buffer(out, &glyphs, &evidence).expect("fixture shape buffer write succeeds");
    i64::try_from(needed).expect("shape buffer size fits i64")
}

/// [ascent, descent, leading, typo ascent, typo descent] scaled by the font
/// size, the fixture numbers of the js backend.
unsafe extern "C" fn fixture_metrics(
    _session_id: *const c_char,
    _serialized_families: *const c_char,
    font_size: f64,
    _font_weight: i32,
    _italic: i32,
    _role: *const c_char,
    _face_selection_text: *const c_char,
    out_metrics: *mut f64,
    _error_out: *mut *mut c_char,
) -> i64 {
    if out_metrics.is_null() {
        return -1;
    }
    let values = [
        font_size * 1.04,
        font_size * 0.28,
        0.0,
        font_size * 0.88,
        font_size * 0.12,
    ];
    for (index, value) in values.iter().enumerate() {
        // SAFETY: the engine passes five live doubles at `out_metrics`.
        unsafe { *out_metrics.add(index) = *value };
    }
    0
}

/// Vtable callback; the fixture backend produces no error strings.
unsafe extern "C" fn fixture_release_string(_string: *const c_char) {}

fn corpus() -> Vec<(&'static str, ParagraphRequest)> {
    let base = || ParagraphRequest {
        font_session_id: "fixture-session".to_string(),
        text: String::new(),
        max_width_px: 36.0,
        font_families: vec!["Fixture CJK".to_string()],
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
    };

    let mut plain = base();
    plain.text = "中文中文中文中文".to_string();

    let mut punctuation = base();
    punctuation.text = "中文，中文；中文。".to_string();
    punctuation.max_width_px = 72.0;

    let mut mixed = base();
    mixed.text = "Hello 中文 world 字".to_string();
    mixed.max_width_px = 90.0;
    mixed.line_length_grid_enabled = false;

    let mut indent = base();
    indent.text = "中文中文中文".to_string();
    indent.first_line_indent_ic = 2.0;

    let mut span = base();
    span.text = "中文中文".to_string();
    span.text_spans = vec![TextSpanInput {
        start: 0,
        end: 2,
        families: vec!["Fixture CJK".to_string()],
        font_size_px: 20.0,
        font_weight: 700,
        italic: false,
        baseline_shift: 0.0,
    }];

    let mut boundaries = base();
    boundaries.text = "中文中文中文".to_string();
    boundaries.source_boundaries = vec![2, 4];

    let mut policy = base();
    policy.text = "URLhttps://example.com/中文".to_string();
    policy.max_width_px = 90.0;
    policy.line_length_grid_enabled = false;
    policy.line_break_spans = vec![LineBreakSpanInput {
        start: 0,
        end: 25,
        policy: LineBreakPolicyCode::ProgressiveTechnical,
    }];

    let mut inline_box = base();
    inline_box.text = "中文字中文".to_string();
    inline_box.inline_boxes = vec![InlineBoxInput {
        start: 2,
        end: 3,
        inline_start: 6.0,
        inline_end: 12.0,
        outer_spacing: InlineBoxOuterSpacingCode::Narrow,
    }];

    let mut ellipsis = base();
    ellipsis.text = "……".to_string();
    ellipsis.max_width_px = 72.0;

    vec![
        ("plainWrap", plain),
        ("punctuation", punctuation),
        ("mixed", mixed),
        ("indent", indent),
        ("span", span),
        ("boundaries", boundaries),
        ("lineBreakPolicy", policy),
        ("inlineBox", inline_box),
        ("ellipsis", ellipsis),
    ]
}

fn parity_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../build/plan-parity")
}

#[test]
fn native_plans_match_the_js_oracle_byte_for_byte() {
    install_fixture_backend();
    let mut native = Vec::<(String, Json)>::new();
    for (name, request) in corpus() {
        // The dump must hold the exact engine bytes, so the test drives the
        // ABI directly instead of reading `precompute_paragraph`'s `Plan`.
        let packed = request
            .to_layout_request()
            .unwrap_or_else(|error| panic!("{name}: request invalid: {error}"))
            .pack()
            .unwrap_or_else(|error| panic!("{name}: request pack failed: {error}"));
        let plan_json = tiqian::engine::layout_paragraph(&packed)
            .unwrap_or_else(|error| panic!("{name}: precompute failed: {error}"));
        let plan = Plan::from_json_str(&plan_json)
            .unwrap_or_else(|error| panic!("{name}: plan unreadable: {error}"));
        assert!(!plan.lines.is_empty(), "{name}: no lines");
        assert_eq!(
            plan.lines.last().unwrap().end_reason,
            PlanEndReason::ParagraphEnd,
            "{name}: last line must close the paragraph"
        );
        native.push((name.to_string(), Json::Str(plan_json)));
    }

    let dump = Json::Obj(native).render();
    std::fs::create_dir_all(parity_dir()).expect("create parity dump directory");
    let native_path = parity_dir().join("native.json");
    std::fs::write(&native_path, &dump).expect("write native dump");

    let oracle_path = parity_dir().join("oracle.json");
    let Ok(oracle) = std::fs::read_to_string(&oracle_path) else {
        if std::env::var("TIQIAN_REQUIRE_PARITY_ORACLE").is_ok_and(|value| value == "1") {
            panic!(
                "TIQIAN_REQUIRE_PARITY_ORACLE=1 but no oracle dump at {}; \
                 run node scripts/plan-parity-oracle.mjs in frontend/web-precompute",
                oracle_path.display()
            );
        }
        eprintln!(
            "skipped: no oracle dump at {}; run node scripts/plan-parity-oracle.mjs in frontend/web-precompute to produce it",
            oracle_path.display()
        );
        return;
    };
    let oracle = oracle.trim_end();
    let dump = dump.trim_end();
    if oracle != dump {
        for (oracle_case, native_case) in oracle.split("},{").zip(dump.split("},{")) {
            if oracle_case != native_case {
                panic!("plan divergence:\noracle: {oracle_case}\nnative: {native_case}");
            }
        }
        panic!("plan dumps differ in structure");
    }
}
