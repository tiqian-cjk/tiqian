//! Snapshot manifest transport of `snapshot-manifest.js` (ADR 0050). Shared
//! tables deduplicate typography values, face descriptors, and shaping
//! replay rows; the compact encoding interns replay strings.
//!
//! Values cross this module as wire `Json`. Damage that js reports with a raw
//! `TypeError` (a null face descriptor, a non-object entry) surfaces with the
//! nearest named issue instead. Fields js would leave `undefined` stay absent
//! from the wire objects; version evidence compares structurally.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::js_compat::{js_int_to_number, trunc_sat_usize};
use crate::json::{parse_json, Json};
use crate::replay::{metric_replay_key, shape_replay_key};
use crate::schema::{stable_stringify, FONT_REPLAY_REVISION, FONT_REPLAY_TRANSPORT};
use crate::snapshot_source::js_number_value;
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

fn is_safe_integer(value: f64) -> bool {
    const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;
    value.fract() == 0.0 && value.abs() <= MAX_SAFE_INTEGER
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
/// and probe evidence.
/// js nullish: absent or `null`.
fn nullish(value: &Option<Json>) -> bool {
    matches!(value, None | Some(Json::Null))
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

/// `compactFontReplay`: intern strings and flatten replay rows.
/// The replay-string intern table. Per-manifest compaction owns a local one;
/// station tables own a process-lifetime one. Both flatten rows through
/// [`ReplayStrings::intern`] so their string indexes cannot diverge.
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
/// through `sink`. Shared by the per-manifest encoding and the snapshot tables.
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

pub fn compact_font_replay(shapes: &[Json], metrics: &[Json]) -> Result<Json, NamedError> {
    let mut strings = ReplayStrings::new();
    let mut compact_shapes = Vec::with_capacity(shapes.len());
    for item in shapes {
        compact_shapes.push(compact_shape_row(
            item,
            &mut StringSink::Absorb(&mut strings),
        )?);
    }
    let mut compact_metrics = Vec::with_capacity(metrics.len());
    for item in metrics {
        compact_metrics.push(compact_metric_row(
            item,
            &mut StringSink::Absorb(&mut strings),
        )?);
    }
    Ok(Json::Obj(vec![
        ("revision".to_string(), Json::str(FONT_REPLAY_REVISION)),
        ("encoding".to_string(), Json::str(FONT_REPLAY_TRANSPORT)),
        ("strings".to_string(), Json::Arr(strings.rows())),
        ("shapes".to_string(), Json::Arr(compact_shapes)),
        ("metrics".to_string(), Json::Arr(compact_metrics)),
    ]))
}

/// `tableReference`: a table index must be a safe integer inside the table.
fn table_reference<'a>(
    table: &'a [Json],
    index: Option<&Json>,
    issue: &str,
) -> Result<&'a Json, NamedError> {
    let Json::Num(value) = index.cloned().unwrap_or(Json::Null) else {
        return Err(named(issue));
    };
    let length =
        i64::try_from(table.len()).map_err(|_| named("SnapshotManifestIndexConversion"))?;
    if !is_safe_integer(value) || value < 0.0 || value >= js_int_to_number(length) {
        return Err(named(issue));
    }
    // The checks above gate the value to a safe integer inside the table.
    Ok(&table[trunc_sat_usize(value)])
}

fn string_at<'a>(strings: &'a [Json], index: &Json) -> Result<&'a str, NamedError> {
    let referenced = table_reference(
        strings,
        Some(index),
        "SnapshotFontReplayStringReferenceInvalid",
    )?;
    let Json::Str(text) = referenced else {
        return Err(named("SnapshotFontReplayStringReferenceInvalid"));
    };
    Ok(text)
}

fn flag_row_value(value: &Json) -> Option<bool> {
    match value {
        Json::Num(inner) if *inner == 0.0 => Some(false),
        Json::Num(inner) if *inner == 1.0 => Some(true),
        _ => None,
    }
}

