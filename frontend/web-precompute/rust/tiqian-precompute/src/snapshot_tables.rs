//! Shared snapshot tables (ADR 0052 `BundleLayering`, station tables): the
//! rows every article manifest of one build references by index. A build
//! absorbs the corpus entry by entry, then freezes the table once; the frozen
//! bytes are content-addressed by the sha of their canonical rendering and
//! every article manifest of that build carries the same sha. Rendering against
//! a frozen table only resolves references: a row the absorb passes missed
//! surfaces as a named error instead of growing the table.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::canonical::digest;
use crate::js_compat::trunc_sat_usize;
use crate::json::Json;
use crate::replay::metric_replay_key;
use crate::schema::{stable_stringify, FONT_REPLAY_REVISION};
use crate::snapshot_manifest::{
    arr_of, compact_metric_row, compact_shape_row, face_descriptor, field, key_string_of,
    table_index, truthy, ReplayStrings, StringSink,
};
use crate::snapshot_table_binary;

fn named(message: impl Into<String>) -> NamedError {
    NamedError(message.into())
}

/// The frozen bytes of one snapshot table plus their content hash. `bytes` is
/// the binary rendering (see `snapshot_table_binary`) hosts serve verbatim;
/// `sha256` is the hex digest of those bytes, the value article manifests pin.
pub struct SnapshotTableFile {
    pub bytes: Vec<u8>,
    pub sha256: String,
}

/// One table set's shared rows. Indexes are append-stable: a restore rebuilds
/// the previous build's rows so an incremental rebuild keeps serving the union
/// table under one URL.
pub struct SnapshotTables {
    frozen_file: Option<SnapshotTableFile>,
    pub(crate) typographies: Vec<Json>,
    typography_indexes: HashMap<String, usize>,
    pub(crate) faces: Vec<Json>,
    face_indexes: HashMap<String, usize>,
    pub(crate) probes: Vec<Json>,
    probe_indexes: HashMap<String, usize>,
    pub(crate) strings: ReplayStrings,
    pub(crate) metrics: Vec<Json>,
    metric_keys: HashMap<String, usize>,
    pub(crate) value_styles: Vec<String>,
    value_style_indexes: HashMap<String, usize>,
    pub(crate) backend_revision: Option<Json>,
    pub(crate) harfbuzz_version: Option<Json>,
}

impl Default for SnapshotTables {
    fn default() -> Self {
        Self::new()
    }
}

impl SnapshotTables {
    pub fn new() -> Self {
        SnapshotTables {
            frozen_file: None,
            typographies: Vec::new(),
            typography_indexes: HashMap::new(),
            faces: Vec::new(),
            face_indexes: HashMap::new(),
            probes: Vec::new(),
            probe_indexes: HashMap::new(),
            strings: ReplayStrings::new(),
            metrics: Vec::new(),
            metric_keys: HashMap::new(),
            value_styles: Vec::new(),
            value_style_indexes: HashMap::new(),
            backend_revision: None,
            harfbuzz_version: None,
        }
    }

    pub fn frozen(&self) -> bool {
        self.frozen_file.is_some()
    }

    /// The content hash finalize produced, if the table is frozen.
    pub fn sha256(&self) -> Option<&str> {
        self.frozen_file.as_ref().map(|file| file.sha256.as_str())
    }

