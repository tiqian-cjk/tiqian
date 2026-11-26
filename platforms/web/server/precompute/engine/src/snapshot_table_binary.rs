// The snapshot-table binary form of ADR 0052 BundleLayering. The byte
// contract -- magic, header counts, region order, delta coding, the metric
// sort, pool dedup and the f64 bit patterns -- is single-sourced in Haxe
// and arrives generated in the tiqian-protocol crate; this file is
// only the platform shell around it: the Json lowering of SnapshotTables
// into the generated input shape, the canonical-JSON text serialization the
// shell owns per the Stage1-P2 boundary ruling, and the materialization of
// the decoded stored form back into the Json rows SnapshotTables restores.
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

use tiqian::NamedError;
use tiqian_protocol::org::tiqian::protocol::snapshot_table_binary::SnapshotTableBinary;
use tiqian_protocol::org::tiqian::protocol::table_data::TableData;
use tiqian_protocol::org::tiqian::protocol::table_input::TableInput;
use tiqian_protocol::org::tiqian::protocol::table_metric_row::TableMetricRow;
use tiqian_protocol::org::tiqian::protocol::table_probe::TableProbe;
use tiqian_protocol::runtime::u_string::UString;

use crate::js_compat::trunc_sat_usize;
use crate::json::{parse_json, Json};
use crate::schema::stable_stringify;
use crate::snapshot_manifest::{arr_of, field};
use crate::snapshot_tables::SnapshotTables;

fn invalid() -> NamedError {
    NamedError("SnapshotTablesInvalid".to_string())
}

fn number_of(value: &Json) -> Result<f64, NamedError> {
    let Json::Num(number) = value else {
        return Err(invalid());
    };
    Ok(*number)
}

fn finite_number_of(value: &Json) -> Result<f64, NamedError> {
    let number = number_of(value)?;
    if !number.is_finite() {
        return Err(invalid());
    }
    Ok(number)
}

fn string_of(value: &Json) -> Result<&str, NamedError> {
    let Json::Str(text) = value else {
        return Err(invalid());
    };
    Ok(text)
}

fn u32_index_of(value: &Json) -> Result<u32, NamedError> {
    let number = number_of(value)?;
    if number.fract() != 0.0 || number < 0.0 || number >= 4294967296.0 {
        return Err(invalid());
    }
    Ok(u32::try_from(trunc_sat_usize(number)).map_err(|_| invalid())?)
}

// ---------------------------------------------------------------------------
// Encoding: Json lowering into the generated input shape
// ---------------------------------------------------------------------------