/// `expandFontReplay`: rebuild canonical replay rows from the compact
/// transport. A replay without an encoding is already canonical and passes
/// through unchanged.
pub fn expand_font_replay(replay: &Json) -> Result<Json, NamedError> {
    let revision_ok = field(replay, "revision") == Some(&Json::str(FONT_REPLAY_REVISION));
    let (Some(shapes), Some(metrics)) = (
        arr_of(field(replay, "shapes")),
        arr_of(field(replay, "metrics")),
    ) else {
        return Err(named("SnapshotFontReplayInvalid"));
    };
    if !revision_ok {
        return Err(named("SnapshotFontReplayInvalid"));
    }
    let encoding = field(replay, "encoding");
    if encoding.is_none() || encoding == Some(&Json::Null) {
        return Ok(replay.clone());
    }
    if !matches!(encoding, Some(&Json::Str(ref value)) if value == FONT_REPLAY_TRANSPORT) {
        return Err(named("SnapshotFontReplayTransportInvalid"));
    }
    let Some(strings) = arr_of(field(replay, "strings")) else {
        return Err(named("SnapshotFontReplayTransportInvalid"));
    };
    if strings.iter().any(|value| !matches!(value, Json::Str(_))) {
        return Err(named("SnapshotFontReplayTransportInvalid"));
    }

    let mut expanded_shapes = Vec::with_capacity(shapes.len());
    for row in shapes {
        let Json::Arr(row) = row else {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        };
        if row.len() != 14 || !matches!(row[10], Json::Arr(_)) || flag_row_value(&row[3]).is_none()
        {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        }
        let glyph_rows_ok = match &row[13] {
            Json::Arr(values) => values.len() % 8 == 0,
            _ => false,
        };
        if !glyph_rows_ok {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        }
        let Json::Arr(glyph_values) = &row[13] else {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        };
        let mut glyphs = Vec::with_capacity(glyph_values.len() / 8);
        for glyph in glyph_values.chunks(8) {
            let bounds = glyph[4..8].to_vec();
            let all_null = bounds.iter().all(|value| *value == Json::Null);
            if !all_null && bounds.iter().any(|value| *value == Json::Null) {
                return Err(named("SnapshotFontReplayGlyphBoundsInvalid"));
            }
            glyphs.push(Json::Obj(vec![
                ("id".to_string(), glyph[0].clone()),
                ("advanceEm".to_string(), glyph[1].clone()),
                ("xEm".to_string(), glyph[2].clone()),
                ("yEm".to_string(), glyph[3].clone()),
                (
                    "boundsEm".to_string(),
                    if all_null {
                        Json::Null
                    } else {
                        Json::Arr(bounds)
                    },
                ),
            ]));
        }
        let Json::Arr(features) = &row[10] else {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        };
        let display_text = string_at(strings, &row[0])?;
        let serialized_families = string_at(strings, &row[1])?;
        let Some(italic) = flag_row_value(&row[3]) else {
            return Err(named("SnapshotFontReplayShapeTransportInvalid"));
        };
        let locale = string_at(strings, &row[4])?;
        let role = string_at(strings, &row[5])?;
        let source_text = string_at(strings, &row[6])?;
        let key = shape_replay_key(
            display_text,
            serialized_families,
            js_number_value(&row[2]),
            italic,
            locale,
            Some(role),
            source_text,
        );
        expanded_shapes.push(Json::Obj(vec![
            ("key".to_string(), Json::str(key)),
            (
                "result".to_string(),
                Json::Obj(vec![
                    (
                        "faceId".to_string(),
                        Json::str(string_at(strings, &row[7])?),
                    ),
                    (
                        "fontInstanceId".to_string(),
                        Json::str(string_at(strings, &row[8])?),
                    ),
                    (
                        "script".to_string(),
                        Json::str(string_at(strings, &row[9])?),
                    ),
                    (
                        "features".to_string(),
                        Json::Arr(
                            features
                                .iter()
                                .map(|index| Ok(Json::str(string_at(strings, index)?)))
                                .collect::<Result<Vec<_>, _>>()?,
                        ),
                    ),
                    ("unsafeBreakCount".to_string(), row[11].clone()),
                    ("advanceEm".to_string(), row[12].clone()),
                    ("glyphs".to_string(), Json::Arr(glyphs)),
                ]),
            ),
        ]));
    }

    let mut expanded_metrics = Vec::with_capacity(metrics.len());
    for row in metrics {
        let Json::Arr(row) = row else {
            return Err(named("SnapshotFontReplayMetricsTransportInvalid"));
        };
        if row.len() != 10 || flag_row_value(&row[2]).is_none() {
            return Err(named("SnapshotFontReplayMetricsTransportInvalid"));
        }
        let serialized_families = string_at(strings, &row[0])?;
        let Some(italic) = flag_row_value(&row[2]) else {
            return Err(named("SnapshotFontReplayMetricsTransportInvalid"));
        };
        let role = string_at(strings, &row[3])?;
        let face_selection_text = string_at(strings, &row[4])?;
        let key = metric_replay_key(
            serialized_families,
            js_number_value(&row[1]),
            italic,
            Some(role),
            Some(face_selection_text),
        );
        expanded_metrics.push(Json::Obj(vec![
            ("key".to_string(), Json::str(key)),
            ("valuesEm".to_string(), Json::Arr(row[5..10].to_vec())),
        ]));
    }

    Ok(Json::Obj(vec![
        (
            "revision".to_string(),
            field(replay, "revision").cloned().unwrap_or(Json::Null),
        ),
        ("shapes".to_string(), Json::Arr(expanded_shapes)),
        ("metrics".to_string(), Json::Arr(expanded_metrics)),
    ]))
}

