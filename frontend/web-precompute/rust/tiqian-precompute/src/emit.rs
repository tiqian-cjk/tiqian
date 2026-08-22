//! JSON emitters shared by the parity harness and the Neon boundary: session
//! results in the exact byte shape the JS oracle emits, built with the
//! `JSON.stringify` semantics of `json.rs`.

use tiqian::NamedError;

use crate::js_compat::js_int_to_number;
use crate::json::Json;
use crate::session::{
    FaceInfo, FaceUsage, FontEvidence, MetricReplay, ShapeReplay, FONT_REPLAY_REVISION,
};
use crate::shaping::ShapeRecordResult;

/// One entry of `session.faces` / evidence `faces`.
pub fn face_info_json(face: &FaceInfo) -> Json {
    Json::Obj(vec![
        ("family".into(), Json::str(face.family.clone())),
        ("style".into(), Json::str(face.style)),
        (
            "weight".into(),
            Json::Arr(vec![Json::Num(face.weight[0]), Json::Num(face.weight[1])]),
        ),
        ("unicodeRange".into(), Json::str(face.unicode_range.clone())),
        ("publicUrl".into(), Json::str(face.public_url.clone())),
        ("sourceSha256".into(), Json::str(face.source_sha256.clone())),
        ("sfntSha256".into(), Json::str(face.sfnt_sha256.clone())),
        ("faceIndex".into(), Json::Num(face.face_index)),
        (
            "sourceOrder".into(),
            Json::Num(f64::from(face.source_order)),
        ),
        (
            "axisTags".into(),
            Json::Arr(
                face.axis_tags
                    .iter()
                    .map(|tag| Json::str(tag.clone()))
                    .collect(),
            ),
        ),
        (
            "localNames".into(),
            Json::Arr(
                face.local_names
                    .iter()
                    .map(|name| Json::str(name.clone()))
                    .collect(),
            ),
        ),
    ])
}

/// A `shape(...)` result in oracle field order. The count conversion fails
/// only when a shape produced more unsafe breaks than i64 holds.
pub fn shape_result_json(result: &ShapeRecordResult) -> Result<Json, NamedError> {
    Ok(Json::Obj(vec![
        ("faceId".into(), Json::str(result.face_id.clone())),
        (
            "fontInstanceId".into(),
            Json::str(result.font_instance_id.clone()),
        ),
        ("script".into(), Json::str(result.script.clone())),
        (
            "features".into(),
            Json::Arr(
                result
                    .features
                    .iter()
                    .map(|f| Json::str(f.clone()))
                    .collect(),
            ),
        ),
        (
            "probeFeatures".into(),
            Json::Arr(
                result
                    .probe_features
                    .iter()
                    .map(|f| Json::str(f.clone()))
                    .collect(),
            ),
        ),
        (
            "unsafeBreakCount".into(),
            Json::Num(js_int_to_number(
                i64::try_from(result.unsafe_break_count)
                    .map_err(|_| NamedError("EmitUnsafeBreakCountConversion".to_string()))?,
            )),
        ),
        ("advance".into(), Json::Num(result.advance)),
        (
            "glyphs".into(),
            Json::Arr(
                result
                    .glyphs
                    .iter()
                    .map(|glyph| {
                        let mut fields = vec![
                            ("id".into(), Json::Num(f64::from(glyph.id))),
                            ("cluster".into(), Json::Num(f64::from(glyph.cluster))),
                            ("advance".into(), Json::Num(glyph.advance)),
                            ("x".into(), Json::Num(glyph.x)),
                            ("y".into(), Json::Num(glyph.y)),
                        ];
                        if let Some(bounds) = &glyph.bounds {
                            fields.push((
                                "bounds".into(),
                                Json::Arr(bounds.iter().map(|v| Json::Num(*v)).collect()),
                            ));
                        }
                        Json::Obj(fields)
                    })
                    .collect(),
            ),
        ),
    ]))
}

/// `captureEvidence()` in oracle field order. The count conversion fails
/// only when a shape produced more unsafe breaks than i64 holds.
pub fn evidence_json(evidence: &FontEvidence) -> Result<Json, NamedError> {
    Ok(Json::Obj(vec![
        (
            "backendRevision".into(),
            Json::str(evidence.backend_revision),
        ),
        (
            "harfbuzzVersion".into(),
            Json::str(evidence.harfbuzz_version),
        ),
        (
            "faces".into(),
            Json::Arr(evidence.faces.iter().map(usage_json).collect()),
        ),
        (
            "replay".into(),
            Json::Obj(vec![
                ("revision".into(), Json::str(FONT_REPLAY_REVISION)),
                (
                    "shapes".into(),
                    Json::Arr(
                        evidence
                            .replay_shapes
                            .iter()
                            .map(shape_replay_json)
                            .collect::<Result<Vec<_>, _>>()?,
                    ),
                ),
                (
                    "metrics".into(),
                    Json::Arr(
                        evidence
                            .replay_metrics
                            .iter()
                            .map(metric_replay_json)
                            .collect(),
                    ),
                ),
            ]),
        ),
    ]))
}

