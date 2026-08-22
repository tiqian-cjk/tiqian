//! Snapshot bundle assembly of `buildSnapshotBundle` in `precompute.js`
//! (ADR 0050). The bundle layer re-renders every prepared paragraph with the
//! shared `tqv-` value-style classes, compacts the manifest tables, and emits
//! the inert server template plus the client font-contract template.
//!
//! ADR 0052 `BundleLayering` splits the render in two: the data phase
//! re-renders bodies and may mint value-style rows into mutable snapshot
//! tables; the assembly phase compacts the manifest against the frozen table,
//! so every article of one build pins the same content hash. The one-shot
//! entry points keep the schema-1 behavior with byte-identical templates.
//!
//! The js module keeps the three public entry points for Node callers; this
//! port serves the native precompute package. The shared runtime style stays
//! a caller parameter so the crate ships without reading package files.
//! Damage js reports with a raw `TypeError` (a non-array paragraph list)
//! surfaces with `MissingPreparedParagraphs`; re-render damage keeps the
//! named issues of the prepared DOM lowering.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::font_source::sha256_hex;
use crate::js_compat::{js_int_to_number, js_number_string, js_trim, trunc_sat_usize};
use crate::json::Json;
use crate::prepared_dom::{render_prepared_paragraph_artifact, PreparedRenderOptions};
use crate::schema::{
    stable_stringify, FONT_SOURCE_POLICY, LAYOUT_REVISION, RENDER_REVISION, SNAPSHOT_SCHEMA,
};
use crate::snapshot_manifest::{
    annotate_missing, compact_snapshot_manifest, compact_snapshot_manifest_with_tables,
    index_number, key_string_of,
};
use crate::snapshot_source::js_string_value;
use crate::snapshot_tables::SnapshotTables;

/// `PLAIN_PARAGRAPH_SELECTOR`: canonical plain paragraphs of a snapshot root.
pub const PLAIN_PARAGRAPH_SELECTOR: &str = ":is(p, li)[data-tq-snapshot-key]";

/// `RUNTIME_PARAGRAPH_SELECTOR`: every live paragraph of a semantic root.
pub const RUNTIME_PARAGRAPH_SELECTOR: &str = ":is(p, li):not([data-tiqian-skip])";

const DEFAULT_LOCALE: &str = "zh-Hans";

/// Options of the bundle entry points. `None` matches the `??` defaults of
/// the js signatures; the shared runtime style is a required parameter
/// because the crate never reads the package stylesheet itself. Snapshot
/// tables select the schema-2 split render; the one-shot entries reject
/// them because a build must render every article before it freezes.
pub struct SnapshotBundleOptions<'a> {
    pub id: Option<&'a str>,
    pub paragraph_selector: Option<&'a str>,
    pub font_contract_paragraphs: Option<&'a Json>,
    pub shared_runtime_style: &'a str,
    /// Finalized snapshot tables (ADR 0052 schema 2). `None` keeps the
    /// self-contained schema-1 manifest every current golden pins.
    pub snapshot_tables: Option<&'a SnapshotTables>,
}

impl<'a> SnapshotBundleOptions<'a> {
    pub fn new(shared_runtime_style: &'a str) -> Self {
        SnapshotBundleOptions {
            id: None,
            paragraph_selector: None,
            font_contract_paragraphs: None,
            shared_runtime_style,
            snapshot_tables: None,
        }
    }
}

/// The assembled snapshot: templates, first-paint style, and entry bodies.
pub struct SnapshotBundle {
    pub id: String,
    pub template: String,
    pub client_template: String,
    pub inert_template: String,
    pub initial_style: String,
    pub render_font_families: Json,
    pub font_preloads: Json,
    pub root_attributes: Json,
    pub entries: Json,
}

/// The data phase output of one bundle: re-rendered bodies plus everything
/// assembly needs. Value styles mint in render order; the schema-1 path
/// keeps the local list, the table path records the table indexes the
/// classes used so assembly resolves declarations from frozen rows.
pub struct SnapshotBundleData {
    pub id: String,
    pub paragraph_selector: String,
    pub render_font_families: Vec<Json>,
    pub rendered_entries: Vec<Json>,
    pub font_contract_entries: Vec<Json>,
    /// Schema-1 local declarations in first-mint order.
    pub value_styles: Vec<String>,
    /// Table indexes this bundle's classes used, in first-mint order.
    pub used_value_style_indexes: Vec<usize>,
}

impl SnapshotBundleData {
    /// The wire form the neon boundary passes between the data and assembly
    /// calls; the host holds it for the span of one build.
    pub fn to_json(&self) -> Json {
        let mut used_indexes: Vec<Json> = Vec::with_capacity(self.used_value_style_indexes.len());
        for index in &self.used_value_style_indexes {
            used_indexes.push(match i64::try_from(*index) {
                Ok(value) => Json::Num(js_int_to_number(value)),
                // Table row counts stay far below the i64 limit.
                Err(_) => Json::Num(js_int_to_number(0)),
            });
        }
        Json::Obj(vec![
            ("id".to_string(), Json::str(self.id.clone())),
            (
                "paragraphSelector".to_string(),
                Json::str(self.paragraph_selector.clone()),
            ),
            (
                "renderFontFamilies".to_string(),
                Json::Arr(self.render_font_families.clone()),
            ),
            (
                "renderedEntries".to_string(),
                Json::Arr(self.rendered_entries.clone()),
            ),
            (
                "fontContractEntries".to_string(),
                Json::Arr(self.font_contract_entries.clone()),
            ),
            (
                "valueStyles".to_string(),
                Json::Arr(
                    self.value_styles
                        .iter()
                        .map(|item| Json::str(item.clone()))
                        .collect(),
                ),
            ),
            ("usedValueStyleIndexes".to_string(), Json::Arr(used_indexes)),
        ])
    }

