// Prepared DOM lowering parity (ADR 0050 Verification).
//
// The committed corpus is shared with the js lane
// `frontend/web/npm/prepared-dom-corpus.test.mjs`; both sides assert the same
// bytes. Regenerate the fixture with
// `node scripts/build-prepared-dom-corpus.mjs` from frontend/web-precompute
// after changing either implementation, then review the diff.

use std::path::PathBuf;

use tiqian::NamedError;
use tiqian_precompute::json::{parse_json, Json};
use tiqian_precompute::prepared_dom::{render_prepared_paragraph_artifact, PreparedRenderOptions};

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../../frontend/web/npm/prepared-dom-corpus.fixture.json")
}

fn field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

fn str_field<'a>(value: &'a Json, key: &str) -> Option<&'a str> {
    match field(value, key) {
        Some(Json::Str(text)) => Some(text),
        _ => None,
    }
}

/// Counts are read as JSON numbers and compared in that type; the render
/// counts are narrowed first.
fn count_field(value: &Json, key: &str) -> f64 {
    match field(value, key) {
        Some(Json::Num(number)) => *number,
        _ => 0.0,
    }
}

#[test]
fn prepared_dom_corpus_matches_the_js_oracle_fixture() {
    let raw = std::fs::read_to_string(fixture_path())
        .expect("the shared corpus fixture is committed with the module");
    let fixture = parse_json(&raw).expect("the corpus fixture is valid JSON");
    let cases = match field(&fixture, "cases") {
        Some(Json::Arr(cases)) => cases,
        _ => panic!("the corpus fixture carries a cases array"),
    };
    assert!(
        cases.len() >= 20,
        "the corpus keeps covering the lowering paths"
    );

    for case in cases {
        let name = str_field(case, "name").unwrap_or_default().to_string();
        let plan = str_field(case, "plan")
            .expect("each case carries plan JSON")
            .to_string();
        let locale = str_field(case, "locale").unwrap_or("zh-Hans");
        let options_json = field(case, "options")
            .cloned()
            .unwrap_or(Json::Obj(Vec::new()));
        let expect = field(case, "expect").expect("each case carries an expectation");

        let mut style_callback = |declaration: &str| format!("tqc-{}", declaration.len());
        let mut options = PreparedRenderOptions::new();
        options.semantic_replay = str_field(&options_json, "semanticReplay");
        options.source_text = str_field(&options_json, "sourceText");
        options.semantics = field(&options_json, "semantics");
        options.render_text_spans = field(&options_json, "renderTextSpans");
        options.inline_boxes = field(&options_json, "inlineBoxes");
        if str_field(&options_json, "styleClassFor").is_some() {
            options.style_class_for = Some(&mut style_callback);
        }

        let lowered = render_prepared_paragraph_artifact(&plan, locale, &mut options);
        match str_field(expect, "kind") {
            Some("ok") => {
                let lowered = lowered.unwrap_or_else(|error| {
                    panic!("case {name}: expected a render, got {}", error.name())
                });
                assert_eq!(
                    lowered.html,
                    str_field(expect, "html").unwrap_or_default(),
                    "case {name}: html"
                );
                assert_eq!(
                    lowered.artifact.render(),
                    str_field(expect, "artifact").unwrap_or_default(),
                    "case {name}: artifact"
                );
                assert_eq!(
                    count_field(expect, "liveSemanticCount"),
                    f64::from(
                        u32::try_from(lowered.live_semantic_count)
                            .expect("live semantic count fits u32")
                    ),
                    "case {name}: live semantic count"
                );
                assert_eq!(
                    count_field(expect, "markerCount"),
                    f64::from(u32::try_from(lowered.marker_count).expect("marker count fits u32")),
                    "case {name}: marker count"
                );
            }
            Some("error") => {
                let expected = str_field(expect, "error").unwrap_or_default();
                match lowered {
                    Err(NamedError(name)) if name == expected => {}
                    Err(error) => panic!("case {name}: expected {expected}, got {}", error.name()),
                    Ok(_) => panic!("case {name}: expected error {expected}, got a render"),
                }
            }
            other => panic!("case {name}: unknown expectation kind {other:?}"),
        }
    }
}
