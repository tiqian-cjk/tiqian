//! The precompute and precompute-html export lanes (ADR 0050). Flat
//! arguments in, JSON strings out: the wrapper owns every js object shape,
//! these calls carry the same values the js entry points exchange with their
//! callers. `prepareHtml` and `prepareParagraphs` are the batch entries; the
//! paragraph loops stay inside Rust.

use neon::prelude::*;
use neon::types::buffer::TypedArray;

use tiqian_precompute::build_fonts::StylesheetFace;
use tiqian_precompute::cache::WriteBudgetTier;
use tiqian_precompute::font_record::FontWeightSpec;
use tiqian_precompute::js_compat::js_int_to_number;
use tiqian_precompute::json::{member, parse_json, Json};
use tiqian_precompute::normalize::TypographyInput;
use tiqian_precompute::precompute_html::{
    HtmlPrepareOptions, HtmlPreparerOptions, SnapshotServerAssets,
};
use tiqian_precompute::precomputer::{Precomputer, PrecomputerOptions, PrepareInput};
use tiqian_precompute::snapshot_bundle::{
    SnapshotBundle, SnapshotBundleData, SnapshotBundleOptions,
};
use tiqian_precompute::snapshot_source::js_string_value;
use tiqian_precompute::snapshot_tables::SnapshotTables;
use tiqian_precompute::NamedError;

use crate::calls::{read_face_arguments, session_face_specs};
use crate::registry;

/// Parses one JSON string argument; the wrapper serializes every structured
/// value, so a parse failure is a wrapper bug and reports as one.
fn json_argument(cx: &mut FunctionContext, index: usize, name: &str) -> NeonResult<Json> {
    let text = cx.argument::<JsString>(index)?.value(cx);
    match parse_json(&text) {
        Ok(value) => Ok(value),
        Err(_) => cx.throw_error(format!("InvalidJsonArgument:{name}")),
    }
}

fn member_str<'a>(value: &'a Json, name: &str) -> Option<&'a str> {
    match member(value, name) {
        Some(Json::Str(inner)) => Some(inner),
        _ => None,
    }
}

fn member_string(value: &Json, name: &str) -> String {
    member(value, name).map(js_string_value).unwrap_or_default()
}

/// `normalizeTypography(typographyJson)`: the first js step of the create
/// calls. The wrapper calls it before reading any font file, so a bad
/// typography reports its named issue first, the js order; the create calls
/// normalize the same value again behind their own boundary.
pub fn normalize_typography(mut cx: FunctionContext) -> JsResult<JsString> {
    let typography = TypographyInput::from_json(&json_argument(&mut cx, 0, "typography")?);
    match tiqian_precompute::normalize::normalize_typography(typography) {
        Ok(normalized) => Ok(
            cx.string(tiqian_precompute::precomputer::typography_value_json(&normalized).render())
        ),
        Err(error) => cx.throw_error(error.0),
    }
}

/// `createPrecomputer(typographyJson, faces, sources, budgetCode?)`: registers
/// the precomputer and returns its handle.
pub fn create_precomputer(mut cx: FunctionContext) -> JsResult<JsString> {
    let typography = TypographyInput::from_json(&json_argument(&mut cx, 0, "typography")?);
    let faces = cx.argument::<JsArray>(1)?;
    let sources = cx.argument::<JsArray>(2)?;
    let (owned, fonts) = read_face_arguments(&mut cx, &faces, &sources)?;
    let specs = session_face_specs(&owned, &fonts);
    let mut options = PrecomputerOptions::new(typography, specs);
    options.write_budget = write_budget_argument(&mut cx, 3)?;
    match tiqian_precompute::precomputer::create_precomputer(options) {
        Ok(precomputer) => {
            let (handle, _) = registry::insert_precomputer(precomputer);
            Ok(cx.string(handle))
        }
        Err(error) => cx.throw_error(error.0),
    }
}