    /// Restores the data phase output from its wire form.
    pub fn from_json(value: &Json) -> Result<Self, NamedError> {
        let invalid = || NamedError("SnapshotBundleDataInvalid".to_string());
        let id = match field(value, "id") {
            Some(Json::Str(text)) => text.clone(),
            _ => return Err(invalid()),
        };
        let paragraph_selector = match field(value, "paragraphSelector") {
            Some(Json::Str(text)) => text.clone(),
            _ => return Err(invalid()),
        };
        let render_font_families = match field(value, "renderFontFamilies") {
            Some(Json::Arr(items)) => items.clone(),
            _ => return Err(invalid()),
        };
        let rendered_entries = match field(value, "renderedEntries") {
            Some(Json::Arr(items)) => items.clone(),
            _ => return Err(invalid()),
        };
        let font_contract_entries = match field(value, "fontContractEntries") {
            Some(Json::Arr(items)) => items.clone(),
            _ => return Err(invalid()),
        };
        let mut value_styles: Vec<String> = Vec::new();
        if let Some(Json::Arr(rows)) = field(value, "valueStyles") {
            for row in rows {
                let Json::Str(text) = row else {
                    return Err(invalid());
                };
                value_styles.push(text.clone());
            }
        }
        let mut used_value_style_indexes: Vec<usize> = Vec::new();
        if let Some(Json::Arr(rows)) = field(value, "usedValueStyleIndexes") {
            for row in rows {
                let Json::Num(number) = row else {
                    return Err(invalid());
                };
                if number.fract() != 0.0 || *number < 0.0 {
                    return Err(invalid());
                }
                used_value_style_indexes.push(trunc_sat_usize(*number));
            }
        }
        Ok(SnapshotBundleData {
            id,
            paragraph_selector,
            render_font_families,
            rendered_entries,
            font_contract_entries,
            value_styles,
            used_value_style_indexes,
        })
    }
}

/// `renderSnapshotBundle`: the inert prepared-DOM template plus the compact
/// manifests used by server and client-navigation adapters.
pub fn render_snapshot_bundle(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    if options.snapshot_tables.is_some() {
        return Err(named("SnapshotTablesRequireSplitRender"));
    }
    let data = render_snapshot_bundle_data_inner(
        &array_input(prepared_paragraphs)?,
        &array_input(options.font_contract_paragraphs)?,
        options,
        None,
        PLAIN_PARAGRAPH_SELECTOR,
    )?;
    assemble_snapshot_bundle(&data, options)
}

/// `renderFontContractBundle`: the compact exact-font contract for roots that
/// keep their semantic source DOM and lay out in the browser.
pub fn render_font_contract_bundle(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    if options.snapshot_tables.is_some() {
        return Err(named("SnapshotTablesRequireSplitRender"));
    }
    let data = render_snapshot_bundle_data_inner(
        &array_input(prepared_paragraphs)?,
        &array_input(options.font_contract_paragraphs)?,
        options,
        None,
        RUNTIME_PARAGRAPH_SELECTOR,
    )?;
    assemble_font_contract_bundle(&data, options)
}

/// `renderSnapshotTemplate`: the inert template alone.
pub fn render_snapshot_template(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<String, NamedError> {
    if options.snapshot_tables.is_some() {
        return Err(named("SnapshotTablesRequireSplitRender"));
    }
    render_snapshot_bundle_data_inner(
        &array_input(prepared_paragraphs)?,
        &array_input(options.font_contract_paragraphs)?,
        options,
        None,
        PLAIN_PARAGRAPH_SELECTOR,
    )
    .and_then(|data| assemble_snapshot_bundle(&data, options))
    .map(|bundle| bundle.inert_template)
}

/// The data phase for plain snapshot bundles: mutable tables mint the
/// value-style rows this bundle's classes reference.
pub fn render_snapshot_bundle_data(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
    tables: Option<&mut SnapshotTables>,
) -> Result<SnapshotBundleData, NamedError> {
    render_snapshot_bundle_data_inner(
        &array_input(prepared_paragraphs)?,
        &array_input(options.font_contract_paragraphs)?,
        options,
        tables,
        PLAIN_PARAGRAPH_SELECTOR,
    )
}

/// The data phase for font-contract bundles.
pub fn render_font_contract_bundle_data(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
    tables: Option<&mut SnapshotTables>,
) -> Result<SnapshotBundleData, NamedError> {
    render_snapshot_bundle_data_inner(
        &array_input(prepared_paragraphs)?,
        &array_input(options.font_contract_paragraphs)?,
        options,
        tables,
        RUNTIME_PARAGRAPH_SELECTOR,
    )
}

fn named(message: &str) -> NamedError {
    NamedError(message.to_string())
}

fn field<'a>(value: &'a Json, key: &str) -> Option<&'a Json> {
    match value {
        Json::Obj(fields) => fields
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value),
        _ => None,
    }
}

fn arr_of(value: Option<&Json>) -> Option<&[Json]> {
    match value {
        Some(Json::Arr(items)) => Some(items),
        _ => None,
    }
}

/// `Array.from(value ?? [])`: nullish inputs empty the list, arrays pass
/// through, anything else reports the paragraph-list gate name.
fn array_input(value: Option<&Json>) -> Result<Vec<Json>, NamedError> {
    match value {
        None | Some(Json::Null) => Ok(Vec::new()),
        Some(Json::Arr(items)) => Ok(items.clone()),
        Some(_) => Err(named("MissingPreparedParagraphs")),
    }
}

