//! Hash-first submission over the binary bridge (ADR 0052). Hosts submit
//! content hashes; hits resolve against the layered cache and never move
//! content, misses come back as a need-content marker, and the resend carries
//! the canonical bytes plus the logical key. The resend recomputes the digest
//! and compares before trusting it, so a mismatched claim is a named error
//! and never a wrong cache identity.

use std::sync::Arc;

use tiqian::NamedError;

use crate::cache::{CacheRecord, CacheTier};
use crate::canonical::{self, decode_input, digest, store_key};
use crate::json::Json;
use crate::precomputer::Precomputer;
use crate::precomputer::PrepareInput;
use crate::renderer::{global_pool, wait_job, QueuePosition};

/// One submission outcome per item.
#[derive(Debug)]
pub enum SubmissionOutcome {
    /// The cache holds the entry: the marker plus the artifact digest. The
    /// host compares the digest with its local copy and uses it without any
    /// bytes crossing.
    Hit { artifact_sha: [u8; 32] },
    /// This call computed the entry (or attached to a concurrent twin that
    /// did); the artifact bytes come back for the host to persist.
    Computed { artifact: Vec<u8> },
    /// The cache has no entry and no content arrived: the host resends with
    /// content or lets the sync egress compute later.
    NeedContent,
}

/// One content-carrying resend item.
pub struct SubmissionItem {
    pub hash: [u8; 32],
    pub logical_key: String,
    pub canonical: Vec<u8>,
}

impl Precomputer {
    /// The context fingerprint of this precomputer, opaque to hosts.
    pub fn cache_context(&self) -> &[u8; 32] {
        self.cache.context()
    }

    /// The layered store behind this precomputer; the bridge layer reads the
    /// drain queue and the prefetch entry through it.
    pub fn cache_store(&self) -> &crate::cache::LayeredCacheStore {
        &self.cache
    }

    /// Hash-only submission: every item resolves to a hit marker with the
    /// artifact digest, or a need-content marker when the store has nothing.
    /// The tier never appears: the kind byte sits inside the canonical form,
    /// so a snapshot and a contract hash differently by construction.
    pub fn submit_hashes(&self, hashes: &[[u8; 32]]) -> Result<Vec<SubmissionOutcome>, NamedError> {
        let keys: Vec<[u8; 32]> = hashes
            .iter()
            .map(|hash| store_key(self.cache.context(), hash))
            .collect();
        let records = self.cache.lookup(&keys);
        Ok(records
            .into_iter()
            .map(|record| match record {
                Some(record) => SubmissionOutcome::Hit {
                    artifact_sha: record.artifact_sha,
                },
                None => SubmissionOutcome::NeedContent,
            })
            .collect())
    }

    /// Content-carrying submission, waiting egress: items enqueue on the
    /// batch renderer, the call parks on each job, and outcomes arrive in
    /// input order. Each item's kind byte sits inside its canonical form, so
    /// snapshot and contract items share one call. Hits return the stored
    /// artifact bytes because a caller that resends content has no local
    /// copy. The reported error is the one of the lowest failing index, the
    /// sequential loop's `?` order, matching the low-level batch lanes.
    pub fn submit_contents(
        self: &Arc<Self>,
        items: Vec<SubmissionItem>,
    ) -> Result<Vec<SubmissionOutcome>, NamedError> {
        let planned = self.plan_submissions(&items, QueuePosition::Front)?;
        let mut outcomes: Vec<SubmissionOutcome> = Vec::with_capacity(items.len());
        let mut first_error: Option<(usize, NamedError)> = None;
        for (index, planned) in planned.into_iter().enumerate() {
            let outcome = match planned {
                PlannedSubmission::Hit(record) => SubmissionOutcome::Computed {
                    artifact: record.artifact.to_vec(),
                },
                PlannedSubmission::Compute(job) => match wait_job(&job) {
                    Ok(()) => {
                        // A completed job wrote through before signaling, so
                        // the store holds the entry unless eviction raced;
                        // an evicted race reads as need-content, the host
                        // resubmits.
                        match self
                            .cache
                            .lookup(&[store_key(self.cache.context(), &items[index].hash)])
                            .into_iter()
                            .next()
                            .flatten()
                        {
                            Some(record) => SubmissionOutcome::Computed {
                                artifact: record.artifact.to_vec(),
                            },
                            None => SubmissionOutcome::NeedContent,
                        }
                    }
                    Err(error) => {
                        if first_error.is_none() {
                            first_error = Some((index, error));
                        }
                        SubmissionOutcome::NeedContent
                    }
                },
            };
            outcomes.push(outcome);
        }
        if let Some((_, error)) = first_error {
            return Err(error);
        }
        Ok(outcomes)
    }

