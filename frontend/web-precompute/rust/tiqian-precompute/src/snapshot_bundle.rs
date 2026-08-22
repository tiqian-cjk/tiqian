//! Snapshot bundle assembly of `buildSnapshotBundle` in `precompute.js`
//! (ADR 0050). The bundle layer re-renders every prepared paragraph with the
//! shared `tqv-` value-style classes, compacts the manifest tables, and emits
//! the inert server template plus the client font-contract template.
//!
//! The js module keeps the three public entry points for Node callers; this
//! port serves the native precompute package with byte-identical templates.
//! The shared runtime style stays a caller parameter so the crate ships
//! without reading package files. Damage js reports with a raw `TypeError`
//! (a non-array paragraph list) surfaces with `MissingPreparedParagraphs`;
//! re-render damage keeps the named issues of the prepared DOM lowering.

use std::collections::HashMap;

use tiqian::NamedError;

use crate::font_source::sha256_hex;
use crate::js_compat::{js_int_to_number, js_number_string, js_trim};
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
/// because the crate never reads the package stylesheet itself.
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

/// `renderSnapshotBundle`: the inert prepared-DOM template plus the compact
/// manifests used by server and client-navigation adapters.
pub fn render_snapshot_bundle(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    let entries = array_input(prepared_paragraphs)?;
    let font_contract_entries = array_input(options.font_contract_paragraphs)?;
    build_snapshot_bundle(
        &entries,
        &font_contract_entries,
        options,
        PLAIN_PARAGRAPH_SELECTOR,
    )
}

/// `renderFontContractBundle`: the compact exact-font contract for roots that
/// keep their semantic source DOM and lay out in the browser.
pub fn render_font_contract_bundle(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<SnapshotBundle, NamedError> {
    let entries = array_input(prepared_paragraphs)?;
    let font_contract_entries = array_input(options.font_contract_paragraphs)?;
    let mut bundle = build_snapshot_bundle(
        &entries,
        &font_contract_entries,
        options,
        RUNTIME_PARAGRAPH_SELECTOR,
    )?;
    bundle.template = bundle.client_template.clone();
    bundle.inert_template = bundle.client_template.clone();
    bundle.initial_style = exact_render_font_style(&bundle.id);
    bundle.root_attributes = Json::Obj(Vec::new());
    bundle.entries = Json::Arr(Vec::new());
    Ok(bundle)
}

/// `renderSnapshotTemplate`: the inert template alone.
pub fn render_snapshot_template(
    prepared_paragraphs: Option<&Json>,
    options: &SnapshotBundleOptions,
) -> Result<String, NamedError> {
    let entries = array_input(prepared_paragraphs)?;
    let font_contract_entries = array_input(options.font_contract_paragraphs)?;
    build_snapshot_bundle(
        &entries,
        &font_contract_entries,
        options,
        PLAIN_PARAGRAPH_SELECTOR,
    )
    .map(|bundle| bundle.inert_template)
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

/// `buildSnapshotBundle`: the shared core of the three entry points.
fn build_snapshot_bundle(
    entries: &[Json],
    font_contract_entries: &[Json],
    options: &SnapshotBundleOptions,
    supported_paragraph_selector: &str,
) -> Result<SnapshotBundle, NamedError> {
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
    let mut style_class_for = |declaration: &str| -> String {
        if let Some(&index) = value_style_indexes.get(declaration) {
            return format!("tqv-{}", to_string_36(index));
        }
        let index = value_styles.len();
        value_styles.push(declaration.to_string());
        value_style_indexes.insert(declaration.to_string(), index);
        format!("tqv-{}", to_string_36(index))
    };
    let mut rendered_entries: Vec<Json> = Vec::with_capacity(entries.len());
    let mut rendered_pairs: Vec<(String, String)> = Vec::with_capacity(entries.len());
    for entry in entries {
        let plan_json = match field(entry, "plan") {
            Some(Json::Str(text)) => text.clone(),
            Some(other) => other.render(),
            None => return Err(named("InvalidPreparedParagraphGeometry")),
        };
        let locale = prepared_locale(field(entry, "typography"));
        let mut render_options = PreparedRenderOptions::new();
        render_options.style_class_for = Some(&mut style_class_for);
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
        let key = js_string_value(field(entry, "key").unwrap_or(&Json::Null));
        rendered_pairs.push((key, rendered.html.clone()));
        rendered_entries.push(Json::Obj(fields));
    }

    let value_styles_json = Json::Arr(value_styles.iter().map(|item| Json::str(item)).collect());
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
            Json::str(paragraph_selector),
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
    let mut corpus_entries = rendered_entries.clone();
    corpus_entries.extend(font_contract_entries.iter().cloned());
    let (manifest, client_manifest) = match options.snapshot_tables {
        Some(tables) => {
            let compact = compact_snapshot_manifest_with_tables(
                &Json::Arr(corpus_entries),
                &metadata,
                tables,
            )?;
            let manifest = if font_contract_entries.is_empty() {
                compact
            } else {
                split_contract_entries(compact, rendered_entries.len())
            };
            // The schema-2 walk reads the prepared corpus: coverage text and
            // probes left the compact entries but stay on the source faces.
            let client = client_font_contract_manifest_with_tables(
                entries,
                font_contract_entries,
                tables,
                &manifest,
            )?;
            (manifest, client)
        }
        None => {
            let compact = compact_snapshot_manifest(&Json::Arr(corpus_entries), &metadata)?;
            let manifest = if font_contract_entries.is_empty() {
                compact
            } else {
                split_contract_entries(compact, rendered_entries.len())
            };
            let client = client_font_contract_manifest(&manifest)?;
            (manifest, client)
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
        escape_attribute(&id),
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
        escape_attribute(&id),
        SNAPSHOT_SCHEMA,
        LAYOUT_REVISION,
        RENDER_REVISION,
        client_manifest_json,
    );
    // The line strut, geometry reset, and nowrap contract of the prepared DOM
    // belong in the server-injected first-paint style as well.
    let mut initial_style = String::from(options.shared_runtime_style);
    initial_style.push_str(&exact_render_font_style(&id));
    for (index, declaration) in value_styles.iter().enumerate() {
        initial_style.push_str(&format!(
            "tiqian-prose[snapshot-ref=\"{}\"] [data-tq-rendered=\"true\"] .tqv-{}{{{}}}",
            escape_attribute(&id),
            to_string_36(index),
            declaration,
        ));
    }
    Ok(SnapshotBundle {
        id,
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
                                    ("sizePx".to_string(), Json::Num(16.0)),
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