/// The optional `budgetCode` argument: a write-budget tier code. Absent or
/// undefined means `Normal`; the ts layer validates names, so an unknown code
/// here is a wrapper bug and reports as one.
fn write_budget_argument(cx: &mut FunctionContext, index: usize) -> NeonResult<WriteBudgetTier> {
    let Some(value) = cx.argument_opt(index) else {
        return Ok(WriteBudgetTier::Normal);
    };
    if value.is_a::<JsNull, _>(cx) || value.is_a::<JsUndefined, _>(cx) {
        return Ok(WriteBudgetTier::Normal);
    }
    let code = value.downcast_or_throw::<JsNumber, _>(cx)?.value(cx);
    // Whole-number comparison keeps NaN and fractions on the error arm
    // without any saturation cast.
    let tier = if code == 0.0 {
        WriteBudgetTier::Tight
    } else if code == 1.0 {
        WriteBudgetTier::Normal
    } else if code == 2.0 {
        WriteBudgetTier::Generous
    } else {
        return cx.throw_error(format!("UnknownWriteBudgetCode:{code}"));
    };
    Ok(tier)
}

/// `precomputerInfo(handle)`: the normalized typography and the resolved
/// render families of one precomputer.
pub fn precomputer_info(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let info = registry::with_precomputer(&handle, |precomputer| {
        Json::Obj(vec![
            (
                "typography".to_string(),
                tiqian_precompute::precomputer::typography_value_json(precomputer.typography()),
            ),
            (
                "renderFontFamilies".to_string(),
                Json::Arr(
                    precomputer
                        .render_font_families()
                        .iter()
                        .map(|family| Json::str(family.clone()))
                        .collect(),
                ),
            ),
        ])
    });
    match info {
        Ok(json) => Ok(cx.string(json.render())),
        Err(error) => cx.throw_error(error),
    }
}