/// Encodes the state of one table set; finalize is the sanctioned caller.
/// The generated encoder interns, sorts and pools; the replay strings keep
/// their indexes, so a duplicate among them would no longer round-trip its
/// own indexes and fails here (the old encoder's invariant).
pub(crate) fn encode(tables: &SnapshotTables) -> Result<Vec<u8>, NamedError> {
    let mut replay_strings: Vec<String> = Vec::new();
    let mut seen_replay: HashSet<String> = HashSet::new();
    for row in tables.strings.rows() {
            let text = string_of(&row)?.to_string();
        if !seen_replay.insert(text.clone()) {
            return Err(invalid());
        }
        replay_strings.push(text.to_string());
    }

    let all_strings: Vec<String> = tables
        .strings
        .rows()
        .into_iter()
        .map(|row| string_of(&row).map(|text| text.to_string()))
        .collect::<Result<Vec<String>, NamedError>>()?;
    let mut metrics: Vec<Rc<RefCell<TableMetricRow>>> = Vec::with_capacity(tables.metrics.len());
    for row in &tables.metrics {
        let Json::Arr(values) = row else {
            return Err(invalid());
        };
        if values.len() != 10 {
            return Err(invalid());
        }
        let italic_number = finite_number_of(&values[2])?;
        if italic_number != 0.0 && italic_number != 1.0 {
            return Err(invalid());
        }
        // Restored rows carry resolved string refs; map them back through the
        // string table so the generated intern pass reassigns the same refs.
        let families_ref = u32_index_of(&values[0])?;
        let role_ref = u32_index_of(&values[3])?;
        let face_selection_ref = u32_index_of(&values[4])?;
        let mut values_em: Vec<Option<f64>> = Vec::with_capacity(5);
        for value in &values[5..10] {
            values_em.push(match value {
                Json::Null => None,
                Json::Num(_) => Some(finite_number_of(value)?),
                _ => return Err(invalid()),
            });
        }
        // The generated rows carry Haxe strings; the string-table lookups
        // produce `String`, so each ref converts through `From<&str>`.
        let to_ustring = |text: &String| UString::from(text.as_str());
        metrics.push(TableMetricRow::new(
            &to_ustring(
                all_strings
                    .get(usize::try_from(families_ref).map_err(|_| invalid())?)
                    .ok_or_else(invalid)?,
            ),
            finite_number_of(&values[1])?,
            italic_number == 1.0,
            &to_ustring(
                all_strings
                    .get(usize::try_from(role_ref).map_err(|_| invalid())?)
                    .ok_or_else(invalid)?,
            ),
            &to_ustring(
                all_strings
                    .get(usize::try_from(face_selection_ref).map_err(|_| invalid())?)
                    .ok_or_else(invalid)?,
            ),
            values_em,
        ));
    }

    let mut probes: Vec<Rc<RefCell<TableProbe>>> = Vec::with_capacity(tables.probes.len());
    for probe in &tables.probes {
        let mut features: Vec<String> = Vec::new();
        for feature in arr_of(Some(field(probe, "features").ok_or_else(invalid)?)).ok_or_else(invalid)? {
            features.push(string_of(feature)?.to_string());
        }
        probes.push(TableProbe::new(
            &UString::from(string_of(field(probe, "text").ok_or_else(invalid)?)?),
            finite_number_of(field(probe, "advancePx").ok_or_else(invalid)?)?,
            finite_number_of(field(probe, "fontSizePx").ok_or_else(invalid)?)?,
            finite_number_of(field(probe, "fontWeight").ok_or_else(invalid)?)?,
            match field(probe, "italic").ok_or_else(invalid)? {
                Json::Bool(value) => *value,
                _ => return Err(invalid()),
            },
            &UString::from(string_of(field(probe, "script").ok_or_else(invalid)?)?),
            &UString::from(string_of(field(probe, "language").ok_or_else(invalid)?)?),
            features.iter().map(|f| UString::from(f.as_str())).collect(),
        ));
    }

    let face_texts: Vec<String> = tables
        .faces
        .iter()
        .map(|face| stable_stringify(face))
        .collect();
    let typography_texts: Vec<String> = tables
        .typographies
        .iter()
        .map(|row| stable_stringify(row))
        .collect();
    let font_preloads = tables.derived_font_preload_urls();

    let mut revisions: Vec<(String, Json)> = Vec::new();
    if let Some(value) = &tables.backend_revision {
        revisions.push(("backendRevision".to_string(), value.clone()));
    }
    if let Some(value) = &tables.harfbuzz_version {
        revisions.push(("harfbuzzVersion".to_string(), value.clone()));
    }
    let revision_text = stable_stringify(&Json::Obj(revisions));

    // The generated encoder interns Haxe strings; the lane rows are
    // `String`, so every list converts at the single encode boundary.
    let to_ustring = |text: &String| UString::from(text.as_str());
    Ok(SnapshotTableBinary::snapshot_table_binary_encode(
        TableInput::new(
            replay_strings.iter().map(to_ustring).collect(),
            metrics,
            probes,
            face_texts.iter().map(to_ustring).collect(),
            typography_texts.iter().map(to_ustring).collect(),
            // Value styles left the shared table with the shared-layer
            // cutover: the column stays on the wire and is always empty.
            Vec::new(),
            font_preloads.iter().map(to_ustring).collect(),
            &UString::from(revision_text.as_str()),
        ),
    ))
}

// ---------------------------------------------------------------------------
// Decoding: materialize the generated stored form into restorable rows
// ---------------------------------------------------------------------------

/// The decoded rows of one binary table in the shape SnapshotTables
/// restores.
pub(crate) struct DecodedTable {
    pub(crate) replay_string_count: usize,
    pub(crate) typographies: Vec<Json>,
    pub(crate) faces: Vec<Json>,
    pub(crate) probes: Vec<Json>,
    pub(crate) strings: Vec<Json>,
    pub(crate) metrics: Vec<Json>,
    pub(crate) backend_revision: Option<Json>,
    pub(crate) harfbuzz_version: Option<Json>,
}

