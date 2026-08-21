//! Neon addon boundary for `tiqian-precompute` (ADR 0050). The font session
//! API runs in Rust; this crate only wires the exported names to it.

mod cache_calls;
mod calls;
mod pin;
mod precompute_calls;
mod registry;

use neon::prelude::*;

#[neon::main]
fn main(mut cx: ModuleContext) -> NeonResult<()> {
    pin::pin_once();
    cx.export_function("backendRevision", calls::backend_revision)?;
    cx.export_function("harfbuzzVersion", calls::harfbuzz_version)?;
    cx.export_function("createFontSession", calls::create_font_session)?;
    cx.export_function("sessionFaces", calls::session_faces)?;
    cx.export_function("shape", calls::shape)?;
    cx.export_function("metrics", calls::metrics)?;
    cx.export_function("renderFamilies", calls::render_families)?;
    cx.export_function("sourceBoundaries", calls::source_boundaries)?;
    cx.export_function("precomputeParagraph", calls::precompute_paragraph)?;
    cx.export_function("beginCapture", calls::begin_capture)?;
    cx.export_function("captureEvidence", calls::capture_evidence)?;
    cx.export_function("closeSession", calls::close_session)?;
    cx.export_function(
        "normalizeTypography",
        precompute_calls::normalize_typography,
    )?;
    cx.export_function("createPrecomputer", precompute_calls::create_precomputer)?;
    cx.export_function("precomputerInfo", precompute_calls::precomputer_info)?;
    cx.export_function("prepareParagraph", precompute_calls::prepare_paragraph)?;
    cx.export_function("prepareParagraphs", precompute_calls::prepare_paragraphs)?;
    cx.export_function(
        "prepareFontContract",
        precompute_calls::prepare_font_contract,
    )?;
    cx.export_function(
        "prepareFontContracts",
        precompute_calls::prepare_font_contracts,
    )?;
    cx.export_function("closePrecomputer", precompute_calls::close_precomputer)?;
    cx.export_function("createHtmlPreparer", precompute_calls::create_html_preparer)?;
    cx.export_function("prepareHtml", precompute_calls::prepare_html)?;
    cx.export_function("closeHtmlPreparer", precompute_calls::close_html_preparer)?;
    cx.export_function("htmlPreparerInfo", precompute_calls::html_preparer_info)?;
    cx.export_function(
        "renderSnapshotBundle",
        precompute_calls::render_snapshot_bundle,
    )?;
    cx.export_function(
        "renderFontContractBundle",
        precompute_calls::render_font_contract_bundle,
    )?;
    cx.export_function(
        "renderSnapshotTemplate",
        precompute_calls::render_snapshot_template,
    )?;
    cx.export_function(
        "snapshotPlainTextIssue",
        precompute_calls::snapshot_plain_text_issue,
    )?;
    cx.export_function(
        "findHtmlOpeningTags",
        precompute_calls::find_html_opening_tags,
    )?;
    cx.export_function(
        "injectHtmlAttributes",
        precompute_calls::inject_html_attributes,
    )?;
    cx.export_function(
        "snapshotServerAssets",
        precompute_calls::snapshot_server_assets,
    )?;
    cx.export_function(
        "renderSnapshotServerAssets",
        precompute_calls::render_snapshot_server_assets,
    )?;
    cx.export_function(
        "parseBuildFontStylesheet",
        precompute_calls::parse_build_font_stylesheet,
    )?;
    cx.export_function("cacheContext", cache_calls::cache_context)?;
    cx.export_function("cacheSubmitHashes", cache_calls::cache_submit_hashes)?;
    cx.export_function("cacheSubmitContents", cache_calls::cache_submit_contents)?;
    cx.export_function("cachePrefillContents", cache_calls::cache_prefill_contents)?;
    cx.export_function("cachePrefetch", cache_calls::cache_prefetch)?;
    cx.export_function("cacheDrainWrites", cache_calls::cache_drain_writes)?;
    cx.export_function("cacheEvictExcept", cache_calls::cache_evict_except)?;
    Ok(())
}