/// The data phase of `buildSnapshotBundle`: validation gates plus the
/// re-render that mints value-style classes. `tables` selects where the
/// classes index: table rows (schema 2) or the local list (schema 1).
fn render_snapshot_bundle_data_inner(
    entries: &[Json],
    font_contract_entries: &[Json],
    options: &SnapshotBundleOptions,
    mut tables: Option<&mut SnapshotTables>,
    supported_paragraph_selector: &str,
) -> Result<SnapshotBundleData, NamedError> {
    let mut corpus: Vec<&Json> = Vec::with_capacity(entries.len() + font_contract_entries.len());
    corpus.extend(entries.iter());
    corpus.extend(font_contract_entries.iter());
    if entries.is_empty() {
        return Err(named("MissingPreparedParagraphs"));
    }
    if corpus
        .iter()
        .any(|entry| field(entry, "status") != Some(&Json::str("prepared")))
    {
        return Err(named("SnapshotTemplateContainsUnsupportedParagraph"));
    }
    if corpus.iter().any(|entry| {
        field(entry, "schema") != Some(&Json::Num(js_int_to_number(SNAPSHOT_SCHEMA)))
            || field(entry, "layoutRevision") != Some(&Json::str(LAYOUT_REVISION))
            || field(entry, "renderRevision") != Some(&Json::str(RENDER_REVISION))
            || !matches!(field(entry, "renderArtifactSha256"), Some(Json::Str(_)))
    }) {
        return Err(named("SnapshotTemplateContainsStalePreparedParagraph"));
    }
    let mut seen_keys: Vec<Json> = Vec::with_capacity(corpus.len());
    for entry in &corpus {
        let key = field(entry, "key").cloned().unwrap_or(Json::Null);
        if seen_keys.contains(&key) {
            return Err(named("DuplicateSnapshotKey"));
        }
        seen_keys.push(key);
    }
    let families = match field(&entries[0], "renderFontFamilies") {
        Some(Json::Arr(items)) if !items.is_empty() => items,
        _ => return Err(named("MissingExactRenderFontFamilies")),
    };
    for family in families {
        match family {
            Json::Str(text) if !js_trim(text).is_empty() => {}
            _ => return Err(named("MissingExactRenderFontFamilies")),
        }
    }
    let render_family_signature = stable_stringify(&Json::Arr(families.to_vec()));
    for entry in &corpus {
        let signature = field(entry, "renderFontFamilies")
            .map(stable_stringify)
            .unwrap_or_default();
        if signature != render_family_signature {
            return Err(named("SnapshotRenderFontFamilyConflict"));
        }
    }
    let id = js_trim(options.id.unwrap_or("")).to_string();
    if id.is_empty() {
        return Err(named("MissingSnapshotTemplateId"));
    }
    if !valid_template_id(&id) {
        return Err(named("InvalidSnapshotTemplateId"));
    }
    let paragraph_selector = options
        .paragraph_selector
        .unwrap_or(supported_paragraph_selector);
    if paragraph_selector != supported_paragraph_selector {
        return Err(named("UnsupportedSnapshotParagraphSelector"));
    }

    let mut value_styles: Vec<String> = Vec::new();
    let mut value_style_indexes: HashMap<String, usize> = HashMap::new();
    let mut used_value_style_indexes: Vec<usize> = Vec::new();
    let mut class_for: Box<dyn FnMut(&str) -> String + '_> = match tables.as_deref_mut() {
        Some(table) => Box::new(|declaration: &str| {
            // Table rows define the class indexes; the data phase records
            // which rows this bundle used so assembly writes the rules.
            let index = table.intern_value_style(declaration);
            if !used_value_style_indexes.contains(&index) {
                used_value_style_indexes.push(index);
            }
            format!("tqv-{}", to_string_36(index))
        }),
        None => Box::new(|declaration: &str| {
            if let Some(&index) = value_style_indexes.get(declaration) {
                return format!("tqv-{}", to_string_36(index));
            }
            let index = value_styles.len();
            value_styles.push(declaration.to_string());
            value_style_indexes.insert(declaration.to_string(), index);
            format!("tqv-{}", to_string_36(index))
        }),
    };
    let mut rendered_entries: Vec<Json> = Vec::with_capacity(entries.len());
    for entry in entries {
        let plan_json = match field(entry, "plan") {
            Some(Json::Str(text)) => text.clone(),
            Some(other) => other.render(),
            None => return Err(named("InvalidPreparedParagraphGeometry")),
        };
        let locale = prepared_locale(field(entry, "typography"));
        let mut render_options = PreparedRenderOptions::new();
        render_options.style_class_for = Some(&mut class_for);
        render_options.semantics = field(entry, "semantics");
        render_options.inline_boxes = field(entry, "inlineBoxes");
        render_options.render_text_spans = field(entry, "renderTextSpans");
        if let Some(Json::Str(text)) = field(entry, "sourceText") {
            render_options.source_text = Some(text.as_str());
        }
        let rendered =
            render_prepared_paragraph_artifact(&plan_json, &locale, &mut render_options)?;
        let artifact_sha = sha256_hex(stable_stringify(&rendered.artifact).as_bytes());
        let mut fields = match entry {
            Json::Obj(fields) => fields.clone(),
            _ => Vec::new(),
        };
        let mut has_html = false;
        let mut has_artifact_sha = false;
        for (name, value) in fields.iter_mut() {
            if name == "html" {
                *value = Json::str(&rendered.html);
                has_html = true;
            } else if name == "renderArtifactSha256" {
                *value = Json::str(&artifact_sha);
                has_artifact_sha = true;
            }
        }
        if !has_html {
            fields.push(("html".to_string(), Json::str(&rendered.html)));
        }
        if !has_artifact_sha {
            fields.push(("renderArtifactSha256".to_string(), Json::str(&artifact_sha)));
        }
        rendered_entries.push(Json::Obj(fields));
    }
    drop(class_for);
    Ok(SnapshotBundleData {
        id,
        paragraph_selector: paragraph_selector.to_string(),
        render_font_families: families.to_vec(),
        rendered_entries,
        font_contract_entries: font_contract_entries.to_vec(),
        value_styles,
        used_value_style_indexes,
    })
}