    /// Content-carrying submission, background egress: items enqueue at the
    /// back and the call returns once they are queued; computation advances
    /// while the host walks its render loop. Failures surface when the same
    /// content arrives through a waiting submission.
    pub fn prefill_contents(
        self: &Arc<Self>,
        items: Vec<SubmissionItem>,
    ) -> Result<usize, NamedError> {
        let planned = self.plan_submissions(&items, QueuePosition::Back)?;
        let mut queued = 0;
        for planned in planned {
            if let PlannedSubmission::Compute(_) = planned {
                queued += 1;
            }
        }
        Ok(queued)
    }

    /// Shared planning: verify every digest, serve memory hits directly and
    /// queue one renderer job per miss. The waiting and background egresses
    /// differ only in queue position and whether the caller parks.
    fn plan_submissions(
        self: &Arc<Self>,
        items: &[SubmissionItem],
        position: QueuePosition,
    ) -> Result<Vec<PlannedSubmission>, NamedError> {
        // Digests and kinds verify before anything computes: the claimed
        // hash is the cache identity, so a mismatched claim is a host bug,
        // not data.
        for item in items {
            if digest(&item.canonical) != item.hash {
                return Err(NamedError("CanonicalHashMismatch".to_string()));
            }
            canonical::kind_of(&item.canonical)?;
        }
        let keys: Vec<[u8; 32]> = items
            .iter()
            .map(|item| store_key(self.cache.context(), &item.hash))
            .collect();
        let hits = self.cache.lookup(&keys);
        let mut planned = Vec::with_capacity(items.len());
        for (index, item) in items.iter().enumerate() {
            let key = keys[index];
            if let Some(record) = &hits[index] {
                planned.push(PlannedSubmission::Hit(record.clone()));
                continue;
            }
            let precomputer = self.clone();
            let hash = item.hash;
            let logical_key = item.logical_key.clone();
            let canonical = item.canonical.clone();
            let kind = canonical::kind_of(&canonical).unwrap_or(canonical::KIND_SNAPSHOT);
            let job = global_pool().enqueue(
                Some((self.cache_owner, key)),
                position,
                Box::new(move || {
                    let decoded = decode_input(&canonical, kind)?;
                    let wired = with_key(decoded.value, &logical_key);
                    let input = PrepareInput::from_json(&wired);
                    let entry = match tier_from_kind(kind) {
                        Some(CacheTier::Snapshot) => precomputer.prepare_paragraph(&input)?,
                        Some(CacheTier::FontContract) => {
                            precomputer.prepare_font_contract(&input)?
                        }
                        None => return Err(NamedError("InvalidCanonicalKind".to_string())),
                    };
                    let artifact = entry.render().into_bytes();
                    let artifact_sha = digest(&artifact);
                    precomputer.cache.store(CacheRecord {
                        tier: tier_from_kind(kind).unwrap_or(CacheTier::Snapshot),
                        key,
                        content_hash: hash,
                        artifact,
                        artifact_sha,
                    })?;
                    Ok(())
                }),
            )?;
            planned.push(PlannedSubmission::Compute(job));
        }
        Ok(planned)
    }
}

fn tier_from_kind(kind: u8) -> Option<CacheTier> {
    CacheTier::from_code(kind)
}

enum PlannedSubmission {
    Hit(Arc<CacheRecord>),
    Compute(Arc<crate::renderer::RenderJob>),
}

/// Rebuilds the wire input with the logical key in place: the canonical form
/// carries content only, the key belongs to the caller.
fn with_key(mut value: Json, logical_key: &str) -> Json {
    if let Json::Obj(fields) = &mut value {
        fields.push(("key".to_string(), Json::Str(logical_key.to_string())));
    }
    value
}

/// The precomputer's submissions carry no key in their canonical bytes; the
/// decoded wire form regains it through [`with_key`]. This test pins the
/// round shape.
#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::member;

    #[test]
    fn with_key_adds_the_member_the_reader_expects() {
        let decoded = decode_input(
            &canonical::encode_input(
                &crate::json::parse_json(r#"{"text":"正文"}"#).expect("parses"),
                canonical::KIND_SNAPSHOT,
            )
            .expect("encodes"),
            canonical::KIND_SNAPSHOT,
        )
        .expect("decodes");
        let wired = with_key(decoded.value, "p-1");
        let input = PrepareInput::from_json(&wired);
        assert_eq!(input.key_string(), "p-1");
        assert_eq!(input.text_string(), "正文");
        assert!(member(&wired, "semantics").is_some());
    }
}
