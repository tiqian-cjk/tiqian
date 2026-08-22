// Snapshot bundle split render (ADR 0050, ADR 0052 schema 2).
//
// The data phase validates the prepared corpus and mints value-style rows
// into mutable station tables. The assembly phase compacts the manifest
// against the frozen table, so the manifest pins the table's content hash
// and carries indexes instead of inline tables. The tests pin that structure
// and the named gates of the data phase.

use tiqian::NamedError;
use tiqian_precompute::json::{parse_json, Json};
use tiqian_precompute::snapshot_bundle::{
    assemble_font_contract_bundle, assemble_snapshot_bundle, render_font_contract_bundle_data,
    render_snapshot_bundle_data, SnapshotBundle, SnapshotBundleOptions, PLAIN_PARAGRAPH_SELECTOR,
    RUNTIME_PARAGRAPH_SELECTOR,
};
use tiqian_precompute::snapshot_tables::SnapshotTables;

const SHARED_STYLE: &str = "/*shared-runtime-style*/";

const ENTRY_A: &str = r###"{"status":"prepared","schema":1,"layoutRevision":"tiqian-layout-v2","renderRevision":"prebroken-dom-v15","key":"p-1","sourceText":"正文","sourceSha256":"d661c3d96d53ebc0ca8a55aae24b5df4a4d1bf28d37337b982fe8ebf54846eeb","sourceArtifactSha256":"022be43d07155ae6136f2cec8d5a4054bbe28c175f11bfa4e31bc89c221ce73d","semantics":[{"start":0,"end":2,"tagName":"strong","attributes":[]}],"inlineBoxes":[],"renderTextSpans":[],"typography":{"fontFamilies":["Fixture CJK"],"fontSizePx":18,"lineHeightPx":27,"locale":"zh-Hans","fontWeight":400,"italic":false,"firstLineIndentIc":0,"lineLengthGridEnabled":true,"letterSpacingPx":0,"fontFeatureSettings":"normal","fontVariationSettings":"normal","fontVariantNumeric":"normal"},"renderFontFamilies":["Snapshot Sans"],"typographySha256":"c21cdb8a7e87a74ea0133ebef2938e3741095446d97278621f940d1f03a1eb68","maxWidthPx":360,"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","harfbuzzVersion":"harfrust-0.13.0","faces":[{"family":"Fixture CJK","publicUrl":"/fonts/f-a.woff2","coverageText":"正文","probe":{"text":"正","advancePx":18,"fontSizePx":18,"fontWeight":400,"italic":false,"script":"hani","language":"ZH","features":[]}}],"replay":{"revision":"tiqian-server-shaping-replay-v1","shapes":[],"metrics":[]}},"plan":{"schema":1,"layoutRevision":"tiqian-layout-v2","width":360,"height":27,"lines":[{"rangeStart":0,"rangeEnd":2,"top":0,"bottom":27,"baseline":20,"indent":0,"visualWidth":36,"hyphenAdvance":0,"endReason":"ParagraphEnd","cells":[{"rangeStart":0,"rangeEnd":2,"source":"正文","display":"正文","drawX":0,"naturalWidth":36,"leadingLayoutAdvance":0}]}]},"html":"<span>正文</span>","renderArtifactSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}"###;

const ENTRY_B: &str = r###"{"status":"prepared","schema":1,"layoutRevision":"tiqian-layout-v2","renderRevision":"prebroken-dom-v15","key":"p-2","sourceText":"后文","sourceSha256":"30bc60d288a5cf9c0e04bfd90351fa771abf3520b8f812a8123da21e19f39a0d","inlineBoxes":[],"renderTextSpans":[],"typography":{"fontFamilies":["Fixture CJK"],"fontSizePx":18,"lineHeightPx":27,"locale":"zh-Hans","fontWeight":400,"italic":false,"firstLineIndentIc":0,"lineLengthGridEnabled":true,"letterSpacingPx":0,"fontFeatureSettings":"normal","fontVariationSettings":"normal","fontVariantNumeric":"normal"},"renderFontFamilies":["Snapshot Sans"],"typographySha256":"c21cdb8a7e87a74ea0133ebef2938e3741095446d97278621f940d1f03a1eb68","maxWidthPx":360,"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","harfbuzzVersion":"harfrust-0.13.0","faces":[{"family":"Fixture CJK","publicUrl":"/fonts/f-a.woff2","coverageText":"后文","probe":{"text":"后","advancePx":18,"fontSizePx":18,"fontWeight":400,"italic":false,"script":"hani","language":"ZH","features":[]}}],"replay":{"revision":"tiqian-server-shaping-replay-v1","shapes":[],"metrics":[]}},"plan":{"schema":1,"layoutRevision":"tiqian-layout-v2","width":360,"height":27,"lines":[{"rangeStart":0,"rangeEnd":2,"top":0,"bottom":27,"baseline":20,"indent":0,"visualWidth":36,"hyphenAdvance":0,"endReason":"ParagraphEnd","cells":[{"rangeStart":0,"rangeEnd":2,"source":"后文","display":"后文","drawX":0,"naturalWidth":36,"leadingLayoutAdvance":0}]}]},"html":"<span>后文</span>","renderArtifactSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}"###;

