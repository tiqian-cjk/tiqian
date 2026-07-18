import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("published package includes the generated runtime and no repository-only bin", async () => {
  const manifest = JSON.parse(await readFile(new URL("./package.json", import.meta.url), "utf8"));

  assert.equal(manifest.name, "@tiqian/prose");
  assert.equal(manifest.version, "0.1.0-alpha.1");
  assert.equal(manifest.license, "MPL-2.0");
  assert.equal(manifest.types, "./api.d.ts");
  assert.equal(manifest.engines.node, ">=22");
  assert.deepEqual(manifest.publishConfig, { access: "public", tag: "alpha" });
  assert.ok(manifest.files.includes("LICENSE"));
  assert.ok(manifest.files.includes("README.md"));
  assert.ok(manifest.files.includes("runtime/"));
  assert.ok(manifest.files.includes("precompute-runtime/"));
  assert.ok(manifest.files.includes("precompute-node-fonts.js"));
  assert.ok(manifest.files.includes("browser-font-replay.js"));
  assert.ok(manifest.files.includes("browser-fonts.js"));
  assert.ok(manifest.files.includes("font-face-boundaries.js"));
  assert.ok(manifest.files.includes("lazy-capabilities.js"));
  assert.ok(manifest.files.includes("layout-worker.js"));
  assert.ok(manifest.files.includes("prepared-dom.js"));
  assert.ok(manifest.files.includes("snapshot-manifest.js"));
  assert.ok(manifest.files.includes("snapshot-source.js"));
  assert.ok(manifest.files.includes("snapshot-client.js"));
  assert.ok(manifest.files.includes("worker-layout.js"));
  assert.equal(manifest.exports["./precompute"].default, "./precompute.js");
  assert.equal(manifest.exports["./snapshot-client"].default, "./snapshot-client.js");
  assert.equal(manifest.bin, undefined);
  assert.equal(manifest.exports["./build-runtime"], undefined);
  assert.equal(manifest.dependencies?.puppeteer, undefined);
  assert.equal(manifest.dependencies?.playwright, undefined);
  assert.ok(manifest.sideEffects.includes("./prepared-dom.js"));
  assert.equal(
    manifest.scripts.prepack,
    "npm run build:runtime && npm test && npm run verify:package",
  );
  assert.equal(
    manifest.scripts["verify:release"],
    "npm run prepack && node ./verify-release.mjs",
  );
  assert.equal(manifest.files.includes("verify-release.mjs"), false);
});

test("the release verifier accepts both assembled Kotlin/JS runtimes", async () => {
  const { verifyPackage } = await import("./verify-package.mjs");
  const artifacts = await verifyPackage();

  assert.deepEqual(
    artifacts.map((artifact) => artifact.path),
    [
      "runtime/tiqian-web.js",
      "precompute-runtime/Tiqian-tiqian-web-precompute.mjs",
    ],
  );
  assert.ok(artifacts.every((artifact) => artifact.size > 8));
});

test("the release build clears both Kotlin/JS package targets and bypasses build cache", async () => {
  const source = await readFile(new URL("./build-runtime.mjs", import.meta.url), "utf8");

  assert.match(source, /":tiqian-web-precompute:clean"/u);
  assert.match(source, /":tiqian-web:clean"/u);
  assert.match(source, /":tiqian-web:assembleNpmPackage"/u);
  assert.match(source, /"--no-build-cache"/u);
});