    /// Absorbs the font evidence of one batch of prepared entries. The walk is
    /// the schema-1 compaction walk: same gates, same row encodings, so a
    /// later render against the frozen table resolves every reference.
    pub fn absorb_prepared(&mut self, prepared: &Json) -> Result<usize, NamedError> {
        if self.frozen() {
            return Err(named("SnapshotTablesFrozen"));
        }
        let entries =
            arr_of(Some(prepared)).ok_or_else(|| named("SnapshotFontEvidenceInvalid:undefined"))?;
        let mut absorbed = 0;
        for entry in entries {
            let entry_key = key_string_of(entry);
            let evidence = field(entry, "fontEvidence");
            let faces_list = evidence.and_then(|value| arr_of(field(value, "faces")));
            let evidence_ok =
                evidence.is_some_and(truthy) && faces_list.is_some_and(|list| !list.is_empty());
            if !evidence_ok {
                return Err(named(format!("SnapshotFontEvidenceInvalid:{entry_key}")));
            }
            let (Some(evidence), Some(faces_list)) = (evidence, faces_list) else {
                return Err(named(format!("SnapshotFontEvidenceInvalid:{entry_key}")));
            };
            let replay = field(evidence, "replay");
            let replay_ok = replay.is_some_and(|value| {
                field(value, "revision") == Some(&Json::str(FONT_REPLAY_REVISION))
                    && arr_of(field(value, "shapes")).is_some()
                    && arr_of(field(value, "metrics")).is_some()
            });
            if !replay_ok {
                return Err(named(format!("SnapshotFontReplayInvalid:{entry_key}")));
            }
            let Some(replay) = replay else {
                return Err(named(format!("SnapshotFontReplayInvalid:{entry_key}")));
            };
            let (Some(shapes), Some(metrics)) = (
                arr_of(field(replay, "shapes")),
                arr_of(field(replay, "metrics")),
            ) else {
                return Err(named(format!("SnapshotFontReplayInvalid:{entry_key}")));
            };
            for shape in shapes {
                // The shape row itself stays per-article; only its strings
                // enter the snapshot table. Compacting here is what keeps the
                // render-side string indexes identical.
                compact_shape_row(shape, &mut StringSink::Absorb(&mut self.strings))?;
            }
            for metric in metrics {
                self.absorb_metric(metric)?;
            }
            let backend = field(evidence, "backendRevision").cloned();
            match &self.backend_revision {
                None | Some(Json::Null) => self.backend_revision = backend.clone(),
                _ => {}
            }
            if self.backend_revision != backend {
                return Err(named("SnapshotFontEvidenceVersionConflict"));
            }
            let version = field(evidence, "harfbuzzVersion").cloned();
            match &self.harfbuzz_version {
                None | Some(Json::Null) => self.harfbuzz_version = version.clone(),
                _ => {}
            }
            if self.harfbuzz_version != version {
                return Err(named("SnapshotFontEvidenceVersionConflict"));
            }
            let mut typography_row: Vec<(String, Json)> = Vec::new();
            if let Some(value) = field(entry, "typographySha256") {
                typography_row.push(("sha256".to_string(), value.clone()));
            }
            if let Some(value) = field(entry, "typography") {
                typography_row.push(("value".to_string(), value.clone()));
            }
            table_index(
                &mut self.typographies,
                &mut self.typography_indexes,
                Json::Obj(typography_row),
            );
            for face in faces_list {
                let descriptor = face_descriptor(face, &entry_key)?;
                table_index(&mut self.faces, &mut self.face_indexes, descriptor);
                if let Some(probe) = field(face, "probe") {
                    table_index(&mut self.probes, &mut self.probe_indexes, probe.clone());
                }
            }
            absorbed += 1;
        }
        Ok(absorbed)
    }

    /// Absorbs one canonical metric row: keyed dedup with the same conflict
    /// gate as the per-manifest compaction, the row compacted through the
    /// snapshot string table so its indexes match the render-side rows.
    fn absorb_metric(&mut self, metric: &Json) -> Result<(), NamedError> {
        let key = match field(metric, "key") {
            Some(Json::Str(text)) if !text.is_empty() => text.clone(),
            _ => return Err(named("SnapshotFontReplayMetricsInvalid")),
        };
        let row = compact_metric_row(metric, &mut StringSink::Absorb(&mut self.strings))?;
        if let Some(existing) = self.metric_keys.get(&key) {
            if stable_stringify(&self.metrics[*existing]) != stable_stringify(&row) {
                return Err(named("SnapshotFontReplayMetricsConflict"));
            }
            return Ok(());
        }
        self.metric_keys.insert(key, self.metrics.len());
        self.metrics.push(row);
        Ok(())
    }