/// The assembly phase: manifest compaction against the frozen table (or the
/// self-contained schema-1 compaction), templates, and the first-paint
/// style. Runs after every bundle of one build rendered and the table froze.
pub fn assemble_snapshot_bundle(
    data: &SnapshotBundleData,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    let rendered_pairs: Vec<(String, String)> = data
        .rendered_entries
        .iter()
        .map(|entry| {
            (
                js_string_value(field(entry, "key").unwrap_or(&Json::Null)),
                match field(entry, "html") {
                    Some(Json::Str(text)) => text.clone(),
                    _ => String::new(),
                },
            )
        })
        .collect();
    let families = &data.render_font_families;
    let mut corpus_entries = data.rendered_entries.clone();
    corpus_entries.extend(data.font_contract_entries.iter().cloned());
    let (manifest, client_manifest, manifest_has_local_styles) = match options.snapshot_tables {
        Some(tables) => {
            let compact = compact_snapshot_manifest_with_tables(
                &Json::Arr(corpus_entries),
                &tables_metadata(data),
                tables,
            )?;
            let manifest = if data.font_contract_entries.is_empty() {
                compact
            } else {
                split_contract_entries(compact, data.rendered_entries.len())
            };
            // The schema-2 walk reads the prepared corpus: coverage text and
            // probes left the compact entries but stay on the source faces.
            let client = client_font_contract_manifest_with_tables(
                &data.rendered_entries,
                &data.font_contract_entries,
                tables,
                &manifest,
            )?;
            (manifest, client, false)
        }
        None => {
            let value_styles_json = Json::Arr(
                data.value_styles
                    .iter()
                    .map(|item| Json::str(item.clone()))
                    .collect(),
            );
            let metadata = Json::Obj(vec![
                (
                    "schema".to_string(),
                    Json::Num(js_int_to_number(SNAPSHOT_SCHEMA)),
                ),
                ("layoutRevision".to_string(), Json::str(LAYOUT_REVISION)),
                ("renderRevision".to_string(), Json::str(RENDER_REVISION)),
                (
                    "fontSourcePolicy".to_string(),
                    Json::str(FONT_SOURCE_POLICY),
                ),
                (
                    "paragraphSelector".to_string(),
                    Json::str(data.paragraph_selector.clone()),
                ),
                ("valueStyles".to_string(), value_styles_json.clone()),
                (
                    "valueStylesSha256".to_string(),
                    Json::str(sha256_hex(stable_stringify(&value_styles_json).as_bytes())),
                ),
                (
                    "renderFontFamilies".to_string(),
                    Json::Arr(families.to_vec()),
                ),
            ]);
            let compact = compact_snapshot_manifest(&Json::Arr(corpus_entries), &metadata)?;
            let manifest = if data.font_contract_entries.is_empty() {
                compact
            } else {
                split_contract_entries(compact, data.rendered_entries.len())
            };
            let client = client_font_contract_manifest(&manifest)?;
            (manifest, client, true)
        }
    };
    let manifest_json = manifest.render().replace('<', "\\u003c");

    let body = rendered_pairs
        .iter()
        .map(|(key, html)| {
            format!(
                "<div data-tq-entry=\"{}\">{}</div>",
                escape_attribute(key),
                html
            )
        })
        .collect::<String>();
    let inert_template = format!(
        "<template id=\"{}\" data-tq-snapshot-schema=\"{}\" data-tq-layout-revision=\"{}\" \
data-tq-render-revision=\"{}\" data-pagefind-ignore><script type=\"application/json\" \
data-tq-snapshot-manifest>{}</script>{}</template>",
        escape_attribute(&data.id),
        SNAPSHOT_SCHEMA,
        LAYOUT_REVISION,
        RENDER_REVISION,
        manifest_json,
        body,
    );
    // The compatibility alias deliberately stays inert; package output never
    // advertises a server-dom manifest.
    let template = inert_template.clone();
    let client_manifest_json = client_manifest.render().replace('<', "\\u003c");
    let client_template = format!(
        "<template id=\"{}\" data-tq-snapshot-schema=\"{}\" data-tq-layout-revision=\"{}\" \
data-tq-render-revision=\"{}\" data-pagefind-ignore><script type=\"application/json\" \
data-tq-snapshot-manifest>{}</script></template>",
        escape_attribute(&data.id),
        SNAPSHOT_SCHEMA,
        LAYOUT_REVISION,
        RENDER_REVISION,
        client_manifest_json,
    );
    // The line strut, geometry reset, and nowrap contract of the prepared DOM
    // belong in the server-injected first-paint style as well.
    let mut initial_style = String::from(options.shared_runtime_style);
    initial_style.push_str(&exact_render_font_style(&data.id));
    if manifest_has_local_styles {
        for (index, declaration) in data.value_styles.iter().enumerate() {
            initial_style.push_str(&format!(
                "tiqian-prose[snapshot-ref=\"{}\"] [data-tq-rendered=\"true\"] .tqv-{}{{{}}}",
                escape_attribute(&data.id),
                to_string_36(index),
                declaration,
            ));
        }
    } else if let Some(tables) = options.snapshot_tables {
        for &index in &data.used_value_style_indexes {
            let Some(declaration) = tables.value_style_at(index) else {
                return Err(named("SnapshotTableValueStyleMissing"));
            };
            initial_style.push_str(&format!(
                "tiqian-prose[snapshot-ref=\"{}\"] [data-tq-rendered=\"true\"] .tqv-{}{{{}}}",
                escape_attribute(&data.id),
                to_string_36(index),
                declaration,
            ));
        }
    }
    Ok(SnapshotBundle {
        id: data.id.clone(),
        template,
        client_template,
        inert_template,
        initial_style,
        render_font_families: Json::Arr(families.to_vec()),
        font_preloads: Json::Arr(Vec::new()),
        root_attributes: Json::Obj(vec![(
            "data-tiqian-exact-render-font".to_string(),
            Json::str("true"),
        )]),
        entries: Json::Arr(
            rendered_pairs
                .into_iter()
                .map(|(key, html)| {
                    Json::Obj(vec![
                        ("key".to_string(), Json::str(key)),
                        ("html".to_string(), Json::str(html)),
                    ])
                })
                .collect(),
        ),
    })
}

/// Assembly of a font-contract bundle: the shared assembly plus the
/// client-only post-processing of `renderFontContractBundle`.
pub fn assemble_font_contract_bundle(
    data: &SnapshotBundleData,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    let mut bundle = assemble_snapshot_bundle(data, options)?;
    bundle.template = bundle.client_template.clone();
    bundle.inert_template = bundle.client_template.clone();
    bundle.initial_style = exact_render_font_style(&bundle.id);
    bundle.root_attributes = Json::Obj(Vec::new());
    bundle.entries = Json::Arr(Vec::new());
    Ok(bundle)
}