/// `compactSnapshotManifest`: shared tables plus per-paragraph references.
pub fn compact_snapshot_manifest(entries: &Json, metadata: &Json) -> Result<Json, NamedError> {
    let entry_list =
        arr_of(Some(entries)).ok_or_else(|| named("SnapshotFontEvidenceInvalid:undefined"))?;
    let mut typographies: Vec<Json> = Vec::new();
    let mut typography_indexes: HashMap<String, usize> = HashMap::new();
    let mut faces: Vec<Json> = Vec::new();
    let mut face_indexes: HashMap<String, usize> = HashMap::new();
    let mut backend_revision: Option<Json> = Some(Json::Null);
    let mut harfbuzz_version: Option<Json> = Some(Json::Null);
    let mut replay_shapes: Vec<Json> = Vec::new();
    let mut replay_shape_indexes: HashMap<String, usize> = HashMap::new();
    let mut replay_metrics: Vec<Json> = Vec::new();
    let mut replay_metric_indexes: HashMap<String, usize> = HashMap::new();

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
            replay_table_index(
                &mut replay_shapes,
                &mut replay_shape_indexes,
                shape,
                "SnapshotFontReplayShapeConflict",
            )?;
        }
        for metric in metrics {
            replay_table_index(
                &mut replay_metrics,
                &mut replay_metric_indexes,
                metric,
                "SnapshotFontReplayMetricsConflict",
            )?;
        }
        // `??=` keeps the slot writable until real evidence arrives, so a
        // missing version on early entries never conflicts with later ones.
        let backend = field(evidence, "backendRevision").cloned();
        if nullish(&backend_revision) {
            backend_revision = backend.clone();
        }
        if backend_revision != backend {
            return Err(named("SnapshotFontEvidenceVersionConflict"));
        }
        let version = field(evidence, "harfbuzzVersion").cloned();
        if nullish(&harfbuzz_version) {
            harfbuzz_version = version.clone();
        }
        if harfbuzz_version != version {
            return Err(named("SnapshotFontEvidenceVersionConflict"));
        }
        // js drops `undefined` fields from the table row; explicit nulls stay.
        let mut typography_row: Vec<(String, Json)> = Vec::new();
        if let Some(value) = field(entry, "typographySha256") {
            typography_row.push(("sha256".to_string(), value.clone()));
        }
        if let Some(value) = field(entry, "typography") {
            typography_row.push(("value".to_string(), value.clone()));
        }
        let typography_ref = table_index(
            &mut typographies,
            &mut typography_indexes,
            Json::Obj(typography_row),
        );
        let mut font_face_evidence = Vec::with_capacity(faces_list.len());
        for face in faces_list {
            let descriptor = face_descriptor(face, &entry_key)?;
            let face_ref = table_index(&mut faces, &mut face_indexes, descriptor);
            let mut row = vec![("faceRef".to_string(), index_number(face_ref)?)];
            if let Some(value) = field(face, "coverageText") {
                row.push(("coverageText".to_string(), value.clone()));
            }
            if let Some(value) = field(face, "probe") {
                row.push(("probe".to_string(), value.clone()));
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

    let mut output: Vec<(String, Json)> = fields_of(metadata)
        .map(|fields| fields.to_vec())
        .unwrap_or_default();
    output.push(("typographies".to_string(), Json::Arr(typographies)));
    // Version slots no entry ever supplied stay undefined and drop from the
    // wire. An empty entry list keeps the initial null slot.
    let mut font_evidence: Vec<(String, Json)> = Vec::new();
    if let Some(value) = backend_revision {
        font_evidence.push(("backendRevision".to_string(), value));
    }
    if let Some(value) = harfbuzz_version {
        font_evidence.push(("harfbuzzVersion".to_string(), value));
    }
    font_evidence.push(("faces".to_string(), Json::Arr(faces)));
    output.push(("fontEvidence".to_string(), Json::Obj(font_evidence)));
    output.push((
        "fontReplay".to_string(),
        compact_font_replay(&replay_shapes, &replay_metrics)?,
    ));
    output.push(("entries".to_string(), Json::Arr(compact_entries)));
    Ok(Json::Obj(output))
}

/// `compactSnapshotManifest` against finalized snapshot tables (ADR 0052
/// schema 2, 「篇级 manifest」): entries resolve typography, face, probe, and
/// replay-string references into the table by index, shape rows stay
/// per-article, metric rows live only in the table, and the manifest pins the
/// table's content hash. The value styles live in the table and drop out of
/// the metadata spread. Entry validation mirrors the schema-1 walk; the two
/// must gate identically because a build may emit either form.
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

fn expanded_entry(
    entry: &Json,
    typographies: &[Json],
    descriptors: &[Json],
    manifest_evidence: &Json,
) -> Result<Json, NamedError> {
    let typography = table_reference(
        typographies,
        field(entry, "typographyRef"),
        "SnapshotTypographyReferenceInvalid",
    )?;
    let sha256_string = matches!(field(typography, "sha256"), Some(Json::Str(_)));
    let value_truthy = field(typography, "value").is_some_and(truthy);
    if !sha256_string || !value_truthy {
        return Err(named("SnapshotTypographyTableInvalid"));
    }
    let evidence_list = arr_of(field(entry, "fontFaceEvidence"))
        .filter(|list| !list.is_empty())
        .ok_or_else(|| named("SnapshotFontEvidenceReferenceInvalid"))?;
    let mut faces = Vec::with_capacity(evidence_list.len());
    for evidence in evidence_list {
        let descriptor = table_reference(
            descriptors,
            field(evidence, "faceRef"),
            "SnapshotFontFaceReferenceInvalid",
        )?;
        let mut face = match descriptor {
            Json::Obj(fields) => fields.to_vec(),
            _ => Vec::new(),
        };
        if let Some(value) = field(evidence, "coverageText") {
            face.push(("coverageText".to_string(), value.clone()));
        }
        if let Some(value) = field(evidence, "probe") {
            face.push(("probe".to_string(), value.clone()));
        }
        faces.push(Json::Obj(face));
    }
    let mut expanded = Vec::new();
    if let Some(value) = field(entry, "key") {
        expanded.push(("key".to_string(), value.clone()));
    }
    if let Some(value) = field(entry, "sourceSha256") {
        expanded.push(("sourceSha256".to_string(), value.clone()));
    }
    if let Some(Json::Str(artifact)) = field(entry, "sourceArtifactSha256") {
        expanded.push((
            "sourceArtifactSha256".to_string(),
            Json::str(artifact.clone()),
        ));
    }
    if field(entry, "semantic") == Some(&Json::Bool(true)) {
        expanded.push(("semantic".to_string(), Json::Bool(true)));
    }
    expanded.push((
        "typographySha256".to_string(),
        field(typography, "sha256").cloned().unwrap_or(Json::Null),
    ));
    expanded.push((
        "typography".to_string(),
        field(typography, "value").cloned().unwrap_or(Json::Null),
    ));
    if let Some(value) = field(entry, "maxWidthPx") {
        expanded.push(("maxWidthPx".to_string(), value.clone()));
    }
    // Version evidence copies through only when the manifest carries it.
    let mut evidence_obj: Vec<(String, Json)> = Vec::new();
    if let Some(value) = field(manifest_evidence, "backendRevision") {
        evidence_obj.push(("backendRevision".to_string(), value.clone()));
    }
    if let Some(value) = field(manifest_evidence, "harfbuzzVersion") {
        evidence_obj.push(("harfbuzzVersion".to_string(), value.clone()));
    }
    evidence_obj.push(("faces".to_string(), Json::Arr(faces)));
    expanded.push(("fontEvidence".to_string(), Json::Obj(evidence_obj)));
    if let Some(value) = field(entry, "renderArtifactSha256") {
        expanded.push(("renderArtifactSha256".to_string(), value.clone()));
    }
    Ok(Json::Obj(expanded))
}

fn expand_entries_list(
    entries: &[Json],
    typographies: &[Json],
    descriptors: &[Json],
    manifest_evidence: &Json,
) -> Result<Vec<Json>, NamedError> {
    entries
        .iter()
        .map(|entry| expanded_entry(entry, typographies, descriptors, manifest_evidence))
        .collect()
}

/// `expandSnapshotManifest`: rebuild the canonical runtime manifest from the
/// compact transport, keeping every metadata field in place.
pub fn expand_snapshot_manifest(manifest: &Json) -> Result<Json, NamedError> {
    let manifest_fields = fields_of(manifest).ok_or_else(|| named("SnapshotManifestInvalid"))?;
    let typographies = arr_of(field(manifest, "typographies"))
        .ok_or_else(|| named("SnapshotManifestTablesInvalid"))?;
    let font_evidence = field(manifest, "fontEvidence").and_then(fields_of);
    let descriptors = font_evidence
        .and_then(|fields| {
            fields
                .iter()
                .find(|(name, _)| name == "faces")
                .map(|(_, value)| value)
        })
        .and_then(|faces| arr_of(Some(faces)));
    let entries =
        arr_of(field(manifest, "entries")).ok_or_else(|| named("SnapshotManifestTablesInvalid"))?;
    if font_evidence.is_none() || descriptors.is_none() {
        return Err(named("SnapshotManifestTablesInvalid"));
    }
    // The check above passed, so both lookups succeed; the error arms keep
    // the conversions total.
    let font_evidence =
        field(manifest, "fontEvidence").ok_or_else(|| named("SnapshotManifestTablesInvalid"))?;
    let Some(descriptors) = descriptors else {
        return Err(named("SnapshotManifestTablesInvalid"));
    };

    let font_replay = match field(manifest, "fontReplay") {
        None | Some(Json::Null) => None,
        Some(replay) => Some(expand_font_replay(replay)?),
    };
    let expanded_entries = expand_entries_list(entries, typographies, descriptors, font_evidence)?;
    let font_contract_entries = match field(manifest, "fontContractEntries") {
        Some(Json::Arr(list)) => Some(expand_entries_list(
            list,
            typographies,
            descriptors,
            font_evidence,
        )?),
        _ => None,
    };

    // The spread keeps each existing key in place and only replaces values.
    let mut output: Vec<(String, Json)> = manifest_fields.to_vec();
    let replace = |output: &mut Vec<(String, Json)>, key: &str, value: Option<Json>| {
        if let Some(value) = value {
            match output.iter_mut().find(|(name, _)| name == key) {
                Some(slot) => slot.1 = value,
                None => output.push((key.to_string(), value)),
            }
        }
    };
    replace(&mut output, "fontReplay", font_replay);
    replace(&mut output, "entries", Some(Json::Arr(expanded_entries)));
    replace(
        &mut output,
        "fontContractEntries",
        font_contract_entries.map(Json::Arr),
    );
    Ok(Json::Obj(output))
}

/// `parseSnapshotManifest`: parse the wire text and expand.
pub fn parse_snapshot_manifest(text: &str) -> Result<Json, NamedError> {
    let parsed =
        parse_json(text).map_err(|error| named(format!("InvalidSnapshotManifestJson:{error}")))?;
    expand_snapshot_manifest(&parsed)
}