    /// Absorbs the render metadata one build shares across articles. Value
    /// styles are content rows: declarations append in first-seen order and
    /// re-absorbing an existing row keeps its index.
    pub fn absorb_metadata(&mut self, metadata: &Json) -> Result<(), NamedError> {
        if self.frozen() {
            return Err(named("SnapshotTablesFrozen"));
        }
        if let Some(Json::Arr(rows)) = field(metadata, "valueStyles") {
            for row in rows {
                let Json::Str(declaration) = row else {
                    return Err(named("SnapshotTableValueStylesInvalid"));
                };
                self.intern_value_style(declaration);
            }
        }
        Ok(())
    }

    /// Interns one value-style declaration, returning its table index. The
    /// render phase mints `tqv-` classes from these indexes, so a frozen table
    /// keeps every index this returns stable.
    pub fn intern_value_style(&mut self, declaration: &str) -> usize {
        if let Some(&index) = self.value_style_indexes.get(declaration) {
            return index;
        }
        let index = self.value_styles.len();
        self.value_styles.push(declaration.to_string());
        self.value_style_indexes
            .insert(declaration.to_string(), index);
        index
    }

    /// One value-style declaration by table index; the assembly phase emits
    /// the initial-style rules from these lookups.
    pub fn value_style_at(&self, index: usize) -> Option<&str> {
        self.value_styles.get(index).map(String::as_str)
    }

    /// Freezes the table and returns its binary bytes plus content hash.
    /// Freezing again returns the same file; absorbs after the freeze fail.
    pub fn finalize(&mut self) -> Result<SnapshotTableFile, NamedError> {
        if let Some(file) = &self.frozen_file {
            return Ok(SnapshotTableFile {
                bytes: file.bytes.clone(),
                sha256: file.sha256.clone(),
            });
        }
        let bytes = snapshot_table_binary::encode(self)?;
        let sha256 = hex_digest(&digest(&bytes));
        let file = SnapshotTableFile { bytes, sha256 };
        self.frozen_file = Some(SnapshotTableFile {
            bytes: file.bytes.clone(),
            sha256: file.sha256.clone(),
        });
        Ok(file)
    }

    /// Preload URLs of the table faces, first-seen order. Hosts own their
    /// preload markup; this list is the table-scoped source for the runtime
    /// wrappers and the binary table's preload region.
    pub(crate) fn derived_font_preload_urls(&self) -> Vec<String> {
        let mut urls: Vec<String> = Vec::new();
        let mut seen: HashMap<String, usize> = HashMap::new();
        for face in &self.faces {
            if let Some(Json::Str(url)) = field(face, "publicUrl") {
                if !seen.contains_key(url) {
                    seen.insert(url.clone(), urls.len());
                    urls.push(url.clone());
                }
            }
        }
        urls
    }

    /// Rebuilds a table from a previous build's frozen binary bytes so an
    /// incremental rebuild appends to the union instead of forking a new table
    /// lineage. The restored table is unfrozen and its indexes match the
    /// decoded row order, so re-freezing reproduces the same bytes.
    pub fn from_binary(bytes: &[u8]) -> Result<Self, NamedError> {
        let decoded = snapshot_table_binary::decode(bytes)?;
        let mut tables = SnapshotTables::new();
        tables.typographies = decoded.typographies;
        tables.faces = decoded.faces;
        tables.probes = decoded.probes;
        tables.metrics = decoded.metrics;
        tables.value_styles = decoded.value_styles;
        for (index, row) in tables.typographies.iter().enumerate() {
            tables
                .typography_indexes
                .insert(stable_stringify(row), index);
        }
        for (index, row) in tables.faces.iter().enumerate() {
            tables.face_indexes.insert(stable_stringify(row), index);
        }
        for (index, row) in tables.probes.iter().enumerate() {
            tables.probe_indexes.insert(stable_stringify(row), index);
        }
        for (index, declaration) in tables.value_styles.iter().enumerate() {
            tables
                .value_style_indexes
                .insert(declaration.clone(), index);
        }
        // Only the leading replay strings feed the string table; the probe
        // aux strings re-intern through the probe walk on the next encode.
        for row in decoded.strings.iter().take(decoded.replay_string_count) {
            tables.strings.intern(row)?;
        }
        if tables.strings.len() != decoded.replay_string_count {
            return Err(named("SnapshotTableRestoreInvalid"));
        }
        tables.backend_revision = decoded.backend_revision;
        tables.harfbuzz_version = decoded.harfbuzz_version;
        tables.rebuild_metric_keys()?;
        Ok(tables)
    }