/// The metadata spread of the schema-2 compaction: value styles live in the
/// table and drop out, everything else passes through as in schema 1.
fn tables_metadata(data: &SnapshotBundleData) -> Json {
    Json::Obj(vec![
        (
            "schema".to_string(),
            Json::Num(js_int_to_number(SNAPSHOT_SCHEMA)),
        ),
        ("layoutRevision".to_string(), Json::str(LAYOUT_REVISION)),
        ("renderRevision".to_string(), Json::str(RENDER_REVISION)),
        (
            "fontSourcePolicy".to_string(),
            Json::str(FONT_SOURCE_POLICY),
        ),
        (
            "paragraphSelector".to_string(),
            Json::str(data.paragraph_selector.clone()),
        ),
        (
            "renderFontFamilies".to_string(),
            Json::Arr(data.render_font_families.clone()),
        ),
    ])
}

/// Splits the compacted corpus back into `entries` and `fontContractEntries`,
/// keeping every other manifest field and field order in place.
fn split_contract_entries(compact: Json, rendered_count: usize) -> Json {
    let mut fields = match compact {
        Json::Obj(fields) => fields,
        other => return other,
    };
    let (main, contract) = match fields.iter().find(|(name, _)| name == "entries") {
        Some((_, Json::Arr(items))) if items.len() >= rendered_count => (
            Json::Arr(items[..rendered_count].to_vec()),
            Json::Arr(items[rendered_count..].to_vec()),
        ),
        _ => return Json::Obj(fields),
    };
    let mut main = Some(main);
    for (name, value) in fields.iter_mut() {
        if name == "entries" {
            if let Some(main) = main.take() {
                *value = main;
            }
            break;
        }
    }
    if let Some(main) = main {
        fields.push(("entries".to_string(), main));
    }
    fields.push(("fontContractEntries".to_string(), contract));
    Json::Obj(fields)
}

/// `clientFontContractManifest`: per-face coverage unions and deduped probes
/// as one compact contract the client can verify its local faces against.
fn client_font_contract_manifest(manifest: &Json) -> Result<Json, NamedError> {
    struct Group {
        face_ref: Json,
        coverage: Vec<char>,
        probes: Vec<(Option<String>, Option<Json>)>,
    }
    let mut groups: Vec<Group> = Vec::new();
    let mut group_indexes: HashMap<String, usize> = HashMap::new();
    let mut sources: Vec<&Json> = Vec::new();
    if let Some(entries) = arr_of(field(manifest, "entries")) {
        sources.extend(entries.iter());
    }
    if let Some(contract) = arr_of(field(manifest, "fontContractEntries")) {
        sources.extend(contract.iter());
    }
    for entry in sources {
        for evidence in arr_of(field(entry, "fontFaceEvidence")).unwrap_or(&[]) {
            let face_ref = field(evidence, "faceRef").cloned().unwrap_or(Json::Null);
            let group_key = face_ref.render();
            let index = match group_indexes.get(&group_key) {
                Some(&index) => index,
                None => {
                    groups.push(Group {
                        coverage: Vec::new(),
                        face_ref: face_ref.clone(),
                        probes: Vec::new(),
                    });
                    group_indexes.insert(group_key, groups.len() - 1);
                    groups.len() - 1
                }
            };
            let group = &mut groups[index];
            let coverage_text = match field(evidence, "coverageText") {
                Some(Json::Str(text)) if !text.is_empty() => Some(text.clone()),
                _ => field(evidence, "probe")
                    .and_then(|probe| field(probe, "text"))
                    .and_then(|text| match text {
                        Json::Str(text) if !text.is_empty() => Some(text.clone()),
                        _ => None,
                    }),
            };
            if let Some(text) = coverage_text {
                for point in text.chars() {
                    if !group.coverage.contains(&point) {
                        group.coverage.push(point);
                    }
                }
            }
            let probe = field(evidence, "probe").cloned();
            let signature = probe.as_ref().map(stable_stringify);
            if !group
                .probes
                .iter()
                .any(|(existing, _)| *existing == signature)
            {
                group.probes.push((signature, probe));
            }
        }
    }
    let mut contract_entries: Vec<Json> = Vec::new();
    for group in &groups {
        for (_, probe) in &group.probes {
            let mut evidence_row = vec![("faceRef".to_string(), group.face_ref.clone())];
            evidence_row.push((
                "coverageText".to_string(),
                Json::str(group.coverage.iter().collect::<String>()),
            ));
            if let Some(probe) = probe {
                evidence_row.push(("probe".to_string(), probe.clone()));
            }
            contract_entries.push(Json::Obj(vec![
                (
                    "key".to_string(),
                    Json::str(format!("font-contract-{}", contract_entries.len())),
                ),
                ("sourceSha256".to_string(), Json::str("0".repeat(64))),
                ("typographyRef".to_string(), Json::Num(0.0)),
                ("maxWidthPx".to_string(), Json::Num(1.0)),
                (
                    "fontFaceEvidence".to_string(),
                    Json::Arr(vec![Json::Obj(evidence_row)]),
                ),
                (
                    "renderArtifactSha256".to_string(),
                    Json::str("0".repeat(64)),
                ),
            ]));
        }
    }
    if contract_entries.is_empty() {
        return Err(named("SnapshotClientFontContractEmpty"));
    }
    // The client manifest drops fontContractEntries, empties the value
    // styles, replaces the entries, and appends the entry source marker.
    let empty_styles = Json::Arr(Vec::new());
    let mut fields: Vec<(String, Json)> = match manifest {
        Json::Obj(fields) => fields
            .iter()
            .filter(|(name, _)| name != "fontContractEntries")
            .cloned()
            .collect(),
        _ => Vec::new(),
    };
    let mut present = [false; 3];
    for (name, value) in fields.iter_mut() {
        match name.as_str() {
            "valueStyles" => {
                *value = empty_styles.clone();
                present[0] = true;
            }
            "valueStylesSha256" => {
                *value = Json::str(sha256_hex(stable_stringify(&empty_styles).as_bytes()));
                present[1] = true;
            }
            "entries" => {
                *value = Json::Arr(contract_entries.clone());
                present[2] = true;
            }
            _ => {}
        }
    }
    fields.push(("entrySource".to_string(), Json::str("font-contract-v1")));
    if !present[0] {
        fields.push(("valueStyles".to_string(), empty_styles.clone()));
    }
    if !present[1] {
        fields.push((
            "valueStylesSha256".to_string(),
            Json::str(sha256_hex(stable_stringify(&empty_styles).as_bytes())),
        ));
    }
    if !present[2] {
        fields.push(("entries".to_string(), Json::Arr(contract_entries)));
    }
    Ok(Json::Obj(fields))
}

