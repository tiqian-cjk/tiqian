//! Snapshot manifest transport of `snapshot-manifest.js` (ADR 0050). Shared
//! tables deduplicate typography values, face descriptors, and shaping
//! replay rows; the compact encoding interns replay strings. Every manifest
//! is schema 2 (ADR 0052): references resolve into a finalized station table
//! and the manifest pins the table's content hash.
//!
//! Values cross this module as wire `Json`. Damage that js reports with a raw
//! `TypeError` (a null face descriptor, a non-object entry) surfaces with the
//! nearest named issue instead. Fields js would leave `undefined` stay absent
//! from the wire objects; version evidence compares structurally.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::js_compat::js_int_to_number;
use crate::json::{parse_json, Json};
use crate::schema::{stable_stringify, FONT_REPLAY_REVISION, FONT_REPLAY_TRANSPORT};
use crate::snapshot_tables::SnapshotTables;

pub(crate) fn field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields.iter().find(|(name, _)| name == key).map(|(_, v)| v),
        _ => None,
    }
}

fn fields_of(value: &Json) -> Option<&[(String, Json)]> {
    match value {
        Json::Obj(fields) => Some(fields),
        _ => None,
    }
}

pub(crate) fn arr_of(value: Option<&Json>) -> Option<&[Json]> {
    match value {
        Some(Json::Arr(items)) => Some(items),
        _ => None,
    }
}

fn named(message: impl Into<String>) -> NamedError {
    NamedError(message.into())
}

/// js truthiness over a wire value.
pub(crate) fn truthy(value: &Json) -> bool {
    match value {
        Json::Null | Json::Bool(false) => false,
        Json::Num(inner) => *inner != 0.0,
        Json::Str(inner) => !inner.is_empty(),
        Json::Arr(_) | Json::Obj(_) => true,
        Json::Bool(true) => true,
    }
}

/// A table index on the wire. The index addresses a table this module built,
/// so the conversion fails only when the table outgrows i64.
pub(crate) fn index_number(index: usize) -> Result<Json, NamedError> {
    let number = i64::try_from(index).map_err(|_| named("SnapshotManifestIndexConversion"))?;
    Ok(Json::Num(js_int_to_number(number)))
}

pub(crate) fn key_string_of(value: &Json) -> String {
    match field(value, "key") {
        Some(Json::Str(text)) => text.clone(),
        Some(Json::Null) => "null".to_string(),
        None => "undefined".to_string(),
        Some(other) => crate::snapshot_source::js_string_value(other),
    }
}

/// `faceDescriptor`: the shared face identity drops per-paragraph coverage
/// and probe evidence. Any non-null value without entries spreads to an empty
/// descriptor, mirroring `Object.entries`.
pub(crate) fn face_descriptor(face: &Json, entry_key: &str) -> Result<Json, NamedError> {
    let filtered: Vec<(String, Json)> = match face {
        Json::Obj(fields) => fields
            .iter()
            .filter(|(name, _)| name != "coverageText" && name != "probe")
            .cloned()
            .collect(),
        Json::Null => return Err(named(format!("SnapshotFontEvidenceInvalid:{entry_key}"))),
        _ => Vec::new(),
    };
    Ok(Json::Obj(filtered))
}

/// `tableIndex`: deduplicate by the stable rendering of the whole value.
pub(crate) fn table_index(
    table: &mut Vec<Json>,
    indexes: &mut HashMap<String, usize>,
    value: Json,
) -> usize {
    let signature = stable_stringify(&value);
    if let Some(existing) = indexes.get(&signature) {
        return *existing;
    }
    let index = table.len();
    table.push(value);
    indexes.insert(signature, index);
    index
}

/// `replayTableIndex`: replay rows deduplicate by key; a repeated key with a
/// different payload is a conflict.
pub(crate) fn replay_table_index(
    table: &mut Vec<Json>,
    indexes: &mut HashMap<String, usize>,
    value: &Json,
    conflict_issue: &str,
) -> Result<usize, NamedError> {
    let key = match field(value, "key") {
        Some(Json::Str(text)) if !text.is_empty() => text.clone(),
        _ => return Err(named(conflict_issue.replace("Conflict", "Invalid"))),
    };
    if let Some(existing) = indexes.get(&key) {
        if stable_stringify(&table[*existing]) != stable_stringify(value) {
            return Err(named(conflict_issue));
        }
        return Ok(*existing);
    }
    let index = table.len();
    table.push(value.clone());
    indexes.insert(key, index);
    Ok(index)
}