    /// Restores the metric key index from compact rows: the key of a row is
    /// the replay key of its leading five columns, so the conflict gate keeps
    /// working across restored tables.
    fn rebuild_metric_keys(&mut self) -> Result<(), NamedError> {
        for (index, row) in self.metrics.iter().enumerate() {
            let Json::Arr(values) = row else {
                return Err(named("SnapshotTableRestoreInvalid"));
            };
            if values.len() < 5 {
                return Err(named("SnapshotTableRestoreInvalid"));
            }
            let string_at = |position: usize| -> Result<String, NamedError> {
                let Json::Str(text) = self.string_row(values.get(position))? else {
                    return Err(named("SnapshotTableRestoreInvalid"));
                };
                Ok(text.clone())
            };
            let Json::Num(weight) = &values[1] else {
                return Err(named("SnapshotTableRestoreInvalid"));
            };
            let italic = matches!(&values[2], Json::Num(value) if *value == 1.0);
            let key = metric_replay_key(
                &string_at(0)?,
                *weight,
                italic,
                Some(&string_at(3)?),
                Some(&string_at(4)?),
            );
            self.metric_keys.insert(key, index);
        }
        Ok(())
    }

    /// One string-table row addressed by a wire index inside a metric row.
    fn string_row(&self, value: Option<&Json>) -> Result<&Json, NamedError> {
        let index = match value {
            Some(Json::Num(number)) if number.fract() == 0.0 && *number >= 0.0 => {
                trunc_sat_usize(*number)
            }
            _ => return Err(named("SnapshotTableRestoreInvalid")),
        };
        if index >= self.strings.len() {
            return Err(named("SnapshotTableRestoreInvalid"));
        }
        match self.strings.row_at(index) {
            Some(row) => Ok(row),
            None => Err(named("SnapshotTableRestoreInvalid")),
        }
    }

    /// Frozen-reference resolves for the schema-2 manifest compaction.
    pub(crate) fn typography_ref(&self, entry: &Json) -> Result<usize, NamedError> {
        let mut typography_row: Vec<(String, Json)> = Vec::new();
        if let Some(value) = field(entry, "typographySha256") {
            typography_row.push(("sha256".to_string(), value.clone()));
        }
        if let Some(value) = field(entry, "typography") {
            typography_row.push(("value".to_string(), value.clone()));
        }
        let row = Json::Obj(typography_row);
        match self.typography_indexes.get(&stable_stringify(&row)) {
            Some(index) => Ok(*index),
            None => Err(named("SnapshotTableTypographyMissing")),
        }
    }

    pub(crate) fn face_ref(&self, face: &Json, entry_key: &str) -> Result<usize, NamedError> {
        let descriptor = face_descriptor(face, entry_key)?;
        match self.face_indexes.get(&stable_stringify(&descriptor)) {
            Some(index) => Ok(*index),
            None => Err(named("SnapshotTableFaceMissing")),
        }
    }

    pub(crate) fn probe_ref(&self, probe: &Json) -> Result<usize, NamedError> {
        match self.probe_indexes.get(&stable_stringify(probe)) {
            Some(index) => Ok(*index),
            None => Err(named("SnapshotTableProbeMissing")),
        }
    }

