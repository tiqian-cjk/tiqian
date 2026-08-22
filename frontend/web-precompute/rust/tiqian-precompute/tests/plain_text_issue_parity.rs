//! Plain-text issue parity against the frozen js oracle dump over every
//! Unicode code point (ADR 0050 amendment `PrecomputeInRust`).
//!
//! The js implementation was removed with the legacy cutover, so this test
//! compares the run-length dump of `snapshot_plain_text_issue` against
//! `tests/plain-text-issue-golden.json`, recorded when the lane still ran the
//! js `snapshotPlainTextIssue` over each code point as a single-character
//! text. Regenerate with `TIQIAN_UPDATE_GOLDEN=1 cargo test --test
//! plain_text_issue_parity` after reviewing the diff; a mismatch means the
//! generated Unicode tables drifted from the recorded data.

use std::path::PathBuf;

use tiqian_precompute::json::{parse_json, Json};
use tiqian_precompute::normalize::snapshot_plain_text_issue;

const MAX_CODE_POINT: u32 = 0x10ffff;

/// Range bounds stay f64 because the oracle dump is read back as JSON
/// numbers; comparing in the read type avoids a float to integer cast.
struct IssueRange {
    start: f64,
    end: f64,
    issue: Option<String>,
}

fn oracle_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/plain-text-issue-golden.json")
}

/// The Rust dump over the same single-character corpus.
fn native_ranges() -> Vec<IssueRange> {
    let mut ranges: Vec<IssueRange> = Vec::new();
    let mut current = issue_at(0);
    let mut start = 0u32;
    for point in 1..=MAX_CODE_POINT {
        let issue = issue_at(point);
        if issue != current {
            ranges.push(IssueRange {
                start: f64::from(start),
                end: f64::from(point - 1),
                issue: current,
            });
            start = point;
            current = issue;
        }
    }
    ranges.push(IssueRange {
        start: f64::from(start),
        end: f64::from(MAX_CODE_POINT),
        issue: current,
    });
    ranges
}

fn issue_at(point: u32) -> Option<String> {
    if let Some(ch) = char::from_u32(point) {
        snapshot_plain_text_issue(&ch.to_string()).map(str::to_string)
    } else {
        // Surrogate halves are not Rust chars; the js lane sees lone
        // surrogates and classifies them as unassigned, which the script gate
        // reports. Keep the native dump aligned by classifying them the same
        // way the tables do: surrogates are not Common, not Han.
        Some("UnsupportedSnapshotScript".to_string())
    }
}

fn oracle_ranges(json: &Json) -> Vec<IssueRange> {
    let Json::Arr(entries) = json else {
        panic!("oracle dump is not an array");
    };
    entries
        .iter()
        .map(|entry| {
            let Json::Obj(fields) = entry else {
                panic!("oracle entry is not an object");
            };
            let mut range = IssueRange {
                start: 0.0,
                end: 0.0,
                issue: None,
            };
            for (key, value) in fields {
                match (key.as_str(), value) {
                    ("start", Json::Num(value)) => range.start = *value,
                    ("end", Json::Num(value)) => range.end = *value,
                    ("issue", Json::Str(value)) => range.issue = Some(value.clone()),
                    ("issue", Json::Null) => range.issue = None,
                    _ => panic!("unexpected oracle field {key}"),
                }
            }
            range
        })
        .collect()
}

#[test]
fn plain_text_issue_matches_the_frozen_oracle_dump_over_all_code_points() {
    let native = native_ranges();
    if std::env::var("TIQIAN_UPDATE_GOLDEN").is_ok_and(|value| value == "1") {
        let dump = Json::Arr(
            native
                .iter()
                .map(|range| {
                    Json::Obj(vec![
                        ("start".to_string(), Json::Num(range.start)),
                        ("end".to_string(), Json::Num(range.end)),
                        (
                            "issue".to_string(),
                            match &range.issue {
                                Some(issue) => Json::str(issue.clone()),
                                None => Json::Null,
                            },
                        ),
                    ])
                })
                .collect(),
        );
        std::fs::write(oracle_path(), format!("{}\n", dump.render())).expect("golden writes");
        return;
    }
    let oracle = match std::fs::read_to_string(oracle_path()) {
        Ok(oracle) => oracle,
        Err(error) => panic!(
            "plain-text-issue golden unreadable at {}: {error}; record it with \
             TIQIAN_UPDATE_GOLDEN=1 cargo test --test plain_text_issue_parity",
            oracle_path().display()
        ),
    };
    let expected = oracle_ranges(&parse_json(&oracle).expect("oracle json parses"));
    assert_eq!(native.len(), expected.len(), "range count differs");
    for (index, (left, right)) in native.iter().zip(&expected).enumerate() {
        assert_eq!(left.start, right.start, "range {index} start differs");
        assert_eq!(left.end, right.end, "range {index} end differs");
        assert_eq!(left.issue, right.issue, "range {index} issue differs");
    }
}