/// `clientFontContractManifest` against finalized snapshot tables (ADR 0052
/// schema 2): same per-face coverage unions and deduped probes, with faces and
/// probes resolved through the frozen table. The walk reads the prepared
/// corpus because coverage text and probes live on the source faces, not on
/// the compact entries; the entry marker stays the literal the runtime gates
/// on. A face or probe the absorb pass missed surfaces as a named error that
/// carries the entry key.
fn client_font_contract_manifest_with_tables(
    entries: &[Json],
    font_contract_entries: &[Json],
    tables: &SnapshotTables,
    manifest: &Json,
) -> Result<Json, NamedError> {
    struct Group {
        face_index: usize,
        coverage: Vec<char>,
        probes: Vec<Option<usize>>,
    }
    let mut groups: Vec<Group> = Vec::new();
    let mut group_indexes: HashMap<usize, usize> = HashMap::new();
    for entry in entries.iter().chain(font_contract_entries) {
        let entry_key = key_string_of(entry);
        let faces_list = field(entry, "fontEvidence")
            .and_then(|value| arr_of(field(value, "faces")))
            .unwrap_or(&[]);
        for face in faces_list {
            let face_index = match tables.face_ref(face, &entry_key) {
                Ok(index) => index,
                Err(error) => return Err(annotate_missing(error, &entry_key)),
            };
            let index = match group_indexes.get(&face_index) {
                Some(&index) => index,
                None => {
                    groups.push(Group {
                        coverage: Vec::new(),
                        face_index,
                        probes: Vec::new(),
                    });
                    group_indexes.insert(face_index, groups.len() - 1);
                    groups.len() - 1
                }
            };
            let group = &mut groups[index];
            let coverage_text = match field(face, "coverageText") {
                Some(Json::Str(text)) if !text.is_empty() => Some(text.clone()),
                _ => field(face, "probe")
                    .and_then(|probe| field(probe, "text"))
                    .and_then(|text| match text {
                        Json::Str(text) if !text.is_empty() => Some(text.clone()),
                        _ => None,
                    }),
            };
            if let Some(text) = coverage_text {
                for point in text.chars() {
                    if !group.coverage.contains(&point) {
                        group.coverage.push(point);
                    }
                }
            }
            // A probeless face keeps one row without a probe reference,
            // mirroring the schema-1 contract.
            let probe_index = match field(face, "probe") {
                Some(probe) => match tables.probe_ref(probe) {
                    Ok(index) => Some(index),
                    Err(error) => return Err(annotate_missing(error, &entry_key)),
                },
                None => None,
            };
            if !group.probes.contains(&probe_index) {
                group.probes.push(probe_index);
            }
        }
    }
    let mut contract_entries: Vec<Json> = Vec::new();
    for group in &groups {
        for probe_index in &group.probes {
            let mut evidence_row = vec![
                ("faceRef".to_string(), index_number(group.face_index)?),
                (
                    "coverageText".to_string(),
                    Json::str(group.coverage.iter().collect::<String>()),
                ),
            ];
            if let Some(index) = probe_index {
                evidence_row.push(("probeRef".to_string(), index_number(*index)?));
            }
            contract_entries.push(Json::Obj(vec![
                (
                    "key".to_string(),
                    Json::str(format!("font-contract-{}", contract_entries.len())),
                ),
                ("sourceSha256".to_string(), Json::str("0".repeat(64))),
                ("typographyRef".to_string(), Json::Num(0.0)),
                ("maxWidthPx".to_string(), Json::Num(1.0)),
                (
                    "fontFaceEvidence".to_string(),
                    Json::Arr(vec![Json::Obj(evidence_row)]),
                ),
                (
                    "renderArtifactSha256".to_string(),
                    Json::str("0".repeat(64)),
                ),
            ]));
        }
    }
    if contract_entries.is_empty() {
        return Err(named("SnapshotClientFontContractEmpty"));
    }
    // The schema-2 client manifest drops fontContractEntries and replaces the
    // entries; value styles stay table-scoped, and the table reference passes
    // through so the client resolves probe rows by index.
    let mut fields: Vec<(String, Json)> = match manifest {
        Json::Obj(fields) => fields
            .iter()
            .filter(|(name, _)| name != "fontContractEntries")
            .cloned()
            .collect(),
        _ => Vec::new(),
    };
    let mut has_entries = false;
    for (name, value) in fields.iter_mut() {
        if name == "entries" {
            *value = Json::Arr(contract_entries.clone());
            has_entries = true;
            break;
        }
    }
    fields.push(("entrySource".to_string(), Json::str("font-contract-v1")));
    if !has_entries {
        fields.push(("entries".to_string(), Json::Arr(contract_entries)));
    }
    Ok(Json::Obj(fields))
}

/// `preparedLocale`: a string typography is the locale itself, an object
/// carries the locale field, anything nullish falls back to the default.
fn prepared_locale(typography: Option<&Json>) -> String {
    match typography {
        Some(Json::Str(text)) => text.clone(),
        Some(value) => match field(value, "locale") {
            Some(Json::Str(text)) => text.clone(),
            Some(Json::Num(value)) => js_number_string(*value),
            Some(Json::Bool(value)) => value.to_string(),
            _ => DEFAULT_LOCALE.to_string(),
        },
        None => DEFAULT_LOCALE.to_string(),
    }
}

