//! Prepared DOM rendering through the generated shared crate.

use crate::json::Json;
use crate::plan::Plan;
use crate::shared_prepared::to_prepared_plan;
use crate::snapshot_source::SemanticSpan;
use crate::NamedError;
use tiqian_shared::org::tiqian::shared::prepared_dom::attribute_entry::AttributeEntry;
use tiqian_shared::org::tiqian::shared::prepared_dom::inline_box_entry::InlineBoxEntry;
use tiqian_shared::org::tiqian::shared::prepared_dom::markup_artifact::MarkupArtifact;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_artifact::PreparedArtifact;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_artifact_options::PreparedArtifactOptions;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_render_text_span::PreparedRenderTextSpan;
use tiqian_shared::org::tiqian::shared::prepared_dom::prepared_semantic_span::PreparedSemanticSpan;
use tiqian_shared::runtime::u_string::UString;

fn shared(value: &str) -> UString {
    UString::from(value)
}

fn semantic_spans(semantics: &[SemanticSpan]) -> Vec<PreparedSemanticSpan> {
    semantics
        .iter()
        .enumerate()
        .map(|(index, span)| PreparedSemanticSpan {
            index: index as u32,
            start: span.start as f64,
            end: span.end as f64,
            tag_name: shared(&span.tag_name),
            source_index: index as f64,
            attributes: span
                .attributes
                .iter()
                .map(|(name, value)| AttributeEntry {
                    name: shared(name),
                    value: shared(value),
                })
                .collect(),
            signature: shared(""),
        })
        .collect()
}

pub fn render_shared_artifact(
    plan: &Plan,
    locale: &str,
    semantics: &[SemanticSpan],
    live: bool,
    render_text_spans: &[(i32, i32, Vec<String>)],
    inline_boxes: &[crate::paragraph::InlineBoxInput],
) -> Result<(String, Vec<MarkupArtifact>), NamedError> {
    let prepared = to_prepared_plan(plan);
    let options = PreparedArtifactOptions {
        style_class_for: None,
        live_source: live,
        semantics: semantic_spans(semantics),
        render_text_spans: render_text_spans
            .iter()
            .map(|(start, end, families)| PreparedRenderTextSpan {
                start: f64::from(*start),
                end: f64::from(*end),
                font_families: families.iter().map(|family| shared(family)).collect(),
                signature: shared(""),
            })
            .collect(),
        cjk_strong_semantics: Vec::new(),
        inline_boxes: inline_boxes
            .iter()
            .map(|inline_box| InlineBoxEntry {
                start: f64::from(inline_box.start),
                end: f64::from(inline_box.end),
                inline_start_px: inline_box.inline_start,
                inline_end_px: inline_box.inline_end,
            })
            .collect(),
        emphasis_dot_color: None,
    };
    let locale_text = shared(locale);
    let result = PreparedArtifact::prepared_artifact_render_prepared_paragraph_artifact(
        prepared,
        locale_text.as_ustr(),
        options,
    )
    .map_err(|error| NamedError(format!("{error:?}")))?;
    Ok((result.html.to_utf8_lossy(), result.artifact))
}

pub fn artifact_json(artifacts: &[MarkupArtifact]) -> Json {
    Json::Arr(artifacts.iter().map(artifact_node_json).collect())
}

fn artifact_node_json(artifact: &MarkupArtifact) -> Json {
    match artifact {
        MarkupArtifact::Text { text } => Json::Arr(vec![
            Json::str("#"),
            Json::str(text.to_utf8_lossy()),
        ]),
        MarkupArtifact::Element {
            tag,
            entries,
            children,
        } => Json::Arr(vec![
            Json::str(tag.to_utf8_lossy()),
            Json::Arr(
                entries
                    .iter()
                    .map(|entry| {
                        Json::Arr(vec![
                            Json::str(entry.name.to_utf8_lossy()),
                            Json::str(entry.value.to_utf8_lossy()),
                        ])
                    })
                    .collect(),
            ),
            Json::Arr(children.iter().map(artifact_node_json).collect()),
        ]),
    }
}