fn prepare_entry<'a>(
    cx: &mut FunctionContext<'a>,
    call: impl Fn(&Precomputer, &PrepareInput) -> Result<Json, NamedError>,
) -> JsResult<'a, JsString> {
    let handle = cx.argument::<JsString>(0)?.value(cx);
    let input = json_argument(cx, 1, "input")?;
    let prepared = PrepareInput::from_json(&input);
    let result = registry::with_precomputer(&handle, |precomputer| call(precomputer, &prepared));
    match result {
        Ok(Ok(entry)) => Ok(cx.string(entry.render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `prepareParagraph(handle, inputJson)`: the snapshot lane of one paragraph.
pub fn prepare_paragraph(mut cx: FunctionContext) -> JsResult<JsString> {
    prepare_entry(&mut cx, |precomputer, input| {
        precomputer.prepare_paragraph(input)
    })
}

/// `prepareFontContract(handle, inputJson)`: the contract lane of one
/// paragraph, including the CJK dash retry.
pub fn prepare_font_contract(mut cx: FunctionContext) -> JsResult<JsString> {
    prepare_entry(&mut cx, |precomputer, input| {
        precomputer.prepare_font_contract(input)
    })
}

/// `prepareFontContracts(handle, inputsJson)`: the batch contract lane. One
/// call prepares every contract in input order; the loop stays here and
/// spreads over the configured workers. Each item owns its capture window
/// and its CJK dash retry, so the entries match the singular lane byte for
/// byte.
pub fn prepare_font_contracts(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let inputs = json_argument(&mut cx, 1, "inputs")?;
    let Json::Arr(items) = &inputs else {
        return cx.throw_error("InvalidJsonArgument:inputs");
    };
    let prepared_inputs: Vec<PrepareInput> = items.iter().map(PrepareInput::from_json).collect();
    let result = registry::with_precomputer(&handle, |precomputer| {
        precomputer.prepare_font_contracts(&prepared_inputs)
    });
    match result {
        Ok(Ok(entries)) => Ok(cx.string(Json::Arr(entries).render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `prepareParagraphs(handle, inputsJson)`: the batch snapshot lane. One
/// call prepares every paragraph in input order; the loop stays here and
/// spreads over the configured workers. Each paragraph owns its capture
/// window, so the entries match the singular lane byte for byte.
pub fn prepare_paragraphs(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let inputs = json_argument(&mut cx, 1, "inputs")?;
    let Json::Arr(items) = &inputs else {
        return cx.throw_error("InvalidJsonArgument:inputs");
    };
    let prepared_inputs: Vec<PrepareInput> = items.iter().map(PrepareInput::from_json).collect();
    let result = registry::with_precomputer(&handle, |precomputer| {
        precomputer.prepare_paragraphs(&prepared_inputs)
    });
    match result {
        Ok(Ok(entries)) => Ok(cx.string(Json::Arr(entries).render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `closePrecomputer(handle)`: idempotent, the entry stays addressable.
pub fn close_precomputer(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_precomputer(&handle, |precomputer| precomputer.close()) {
        Ok(()) => Ok(cx.undefined()),
        Err(error) => cx.throw_error(error),
    }
}

/// `createHtmlPreparer(precomputerHandle, typographyJson, faces, sources,
/// paragraphSelector, skippedAncestorSelector, sharedRuntimeStyle)`: the
/// precomputer comes from the registry when the handle is present, otherwise
/// one is created from the typography and faces; the shared lane reads null
/// typography and empty arrays. Creation runs before the selectors validate,
/// the js order.
pub fn create_html_preparer(mut cx: FunctionContext) -> JsResult<JsString> {
    let precomputer_handle = crate::calls::optional_string(&mut cx, 0)?;
    let shared = match precomputer_handle {
        Some(handle) => match registry::shared_precomputer(&handle) {
            Ok(shared) => Some(shared),
            Err(error) => return cx.throw_error(error),
        },
        None => None,
    };
    let typography_json = json_argument(&mut cx, 1, "typography")?;
    let faces = cx.argument::<JsArray>(2)?;
    let sources = cx.argument::<JsArray>(3)?;
    let (owned, fonts) = read_face_arguments(&mut cx, &faces, &sources)?;
    let paragraph_selector = crate::calls::optional_string(&mut cx, 4)?;
    let skipped_ancestor_selector = crate::calls::optional_string(&mut cx, 5)?;
    let shared_runtime_style = cx.argument::<JsString>(6)?.value(&mut cx);
    let options = HtmlPreparerOptions {
        precomputer: shared,
        create: PrecomputerOptions::new(
            TypographyInput::from_json(&typography_json),
            session_face_specs(&owned, &fonts),
        ),
        paragraph_selector: paragraph_selector.as_deref(),
        skipped_ancestor_selector: skipped_ancestor_selector.as_deref(),
        shared_runtime_style: &shared_runtime_style,
        projector: None,
    };
    match tiqian_precompute::precompute_html::create_html_preparer(options) {
        Ok(preparer) => Ok(cx.string(registry::insert_preparer(preparer))),
        Err(error) => cx.throw_error(error.0),
    }
}

/// `prepareHtml(handle, html, optionsJson)`: the whole document in one call;
/// the paragraph loop stays inside Rust. Returns `{result, tablesBytes,
/// tablesSha256}`: the result object as json plus the station-table file the
/// emitted manifest pins, when the document produced one.
pub fn prepare_html(mut cx: FunctionContext) -> JsResult<JsObject> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let html = cx.argument::<JsString>(1)?.value(&mut cx);
    let options_json = json_argument(&mut cx, 2, "options")?;
    let options = HtmlPrepareOptions {
        id: member_str(&options_json, "id"),
        snapshot_max_width_px: member(&options_json, "snapshot")
            .and_then(|snapshot| member(snapshot, "maxWidthPx")),
    };
    let result = registry::with_preparer(&handle, |preparer| preparer.prepare(&html, &options));
    let (value, tables) = match result {
        Ok(Ok(prepared)) => prepared,
        Ok(Err(error)) => return cx.throw_error(error.0),
        Err(error) => return cx.throw_error(error),
    };
    let object = JsObject::new(&mut cx);
    let result = cx.string(value.render());
    object.set(&mut cx, "result", result)?;
    match tables {
        Some(file) => {
            let bytes = JsBuffer::from_slice(&mut cx, &file.bytes)?;
            let sha = cx.string(file.sha256);
            object.set(&mut cx, "tablesBytes", bytes)?;
            object.set(&mut cx, "tablesSha256", sha)?;
        }
        None => {
            let empty_bytes = cx.null();
            object.set(&mut cx, "tablesBytes", empty_bytes)?;
            let empty_sha = cx.undefined();
            object.set(&mut cx, "tablesSha256", empty_sha)?;
        }
    }
    Ok(object)
}

/// `closeHtmlPreparer(handle)`: closes the owned precomputer with it; a
/// shared one stays open for its other holders.
pub fn close_html_preparer(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_preparer(&handle, |preparer| preparer.close()) {
        Ok(()) => Ok(cx.undefined()),
        Err(error) => cx.throw_error(error),
    }
}

/// `htmlPreparerInfo(handle)`: the normalized typography of the preparer's
/// precomputer, for the wrapper's `typography` property.
pub fn html_preparer_info(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let info = registry::with_preparer(&handle, |preparer| {
        Json::Obj(vec![(
            "typography".to_string(),
            tiqian_precompute::precomputer::typography_value_json(&preparer.typography()),
        )])
    });
    match info {
        Ok(json) => Ok(cx.string(json.render())),
        Err(error) => cx.throw_error(error),
    }
}

fn bundle_options<'a>(options: &'a Json, style: &'a str) -> SnapshotBundleOptions<'a> {
    SnapshotBundleOptions {
        id: member_str(options, "id"),
        paragraph_selector: member_str(options, "paragraphSelector"),
        font_contract_paragraphs: member(options, "fontContractParagraphs")
            .filter(|value| !matches!(value, Json::Null)),
        shared_runtime_style: style,
    }
}

/// Resolves the `snapshotTables` option for a data phase call: the tables
/// stay mutable while every article of the build renders.
fn run_data_call(
    options_json: &Json,
    style: &str,
    render: impl FnOnce(
        &SnapshotBundleOptions,
        &mut SnapshotTables,
    ) -> Result<SnapshotBundleData, NamedError>,
) -> Result<Result<SnapshotBundleData, NamedError>, String> {
    match member_str(options_json, "snapshotTables") {
        Some(handle) => registry::with_snapshot_tables(handle, |tables| {
            render(&bundle_options(options_json, style), tables)
        }),
        None => Err("SnapshotTablesMissing".to_string()),
    }
}

/// Resolves the `snapshotTables` option for an assembly call: the tables are
/// frozen, and the compaction verifies the content hash.
fn run_assemble_call<T>(
    options_json: &Json,
    style: &str,
    assemble: impl FnOnce(&SnapshotBundleOptions, &SnapshotTables) -> Result<T, NamedError>,
) -> Result<Result<T, NamedError>, String> {
    match member_str(options_json, "snapshotTables") {
        Some(handle) => registry::with_snapshot_tables(handle, |tables| {
            assemble(&bundle_options(options_json, style), tables)
        }),
        None => Err("SnapshotTablesMissing".to_string()),
    }
}

fn bundle_argument(mut cx: &mut FunctionContext, index: usize) -> NeonResult<SnapshotBundleData> {
    let data_json = json_argument(&mut cx, index, "data")?;
    match SnapshotBundleData::from_json(&data_json) {
        Ok(data) => Ok(data),
        Err(error) => cx.throw_error(error.0),
    }
}

/// `renderSnapshotBundleData(preparedParagraphsJson, optionsJson,
/// sharedRuntimeStyle)`: the data phase of the split render; the host holds
/// the returned json until every article rendered and the table froze.
pub fn render_snapshot_bundle_data(mut cx: FunctionContext) -> JsResult<JsString> {
    let prepared = json_argument(&mut cx, 0, "preparedParagraphs")?;
    let options_json = json_argument(&mut cx, 1, "options")?;
    let style = cx.argument::<JsString>(2)?.value(&mut cx);
    match run_data_call(&options_json, &style, |options, tables| {
        tiqian_precompute::snapshot_bundle::render_snapshot_bundle_data(
            Some(&prepared),
            options,
            tables,
        )
    }) {
        Ok(Ok(data)) => Ok(cx.string(data.to_json().render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `renderFontContractBundleData(preparedParagraphsJson, optionsJson,
/// sharedRuntimeStyle)`: the data phase for font-contract bundles.
pub fn render_font_contract_bundle_data(mut cx: FunctionContext) -> JsResult<JsString> {
    let prepared = json_argument(&mut cx, 0, "preparedParagraphs")?;
    let options_json = json_argument(&mut cx, 1, "options")?;
    let style = cx.argument::<JsString>(2)?.value(&mut cx);
    match run_data_call(&options_json, &style, |options, tables| {
        tiqian_precompute::snapshot_bundle::render_font_contract_bundle_data(
            Some(&prepared),
            options,
            tables,
        )
    }) {
        Ok(Ok(data)) => Ok(cx.string(data.to_json().render())),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `assembleSnapshotBundle(dataJson, optionsJson, sharedRuntimeStyle)`: the
/// assembly phase of the split render.
pub fn assemble_snapshot_bundle(mut cx: FunctionContext) -> JsResult<JsString> {
    let data = bundle_argument(&mut cx, 0)?;
    let options_json = json_argument(&mut cx, 1, "options")?;
    let style = cx.argument::<JsString>(2)?.value(&mut cx);
    match run_assemble_call(&options_json, &style, |options, tables| {
        tiqian_precompute::snapshot_bundle::assemble_snapshot_bundle(&data, options, tables)
    }) {
        Ok(Ok(bundle)) => {
            Ok(cx.string(tiqian_precompute::precompute_html::bundle_json(&bundle).render()))
        }
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `assembleFontContractBundle(dataJson, optionsJson, sharedRuntimeStyle)`.
pub fn assemble_font_contract_bundle(mut cx: FunctionContext) -> JsResult<JsString> {
    let data = bundle_argument(&mut cx, 0)?;
    let options_json = json_argument(&mut cx, 1, "options")?;
    let style = cx.argument::<JsString>(2)?.value(&mut cx);
    match run_assemble_call(&options_json, &style, |options, tables| {
        tiqian_precompute::snapshot_bundle::assemble_font_contract_bundle(&data, options, tables)
    }) {
        Ok(Ok(bundle)) => {
            Ok(cx.string(tiqian_precompute::precompute_html::bundle_json(&bundle).render()))
        }
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `createSnapshotTables()`: an empty, unfrozen snapshot-table set for one
/// build.
pub fn create_snapshot_tables(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = registry::insert_snapshot_tables(SnapshotTables::new());
    Ok(cx.string(handle))
}

/// `restoreSnapshotTables(bytes)`: restores a previous build's frozen binary
/// table so an incremental rebuild appends to the union under one URL.
pub fn restore_snapshot_tables(mut cx: FunctionContext) -> JsResult<JsString> {
    let bytes = cx.argument::<JsBuffer>(0)?.as_slice(&cx).to_vec();
    match SnapshotTables::from_binary(&bytes) {
        Ok(tables) => Ok(cx.string(registry::insert_snapshot_tables(tables))),
        Err(error) => cx.throw_error(error.0),
    }
}

/// `absorbSnapshotTables(handle, preparedJson)`: absorbs one batch of prepared
/// entries into the table; returns the absorbed entry count.
pub fn absorb_snapshot_tables(mut cx: FunctionContext) -> JsResult<JsNumber> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let prepared = json_argument(&mut cx, 1, "prepared")?;
    match registry::with_snapshot_tables(&handle, |tables| tables.absorb_prepared(&prepared)) {
        Ok(Ok(count)) => match i64::try_from(count) {
            // Entry counts stay far below the i64 bound; the arm only names
            // the conversion for the wire report.
            Ok(value) => Ok(cx.number(js_int_to_number(value))),
            Err(_) => cx.throw_error("SnapshotTablesCountConversion"),
        },
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `absorbSnapshotTablesMetadata(handle, metadataJson)`: absorbs the
/// table-scoped render metadata of one build.
pub fn absorb_snapshot_tables_metadata(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let metadata = json_argument(&mut cx, 1, "metadata")?;
    match registry::with_snapshot_tables(&handle, |tables| tables.absorb_metadata(&metadata)) {
        Ok(Ok(())) => Ok(cx.undefined()),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `finalizeSnapshotTables(handle)`: freezes the rows and returns
/// `{bytes, sha256}`; hosts serve the binary bytes verbatim under the sha
/// address.
pub fn finalize_snapshot_tables(mut cx: FunctionContext) -> JsResult<JsObject> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    match registry::with_snapshot_tables(&handle, |tables| tables.finalize()) {
        Ok(Ok(file)) => {
            let buffer = JsBuffer::from_slice(&mut cx, &file.bytes)?;
            let sha = cx.string(file.sha256);
            let result = JsObject::new(&mut cx);
            result.set(&mut cx, "bytes", buffer)?;
            result.set(&mut cx, "sha256", sha)?;
            Ok(result)
        }
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `closeSnapshotTables(handle)`: drops the table set.
pub fn close_snapshot_tables(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    registry::remove_snapshot_tables(&handle);
    Ok(cx.undefined())
}

/// `snapshotPlainTextIssue(text)`: the named issue or null.
pub fn snapshot_plain_text_issue(mut cx: FunctionContext) -> JsResult<JsString> {
    let text = cx.argument::<JsString>(0)?.value(&mut cx);
    let issue = match tiqian_precompute::normalize::snapshot_plain_text_issue(&text) {
        Some(issue) => Json::str(issue),
        None => Json::Null,
    };
    Ok(cx.string(issue.render()))
}

/// `findHtmlOpeningTags(html, tagNamesJson)`.
pub fn find_html_opening_tags(mut cx: FunctionContext) -> JsResult<JsString> {
    let html = cx.argument::<JsString>(0)?.value(&mut cx);
    let names_json = json_argument(&mut cx, 1, "tagNames")?;
    let names: Vec<String> = match &names_json {
        Json::Arr(items) => items.iter().map(js_string_value).collect(),
        _ => Vec::new(),
    };
    let references: Vec<&str> = names.iter().map(String::as_str).collect();
    let tags = tiqian_precompute::precompute_html::find_html_opening_tags(&html, &references);
    let mut objects = Vec::with_capacity(tags.len());
    for tag in &tags {
        let end = match u32::try_from(tag.end) {
            Ok(end) => end,
            Err(_) => return cx.throw_error("HtmlOffsetOutOfRange"),
        };
        objects.push(Json::Obj(vec![
            ("end".to_string(), Json::Num(f64::from(end))),
            ("source".to_string(), Json::str(tag.source.clone())),
            ("tagName".to_string(), Json::str(tag.tag_name.clone())),
        ]));
    }
    let dumped = Json::Arr(objects);
    Ok(cx.string(dumped.render()))
}

/// `injectHtmlAttributes(html, insertionsJson)`.
pub fn inject_html_attributes(mut cx: FunctionContext) -> JsResult<JsString> {
    let html = cx.argument::<JsString>(0)?.value(&mut cx);
    let insertions = json_argument(&mut cx, 1, "insertions")?;
    match tiqian_precompute::precompute_html::inject_html_attributes(&html, Some(&insertions)) {
        Ok(result) => Ok(cx.string(result)),
        Err(error) => cx.throw_error(error.0),
    }
}

fn bundle_from_json(value: &Json) -> SnapshotBundle {
    SnapshotBundle {
        id: member_string(value, "id"),
        template: member_string(value, "template"),
        client_template: member_string(value, "clientTemplate"),
        inert_template: member_string(value, "inertTemplate"),
        initial_style: member_string(value, "initialStyle"),
        render_font_families: member(value, "renderFontFamilies")
            .cloned()
            .unwrap_or(Json::Null),
        font_preloads: member(value, "fontPreloads").cloned().unwrap_or(Json::Null),
        root_attributes: member(value, "rootAttributes")
            .cloned()
            .unwrap_or(Json::Null),
        entries: member(value, "entries").cloned().unwrap_or(Json::Null),
    }
}

/// `snapshotServerAssets(bundleJson | null)`.
pub fn snapshot_server_assets(mut cx: FunctionContext) -> JsResult<JsString> {
    let bundle = json_argument(&mut cx, 0, "bundle")?;
    let parsed = if matches!(bundle, Json::Null) {
        None
    } else {
        Some(bundle_from_json(&bundle))
    };
    let dumped = match tiqian_precompute::precompute_html::snapshot_server_assets(parsed.as_ref()) {
        Some(assets) => Json::Obj(vec![
            ("id".to_string(), Json::str(assets.id.clone())),
            (
                "initialStyle".to_string(),
                Json::str(assets.initial_style.clone()),
            ),
            (
                "inertTemplate".to_string(),
                Json::str(assets.inert_template.clone()),
            ),
            ("fontPreloads".to_string(), assets.font_preloads.clone()),
        ]),
        None => Json::Null,
    };
    Ok(cx.string(dumped.render()))
}

fn assets_from_json(value: &Json) -> SnapshotServerAssets {
    SnapshotServerAssets {
        id: member_string(value, "id"),
        initial_style: member_string(value, "initialStyle"),
        inert_template: member_string(value, "inertTemplate"),
        font_preloads: member(value, "fontPreloads").cloned().unwrap_or(Json::Null),
    }
}

/// `renderSnapshotServerAssets(assetsJson | null)`.
pub fn render_snapshot_server_assets(mut cx: FunctionContext) -> JsResult<JsString> {
    let assets = json_argument(&mut cx, 0, "assets")?;
    let rendered = if matches!(assets, Json::Null) {
        None
    } else {
        Some(assets_from_json(&assets))
    };
    Ok(cx.string(
        tiqian_precompute::precompute_html::render_snapshot_server_assets(rendered.as_ref()),
    ))
}

fn weight_json(weight: &FontWeightSpec) -> Json {
    match weight {
        FontWeightSpec::Single(Some(value)) => Json::Num(*value),
        FontWeightSpec::Single(None) => Json::Null,
        FontWeightSpec::Range(low, high) => Json::Arr(vec![Json::Num(*low), Json::Num(*high)]),
    }
}

fn stylesheet_face_json(face: &StylesheetFace) -> Json {
    Json::Obj(vec![
        ("family".to_string(), Json::str(face.family.clone())),
        ("source".to_string(), Json::str(face.source_path.clone())),
        ("publicUrl".to_string(), Json::str(face.public_url.clone())),
        ("weight".to_string(), weight_json(&face.weight)),
        ("style".to_string(), Json::str(face.style.clone())),
        (
            "unicodeRange".to_string(),
            Json::str(face.unicode_range.clone()),
        ),
    ])
}

/// `parseBuildFontStylesheet(css, sourceFileUrl, publicUrl)`: the resolved
/// faces; `source` is the font file path the wrapper reads.
pub fn parse_build_font_stylesheet(mut cx: FunctionContext) -> JsResult<JsString> {
    let css = cx.argument::<JsString>(0)?.value(&mut cx);
    let source = cx.argument::<JsString>(1)?.value(&mut cx);
    let public_url = crate::calls::optional_string(&mut cx, 2)?;
    match tiqian_precompute::build_fonts::parse_build_font_stylesheet(
        &css,
        &source,
        public_url.as_deref(),
    ) {
        Ok(faces) => {
            let dumped = Json::Arr(faces.iter().map(stylesheet_face_json).collect());
            Ok(cx.string(dumped.render()))
        }
        Err(error) => cx.throw_error(error.0),
    }
}