    pub(crate) fn strings(&self) -> &ReplayStrings {
        &self.strings
    }

    /// Render-side metric gate: the row must already live in the table with
    /// this payload. A miss means the absorb passes never saw this entry.
    pub(crate) fn metric_present(&self, metric: &Json) -> Result<(), NamedError> {
        let key = match field(metric, "key") {
            Some(Json::Str(text)) if !text.is_empty() => text.clone(),
            _ => return Err(named("SnapshotFontReplayMetricsInvalid")),
        };
        let row = compact_metric_row(metric, &mut StringSink::Frozen(&self.strings))?;
        match self.metric_keys.get(&key) {
            Some(existing) => {
                if stable_stringify(&self.metrics[*existing]) != stable_stringify(&row) {
                    return Err(named("SnapshotFontReplayMetricsConflict"));
                }
                Ok(())
            }
            None => Err(named("SnapshotTableMetricMissing")),
        }
    }

    /// Render-side version gate against the revisions the table carries. An
    /// empty table slot accepts whatever the entry reports.
    pub(crate) fn versions_accept(&self, evidence: &Json) -> Result<(), NamedError> {
        let backend = field(evidence, "backendRevision");
        if let (Some(expected), Some(actual)) = (&self.backend_revision, backend) {
            if !matches!(expected, Json::Null) && expected != actual {
                return Err(named("SnapshotFontEvidenceVersionConflict"));
            }
        }
        let version = field(evidence, "harfbuzzVersion");
        if let (Some(expected), Some(actual)) = (&self.harfbuzz_version, version) {
            if !matches!(expected, Json::Null) && expected != actual {
                return Err(named("SnapshotFontEvidenceVersionConflict"));
            }
        }
        Ok(())
    }
}