/// `^[A-Za-z][A-Za-z0-9_-]*$`: the template id grammar.
fn valid_template_id(id: &str) -> bool {
    let mut bytes = id.bytes();
    match bytes.next() {
        Some(byte) if byte.is_ascii_alphabetic() => {}
        _ => return false,
    }
    bytes.all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
}

/// `index.toString(36)` of the non-negative class indexes.
fn to_string_36(index: usize) -> String {
    const DIGITS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    // The digit table holds ascii, so char::from is total on each byte.
    let mut digits: Vec<char> = Vec::new();
    let mut value = index;
    loop {
        digits.push(char::from(DIGITS[value % 36]));
        value /= 36;
        if value == 0 {
            break;
        }
    }
    digits.reverse();
    digits.into_iter().collect()
}

fn escape_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn escape_attribute(value: &str) -> String {
    escape_text(value).replace('"', "&quot;")
}

fn css_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

/// `exactRenderFontStyle`: the kerning contract of exact render fonts.
fn exact_render_font_style(id: &str) -> String {
    let root = format!(
        ":is(tiqian-prose,[data-tiqian-root])[snapshot-ref={}]",
        css_string(id)
    );
    let prepared = format!(
        "{root}[data-tiqian-exact-render-font=true]:not([data-tiqian-exact-layout-fallback]) [data-tq-rendered=true]:is([data-tq-canonical-plain=true],[data-tq-exact-prepared-dom=true])"
    );
    format!("{prepared}{{font-kerning:normal!important;font-optical-sizing:none!important}}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::parse_json;
    use crate::schema::FONT_REPLAY_REVISION;

    #[test]
    fn base36_strings_match_js_tostring36() {
        assert_eq!(to_string_36(0), "0");
        assert_eq!(to_string_36(9), "9");
        assert_eq!(to_string_36(10), "a");
        assert_eq!(to_string_36(35), "z");
        assert_eq!(to_string_36(36), "10");
        assert_eq!(to_string_36(71), "1z");
    }

    #[test]
    fn template_id_grammar_rejects_leading_digits_and_spaces() {
        assert!(valid_template_id("tq-page"));
        assert!(valid_template_id("A"));
        assert!(valid_template_id("a-b_C9"));
        assert!(!valid_template_id("1abc"));
        assert!(!valid_template_id("ab cd"));
        assert!(!valid_template_id("-abc"));
        assert!(!valid_template_id(""));
    }

    #[test]
    fn one_shot_entries_reject_snapshot_tables() {
        let tables = SnapshotTables::new();
        let options = SnapshotBundleOptions {
            snapshot_tables: Some(&tables),
            ..SnapshotBundleOptions::new("")
        };
        let reject = |error: NamedError| {
            assert_eq!(error.0, "SnapshotTablesRequireSplitRender");
        };
        match render_snapshot_bundle(None, &options) {
            Ok(_) => panic!("bundle rejects tables"),
            Err(error) => reject(error),
        }
        match render_font_contract_bundle(None, &options) {
            Ok(_) => panic!("contract rejects tables"),
            Err(error) => reject(error),
        }
        match render_snapshot_template(None, &options) {
            Ok(_) => panic!("template rejects tables"),
            Err(error) => reject(error),
        }
    }

    #[test]
    fn bundle_data_round_trips_through_its_wire_form() {
        let data = SnapshotBundleData {
            id: "tq-page".to_string(),
            paragraph_selector: PLAIN_PARAGRAPH_SELECTOR.to_string(),
            render_font_families: vec![Json::str("Tiqian Serif")],
            rendered_entries: vec![Json::Obj(vec![
                ("key".to_string(), Json::str("p1")),
                ("html".to_string(), Json::str("<span>p</span>")),
            ])],
            font_contract_entries: Vec::new(),
            value_styles: vec!["font-weight:600".to_string()],
            used_value_style_indexes: vec![0, 2],
        };
        let wire = data.to_json().render();
        let restored = SnapshotBundleData::from_json(&parse_json(&wire).expect("wire form parses"))
            .expect("wire form restores");
        assert_eq!(restored.id, "tq-page");
        assert_eq!(restored.paragraph_selector, PLAIN_PARAGRAPH_SELECTOR);
        assert_eq!(restored.value_styles, vec!["font-weight:600".to_string()]);
        assert_eq!(restored.used_value_style_indexes, vec![0, 2]);
        assert_eq!(restored.rendered_entries.len(), 1);
    }

    #[test]
    fn bundle_data_wire_form_rejects_fractional_indexes() {
        let wire = Json::Obj(vec![
            ("id".to_string(), Json::str("tq-page")),
            (
                "paragraphSelector".to_string(),
                Json::str(PLAIN_PARAGRAPH_SELECTOR),
            ),
            ("renderFontFamilies".to_string(), Json::Arr(Vec::new())),
            ("renderedEntries".to_string(), Json::Arr(Vec::new())),
            ("fontContractEntries".to_string(), Json::Arr(Vec::new())),
            ("valueStyles".to_string(), Json::Arr(Vec::new())),
            (
                "usedValueStyleIndexes".to_string(),
                Json::Arr(vec![Json::Num(0.5)]),
            ),
        ]);
        let error = match SnapshotBundleData::from_json(&wire) {
            Ok(_) => panic!("fractional index rejects"),
            Err(error) => error,
        };
        assert_eq!(error.0, "SnapshotBundleDataInvalid");
    }

    fn contract_entry(key: &str, coverage: &str, probe_text: &str) -> Json {
        Json::Obj(vec![
            ("key".to_string(), Json::str(key)),
            (
                "fontEvidence".to_string(),
                Json::Obj(vec![
                    (
                        "faces".to_string(),
                        Json::Arr(vec![Json::Obj(vec![
                            ("family".to_string(), Json::str("serif")),
                            ("weight".to_string(), Json::Num(400.0)),
                            ("coverageText".to_string(), Json::str(coverage)),
                            (
                                "probe".to_string(),
                                Json::Obj(vec![
                                    ("text".to_string(), Json::str(probe_text)),
                                    ("advancePx".to_string(), Json::Num(16.0)),
                                    ("fontSizePx".to_string(), Json::Num(16.0)),
                                    ("fontWeight".to_string(), Json::Num(400.0)),
                                    ("italic".to_string(), Json::Bool(false)),
                                    ("script".to_string(), Json::str("hani")),
                                    ("language".to_string(), Json::str("ZH")),
                                    ("features".to_string(), Json::Arr(Vec::new())),
                                ]),
                            ),
                        ])]),
                    ),
                    (
                        "replay".to_string(),
                        Json::Obj(vec![
                            ("revision".to_string(), Json::str(FONT_REPLAY_REVISION)),
                            ("shapes".to_string(), Json::Arr(Vec::new())),
                            ("metrics".to_string(), Json::Arr(Vec::new())),
                        ]),
                    ),
                ]),
            ),
        ])
    }

    #[test]
    fn tables_client_contract_unions_coverage_and_references_probes() {
        let mut tables = SnapshotTables::new();
        let first = contract_entry("p1", "中文", "中");
        let second = contract_entry("p2", "文字", "字");
        tables
            .absorb_prepared(&Json::Arr(vec![first.clone(), second.clone()]))
            .expect("absorb succeeds");
        tables.finalize().expect("finalize succeeds");
        let manifest = Json::Obj(vec![
            ("entries".to_string(), Json::Arr(Vec::new())),
            (
                "tables".to_string(),
                Json::Obj(vec![(
                    "snapshot".to_string(),
                    Json::str(tables.sha256().unwrap_or("")),
                )]),
            ),
        ]);
        let client =
            client_font_contract_manifest_with_tables(&[first, second], &[], &tables, &manifest)
                .expect("client contract succeeds");
        // Both entries share one face row; each distinct probe keeps its own
        // contract entry, as in the schema-1 contract.
        let entries = arr_of(field(&client, "entries")).unwrap_or(&[]);
        assert_eq!(entries.len(), 2);
        let mut probe_refs: Vec<f64> = Vec::new();
        for entry in entries {
            let evidence = arr_of(field(entry, "fontFaceEvidence")).unwrap_or(&[]);
            assert_eq!(evidence.len(), 1);
            let row = &evidence[0];
            assert_eq!(field(row, "faceRef"), Some(&Json::Num(0.0)));
            let coverage = match field(row, "coverageText") {
                Some(Json::Str(text)) => text.clone(),
                _ => String::new(),
            };
            for point in ["中", "文", "字"] {
                assert!(coverage.contains(point));
            }
            match field(row, "probeRef") {
                Some(Json::Num(value)) => probe_refs.push(*value),
                _ => panic!("probe reference present"),
            }
        }
        assert_eq!(probe_refs, vec![0.0, 1.0]);
        assert_eq!(
            field(&client, "entrySource"),
            Some(&Json::str("font-contract-v1"))
        );
        assert!(field(&client, "tables").is_some());
        assert!(field(&client, "valueStyles").is_none());
    }

    #[test]
    fn tables_client_contract_keeps_a_row_for_a_probeless_face() {
        let mut tables = SnapshotTables::new();
        let stripped_entry = strip_probe(&contract_entry("p1", "中文", "中"));
        tables
            .absorb_prepared(&Json::Arr(vec![stripped_entry.clone()]))
            .expect("absorb succeeds");
        tables.finalize().expect("finalize succeeds");
        let client = client_font_contract_manifest_with_tables(
            &[stripped_entry],
            &[],
            &tables,
            &Json::Obj(Vec::new()),
        )
        .expect("client contract succeeds");
        let entries = arr_of(field(&client, "entries")).unwrap_or(&[]);
        assert_eq!(entries.len(), 1);
        let evidence = arr_of(field(&entries[0], "fontFaceEvidence")).unwrap_or(&[]);
        assert!(field(&evidence[0], "probeRef").is_none());
        assert!(field(&evidence[0], "coverageText").is_some());
    }

    #[test]
    fn tables_client_contract_names_the_entry_that_missed_the_table() {
        let mut tables = SnapshotTables::new();
        tables.finalize().expect("finalize succeeds");
        let stray = contract_entry("p9", "中", "中");
        let error = client_font_contract_manifest_with_tables(
            &[stray],
            &[],
            &tables,
            &Json::Obj(Vec::new()),
        )
        .expect_err("face missed the absorb pass");
        assert_eq!(error.0, "SnapshotTableFaceMissing:p9");
    }

    fn strip_probe(entry: &Json) -> Json {
        let Json::Obj(fields) = entry else {
            return entry.clone();
        };
        let mut rebuilt: Vec<(String, Json)> = Vec::new();
        for (name, value) in fields {
            if name == "fontEvidence" {
                let Json::Obj(evidence_fields) = value else {
                    rebuilt.push((name.clone(), value.clone()));
                    continue;
                };
                let mut evidence_rebuilt: Vec<(String, Json)> = Vec::new();
                for (evidence_name, evidence_value) in evidence_fields {
                    if evidence_name == "faces" {
                        let Json::Arr(faces) = evidence_value else {
                            evidence_rebuilt.push((evidence_name.clone(), evidence_value.clone()));
                            continue;
                        };
                        let mut stripped_faces: Vec<Json> = Vec::new();
                        for face in faces {
                            let Json::Obj(face_fields) = face else {
                                stripped_faces.push(face.clone());
                                continue;
                            };
                            stripped_faces.push(Json::Obj(
                                face_fields
                                    .iter()
                                    .filter(|(face_name, _)| face_name != "probe")
                                    .cloned()
                                    .collect(),
                            ));
                        }
                        evidence_rebuilt.push(("faces".to_string(), Json::Arr(stripped_faces)));
                    } else {
                        evidence_rebuilt.push((evidence_name.clone(), evidence_value.clone()));
                    }
                }
                rebuilt.push(("fontEvidence".to_string(), Json::Obj(evidence_rebuilt)));
            } else {
                rebuilt.push((name.clone(), value.clone()));
            }
        }
        Json::Obj(rebuilt)
    }
}
