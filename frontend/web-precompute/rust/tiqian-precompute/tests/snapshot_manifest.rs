// Snapshot manifest compaction (ADR 0050, ADR 0052 schema 2).
//
// Compaction runs against finalized station tables: entries resolve
// typography, face, and probe references by table index and the manifest
// pins the table's content hash. The tests pin the metadata spread, the
// version gate, the entry-row field passthrough, and the issue vocabulary
// of the absorb-and-compact pipeline.

use tiqian::NamedError;
use tiqian_precompute::json::{parse_json, Json};
use tiqian_precompute::snapshot_manifest::compact_snapshot_manifest_with_tables;
use tiqian_precompute::snapshot_tables::SnapshotTables;

const SHAPE_ITEM: &str = r#"{"key":"[\"排\",\"Tiqian Han\",400,false,\"zh-Hans\",\"body\",\"排\"]","result":{"faceId":"face-1","fontInstanceId":"fi-1","script":"hani","features":["pwid","palt"],"unsafeBreakCount":0,"advanceEm":1000,"glyphs":[{"id":1,"advanceEm":500,"xEm":10,"yEm":-2,"boundsEm":[0,-2,500,700]},{"id":2,"advanceEm":500,"xEm":5,"yEm":0,"boundsEm":null}]}}"#;
const METRIC_ITEM: &str =
    r#"{"key":"[\"Tiqian Han\",400,false,\"body\",\"永\"]","valuesEm":[1.5,2,3,4,5]}"#;

/// A full probe row: the binary table encodes every column, so fixtures
/// carry the complete object.
const PROBE: &str = r#""probe":{"text":"永","advancePx":18,"fontSizePx":18,"fontWeight":400,"italic":false,"script":"hani","language":"ZH","features":[]}"#;

fn entry_text_with(
    shapes: &str,
    metrics: &str,
    key: &str,
    typography: &str,
    extra: &str,
    versions: &str,
) -> String {
    format!(
        r#"{{"key":"{key}","sourceSha256":"sha-{key}",{extra}"typographySha256":"typ-{typography}","typography":{{"value":"{typography}","lineHeight":1.6}},"maxWidthPx":320,"fontEvidence":{{{versions}"faces":[{{"family":"Tiqian Han","style":"normal","weight":400,"coverageText":"永中",{PROBE}}}],"replay":{{"revision":"tiqian-server-shaping-replay-v1","shapes":[{shapes}],"metrics":[{metrics}]}}}},"renderArtifactSha256":"render-{key}"}}"#,
    )
}

fn entry_text(key: &str, typography: &str, extra: &str, versions: &str) -> String {
    entry_text_with(SHAPE_ITEM, METRIC_ITEM, key, typography, extra, versions)
}

const BACKEND_7: &str = r#""backendRevision":"backend-7","#;

fn entries_a() -> Json {
    let p1 = entry_text("p1", "typo-a", "", BACKEND_7);
    let p2 = entry_text(
        "p2",
        "typo-a",
        r#""sourceArtifactSha256":"art-p2","semantics":[{"start":0,"end":2}],"#,
        BACKEND_7,
    );
    let p3 = entry_text("p3", "typo-b", "", BACKEND_7);
    parse_json(&format!("[{p1},{p2},{p3}]")).expect("entries parse")
}