/// `replayKeyParts`: the key is a JSON array of a fixed length.
fn replay_key_parts(
    key: &str,
    expected_length: usize,
    issue: &str,
) -> Result<Vec<Json>, NamedError> {
    let parsed = parse_json(key).map_err(|_| named(issue))?;
    match parsed {
        Json::Arr(parts) if parts.len() == expected_length => Ok(parts),
        _ => Err(named(issue)),
    }
}

/// The replay-string intern table. Station tables own a process-lifetime one
/// and flatten rows through [`ReplayStrings::intern`].
pub(crate) struct ReplayStrings {
    strings: Vec<Json>,
    indexes: HashMap<String, usize>,
}

impl ReplayStrings {
    pub(crate) fn new() -> Self {
        ReplayStrings {
            strings: Vec::new(),
            indexes: HashMap::new(),
        }
    }

    /// `stringRef`: intern one wire string, returning its row index.
    pub(crate) fn intern(&mut self, value: &Json) -> Result<usize, NamedError> {
        let Json::Str(text) = value else {
            return Err(named("SnapshotFontReplayStringInvalid"));
        };
        if let Some(existing) = self.indexes.get(text) {
            return Ok(*existing);
        }
        let index = self.strings.len();
        self.strings.push(value.clone());
        self.indexes.insert(text.clone(), index);
        Ok(index)
    }

    /// Frozen-table lookup for rendering against finalized station tables: the
    /// row must already have been interned by an absorb pass.
    pub(crate) fn find(&self, value: &Json) -> Result<usize, NamedError> {
        let Json::Str(text) = value else {
            return Err(named("SnapshotFontReplayStringInvalid"));
        };
        match self.indexes.get(text) {
            Some(existing) => Ok(*existing),
            None => Err(named("SnapshotTableStringMissing")),
        }
    }

    pub(crate) fn rows(&self) -> Vec<Json> {
        self.strings.clone()
    }

    pub(crate) fn len(&self) -> usize {
        self.strings.len()
    }

    /// One row by index, for reconstruction over serialized rows.
    pub(crate) fn row_at(&self, index: usize) -> Option<&Json> {
        self.strings.get(index)
    }
}

/// String-resolution mode of one row compaction. Absorb interns new strings
/// into a mutable table; a render against finalized snapshot tables resolves
/// every string without growing the table. Both modes build identical rows
/// because intern is idempotent over the same values.
pub(crate) enum StringSink<'a> {
    Absorb(&'a mut ReplayStrings),
    Frozen(&'a ReplayStrings),
}

impl StringSink<'_> {
    fn resolve(&mut self, value: &Json) -> Result<usize, NamedError> {
        match self {
            StringSink::Absorb(table) => table.intern(value),
            StringSink::Frozen(table) => table.find(value),
        }
    }
}