fn usage_json(usage: &FaceUsage) -> Json {
    Json::Obj(vec![
        ("family".into(), Json::str(usage.family.clone())),
        ("style".into(), Json::str(usage.style)),
        (
            "weight".into(),
            Json::Arr(vec![Json::Num(usage.weight[0]), Json::Num(usage.weight[1])]),
        ),
        (
            "unicodeRange".into(),
            Json::str(usage.unicode_range.clone()),
        ),
        ("publicUrl".into(), Json::str(usage.public_url.clone())),
        (
            "sourceSha256".into(),
            Json::str(usage.source_sha256.clone()),
        ),
        ("sfntSha256".into(), Json::str(usage.sfnt_sha256.clone())),
        ("faceIndex".into(), Json::Num(usage.face_index)),
        (
            "sourceOrder".into(),
            Json::Num(f64::from(usage.source_order)),
        ),
        (
            "axes".into(),
            Json::Obj(
                usage
                    .axes
                    .iter()
                    .map(|(tag, value)| (tag.clone(), Json::Num(*value)))
                    .collect(),
            ),
        ),
        (
            "localNames".into(),
            Json::Arr(
                usage
                    .local_names
                    .iter()
                    .map(|name| Json::str(name.clone()))
                    .collect(),
            ),
        ),
        (
            "coverageText".into(),
            Json::str(usage.coverage_text.iter().collect::<String>()),
        ),
        (
            "probe".into(),
            Json::Obj(vec![
                ("text".into(), Json::str(usage.probe_text.clone())),
                ("advancePx".into(), Json::Num(usage.probe_advance_px)),
                ("fontSizePx".into(), Json::Num(usage.probe_font_size_px)),
                ("fontWeight".into(), Json::Num(usage.probe_font_weight)),
                ("italic".into(), Json::Bool(usage.probe_italic)),
                ("script".into(), Json::str(usage.probe_script.clone())),
                ("language".into(), Json::str(usage.probe_language.clone())),
                (
                    "features".into(),
                    Json::Arr(
                        usage
                            .probe_features
                            .iter()
                            .map(|f| Json::str(f.clone()))
                            .collect(),
                    ),
                ),
            ]),
        ),
    ])
}

fn shape_replay_json(replay: &ShapeReplay) -> Result<Json, NamedError> {
    Ok(Json::Obj(vec![
        ("key".into(), Json::str(replay.key.clone())),
        (
            "result".into(),
            Json::Obj(vec![
                ("faceId".into(), Json::str(replay.face_id.clone())),
                (
                    "fontInstanceId".into(),
                    Json::str(replay.font_instance_id.clone()),
                ),
                ("script".into(), Json::str(replay.script.clone())),
                (
                    "features".into(),
                    Json::Arr(
                        replay
                            .features
                            .iter()
                            .map(|f| Json::str(f.clone()))
                            .collect(),
                    ),
                ),
                (
                    "unsafeBreakCount".into(),
                    Json::Num(js_int_to_number(
                        i64::try_from(replay.unsafe_break_count).map_err(|_| {
                            NamedError("EmitUnsafeBreakCountConversion".to_string())
                        })?,
                    )),
                ),
                ("advanceEm".into(), opt_num(replay.advance_em)),
                (
                    "glyphs".into(),
                    Json::Arr(
                        replay
                            .glyphs
                            .iter()
                            .map(|glyph| {
                                Json::Obj(vec![
                                    ("id".into(), Json::Num(f64::from(glyph.id))),
                                    ("advanceEm".into(), opt_num(glyph.advance_em)),
                                    ("xEm".into(), opt_num(glyph.x_em)),
                                    ("yEm".into(), opt_num(glyph.y_em)),
                                    (
                                        "boundsEm".into(),
                                        match &glyph.bounds_em {
                                            None => Json::Null,
                                            Some(bounds) => Json::Arr(
                                                bounds.iter().map(|v| opt_num(*v)).collect(),
                                            ),
                                        },
                                    ),
                                ])
                            })
                            .collect(),
                    ),
                ),
            ]),
        ),
    ]))
}

fn metric_replay_json(replay: &MetricReplay) -> Json {
    Json::Obj(vec![
        ("key".into(), Json::str(replay.key.clone())),
        (
            "valuesEm".into(),
            Json::Arr(replay.values_em.iter().map(|v| opt_num(*v)).collect()),
        ),
    ])
}

fn opt_num(value: Option<f64>) -> Json {
    match value {
        Some(value) => Json::Num(value),
        None => Json::Null,
    }
}