fn entries_b() -> Json {
    let p1 = entry_text("p1", "typo-a", "", "");
    let p2 = entry_text("p2", "typo-a", "", r#""backendRevision":"backend-9","#);
    parse_json(&format!("[{p1},{p2}]")).expect("entries parse")
}

fn metadata() -> Json {
    parse_json(r#"{"createdAt":"2026-08-20","locale":"zh-Hans"}"#).expect("metadata parses")
}

/// The whole pipeline behind one manifest: absorb the corpus, freeze the
/// table, compact against the frozen rows.
fn compact(entries: &Json, metadata: &Json) -> Result<Json, NamedError> {
    let mut tables = SnapshotTables::new();
    tables.absorb_prepared(entries)?;
    tables.finalize()?;
    compact_snapshot_manifest_with_tables(entries, metadata, &tables)
}

fn field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

fn error_name(result: Result<Json, NamedError>) -> String {
    match result {
        Err(error) => error.name().to_string(),
        Ok(_) => panic!("expected an error, got a manifest"),
    }
}

#[test]
fn compact_spreads_metadata_and_pins_the_table_hash() {
    let mut tables = SnapshotTables::new();
    tables
        .absorb_prepared(&entries_a())
        .expect("absorb succeeds");
    let file = tables.finalize().expect("freeze succeeds");
    let metadata = parse_json(
        r#"{"createdAt":"2026-08-20","locale":"zh-Hans","valueStyles":["--tq-line-height:27px!important"],"valueStylesSha256":"style-sha"}"#,
    )
    .expect("metadata parses");
    let manifest = compact_snapshot_manifest_with_tables(&entries_a(), &metadata, &tables)
        .expect("compact succeeds");
    // Metadata spreads through; value styles live in the table.
    assert_eq!(
        field(&manifest, "createdAt"),
        Some(&Json::str("2026-08-20"))
    );
    assert_eq!(field(&manifest, "locale"), Some(&Json::str("zh-Hans")));
    for absent in ["valueStyles", "valueStylesSha256"] {
        assert!(field(&manifest, absent).is_none(), "{absent} dropped");
    }
    // The manifest declares schema 2 and pins the table's content hash.
    assert!(matches!(
        field(&manifest, "schema"),
        Some(Json::Num(value)) if *value == 2.0
    ));
    match field(&manifest, "tables").and_then(|tables| field(tables, "snapshot")) {
        Some(Json::Str(sha)) => assert_eq!(sha, &file.sha256),
        other => panic!("tables.snapshot: {other:?}"),
    }
    // The replay keeps per-article shape rows only.
    let replay = field(&manifest, "fontReplay").expect("fontReplay");
    assert!(field(replay, "strings").is_none());
    assert!(field(replay, "metrics").is_none());
    match field(replay, "shapes") {
        Some(Json::Arr(rows)) => assert_eq!(rows.len(), 1),
        other => panic!("shape rows: {other:?}"),
    }
}

#[test]
fn entry_rows_carry_the_passthrough_fields_and_table_references() {
    let manifest = compact(&entries_a(), &metadata()).expect("compact succeeds");
    let entries = match field(&manifest, "entries") {
        Some(Json::Arr(items)) => items,
        other => panic!("entries: {other:?}"),
    };
    assert_eq!(entries.len(), 3);
    // p1: the bare row.
    assert_eq!(field(&entries[0], "key"), Some(&Json::str("p1")));
    assert_eq!(field(&entries[0], "typographyRef"), Some(&Json::Num(0.0)));
    assert!(field(&entries[0], "semantic").is_none());
    assert!(field(&entries[0], "sourceArtifactSha256").is_none());
    // p2: artifact and semantics markers pass through.
    assert_eq!(
        field(&entries[1], "sourceArtifactSha256"),
        Some(&Json::str("art-p2"))
    );
    assert_eq!(field(&entries[1], "semantic"), Some(&Json::Bool(true)));
    // p3: the second typography row.
    assert_eq!(field(&entries[2], "typographyRef"), Some(&Json::Num(1.0)));
    // Face rows reference the table; coverage text stays on the source faces.
    let evidence = match field(&entries[0], "fontFaceEvidence") {
        Some(Json::Arr(rows)) => rows,
        other => panic!("fontFaceEvidence: {other:?}"),
    };
    assert_eq!(field(&evidence[0], "faceRef"), Some(&Json::Num(0.0)));
    assert!(field(&evidence[0], "probeRef").is_some());
    assert!(field(&evidence[0], "coverageText").is_none());
}

#[test]
fn version_evidence_locks_in_at_the_first_real_value() {
    let manifest = compact(&entries_b(), &metadata()).expect("compact succeeds");
    let entries = match field(&manifest, "entries") {
        Some(Json::Arr(items)) => items,
        other => panic!("entries: {other:?}"),
    };
    assert_eq!(entries.len(), 2);
}

#[test]
fn version_evidence_conflicts_after_locking_in() {
    let p1 = entry_text("p1", "typo-a", "", BACKEND_7);
    let p2 = entry_text("p2", "typo-a", "", "");
    let entries = parse_json(&format!("[{p1},{p2}]")).expect("entries parse");
    assert_eq!(
        error_name(compact(&entries, &metadata())),
        "SnapshotFontEvidenceVersionConflict"
    );
}

#[test]
fn compact_reports_replay_damage_with_js_issue_names() {
    let short_metrics =
        r#"{"key":"[\"Tiqian Han\",400,false,\"body\",\"永\"]","valuesEm":[1,2,3,4]}"#;
    let entry = entry_text_with(SHAPE_ITEM, short_metrics, "p1", "typo-a", "", BACKEND_7);
    let entries = parse_json(&format!("[{entry}]")).expect("entries parse");
    assert_eq!(
        error_name(compact(&entries, &metadata())),
        "SnapshotFontReplayMetricsInvalid"
    );

    let bad_bounds = r#"{"key":"[\"排\",\"Tiqian Han\",400,false,\"zh-Hans\",\"body\",\"排\"]","result":{"faceId":"face-1","fontInstanceId":"fi-1","script":"hani","features":[],"unsafeBreakCount":0,"advanceEm":1,"glyphs":[{"id":1,"boundsEm":[1,2,3]}]}}"#;
    let entry = entry_text_with(bad_bounds, METRIC_ITEM, "p1", "typo-a", "", BACKEND_7);
    let entries = parse_json(&format!("[{entry}]")).expect("entries parse");
    assert_eq!(
        error_name(compact(&entries, &metadata())),
        "SnapshotFontReplayGlyphBoundsInvalid"
    );

    let conflicting = r#"{"key":"[\"排\",\"Tiqian Han\",400,false,\"zh-Hans\",\"body\",\"排\"]","result":{"faceId":"face-1","fontInstanceId":"fi-1","script":"hani","features":["pwid","palt"],"unsafeBreakCount":0,"advanceEm":2000,"glyphs":[]}}"#;
    let other = r#"{"key":"[\"版\",\"Tiqian Han\",400,false,\"zh-Hans\",\"body\",\"版\"]","result":{"faceId":"face-1","fontInstanceId":"fi-1","script":"hani","features":["pwid","palt"],"unsafeBreakCount":0,"advanceEm":1000,"glyphs":[]}}"#;
    let p1 = entry_text("p1", "typo-a", "", BACKEND_7);
    let p2 = entry_text_with(
        &format!("{other},{conflicting}"),
        METRIC_ITEM,
        "p2",
        "typo-a",
        "",
        BACKEND_7,
    );
    let entries = parse_json(&format!("[{p1},{p2}]")).expect("entries parse");
    assert_eq!(
        error_name(compact(&entries, &metadata())),
        "SnapshotFontReplayShapeConflict"
    );

    let empty_faces = r#"{"key":"p1","sourceSha256":"sha-p1","typographySha256":"typ-typo-a","typography":{"value":"typo-a","lineHeight":1.6},"maxWidthPx":320,"fontEvidence":{"backendRevision":"backend-7","faces":[]},"renderArtifactSha256":"render-p1"}"#;
    let entries = parse_json(&format!("[{empty_faces}]")).expect("entries parse");
    assert_eq!(
        error_name(compact(&entries, &metadata())),
        "SnapshotFontEvidenceInvalid:p1"
    );
}

#[test]
fn compact_rejects_a_non_array_entry_list() {
    assert_eq!(
        error_name(compact(&Json::Null, &metadata())),
        "SnapshotFontEvidenceInvalid:undefined"
    );
}