const CONTRACT_FACE: &str = r###"{"status":"prepared","schema":1,"layoutRevision":"tiqian-layout-v2","renderRevision":"prebroken-dom-v15","key":"p-3","sourceText":"序言","sourceSha256":"d9dc1d2fbcde91ce50edb69f99f0f9ef7d00e31de655cd1884a761578b0ca8a0","inlineBoxes":[],"renderTextSpans":[],"typography":{"fontFamilies":["Fixture CJK"],"fontSizePx":18,"lineHeightPx":27,"locale":"zh-Hans","fontWeight":400,"italic":false,"firstLineIndentIc":0,"lineLengthGridEnabled":true,"letterSpacingPx":0,"fontFeatureSettings":"normal","fontVariationSettings":"normal","fontVariantNumeric":"normal"},"renderFontFamilies":["Snapshot Sans"],"typographySha256":"c21cdb8a7e87a74ea0133ebef2938e3741095446d97278621f940d1f03a1eb68","maxWidthPx":360,"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","harfbuzzVersion":"harfrust-0.13.0","faces":[{"family":"Fixture CJK","publicUrl":"/fonts/f-b.woff2","coverageText":"序言","probe":{"text":"序","advancePx":18,"fontSizePx":18,"fontWeight":400,"italic":false,"script":"hani","language":"ZH","features":[]}}],"replay":{"revision":"tiqian-server-shaping-replay-v1","shapes":[],"metrics":[]}},"plan":{"schema":1,"layoutRevision":"tiqian-layout-v2","width":360,"height":27,"lines":[{"rangeStart":0,"rangeEnd":2,"top":0,"bottom":27,"baseline":20,"indent":0,"visualWidth":36,"hyphenAdvance":0,"endReason":"ParagraphEnd","cells":[{"rangeStart":0,"rangeEnd":2,"source":"序言","display":"序言","drawX":0,"naturalWidth":36,"leadingLayoutAdvance":0}]}]},"html":"<span>序言</span>","renderArtifactSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}"###;

fn paragraphs() -> Json {
    parse_json(&format!("[{ENTRY_A},{ENTRY_B}]")).expect("entries parse")
}

fn entry_alone(entry: &str) -> Json {
    parse_json(&format!("[{entry}]")).expect("entry parses")
}

fn two_entries(first: &str, second: &str) -> Json {
    parse_json(&format!("[{first},{second}]")).expect("entries parse")
}

fn options<'a>(id: &'a str) -> SnapshotBundleOptions<'a> {
    let mut options = SnapshotBundleOptions::new(SHARED_STYLE);
    options.id = Some(id);
    options
}