/// Flattens one canonical shape into its compact row, resolving every string
/// through `sink`, shared by absorb and render against the snapshot tables.
pub(crate) fn compact_shape_row(item: &Json, sink: &mut StringSink) -> Result<Json, NamedError> {
    let result = match field(item, "result") {
        Some(result) if truthy(result) => result,
        _ => return Err(named("SnapshotFontReplayShapeInvalid")),
    };
    let Some(Json::Str(key)) = field(item, "key") else {
        return Err(named("SnapshotFontReplayShapeInvalid"));
    };
    let (Some(Json::Arr(features)), Some(Json::Arr(glyphs))) =
        (field(result, "features"), field(result, "glyphs"))
    else {
        return Err(named("SnapshotFontReplayShapeInvalid"));
    };
    let parts = replay_key_parts(key, 7, "SnapshotFontReplayShapeKeyInvalid")?;
    let mut glyphs_flat = Vec::with_capacity(glyphs.len() * 8);
    for glyph in glyphs {
        let glyph_fields: &[(String, Json)] = match glyph {
            Json::Obj(fields) => fields,
            Json::Arr(_) => &[],
            _ => return Err(named("SnapshotFontReplayGlyphInvalid")),
        };
        let lookup = |name: &str| {
            glyph_fields
                .iter()
                .find(|(key, _)| key == name)
                .map(|(_, value)| value)
        };
        let bounds: Vec<Json> = match lookup("boundsEm") {
            None | Some(Json::Null) => vec![Json::Null; 4],
            Some(Json::Arr(values)) if values.len() == 4 => values.clone(),
            _ => return Err(named("SnapshotFontReplayGlyphBoundsInvalid")),
        };
        for name in ["id", "advanceEm", "xEm", "yEm"] {
            glyphs_flat.push(lookup(name).cloned().unwrap_or(Json::Null));
        }
        glyphs_flat.extend(bounds);
    }
    let part = |index: usize| parts.get(index).cloned().unwrap_or(Json::Null);
    let mut row = vec![
        index_number(sink.resolve(&part(0))?)?,
        index_number(sink.resolve(&part(1))?)?,
        part(2),
        Json::Num(f64::from(u8::from(truthy(&part(3))))),
        index_number(sink.resolve(&part(4))?)?,
        index_number(sink.resolve(&part(5))?)?,
        index_number(sink.resolve(&part(6))?)?,
        index_number(sink.resolve(field(result, "faceId").unwrap_or(&Json::Null))?)?,
        index_number(sink.resolve(field(result, "fontInstanceId").unwrap_or(&Json::Null))?)?,
        index_number(sink.resolve(field(result, "script").unwrap_or(&Json::Null))?)?,
    ];
    row.push(Json::Arr(
        features
            .iter()
            .map(|feature| sink.resolve(feature).and_then(index_number))
            .collect::<Result<Vec<_>, _>>()?,
    ));
    row.push(
        field(result, "unsafeBreakCount")
            .cloned()
            .unwrap_or(Json::Null),
    );
    row.push(field(result, "advanceEm").cloned().unwrap_or(Json::Null));
    row.push(Json::Arr(glyphs_flat));
    Ok(Json::Arr(row))
}

/// Flattens one canonical metric into its compact row, resolving every string
/// through `sink`.
pub(crate) fn compact_metric_row(item: &Json, sink: &mut StringSink) -> Result<Json, NamedError> {
    let Some(Json::Str(key)) = field(item, "key") else {
        return Err(named("SnapshotFontReplayMetricsInvalid"));
    };
    let values = arr_of(field(item, "valuesEm"))
        .filter(|values| values.len() == 5)
        .ok_or_else(|| named("SnapshotFontReplayMetricsInvalid"))?;
    let parts = replay_key_parts(key, 5, "SnapshotFontReplayMetricsKeyInvalid")?;
    let part = |index: usize| parts.get(index).cloned().unwrap_or(Json::Null);
    let mut row = vec![
        index_number(sink.resolve(&part(0))?)?,
        part(1),
        Json::Num(f64::from(u8::from(truthy(&part(2))))),
        index_number(sink.resolve(&part(3))?)?,
        index_number(sink.resolve(&part(4))?)?,
    ];
    row.extend(values.iter().cloned());
    Ok(Json::Arr(row))
}

