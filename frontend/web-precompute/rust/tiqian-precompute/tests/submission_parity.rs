//! Submission-lane parity against the low-level batch lanes (ADR 0052). The
//! canonical-encode, submit, decode and compute chain must produce entry
//! bytes identical to `prepare_paragraph` / `prepare_font_contract` over the
//! same input, and the layered cache must serve the recorded artifact back
//! through the hash-only marker. The engine archive must be linked.

#![cfg(tiqian_engine_link)]

use std::path::PathBuf;
use std::sync::Arc;

use tiqian_precompute::canonical::{self, digest};
use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
use tiqian_precompute::json::{member, parse_json, Json};
use tiqian_precompute::normalize::TypographyInput;
use tiqian_precompute::precomputer::{
    create_precomputer, Precomputer, PrecomputerOptions, PrepareInput,
};
use tiqian_precompute::session::SessionFaceSpec;
use tiqian_precompute::submission::{SubmissionItem, SubmissionOutcome};

fn dela_gothic_path() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home).join(".local/share/fonts/DelaGothicOne-Regular.ttf");
    path.is_file().then_some(path)
}

fn fixture_precomputer() -> Option<Arc<Precomputer>> {
    let font_path = dela_gothic_path()?;
    let bytes = std::fs::read(font_path).expect("fixture font reads");
    Some(Arc::new(
        create_precomputer(PrecomputerOptions::new(
            TypographyInput {
                font_families: Some(vec!["Dela Gothic One".to_string()]),
                font_size_px: Some(18.0),
                line_height_px: Some(27.0),
                ..Default::default()
            },
            vec![SessionFaceSpec {
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
            }],
        ))
        .expect("fixture precomputer builds"),
    ))
}

fn submission_item(input_json: &str, kind: u8) -> SubmissionItem {
    let value = parse_json(input_json).expect("input parses");
    // The canonical form carries content only; the logical key rides with the
    // submission, so the test reuses the lane input's own key.
    let logical_key = match member(&value, "key") {
        Some(Json::Str(text)) => text.clone(),
        _ => "fixture".to_string(),
    };
    let bytes = canonical::encode_input(&value, kind).expect("canonical encodes");
    let hash = digest(&bytes);
    SubmissionItem {
        hash,
        logical_key,
        canonical: bytes,
    }
}

fn lane_entry(precomputer: &Precomputer, input_json: &str, contract: bool) -> String {
    let value = parse_json(input_json).expect("input parses");
    let input = PrepareInput::from_json(&value);
    let entry = if contract {
        precomputer.prepare_font_contract(&input)
    } else {
        precomputer.prepare_paragraph(&input)
    };
    entry.expect("lane entry prepares").render()
}

const CASES: &[(&str, &str, bool)] = &[
    (
        "snapshot",
        r#"{"key":"p-1","text":"中文文字排版段落","maxWidthPx":144}"#,
        false,
    ),
    (
        "semantic",
        r#"{"key":"p-2","text":"中文文字排版段落","maxWidthPx":144,"semantics":[{"tagName":"a","start":2,"end":4,"attributes":{"href":"https://example.com"}}]}"#,
        false,
    ),
    (
        "unsupported_emoji",
        r#"{"key":"p-4","text":"中🦔文","maxWidthPx":144}"#,
        false,
    ),
    ("contract", r#"{"key":"fc-1","text":"中文合同段落"}"#, true),
    (
        "contract_dash_retry",
        r#"{"key":"fc-2","text":"도——문"}"#,
        true,
    ),
];

#[test]
fn submission_bytes_match_the_low_level_lanes() {
    let Some(precomputer) = fixture_precomputer() else {
        return;
    };
    for (name, input, contract) in CASES {
        let kind = if *contract {
            canonical::KIND_CONTRACT
        } else {
            canonical::KIND_SNAPSHOT
        };
        let item = submission_item(input, kind);
        let outcomes = precomputer
            .submit_contents(vec![item])
            .expect("submission computes");
        match outcomes.first() {
            Some(SubmissionOutcome::Computed { artifact }) => {
                let lane = lane_entry(&precomputer, input, *contract);
                assert_eq!(
                    String::from_utf8(artifact.clone()).expect("artifact is utf-8"),
                    lane,
                    "case {name}: submission bytes equal the lane bytes"
                );
            }
            other => panic!("case {name}: expected a computed outcome, got {other:?}"),
        }
    }
}

#[test]
fn second_submission_hits_with_the_recorded_digest() {
    let Some(precomputer) = fixture_precomputer() else {
        return;
    };
    let input = r#"{"key":"p-1","text":"中文文字排版段落","maxWidthPx":144}"#;
    let item = submission_item(input, canonical::KIND_SNAPSHOT);
    let outcomes = precomputer
        .submit_contents(vec![item])
        .expect("first submission computes");
    let SubmissionOutcome::Computed { artifact } = outcomes.first().expect("one outcome") else {
        panic!("first submission computes");
    };
    let expected_sha = digest(artifact);

    // The hash-only lane reports the hit and the digest; no content moves.
    let hashes = vec![digest(
        &canonical::encode_input(
            &parse_json(input).expect("parses"),
            canonical::KIND_SNAPSHOT,
        )
        .expect("encodes"),
    )];
    let markers = precomputer
        .submit_hashes(&hashes)
        .expect("hash submission resolves");
    match markers.first() {
        Some(SubmissionOutcome::Hit { artifact_sha }) => {
            assert_eq!(*artifact_sha, expected_sha);
        }
        other => panic!("expected a hit marker, got {other:?}"),
    }

    // The drain queue holds the same artifact for the host to persist.
    let drained = precomputer.cache_store().drain();
    assert_eq!(drained.len(), 1);
    assert_eq!(drained[0].artifact_sha, expected_sha);
    assert_eq!(drained[0].artifact, artifact.as_slice());
}

#[test]
fn drained_records_prefetch_into_a_fresh_precomputer() {
    let Some(precomputer) = fixture_precomputer() else {
        return;
    };
    let input = r#"{"key":"fc-1","text":"中文合同段落"}"#;
    let item = submission_item(input, canonical::KIND_CONTRACT);
    precomputer
        .submit_contents(vec![item])
        .expect("submission computes");
    let drained = precomputer.cache_store().drain();

    // A fresh precomputer over the same configuration derives the same
    // context, so the drained records prefetch and the hash-only lane hits
    // without any computation.
    let Some(fresh) = fixture_precomputer() else {
        return;
    };
    let accepted = fresh
        .cache_store()
        .prefetch(drained)
        .expect("prefetch accepts the drained records");
    assert_eq!(accepted, 1);
    let hashes = vec![digest(
        &canonical::encode_input(
            &parse_json(input).expect("parses"),
            canonical::KIND_CONTRACT,
        )
        .expect("encodes"),
    )];
    let markers = fresh.submit_hashes(&hashes).expect("hashes resolve");
    assert!(matches!(
        markers.first(),
        Some(SubmissionOutcome::Hit { .. })
    ));
}

#[test]
fn a_mismatched_digest_claim_is_a_named_error() {
    let Some(precomputer) = fixture_precomputer() else {
        return;
    };
    let mut item = submission_item(
        r#"{"key":"p-1","text":"中文","maxWidthPx":144}"#,
        canonical::KIND_SNAPSHOT,
    );
    item.hash = [7; 32];
    let error = precomputer
        .submit_contents(vec![item])
        .expect_err("mismatched digest rejects");
    assert_eq!(error.0, "CanonicalHashMismatch");
}