test("the precompute public surface matches its declarations", async () => {
  const source = await readFile(new URL("./precompute.js", import.meta.url), "utf8");
  const declarations = await readFile(new URL("./precompute.d.ts", import.meta.url), "utf8");
  const publicModule = await import("./precompute.js");

  assert.match(source, /export \{ renderPreparedParagraph \} from "\.\/prepared-dom\.js"/u);
  assert.deepEqual(Object.keys(publicModule).sort(), [
    "createPrecomputer",
    "renderFontContractBundle",
    "renderPreparedParagraph",
    "renderSnapshotBundle",
    "renderSnapshotTemplate",
    "snapshotPlainTextIssue",
  ]);
  assert.match(declarations, /function renderPreparedParagraph\(/u);
  assert.match(declarations, /function renderFontContractBundle\(/u);
  assert.match(declarations, /readonly inertTemplate: string/u);
  assert.doesNotMatch(declarations, /renderPreparedParagraphArtifact/u);
  assert.doesNotMatch(declarations, /renderPreparedParagraphInto/u);
  assert.match(source, /SEMANTIC_CAPABILITY_ISSUES/u);
  assert.match(source, /unsupportedParagraph\(key, capabilityIssue, error\)/u);
});

test("the custom element validates a snapshot before dynamically loading the browser runtime", async () => {
  const elementSource = await readFile(new URL("./element.js", import.meta.url), "utf8");
  const elementDeclarations = await readFile(new URL("./element.d.ts", import.meta.url), "utf8");
  const apiSource = await readFile(new URL("./api.js", import.meta.url), "utf8");
  const apiDeclarations = await readFile(new URL("./api.d.ts", import.meta.url), "utf8");
  const browserFontsSource = await readFile(new URL("./browser-fonts.js", import.meta.url), "utf8");
  const layoutWorkerSource = await readFile(new URL("./layout-worker.js", import.meta.url), "utf8");
  const precomputeFontsSource = await readFile(new URL("./precompute-fonts.js", import.meta.url), "utf8");
  const lazyCapabilitiesSource = await readFile(new URL("./lazy-capabilities.js", import.meta.url), "utf8");
  const runtimeSource = await readFile(new URL("./runtime.js", import.meta.url), "utf8");
  const stylesSource = await readFile(new URL("./styles.css", import.meta.url), "utf8");
  const adoption = elementSource.indexOf("snapshot = await tryAdoptRequestedSnapshot(");
  const connectedStart = elementSource.indexOf("  connectedCallback() {");
  const initialSnapshotSource = elementSource.slice(connectedStart, adoption);
  const runtimeLoad = elementSource.indexOf("await (runtimePromise ?? loadTiqianRuntime());", adoption);
  const invalidationStart = elementSource.indexOf("  #invalidateSnapshotAndEnhance(");
  const invalidationEnd = elementSource.indexOf(
    "  #tryReadoptSnapshotAtMaximumMeasure()",
    invalidationStart,
  );
  const invalidationSource = elementSource.slice(invalidationStart, invalidationEnd);
  const invalidationRuntimeLoad = invalidationSource.indexOf("loadTiqianRuntime()");
  const invalidationDispatch = invalidationSource.indexOf("this.#dispatchProgressiveEnhance(");
  const readoptionStart = elementSource.indexOf("  #tryReadoptSnapshotAtMaximumMeasure() {");
  const readoptionEnd = elementSource.indexOf("  #recoverRuntimeAfterSnapshotMiss(", readoptionStart);
  const readoptionSource = elementSource.slice(readoptionStart, readoptionEnd);
  const mixedCompletionStart = elementSource.indexOf("MixedSnapshotRuntimeCompletion");
  const mixedCompletionEnd = elementSource.indexOf(
    "          if (!this.#runtimeStateActive)",
    mixedCompletionStart,
  );
  const mixedCompletionSource = elementSource.slice(mixedCompletionStart, mixedCompletionEnd);
  const viewportListenerStart = elementSource.indexOf("  #ensureViewportResizeListener() {");
  const viewportListenerEnd = elementSource.indexOf(
    "  #handleResponsiveGeometryChange() {",
    viewportListenerStart,
  );
  const viewportListenerSource = elementSource.slice(viewportListenerStart, viewportListenerEnd);

  assert.ok(adoption >= 0);
  assert.match(initialSnapshotSource, /#beginLayoutWork\(\{ captureSignatures: false \}\)/u);
  assert.doesNotMatch(initialSnapshotSource, /#lastTypography = this\.#typographySignature\(\)/u);
  assert.match(
    initialSnapshotSource,
    /if \(this\.hasAttribute\("snapshot-ref"\) && !strongEmphasisRuntimeRequired\) return true;[\s\S]*?waitForTypographyFonts/u,
  );
  assert.ok(runtimeLoad > adoption);
  assert.match(
    elementSource,
    /OptInStrongSnapshotExclusion[\s\S]*?this\.strongAsEmphasisMarks && this\.querySelector\("strong"\) !== null/u,
  );
  assert.match(
    elementSource,
    /SnapshotFirstInputBeforeRuntimeCompile[\s\S]*?this\.hasAttribute\("snapshot-ref"\) &&[\s\S]*?!strongEmphasisRuntimeRequired[\s\S]*?\? null[\s\S]*?: loadTiqianRuntime\(\)/u,
  );
  assert.doesNotMatch(initialSnapshotSource, /initialCompletionSelector/u);
  assert.match(
    elementSource,
    /if \(!strongEmphasisRuntimeRequired\) \{[\s\S]*?tryAdoptRequestedSnapshot\(/u,
  );
  assert.match(runtimeSource, /import\("\.\/runtime\/tiqian-web\.js"\)/u);
  assert.doesNotMatch(elementSource, /from "\.\/runtime\/tiqian-web\.js"/u);
  assert.match(elementSource, /import\("\.\/browser-fonts\.js"\)/u);
  assert.match(elementSource, /import\("\.\/prepared-dom\.js"\)/u);
  assert.match(elementSource, /import\("\.\/worker-layout\.js"\)/u);
  assert.match(elementSource, /preparedDom\.installPreparedDomRendererBridge\(\)/u);
  assert.match(apiSource, /preparedDom\.installPreparedDomRendererBridge\(\)/u);
  assert.doesNotMatch(elementSource, /from "\.\/browser-fonts\.js"/u);
  assert.doesNotMatch(elementSource, /from "\.\/precomputed\.js"/u);
  assert.doesNotMatch(elementSource, /from "\.\/font-shaping\.js"/u);
  assert.doesNotMatch(apiSource, /from "\.\/precomputed\.js"/u);
  assert.doesNotMatch(apiSource, /from "\.\/font-shaping\.js"/u);
  assert.match(lazyCapabilitiesSource, /import\("\.\/precomputed\.js"\)/u);
  assert.doesNotMatch(lazyCapabilitiesSource, /font-shaping\.js/u);
  assert.doesNotMatch(browserFontsSource, /precompute-fonts\.js/u);
  assert.doesNotMatch(layoutWorkerSource, /precompute-fonts\.js|harfbuzzjs|woff2-encoder/u);
  assert.match(layoutWorkerSource, /workerExactSubsetSourceBoundaries\(session\.faces, request\)/u);
  assert.doesNotMatch(browserFontsSource, /harfbuzzjs|woff2-encoder/u);
  assert.doesNotMatch(elementSource, /tiqian:retry-cjk-dash/u);
  assert.match(elementSource, /BrowserDashCapabilityBeforeDispatch/u);
  assert.doesNotMatch(elementSource, /#exactFontSession\?\.reference === reference/u);
  assert.doesNotMatch(apiSource, /existing\?\.reference === reference/u);
  assert.match(browserFontsSource, /await requirePreparedOrExactContract\(root\)/u);
  assert.match(
    browserFontsSource,
    /if \(prepared\?\.matches\) return prepared;[\s\S]*?return requireExactContract\(root\)/u,
  );
  assert.match(browserFontsSource, /ExistingSessionLiveContractRevalidation/u);
  assert.match(browserFontsSource, /ServerReplayNeedsNoBrowserFontBytes/u);
  assert.doesNotMatch(browserFontsSource, /fetchImplementation|createRenderFontFace/u);
  assert.match(browserFontsSource, /export const prepareBrowserRenderFonts/u);
  assert.match(elementSource, /ExactFontSessionLiveRevalidation/u);
  assert.match(elementSource, /await existing\.revalidate\(this, existing\.handle\)/u);
  assert.match(
    elementSource,
    /HostRenderFontReadyBeforeCommit[\s\S]*?await this\.#exactFontSession\.prepareRenderFont\(this, exactFontSession\)/u,
  );
  assert.match(
    elementSource,
    /await prepareWorkerLayouts\([\s\S]*?dispatch\("tiqian:enhance-progressively"/u,
  );
  assert.match(
    elementSource,
    /const layoutOperation = this\.#beginLayoutWork\(\{ usesCapturedMeasure: true \}\)[\s\S]*?request === this\.#enhanceRequest && layoutOperation === this\.#layoutOperation/u,
  );
  assert.match(
    elementSource,
    /observedAttributes = \[[\s\S]*?"emphasis-dot-gap-em",[\s\S]*?"strong-as-emphasis-marks",[\s\S]*?"snapshot-ref",[\s\S]*?\]/u,
  );
  assert.match(elementSource, /get strongAsEmphasisMarks\(\)[\s\S]*?hasAttribute\("strong-as-emphasis-marks"\)/u);
  assert.match(elementDeclarations, /strongAsEmphasisMarks: boolean/u);
  assert.match(apiDeclarations, /strongAsEmphasisMarks\?: boolean/u);
  assert.match(
    elementSource,
    /UpgradeAttributeReactionGuard[\s\S]*?if \(this\.#connected\) this\.#restartConnectedLifecycle\(\)/u,
  );
  assert.match(
    elementSource,
    /ExactFontValidationRenderProjection[\s\S]*?this\.setAttribute\(EXACT_RENDER_FONT_ATTRIBUTE, "true"\)/u,
  );
  assert.match(
    elementSource,
    /ExactPreparedDomFallbackSingleFlight[\s\S]*?#exactFontRejectedAttempt = this\.#exactFontAttemptSignature\(\)/u,
  );
  assert.match(
    elementSource,
    /#exactFontRejectedAttempt === this\.#exactFontAttemptSignature\(reference\)/u,
  );
  assert.match(elementSource, /#restartConnectedLifecycle\(\)/u);
  assert.match(elementSource, /function snapshotCompletionSelector\(root\)/u);
  assert.match(elementSource, /:is\(p, li\):not\(\[data-tq-snapshot-key\]\)/u);
  assert.match(elementSource, /!strongEmphasisRuntimeRequired\) \{/u);
  assert.match(
    elementSource,
    /MixedSnapshotRuntimeCompletion[\s\S]*?#dispatchProgressiveEnhance\(generation, \{[\s\S]*?paragraphSelector: completionSelector/u,
  );
  assert.match(elementSource, /paragraphSelector:\s*completionSelector/u);
  assert.doesNotMatch(
    mixedCompletionSource,
    /restoreLoadedSnapshot\(this\)/u,
  );
  assert.doesNotMatch(elementSource, /runtimeCoversSnapshotParagraphs|preserveSnapshotRenderFont/u);
  assert.match(
    elementSource,
    /restoreImmediatelyBeforeDispatch[\s\S]*?#snapshotAdopted = false/u,
  );
  assert.match(
    readoptionSource,
    /const runtimeSnapshotBackingRestored = this\.#runtimeStateActive/u,
  );
  assert.match(readoptionSource, /RuntimeSnapshotBackingRestore/u);
  assert.ok(
    readoptionSource.indexOf('dispatch("tiqian:destroy", this)') <
      readoptionSource.indexOf("tryAdoptRequestedSnapshot("),
  );
  assert.match(
    elementSource,
    /#recoverRuntimeAfterSnapshotMiss\(operation, reason, runtimeSnapshotBackingRestored = false\)/u,
  );
  assert.doesNotMatch(precomputeFontsSource, /spec\.contentAddressed/u);
  assert.doesNotMatch(elementSource, /tq-inline-size-probe/u);
  assert.match(elementSource, /observer\.observe\(target, \{ box: "border-box" \}\)/u);
  assert.match(
    elementSource,
    /ResponsiveInlineSizeObservation[\s\S]*?Math\.abs\(width - previous\) >= 0\.5[\s\S]*?observer\.disconnect\(\)[\s\S]*?#resizeObserverFrame = requestAnimationFrame/u,
  );
  assert.doesNotMatch(stylesSource, /tq-inline-size-probe/u);
  assert.match(elementSource, /#paragraphWidthSignature\(\)/u);
  assert.doesNotMatch(elementSource, /RESPONSIVE_LAYOUT_SETTLE_MS|#resizeSettleTimer/u);
  assert.doesNotMatch(elementSource, /RESPONSIVE_LATEST_RETARGET_QUIET_MS/u);
  assert.match(
    elementSource,
    /#scheduleResponsiveRetarget\(\)[\s\S]*?#responsiveRetargetFrame = requestAnimationFrame/u,
  );
  assert.match(viewportListenerSource, /ViewportResizeValidatesCapturedLayoutInputs/u);
  assert.match(
    viewportListenerSource,
    /#layoutWorkInFlight && this\.#layoutWorkUsesCapturedMeasure[\s\S]*?#responsiveCommitRequired = true[\s\S]*?#scheduleResponsiveRetarget\(\)/u,
  );
  assert.doesNotMatch(
    viewportListenerSource,
    /#cancelCapturedLayoutForLatestGeometry|#cancelPendingLayoutForLatestGeometry|#restoreRuntimeSourceForRetarget/u,
  );
  assert.match(
    elementSource,
    /#cancelCapturedLayoutForLatestGeometry\(\)[\s\S]*?#restoreRuntimeSourceForRetarget\(\)[\s\S]*?#responsiveRelayoutRequired = true/u,
  );
  assert.match(
    elementSource,
    /TypographyRetargetMustRestart[\s\S]*?#responsiveRelayoutRequired = true/u,
  );
  assert.match(
    elementSource,
    /ProgressiveOutputTypographyBaseline[\s\S]*?#layoutWorkTypographySignature = this\.#typographySignature\(\)/u,
  );
  assert.match(
    elementSource,
    /NativeSourceViewportTypographySignature[\s\S]*?!element\.isConnected[\s\S]*?element\.closest\("\[data-tq-rendered='true'\]"\)[\s\S]*?#elementTypographySignature\(element, includeGenerated, properties\) !== signature/u,
  );
  assert.match(
    elementSource,
    /ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES = TYPOGRAPHY_PROPERTIES\.filter\([\s\S]*?property !== "margin-left" && property !== "margin-right"/u,
  );
  assert.match(
    elementSource,
    /ResponsiveRetargetNativeRollback[\s\S]*?"tiqian:destroy"[\s\S]*?#runtimeStateActive = false/u,
  );
  assert.match(
    elementSource,
    /#scheduleResponsiveGeometryCommit\(\) \{[\s\S]*?if \(this\.#resizeFrame\) return;[\s\S]*?this\.#resizeFrame = requestAnimationFrame/u,
  );
  assert.ok(invalidationRuntimeLoad >= 0);
  assert.ok(invalidationDispatch > invalidationRuntimeLoad);
  assert.equal(invalidationSource.match(/restoreLoadedSnapshot\(this\)/gu)?.length, 1);
  assert.match(
    invalidationSource,
    /const restoreImmediatelyBeforeDispatch = \(\) => \{[\s\S]*?restoreLoadedSnapshot\(this\)/u,
  );
  assert.match(invalidationSource, /beforeDispatch: restoreImmediatelyBeforeDispatch/u);
  assert.match(
    elementSource,
    /ResponsiveSnapshotRollbackAtFirstSafeSignal[\s\S]*?#invalidateSnapshotAndEnhance\(\{ restoreBeforeLoad: true \}\)/u,
  );
  assert.match(
    elementSource,
    /ResponsiveRuntimeRollbackAtFirstSafeSignal[\s\S]*?#restoreRuntimeSourceForRetarget\(\)[\s\S]*?#scheduleResponsiveGeometryCommit\(\)/u,
  );
  assert.match(
    elementSource,
    /MixedSnapshotCompletionResume[\s\S]*?completionSelector && !this\.#runtimeStateActive[\s\S]*?paragraphSelector: completionSelector/u,
  );
  assert.match(
    elementSource,
    /if \(!this\.#runtimeStateActive\) \{[\s\S]*?ReadoptionMissMustReclaimSource[\s\S]*?#dispatchProgressiveEnhance\(generation\)/u,
  );
  assert.match(elementSource, /PreparedSnapshotTransition/u);
  assert.match(
    elementSource,
    /beforeDispatch\?\.\(\);[\s\S]*?usesCapturedMeasure: true[\s\S]*?"tiqian:enhance-progressively"/u,
  );
  assert.match(
    elementSource,
    /ResponsiveNativeBacking[\s\S]*?"tiqian:destroy"[\s\S]*?#dispatchProgressiveEnhance\(generation, \{ revalidateExactFont \}\)/u,
  );
  assert.match(
    elementSource,
    /const exactFontSessionAlreadyPrepared = !revalidateExactFont[\s\S]*?this\.#exactFontSession\?\.reference/u,
  );
  assert.match(
    elementSource,
    /WidthOnlyExactFontSessionReuse[\s\S]*?if \(!exactFontSessionAlreadyPrepared\)/u,
  );
  assert.match(
    elementSource,
    /ResponsiveNativeRetargetSingleFlight[\s\S]*?#responsiveRelayoutRequired && !this\.#runtimeStateActive/u,
  );
  assert.match(elementSource, /this\.addEventListener\("tiqian:relayout-ready"/u);
  assert.match(elementSource, /loadedSnapshotMaximumMeasureMatches\(this\)/u);
  assert.match(elementSource, /this\.#geometryRevision !== this\.#layoutWorkRevision/u);
  assert.match(elementSource, /#paragraphMeasureSignature\(\)/u);
  assert.match(elementSource, /ObserverBaselineAfterUncapturedLayout/u);
  assert.match(
    elementSource,
    /const currentParagraphWidths = this\.#paragraphWidthSignature\(\)[\s\S]*?this\.#lastParagraphWidths = currentParagraphWidths/u,
  );
  assert.match(elementSource, /!widthsChanged && !measuresChanged/u);
  assert.match(
    elementSource,
    /hostInlineSizeRefresh = widthsChanged[\s\S]*?\[data-tq-host-inline-size\][\s\S]*?!hostInlineSizeRefresh/u,
  );
  assert.match(elementSource, /usesCapturedMeasure: true/u);
  assert.match(elementSource, /currentMeasures !== this\.#layoutWorkMeasureSignature/u);
  assert.match(elementSource, /RenderOutputTypographyIsNotAnInputChange/u);
  assert.match(
    elementSource,
    /RendererOwnedProgressiveStyleMutation[\s\S]*?rendererOwnedProgressiveStyleMutation\(record, this\)/u,
  );
  assert.match(elementSource, /attributeOldValue: true/u);
  assert.doesNotMatch(
    elementSource,
    /const capturedTypographyChanged = this\.#layoutWorkUsesCapturedMeasure/u,
  );
  assert.match(
    elementSource,
    /this\.#responsiveRelayoutRequired = !this\.#layoutWorkUsesCapturedMeasure/u,
  );
  assert.match(elementSource, /RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES/u);
  assert.match(elementSource, /if \(stale\) this\.#responsiveCommitRequired = true/u);
  assert.doesNotMatch(elementSource, /tiqian:enhance-atomically/u);
  assert.match(elementSource, /tiqian:cancel-layout-work/u);
  assert.match(elementSource, /this\.#dispatchProgressiveEnhance\(generation\)/u);
  assert.match(elementSource, /#responsiveGeometrySignature\(\) !== this\.#layoutWorkGeometrySignature/u);
  assert.match(elementSource, /#runtimeStateActive = false/u);
  assert.match(elementSource, /operation === this\.#layoutOperation/u);
  assert.doesNotMatch(elementSource, /#snapshotBackedByRuntime/u);
  assert.match(elementSource, /let initialReadyReported = false/u);
  assert.match(
    elementSource,
    /if \(!initialReadyReported\)[\s\S]*?this\.dataset\.tiqianLoadMs/u,
  );
  assert.doesNotMatch(elementSource, /addEventListener\("DOMContentLoaded"/u);
  assert.doesNotMatch(elementSource, /\.then\(\(\) => document\.fonts\?\.ready/u);
  assert.match(elementSource, /\.then\(nextFrame\)[\s\S]*?waitForTypographyFonts/u);
  assert.match(lazyCapabilitiesSource, /DEFAULT_TYPOGRAPHY_FONT_WAIT_MS = 3_000/u);
  assert.match(
    elementSource,
    /fontWait\.status !== "timeout"[\s\S]*?tiqianFontWait = "timeout"[\s\S]*?#deferInitialEnhancementUntilFontsSettle/u,
  );
  assert.match(
    elementSource,
    /#deferInitialEnhancementUntilFontsSettle\([\s\S]*?"loadingdone"[\s\S]*?"loadingerror"[\s\S]*?Promise\.resolve\(completion\)\.then\(restart\)/u,
  );
  assert.match(
    elementSource,
    /LatestObservedAttributeGeneration[\s\S]*?if \(!this\.#hasDispatched\) \{[\s\S]*?this\.#restartConnectedLifecycle\(\)/u,
  );
  assert.match(
    elementSource,
    /attributeChangedCallback\([\s\S]*?#snapshotAdopted \|\| isLoadedSnapshotAdopted\(this\)[\s\S]*?#invalidateSnapshotAndEnhance\(\)[\s\S]*?#refreshRuntimeFromSource\(\)/u,
  );
  assert.match(
    elementSource,
    /#scheduleTypographyCheck\([\s\S]*?#snapshotAdopted \|\| isLoadedSnapshotAdopted\(this\)[\s\S]*?#invalidateSnapshotAndEnhance\(\)[\s\S]*?#refreshRuntimeFromSource\(\)/u,
  );
  assert.match(
    elementSource,
    /disconnectedCallback\(\)[\s\S]*?\+\+this\.#generation[\s\S]*?this\.#clearInitialFontRetry\(\)/u,
  );
  assert.match(stylesSource, /\[data-tq-geometry="true"\]::before/u);
  assert.match(stylesSource, /\[data-tq-rendered="true"\]::before,[\s\S]*?content: none !important/u);
  assert.match(
    stylesSource,
    /\[data-tq-rendered="true"\] span\[data-tq-geometry="true"\][\s\S]*?all: unset !important/u,
  );
  assert.match(
    stylesSource,
    /\[data-tq-rendered="true"\] svg\[data-tq-geometry="true"\][\s\S]*?display: block !important/u,
  );
  assert.match(
    stylesSource,
    /svg\[data-tq-geometry="true"\] circle\[data-tq-decoration-dot\][\s\S]*?fill: var\(--tq-decoration-color\) !important/u,
  );
  assert.match(stylesSource, /\[data-tq-shaping-boundary\]::first-letter/u);
  assert.match(stylesSource, /\[data-tq-rendered="true"\]::first-letter,[\s\S]*?all: unset !important/u);
  assert.match(stylesSource, /text-spacing-trim: space-all !important/u);
  assert.match(
    stylesSource,
    /\[data-tq-rendered="true"\] \.tq-line\[data-tq-geometry="true"\]/u,
  );
  assert.match(
    stylesSource,
    /\[data-tq-rendered="true"\],[\s\S]*?\[data-tq-rendered="true"\] \[data-tq-source-semantic\]/u,
  );
  assert.match(stylesSource, /height: var\(--tq-line-height\) !important/u);
  assert.match(stylesSource, /vertical-align: var\(--tq-line-baseline-offset\) !important/u);
  assert.match(
    stylesSource,
    /\[data-tq-canonical-source="true"\] \[data-tq-line-end-sentinel\]/u,
  );
  assert.match(
    stylesSource,
    /\[data-tq-canonical-source="true"\] \[data-tq-engine-hyphen\]/u,
  );
  assert.match(
    stylesSource,
    /\[data-tq-open-type-features="pwid,palt"\]/u,
  );
  assert.match(stylesSource, /font-variant-east-asian: proportional-width !important/u);
});