/// `compactSnapshotManifest` against finalized snapshot tables (ADR 0052
/// schema 2, 「篇级 manifest」): entries resolve typography, face, probe, and
/// replay-string references into the table by index, shape rows stay
/// per-article, metric rows live only in the table, and the manifest pins the
/// table's content hash. The value styles live in the table and drop out of
/// the metadata spread.
pub fn compact_snapshot_manifest_with_tables(
    entries: &Json,
    metadata: &Json,
    tables: &SnapshotTables,
) -> Result<Json, NamedError> {
    let Some(table_sha) = tables.sha256() else {
        return Err(named("SnapshotTablesNotFinalized"));
    };
    let entry_list =
        arr_of(Some(entries)).ok_or_else(|| named("SnapshotFontEvidenceInvalid:undefined"))?;
    let mut output: Vec<(String, Json)> = fields_of(metadata)
        .map(|fields| {
            fields
                .iter()
                .filter(|(name, _)| name != "valueStyles" && name != "valueStylesSha256")
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    output.push(("schema".to_string(), Json::Num(2.0)));
    output.push((
        "tables".to_string(),
        Json::Obj(vec![("snapshot".to_string(), Json::str(table_sha))]),
    ));

    let mut replay_shapes: Vec<Json> = Vec::new();
    let mut replay_shape_indexes: HashMap<String, usize> = HashMap::new();
    let mut compact_shapes: Vec<Json> = Vec::new();
    let mut compact_entries = Vec::with_capacity(entry_list.len());
    for entry in entry_list {
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
            let fresh_key = match field(shape, "key") {
                Some(Json::Str(text)) if !text.is_empty() => {
                    !replay_shape_indexes.contains_key(text)
                }
                _ => false,
            };
            replay_table_index(
                &mut replay_shapes,
                &mut replay_shape_indexes,
                shape,
                "SnapshotFontReplayShapeConflict",
            )?;
            if fresh_key {
                let row = compact_shape_row(shape, &mut StringSink::Frozen(tables.strings()))
                    .map_err(|error| annotate_missing(error, &entry_key))?;
                compact_shapes.push(row);
            }
        }
        for metric in metrics {
            tables
                .metric_present(metric)
                .map_err(|error| annotate_missing(error, &entry_key))?;
        }
        tables.versions_accept(evidence)?;
        let typography_ref = tables
            .typography_ref(entry)
            .map_err(|error| annotate_missing(error, &entry_key))?;
        let mut font_face_evidence = Vec::with_capacity(faces_list.len());
        for face in faces_list {
            let face_ref = tables
                .face_ref(face, &entry_key)
                .map_err(|error| annotate_missing(error, &entry_key))?;
            let mut row = vec![("faceRef".to_string(), index_number(face_ref)?)];
            if let Some(probe) = field(face, "probe") {
                let probe_ref = tables
                    .probe_ref(probe)
                    .map_err(|error| annotate_missing(error, &entry_key))?;
                row.push(("probeRef".to_string(), index_number(probe_ref)?));
            }
            font_face_evidence.push(Json::Obj(row));
        }
        let mut compact = Vec::new();
        if let Some(value) = field(entry, "key") {
            compact.push(("key".to_string(), value.clone()));
        }
        if let Some(value) = field(entry, "sourceSha256") {
            compact.push(("sourceSha256".to_string(), value.clone()));
        }
        if let Some(Json::Str(artifact)) = field(entry, "sourceArtifactSha256") {
            compact.push((
                "sourceArtifactSha256".to_string(),
                Json::str(artifact.clone()),
            ));
        }
        if matches!(field(entry, "semantics"), Some(Json::Arr(list)) if !list.is_empty()) {
            compact.push(("semantic".to_string(), Json::Bool(true)));
        }
        compact.push(("typographyRef".to_string(), index_number(typography_ref)?));
        if let Some(value) = field(entry, "maxWidthPx") {
            compact.push(("maxWidthPx".to_string(), value.clone()));
        }
        compact.push((
            "fontFaceEvidence".to_string(),
            Json::Arr(font_face_evidence),
        ));
        if let Some(value) = field(entry, "renderArtifactSha256") {
            compact.push(("renderArtifactSha256".to_string(), value.clone()));
        }
        compact_entries.push(Json::Obj(compact));
    }

    output.push((
        "fontReplay".to_string(),
        Json::Obj(vec![
            ("revision".to_string(), Json::str(FONT_REPLAY_REVISION)),
            ("encoding".to_string(), Json::str(FONT_REPLAY_TRANSPORT)),
            ("shapes".to_string(), Json::Arr(compact_shapes)),
        ]),
    ));
    output.push(("entries".to_string(), Json::Arr(compact_entries)));
    Ok(Json::Obj(output))
}

/// Appends the entry key to a table-missing error so a multi-article build
/// names the article that outgrew its absorb pass.
pub(crate) fn annotate_missing(error: NamedError, entry_key: &str) -> NamedError {
    if error.0.starts_with("SnapshotTable") && error.0.ends_with("Missing") {
        return NamedError(format!("{}:{entry_key}", error.0));
    }
    error
}