/// The manifest JSON embedded in one template.
fn manifest_of(template: &str) -> Json {
    let start = template
        .find(r#"data-tq-snapshot-manifest>"#)
        .map(|at| at + r#"data-tq-snapshot-manifest>"#.len())
        .expect("template embeds a manifest");
    let end = template[start..]
        .find("</script>")
        .expect("manifest closes");
    parse_json(&template[start..start + end]).expect("manifest parses")
}

fn member<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

/// Runs the whole split render over one corpus: absorb, data, freeze,
/// assemble. The absorb corpus spans the plain and contract paragraphs, the
/// render input stays the plain list.
fn split_assemble(
    paragraphs: &Json,
    contract: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    let mut absorb = paragraphs.clone();
    if let Some(Json::Arr(items)) = contract {
        if let Json::Arr(rows) = &mut absorb {
            rows.extend(items.iter().cloned());
        }
    }
    let mut tables = SnapshotTables::new();
    tables.absorb_prepared(&absorb)?;
    let data = render_snapshot_bundle_data(Some(paragraphs), options, &mut tables)?;
    tables.finalize()?;
    assemble_snapshot_bundle(&data, options, &tables)
}

fn bundle(result: Result<SnapshotBundle, NamedError>) -> SnapshotBundle {
    match result {
        Ok(bundle) => bundle,
        Err(error) => panic!("expected a bundle, got {}", error.name()),
    }
}

/// The named error of one data phase call; the gates fire before any table
/// row is touched, so the table starts empty.
fn data_error(paragraphs: Option<&Json>, options: &SnapshotBundleOptions) -> String {
    let mut tables = SnapshotTables::new();
    match render_snapshot_bundle_data(paragraphs, options, &mut tables) {
        Err(error) => error.name().to_string(),
        Ok(_) => panic!("expected an error, got data"),
    }
}

/// The named error of the font-contract data phase.
fn contract_data_error(paragraphs: Option<&Json>, options: &SnapshotBundleOptions) -> String {
    let mut tables = SnapshotTables::new();
    match render_font_contract_bundle_data(paragraphs, options, &mut tables) {
        Err(error) => error.name().to_string(),
        Ok(_) => panic!("expected an error, got data"),
    }
}

fn set_field(entry: &mut Json, key: &str, value_text: &str) {
    let value = parse_json(value_text).expect("value parses");
    let Json::Obj(fields) = entry else {
        panic!("entry object")
    };
    for (name, slot) in fields.iter_mut() {
        if name == key {
            *slot = value;
            return;
        }
    }
    panic!("key {key} missing");
}

#[test]
fn snapshot_bundle_emits_a_schema_2_manifest_pinned_to_the_table() {
    let options = options("tq-page");
    let bundle = bundle(split_assemble(&paragraphs(), None, &options));
    assert_eq!(bundle.id, "tq-page");
    let manifest = manifest_of(&bundle.template);
    assert_eq!(member(&manifest, "schema"), Some(&Json::Num(2.0)));
    // The manifest carries no inline tables; every reference resolves through
    // the station table.
    for absent in [
        "typographies",
        "fontEvidence",
        "valueStyles",
        "valueStylesSha256",
    ] {
        assert!(
            member(&manifest, absent).is_none(),
            "manifest drops {absent}"
        );
    }
    let replay = member(&manifest, "fontReplay").expect("fontReplay present");
    assert!(member(replay, "strings").is_none());
    assert!(member(replay, "metrics").is_none());
    assert!(member(replay, "shapes").is_some());
    // The entry rows reference the table by index.
    let entries = match member(&manifest, "entries") {
        Some(Json::Arr(items)) => items,
        _ => panic!("entries present"),
    };
    assert_eq!(entries.len(), 2);
    let first = &entries[0];
    assert_eq!(member(first, "typographyRef"), Some(&Json::Num(0.0)));
    let evidence = match member(first, "fontFaceEvidence") {
        Some(Json::Arr(rows)) => rows,
        _ => panic!("fontFaceEvidence present"),
    };
    let face_row = &evidence[0];
    assert_eq!(member(face_row, "faceRef"), Some(&Json::Num(0.0)));
    assert!(member(face_row, "probeRef").is_some());
    assert!(member(face_row, "coverageText").is_none());
    assert!(member(face_row, "probe").is_none());
    // The rendered bodies carry the minted class and the two entry keys.
    let rendered = match &bundle.entries {
        Json::Arr(items) => items.clone(),
        _ => panic!("entries array"),
    };
    assert_eq!(rendered.len(), 2);
    for (entry, key) in rendered.iter().zip(["p-1", "p-2"]) {
        assert_eq!(member(entry, "key"), Some(&Json::str(key)));
        let html = match member(entry, "html") {
            Some(Json::Str(text)) => text,
            _ => panic!("html present"),
        };
        assert!(html.contains("tqv-0"), "body carries the value class");
    }
    assert_eq!(bundle.render_font_families.render(), r#"["Snapshot Sans"]"#);
    assert_eq!(bundle.font_preloads.render(), "[]");
    assert_eq!(
        bundle.root_attributes.render(),
        r#"{"data-tiqian-exact-render-font":"true"}"#
    );
    // The first-paint style keeps the shared prefix and appends the table
    // rows the classes reference.
    assert!(bundle.initial_style.starts_with(SHARED_STYLE));
    assert!(bundle
        .initial_style
        .contains(r#"tiqian-prose[snapshot-ref="tq-page"] [data-tq-rendered="true"] .tqv-0{--tq-line-height:27px!important;--tq-line-baseline-offset:-7px!important}"#));
}

#[test]
fn manifest_pins_the_sha_of_the_emitted_table() {
    let mut tables = SnapshotTables::new();
    tables
        .absorb_prepared(&paragraphs())
        .expect("absorb succeeds");
    let options = options("tq-page");
    let data = render_snapshot_bundle_data(Some(&paragraphs()), &options, &mut tables)
        .expect("data renders");
    let file = tables.finalize().expect("table freezes");
    let bundle = bundle(assemble_snapshot_bundle(&data, &options, &tables));
    let manifest = manifest_of(&bundle.template);
    assert_eq!(
        member(&manifest, "tables"),
        Some(&Json::Obj(vec![(
            "snapshot".to_string(),
            Json::str(file.sha256)
        )]))
    );
}

#[test]
fn font_contract_paragraphs_split_their_own_manifest_entries() {
    let contract = entry_alone(CONTRACT_FACE);
    let mut options = options("tq-sem");
    options.font_contract_paragraphs = Some(&contract);
    let bundle = bundle(split_assemble(
        &entry_alone(ENTRY_A),
        Some(&contract),
        &options,
    ));
    let manifest = manifest_of(&bundle.template);
    let contract_entries = match member(&manifest, "fontContractEntries") {
        Some(Json::Arr(items)) => items,
        _ => panic!("fontContractEntries present"),
    };
    assert_eq!(contract_entries.len(), 1);
    // The contract face is the second table row; the plain face is the first.
    let evidence = match member(&contract_entries[0], "fontFaceEvidence") {
        Some(Json::Arr(rows)) => rows,
        _ => panic!("contract evidence present"),
    };
    assert_eq!(member(&evidence[0], "faceRef"), Some(&Json::Num(1.0)));
    assert!(member(&evidence[0], "probeRef").is_some());
    // The client template replaces the entries with the font-contract rows.
    let client = manifest_of(&bundle.client_template);
    assert_eq!(
        member(&client, "entrySource"),
        Some(&Json::str("font-contract-v1"))
    );
    assert!(member(&client, "fontContractEntries").is_none());
    let client_entries = match member(&client, "entries") {
        Some(Json::Arr(items)) => items,
        _ => panic!("client entries present"),
    };
    assert!(!client_entries.is_empty());
    let client_evidence = match member(&client_entries[0], "fontFaceEvidence") {
        Some(Json::Arr(rows)) => rows,
        _ => panic!("client evidence present"),
    };
    assert!(member(&client_evidence[0], "coverageText").is_some());
    assert!(member(&client_evidence[0], "probeRef").is_some());
}

#[test]
fn font_contract_lane_uses_the_runtime_selector_and_short_style() {
    let corpus = paragraphs();
    let mut tables = SnapshotTables::new();
    tables.absorb_prepared(&corpus).expect("absorb succeeds");
    let options = options("tq-fc");
    let data = render_font_contract_bundle_data(Some(&corpus), &options, &mut tables)
        .expect("data renders");
    tables.finalize().expect("table freezes");
    let bundle = bundle(assemble_font_contract_bundle(&data, &options, &tables));
    assert_eq!(data.paragraph_selector, RUNTIME_PARAGRAPH_SELECTOR);
    let manifest = manifest_of(&bundle.template);
    assert_eq!(
        member(&manifest, "paragraphSelector"),
        Some(&Json::str(RUNTIME_PARAGRAPH_SELECTOR))
    );
    assert_eq!(bundle.entries.render(), "[]");
    assert_eq!(bundle.root_attributes.render(), "{}");
    assert!(!bundle.initial_style.contains(SHARED_STYLE));
    assert!(!bundle.initial_style.contains(".tqv-"));
    assert!(bundle
        .initial_style
        .contains("font-kerning:normal!important"));
}

#[test]
fn bundle_input_damage_reports_the_paragraph_list_gate_name() {
    assert_eq!(
        data_error(None, &options("tq-page")),
        "MissingPreparedParagraphs"
    );
    assert_eq!(
        data_error(Some(&Json::Null), &options("tq-page")),
        "MissingPreparedParagraphs"
    );
    assert_eq!(
        data_error(Some(&Json::Num(3.0)), &options("tq-page")),
        "MissingPreparedParagraphs"
    );
    assert_eq!(
        data_error(Some(&Json::str("p")), &options("tq-page")),
        "MissingPreparedParagraphs"
    );
}

#[test]
fn unsupported_status_reports_unsupported_paragraph() {
    let first = parse_json(ENTRY_A).expect("entry A");
    let mut second = parse_json(ENTRY_B).expect("entry B");
    set_field(&mut second, "status", r#""unsupported""#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), &second.render())),
            &options("tq-page"),
        ),
        "SnapshotTemplateContainsUnsupportedParagraph",
    );
}

#[test]
fn wrong_schema_reports_stale_paragraph() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "schema", r#"2"#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "SnapshotTemplateContainsStalePreparedParagraph",
    );
}

#[test]
fn wrong_layout_revision_reports_stale_paragraph() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "layoutRevision", r#""old""#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "SnapshotTemplateContainsStalePreparedParagraph",
    );
}