fn hex_digest(bytes: &[u8; 32]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    for byte in bytes {
        let high = char::from(HEX[usize::from(byte / 16)]);
        let low = char::from(HEX[usize::from(byte % 16)]);
        out.push(high);
        out.push(low);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shape(text: &str, advance: f64) -> Json {
        Json::Obj(vec![
            (
                "key".to_string(),
                Json::str(format!(
                    "[\"{text}\",\"serif\",400,false,\"zh\",\"null\",\"{text}\"]"
                )),
            ),
            (
                "result".to_string(),
                Json::Obj(vec![
                    ("faceId".to_string(), Json::str("face-a")),
                    ("fontInstanceId".to_string(), Json::str("instance-1")),
                    ("script".to_string(), Json::str("hani")),
                    ("features".to_string(), Json::Arr(vec![Json::str("kern")])),
                    ("unsafeBreakCount".to_string(), Json::Num(0.0)),
                    ("advanceEm".to_string(), Json::Num(advance)),
                    (
                        "glyphs".to_string(),
                        Json::Arr(vec![Json::Obj(vec![
                            ("id".to_string(), Json::Num(12.0)),
                            ("advanceEm".to_string(), Json::Num(0.5)),
                            ("xEm".to_string(), Json::Num(0.0)),
                            ("yEm".to_string(), Json::Num(0.0)),
                            (
                                "boundsEm".to_string(),
                                Json::Arr(vec![
                                    Json::Num(0.1),
                                    Json::Num(0.2),
                                    Json::Num(0.3),
                                    Json::Num(0.4),
                                ]),
                            ),
                        ])]),
                    ),
                ]),
            ),
        ])
    }

    fn metric(families: &str, advance: f64) -> Json {
        Json::Obj(vec![
            (
                "key".to_string(),
                Json::str(format!("[\"{families}\",400,false,\"null\",\"测\"]")),
            ),
            (
                "valuesEm".to_string(),
                Json::Arr(vec![
                    Json::Num(advance),
                    Json::Num(1.0),
                    Json::Num(2.0),
                    Json::Num(3.0),
                    Json::Num(4.0),
                ]),
            ),
        ])
    }

    fn full_probe() -> Json {
        Json::Obj(vec![
            ("text".to_string(), Json::str("测")),
            ("advancePx".to_string(), Json::Num(18.0)),
            ("fontSizePx".to_string(), Json::Num(18.0)),
            ("fontWeight".to_string(), Json::Num(400.0)),
            ("italic".to_string(), Json::Bool(false)),
            ("script".to_string(), Json::str("hani")),
            ("language".to_string(), Json::str("ZH")),
            ("features".to_string(), Json::Arr(Vec::new())),
        ])
    }

    fn entry(key: &str, text: &str) -> Json {
        Json::Obj(vec![
            ("key".to_string(), Json::str(key)),
            ("sourceSha256".to_string(), Json::str("a".repeat(64))),
            ("typographySha256".to_string(), Json::str("b".repeat(64))),
            (
                "typography".to_string(),
                Json::Obj(vec![("fontSizePx".to_string(), Json::Num(18.0))]),
            ),
            ("maxWidthPx".to_string(), Json::Num(640.0)),
            (
                "fontEvidence".to_string(),
                Json::Obj(vec![
                    ("backendRevision".to_string(), Json::str("backend-1")),
                    ("harfbuzzVersion".to_string(), Json::str("hb-1")),
                    (
                        "faces".to_string(),
                        Json::Arr(vec![Json::Obj(vec![
                            ("publicUrl".to_string(), Json::str("/fonts/main.woff2")),
                            ("family".to_string(), Json::str("serif")),
                            ("coverageText".to_string(), Json::str(text)),
                            ("probe".to_string(), full_probe()),
                        ])]),
                    ),
                    (
                        "replay".to_string(),
                        Json::Obj(vec![
                            ("revision".to_string(), Json::str(FONT_REPLAY_REVISION)),
                            ("shapes".to_string(), Json::Arr(vec![shape(text, 0.5)])),
                            ("metrics".to_string(), Json::Arr(vec![metric("serif", 1.0)])),
                        ]),
                    ),
                ]),
            ),
            (
                "renderArtifactSha256".to_string(),
                Json::str("c".repeat(64)),
            ),
        ])
    }

    #[test]
    fn absorb_dedups_shared_rows_across_entries() {
        let mut tables = SnapshotTables::new();
        let first = Json::Arr(vec![entry("p1", "同文")]);
        let second = Json::Arr(vec![entry("p2", "同文")]);
        assert_eq!(tables.absorb_prepared(&first).expect("absorbs"), 1);
        assert_eq!(tables.absorb_prepared(&second).expect("absorbs"), 1);
        let file = tables.finalize().expect("freezes");
        let decoded = snapshot_table_binary::decode(&file.bytes).expect("decodes");
        // Two entries with identical evidence share every row: one face, one
        // probe, one metric row, and the strings both shapes interned.
        assert_eq!(decoded.faces.len(), 1);
        assert_eq!(decoded.probes.len(), 1);
        assert_eq!(decoded.metrics.len(), 1);
        assert!(decoded.strings.len() > 1);
    }

    #[test]
    fn finalize_freezes_against_further_absorbs() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![entry("p1", "同文")]))
            .expect("absorbs");
        let first = tables.finalize().expect("freezes");
        let again = tables.finalize().expect("refreezes");
        assert_eq!(first.sha256, again.sha256);
        assert_eq!(first.bytes, again.bytes);
        let error = match tables.absorb_prepared(&Json::Arr(vec![entry("p2", "同文")])) {
            Ok(_) => panic!("frozen table rejects absorbs"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTablesFrozen");
    }

    #[test]
    fn value_styles_union_in_first_seen_order() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_metadata(&Json::Obj(vec![(
                "valueStyles".to_string(),
                Json::Arr(vec![Json::str("font-feature-settings:'ss01'")]),
            )]))
            .expect("absorbs");
        // A second absorb with new declarations extends the union; a repeated
        // declaration keeps its index.
        tables
            .absorb_metadata(&Json::Obj(vec![(
                "valueStyles".to_string(),
                Json::Arr(vec![
                    Json::str("font-weight:600"),
                    Json::str("font-feature-settings:'ss01'"),
                ]),
            )]))
            .expect("unions");
        assert_eq!(tables.intern_value_style("font-feature-settings:'ss01'"), 0);
        assert_eq!(tables.intern_value_style("font-weight:600"), 1);
        assert_eq!(tables.value_style_at(1), Some("font-weight:600"));
        let error = match tables.absorb_metadata(&Json::Obj(vec![(
            "valueStyles".to_string(),
            Json::Arr(vec![Json::Num(7.0)]),
        )])) {
            Ok(_) => panic!("non-string row rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableValueStylesInvalid");
    }

    fn object_field_mut<'a>(value: &'a mut Json, name: &str) -> &'a mut Json {
        let Json::Obj(fields) = value else {
            panic!("object field {name}");
        };
        let Some((_, field)) = fields.iter_mut().find(|(key, _)| key == name) else {
            panic!("object field {name}");
        };
        field
    }

    #[test]
    fn conflicting_metric_payloads_surface_the_schema_one_gate() {
        let mut tables = SnapshotTables::new();
        let mut other = Json::Arr(vec![entry("p1", "同文")]);
        // Same metric key, different payload: the row must conflict.
        let Json::Arr(items) = &mut other else {
            panic!("array input");
        };
        let evidence = object_field_mut(&mut items[0], "fontEvidence");
        let replay = object_field_mut(evidence, "replay");
        let metrics = object_field_mut(replay, "metrics");
        let Json::Arr(rows) = metrics else {
            panic!("metrics array");
        };
        rows.push(metric("serif", 2.0));
        let error = match tables.absorb_prepared(&other) {
            Ok(_) => panic!("conflicting metrics rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotFontReplayMetricsConflict");
    }

    #[test]
    fn restore_keeps_rows_and_the_url_stable() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![entry("p1", "同文")]))
            .expect("absorbs");
        let file = tables.finalize().expect("freezes");
        // A restore that appends nothing reproduces the same hash, so the
        // union table keeps serving under one URL across rebuilds.
        let mut restored = SnapshotTables::from_binary(&file.bytes).expect("restores");
        let refile = restored.finalize().expect("refreezes");
        assert_eq!(refile.sha256, file.sha256);
        assert_eq!(refile.bytes, file.bytes);
        // A restore that absorbs a new entry appends rows and changes the
        // hash; the indexes of the old rows stay valid.
        let mut grown = SnapshotTables::from_binary(&file.bytes).expect("restores");
        grown
            .absorb_prepared(&Json::Arr(vec![entry("p3", "异体")]))
            .expect("absorbs after restore");
        let grown_file = grown.finalize().expect("refreezes");
        assert_ne!(grown_file.sha256, file.sha256);
    }

    #[test]
    fn schema_two_compaction_references_the_frozen_table() {
        use crate::snapshot_manifest::{
            compact_snapshot_manifest_with_tables, field as manifest_field,
        };
        let corpus = Json::Arr(vec![entry("p1", "同文"), entry("p2", "同文")]);
        let mut tables = SnapshotTables::new();
        tables.absorb_prepared(&corpus).expect("absorbs");
        tables
            .absorb_metadata(&Json::Obj(vec![(
                "valueStyles".to_string(),
                Json::Arr(vec![Json::str("font-feature-settings:'ss01'")]),
            )]))
            .expect("absorbs metadata");
        let file = tables.finalize().expect("freezes");
        let metadata = Json::Obj(vec![
            (
                "valueStyles".to_string(),
                Json::Arr(vec![Json::str("font-feature-settings:'ss01'")]),
            ),
            (
                "renderFontFamilies".to_string(),
                Json::Arr(vec![Json::str("serif")]),
            ),
        ]);
        let manifest =
            compact_snapshot_manifest_with_tables(&corpus, &metadata, &tables).expect("compacts");
        // The manifest pins the table hash and declares schema 2.
        let tables_field = manifest_field(&manifest, "tables").expect("tables field");
        assert!(
            matches!(manifest_field(tables_field, "snapshot"), Some(Json::Str(sha)) if *sha == file.sha256)
        );
        assert!(matches!(
            manifest_field(&manifest, "schema"),
            Some(Json::Num(value)) if *value == 2.0
        ));
        // Table-resident content left the manifest: no table arrays, no value
        // styles, no metric rows.
        for absent in ["typographies", "fontEvidence", "valueStyles"] {
            assert!(
                manifest_field(&manifest, absent).is_none(),
                "{absent} left the manifest"
            );
        }
        let replay = manifest_field(&manifest, "fontReplay").expect("replay");
        assert!(manifest_field(replay, "strings").is_none());
        assert!(manifest_field(replay, "metrics").is_none());
        let Some(Json::Arr(shapes)) = manifest_field(replay, "shapes") else {
            panic!("shape rows");
        };
        // Two entries share one deduped shape row; its string columns index
        // the table's strings.
        assert_eq!(shapes.len(), 1);
        let Json::Arr(row) = &shapes[0] else {
            panic!("shape row");
        };
        let Json::Num(first_string) = &row[0] else {
            panic!("string index");
        };
        assert!(
            *first_string >= 0.0
                && first_string.fract() == 0.0
                && trunc_sat_usize(*first_string) < tables.strings().len()
        );
        // Entries reference the table by index and carry no coverage text.
        let Some(Json::Arr(entries)) = manifest_field(&manifest, "entries") else {
            panic!("entries");
        };
        assert_eq!(entries.len(), 2);
        let evidence = manifest_field(&entries[0], "fontFaceEvidence").expect("evidence");
        let Some(Json::Arr(faces)) = Some(evidence) else {
            panic!("face evidence rows");
        };
        assert!(matches!(
            manifest_field(&faces[0], "faceRef"),
            Some(Json::Num(value)) if *value == 0.0
        ));
        assert!(matches!(
            manifest_field(&faces[0], "probeRef"),
            Some(Json::Num(value)) if *value == 0.0
        ));
        assert!(manifest_field(&faces[0], "coverageText").is_none());
    }

    #[test]
    fn schema_two_compaction_names_the_entry_that_missed_the_table() {
        use crate::snapshot_manifest::compact_snapshot_manifest_with_tables;
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![entry("p1", "同文")]))
            .expect("absorbs");
        tables.finalize().expect("freezes");
        let unabsorbed = Json::Arr(vec![entry("p9", "未吸收")]);
        let error = match compact_snapshot_manifest_with_tables(
            &unabsorbed,
            &Json::Obj(Vec::new()),
            &tables,
        ) {
            Ok(_) => panic!("unabsorbed entry rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableStringMissing:p9");
    }

    #[test]
    fn schema_two_compaction_requires_finalized_tables() {
        use crate::snapshot_manifest::compact_snapshot_manifest_with_tables;
        let tables = SnapshotTables::new();
        let error = match compact_snapshot_manifest_with_tables(
            &Json::Arr(Vec::new()),
            &Json::Obj(Vec::new()),
            &tables,
        ) {
            Ok(_) => panic!("unfinalized table rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTablesNotFinalized");
    }

    #[test]
    fn frozen_reference_resolves_return_absorbed_indexes() {
        let mut tables = SnapshotTables::new();
        tables
            .absorb_prepared(&Json::Arr(vec![entry("p1", "同文")]))
            .expect("absorbs");
        let probe = full_probe();
        assert_eq!(tables.probe_ref(&probe).expect("resolves"), 0);
        let foreign = Json::Obj(vec![("advancePx".to_string(), Json::Num(19.0))]);
        let error = match tables.probe_ref(&foreign) {
            Ok(_) => panic!("unabsorbed probe rejected"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotTableProbeMissing");
    }
}