/// Decodes a binary table into restorable rows. The generated decoder
/// validates every region boundary and the stored shapes; this shell
/// parses the JSON text regions and rebuilds the canonical row shapes.
pub(crate) fn decode(bytes: &[u8]) -> Result<DecodedTable, NamedError> {
    let data = TableData::new();
    let issue = SnapshotTableBinary::snapshot_table_binary_decode_into(bytes, Rc::clone(&data));
    if !issue.is_empty() {
        return Err(invalid());
    }
    let data = data.borrow();

    let strings: Vec<Json> = data
        .strings
        .iter()
        .map(|text| Json::str(text.to_utf8_lossy()))
        .collect();
    let string_at = |reference: u32| -> Result<Json, NamedError> {
        Ok(
            strings
                .get(usize::try_from(reference).map_err(|_| invalid())?)
                .ok_or_else(invalid)?
                .clone()
        )
    };
    let mut metrics: Vec<Json> = Vec::with_capacity(data.metric_rows.len());
    for row in &data.metric_rows {
        let row = row.borrow();
        let pool = data
            .value_pool
            .get(usize::try_from(row.value_pool_ref).map_err(|_| invalid())?)
            .ok_or_else(invalid)?;
        let pool = pool.borrow();
        let mut values: Vec<Json> = Vec::with_capacity(10);
        values.push(Json::Num(f64::from(row.families_ref)));
        values.push(Json::Num(row.weight));
        values.push(Json::Num(f64::from(row.italic)));
        values.push(Json::Num(f64::from(row.role_ref)));
        values.push(Json::Num(f64::from(row.face_selection_ref)));
        for slot in 0..5 {
            match pool.values[slot] {
                None => values.push(Json::Null),
                Some(value) => values.push(Json::Num(value)),
            }
        }
        metrics.push(Json::Arr(values));
    }

    let mut probes: Vec<Json> = Vec::with_capacity(data.probe_text_refs.len());
    for index in 0..data.probe_text_refs.len() {
        let advance_ref = usize::try_from(data.probe_advance_refs[index]).map_err(|_| invalid())?;
        let style_ref = usize::try_from(data.probe_style_refs[index]).map_err(|_| invalid())?;
        let features_ref = usize::try_from(data.probe_feature_refs[index]).map_err(|_| invalid())?;
        let advance = *data.advance_pool.get(advance_ref).ok_or_else(invalid)?;
        let font_size = *data.style_font_size.get(style_ref).ok_or_else(invalid)?;
        let weight = *data.style_font_weight.get(style_ref).ok_or_else(invalid)?;
        let italic = *data.style_italic.get(style_ref).ok_or_else(invalid)? == 1;
        let script = string_at(*data.style_script_refs.get(style_ref).ok_or_else(invalid)?)?;
        let language = string_at(*data.style_language_refs.get(style_ref).ok_or_else(invalid)?)?;
        let feature_refs = data.features_pool.get(features_ref).ok_or_else(invalid)?;
        let mut features: Vec<Json> = Vec::with_capacity(feature_refs.len());
        for reference in feature_refs {
            features.push(string_at(*reference)?);
        }
        probes.push(Json::Obj(vec![
            ("text".to_string(), string_at(data.probe_text_refs[index])?),
            ("advancePx".to_string(), Json::Num(advance)),
            ("fontSizePx".to_string(), Json::Num(font_size)),
            ("fontWeight".to_string(), Json::Num(weight)),
            ("italic".to_string(), Json::Bool(italic)),
            ("script".to_string(), script),
            ("language".to_string(), language),
            ("features".to_string(), Json::Arr(features)),
        ]));
    }

    // The generated decoder stores JSON text regions as Haxe strings; the
    // lane parses them from the UTF-8 form the generated decode produced.
    let mut typographies = Vec::new();
    for text in &data.typography_texts {
        let text = text.to_utf8_lossy();
        typographies.push(parse_json(&text).map_err(|_| invalid())?);
    }
    let mut faces = Vec::new();
    for text in &data.face_texts {
        let text = text.to_utf8_lossy();
        faces.push(parse_json(&text).map_err(|_| invalid())?);
    }

    let revision_text = data.revision_text.to_utf8_lossy();
    let revisions = parse_json(&revision_text).map_err(|_| invalid())?;

    Ok(DecodedTable {
        replay_string_count: usize::try_from(data.replay_string_count).map_err(|_| invalid())?,
        typographies,
        faces,
        probes,
        strings,
        metrics,
        backend_revision: field(&revisions, "backendRevision").cloned(),
        harfbuzz_version: field(&revisions, "harfbuzzVersion").cloned(),
    })
}