#[test]
fn wrong_render_revision_reports_stale_paragraph() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "renderRevision", r#""old""#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "SnapshotTemplateContainsStalePreparedParagraph",
    );
}

#[test]
fn numeric_render_artifact_sha_reports_stale_paragraph() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "renderArtifactSha256", r#"1"#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "SnapshotTemplateContainsStalePreparedParagraph",
    );
}

#[test]
fn duplicate_key_reports_duplicate_snapshot_key() {
    let mut second = parse_json(ENTRY_B).expect("entry B");
    set_field(&mut second, "key", r#""p-1""#);
    assert_eq!(
        data_error(
            Some(&two_entries(ENTRY_A, &second.render())),
            &options("tq-page"),
        ),
        "DuplicateSnapshotKey",
    );
}

#[test]
fn empty_render_font_families_report_missing_exact_families() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "renderFontFamilies", r#"[]"#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "MissingExactRenderFontFamilies",
    );
}

#[test]
fn blank_render_font_family_reports_missing_exact_families() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "renderFontFamilies", r#"[" "]"#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "MissingExactRenderFontFamilies",
    );
}

#[test]
fn numeric_render_font_family_reports_missing_exact_families() {
    let mut first = parse_json(ENTRY_A).expect("entry A");
    set_field(&mut first, "renderFontFamilies", r#"[1]"#);
    assert_eq!(
        data_error(
            Some(&two_entries(&first.render(), ENTRY_B)),
            &options("tq-page"),
        ),
        "MissingExactRenderFontFamilies",
    );
}

#[test]
fn conflicting_render_font_families_report_a_conflict() {
    let mut second = parse_json(ENTRY_B).expect("entry B");
    set_field(&mut second, "renderFontFamilies", r#"["Other Sans"]"#);
    assert_eq!(
        data_error(
            Some(&two_entries(ENTRY_A, &second.render())),
            &options("tq-page"),
        ),
        "SnapshotRenderFontFamilyConflict",
    );
}

#[test]
fn missing_render_font_families_report_a_conflict() {
    let mut second = parse_json(ENTRY_B).expect("entry B");
    let Json::Obj(fields) = &mut second else {
        panic!("entry object")
    };
    fields.retain(|(name, _)| name != "renderFontFamilies");
    assert_eq!(
        data_error(
            Some(&two_entries(ENTRY_A, &second.render())),
            &options("tq-page"),
        ),
        "SnapshotRenderFontFamilyConflict",
    );
}

#[test]
fn template_id_and_selector_damage_reports_the_js_gate_names() {
    let paragraphs = paragraphs();
    for id in ["", " ", "1abc", "ab cd"] {
        let expected = if id.trim().is_empty() {
            "MissingSnapshotTemplateId"
        } else {
            "InvalidSnapshotTemplateId"
        };
        assert_eq!(data_error(Some(&paragraphs), &options(id)), expected);
    }
    let mut selector_options = options("tq-page");
    selector_options.paragraph_selector = Some(":is(p)");
    assert_eq!(
        data_error(Some(&paragraphs), &selector_options),
        "UnsupportedSnapshotParagraphSelector"
    );
    let mut plain_options = options("tq-fc-plain");
    plain_options.paragraph_selector = Some(PLAIN_PARAGRAPH_SELECTOR);
    assert_eq!(
        contract_data_error(Some(&paragraphs), &plain_options),
        "UnsupportedSnapshotParagraphSelector"
    );
}

#[test]
fn unsupported_contract_paragraph_reports_unsupported_paragraph() {
    let mut damage = parse_json(CONTRACT_FACE).expect("contract parses");
    set_field(&mut damage, "status", "\"unsupported\"");
    let contract = parse_json(&format!("[{}]", damage.render())).expect("contract parses");
    let mut options = options("tq-page");
    options.font_contract_paragraphs = Some(&contract);
    assert_eq!(
        data_error(Some(&entry_alone(ENTRY_A)), &options),
        "SnapshotTemplateContainsUnsupportedParagraph"
    );
}
