import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("published package ships the TS runtime modules and no repository-only bin", async () => {
  const manifest = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  const rootLock = JSON.parse(await readFile(new URL("../../../../../package-lock.json", import.meta.url), "utf8"));
  const lock = rootLock.packages["platforms/web/client/web-component"];

  assert.equal(manifest.name, "@tiqian/web-component");
  assert.equal(lock.version, manifest.version);
  assert.equal(manifest.license, "MPL-2.0");
  assert.equal(manifest.types, "./element.d.ts");
  assert.equal(manifest.engines.node, ">=22");
  assert.deepEqual(manifest.publishConfig, { access: "public", tag: "alpha" });
  assert.ok(manifest.files.includes("LICENSE"));
  assert.ok(manifest.files.includes("README.md"));
  assert.equal(manifest.files.includes("runtime/"), false, "runtime/ moved to @tiqian/core");
  assert.equal(manifest.files.includes("core/"), false, "core/ moved to @tiqian/core");
  assert.equal(
    manifest.files.includes("precompute-runtime/"),
    false,
    "the engine runtime ships as @tiqian/ffi instead",
  );
  assert.equal(manifest.files.includes("browser-font-replay.js"), false);
  assert.equal(manifest.files.includes("browser-fonts.js"), false);
  assert.equal(manifest.files.includes("font-face-boundaries.js"), false);
  assert.equal(manifest.files.includes("lazy-capabilities.js"), false, "lazy-capabilities.js must not ship");
  assert.equal(manifest.files.includes("layout-worker.js"), false);
  assert.ok(manifest.files.includes("prepared-dom.js"));
  assert.ok(manifest.files.includes("auto.js"), "the zero-config auto entry ships");
  assert.equal(manifest.files.includes("snapshot-manifest.js"), false);
  assert.equal(manifest.files.includes("snapshot-source.js"), false);
  assert.ok(manifest.files.includes("snapshot-client.js"));
  assert.equal(manifest.files.includes("worker-layout.js"), false);
  // The server-side precompute entries moved to @tiqian/precompute; only the
  // client snapshot adoption module and web-component integration remain.
  assert.deepEqual(Object.keys(manifest.exports).sort(), [
    ".",
    "./auto",
    "./element",
    "./prepared-dom",
    "./snapshot-client",
  ]);
  assert.equal(manifest.bin, undefined);
  assert.equal(manifest.exports["./build-runtime"], undefined);
  // The workspace pins the sibling to the release version, so the assertion
  // follows the manifest instead of naming a version a release has to edit.
  assert.deepEqual(manifest.dependencies, { "@tiqian/core": manifest.version });
  for (const removed of ["precompute.js", "precompute-html.js", "precompute-fonts.js", "precompute-node-fonts.js"]) {
    assert.equal(manifest.files.includes(removed), false, `${removed} must not ship`);
  }
  assert.ok(manifest.sideEffects.includes("./prepared-dom.js"));
  assert.ok(manifest.sideEffects.includes("./auto.js"), "the auto entry registers on import");
  assert.equal(
    manifest.scripts.prepack,
    "npm test && npm run verify:package",
  );
  assert.equal(
    manifest.scripts["verify:release"],
    "npm run prepack && node ./scripts/verify-release.ts",
  );
  assert.equal(manifest.scripts["release:prepare"], "node ./scripts/prepare-release.ts");
  assert.equal(manifest.files.includes("verify-release.ts"), false);
  assert.equal(manifest.files.includes("prepare-release.ts"), false);

  const coreManifest = JSON.parse(await readFile(new URL("../../core/package.json", import.meta.url), "utf8"));
  assert.equal(coreManifest.name, "@tiqian/core");
  assert.equal(coreManifest.version, manifest.version);
  // The generated protocol and shared trees are workspace members until
  // tools/publish-contract.py resolves them for the packed archive.
  assert.deepEqual(coreManifest.dependencies, {
    "@tiqian/ffi": coreManifest.version,
    "@tiqian/protocol": "workspace:*",
    "@tiqian/shared": "workspace:*",
  });
  assert.ok(coreManifest.files.includes("src/"));
  assert.equal(coreManifest.files.includes("runtime/"), false, "the Kotlin bundle directory is retired");
  assert.ok(coreManifest.files.includes("src/engine/layout-worker.js"));
});

test("the release helper derives the repository tag and commit subject from one version", async () => {
  const { normalizeReleaseVersion, releaseCommitSubject, releaseTag } = await import(
    "../scripts/prepare-release.js"
  );

  assert.equal(normalizeReleaseVersion("0.1.0-alpha.3"), "0.1.0-alpha.3");
  assert.equal(releaseTag("0.1.0-alpha.3"), "@tiqian/web-component@0.1.0-alpha.3");
  assert.equal(releaseCommitSubject("0.1.0-alpha.3"), "chore(web): prepare alpha.3 release");
  assert.equal(releaseCommitSubject("0.1.0"), "chore(web): prepare 0.1.0 release");
  assert.throws(() => normalizeReleaseVersion("v0.1.0-alpha.3"), /InvalidReleaseVersion/u);
  assert.throws(() => normalizeReleaseVersion("0.1.0-alpha.03"), /InvalidReleaseVersion/u);
  assert.throws(() => normalizeReleaseVersion("0.1.0+local"), /InvalidReleaseVersion/u);
});

test("the ffi release workflow mirrors the web-component one for the engine package", async () => {
  const workflow = await readFile(
    new URL("../../../../../.github/workflows/publish-ffi.yml", import.meta.url),
    "utf8",
  );

  // The lane runs from the release entrypoint and from a manual dispatch on
  // the release tag; it no longer triggers on a per-package tag.
  assert.match(workflow, /workflow_call:/u);
  assert.match(workflow, /workflow_dispatch:/u);
  assert.match(workflow, /working-directory: platforms\/web\/client\/engine-runtime/u);
  assert.match(workflow, /TIQIAN_RELEASE_ARTIFACT_DIR/u);
  assert.match(workflow, /tiqian-ffi-release/u);
  assert.match(workflow, /npm publish "\$\{tarball\}" --ignore-scripts --access public --tag alpha/u);
  assert.match(workflow, /npm dist-tag add "@tiqian\/ffi@\$\{RELEASE_VERSION\}" latest/u);
  assert.match(workflow, /tags\.alpha !== version \|\| tags\.latest !== version/u);
});

test("the release workflow publishes one verified artifact and synchronizes both dist-tags", async () => {
  const workflow = await readFile(
    new URL("../../../../../.github/workflows/publish-web-component.yml", import.meta.url),
    "utf8",
  );

  // See the ffi lane: one release entrypoint drives every package lane.
  assert.match(workflow, /workflow_call:/u);
  assert.match(workflow, /id-token: write/u);
  assert.match(workflow, /TIQIAN_RELEASE_ARTIFACT_DIR/u);
  assert.match(workflow, /npm publish "\$\{tarball\}" --ignore-scripts --access public --tag alpha/u);
  assert.match(workflow, /NODE_AUTH_TOKEN: \$\{\{ secrets\.NPM_DIST_TAG_TOKEN \}\}/u);
  assert.match(workflow, /npm dist-tag add "@tiqian\/web-component@\$\{RELEASE_VERSION\}" latest/u);
  assert.match(workflow, /tags\.alpha !== version \|\| tags\.latest !== version/u);
});

test("the release verifier accepts the verified package files", async () => {
  const { verifyPackage } = await import("../scripts/verify-package.js");
  const artifacts = await verifyPackage(new URL("../", import.meta.url));

  assert.ok(artifacts.length > 0);
  assert.ok(artifacts.every((artifact) => artifact.size > 0));
});

test("the custom element validates a snapshot before dynamically loading the browser runtime", async () => {
  const elementSource = await readFile(new URL("../element.js", import.meta.url), "utf8");
  // The monolithic host session dissolved into the EnhancedElementContext
  // composition root and its parts; sessionSource is the concatenation of the
  // dissolved module set so the contract assertions below follow the behavior.
  const dissolvedSessionPaths = [
    "../../core/src/engine/context/enhance-context.js",
    "../../core/src/engine/enhance/context-state.js",
    "../../core/src/engine/enhance/event-channel.js",
    "../../core/src/engine/enhance/options-ledger.js",
    "../../core/src/engine/enhance/responsive.js",
    "../../core/src/engine/enhance/snapshot-adoption.js",
    "../../core/src/engine/enhance/typography.js",
    "../../core/src/engine/enhance/lifecycle/foreign-guard.js",
    "../../core/src/engine/enhance/lifecycle/mount.js",
    "../../core/src/engine/enhance/lifecycle/initial-enhance.js",
    "../../core/src/engine/enhance/lifecycle/progressive-dispatch.js",
  ];
  const sessionSource = (
    await Promise.all(
      dissolvedSessionPaths.map((path) => readFile(new URL(path, import.meta.url), "utf8")),
    )
  ).join("\n");
  const elementDeclarations = await readFile(new URL("../element.d.ts", import.meta.url), "utf8");
  const browserFontsSource = await readFile(
    new URL("../../core/src/measurement/browser-fonts.js", import.meta.url),
    "utf8",
  );
  const layoutWorkerSource = await readFile(new URL("../../core/src/engine/layout-worker.js", import.meta.url), "utf8");
  const loadedSnapshotsSource = await readFile(
    new URL("../../core/src/sampler/snapshot/loaded-snapshots.js", import.meta.url),
    "utf8",
  );
  const eligibilitySource = await readFile(
    new URL("../../core/src/engine/eligibility.js", import.meta.url),
    "utf8",
  );
  const snapshotCompletionSource = await readFile(
    new URL("../../core/src/sampler/snapshot/snapshot-completion.js", import.meta.url),
    "utf8",
  );
  const responsiveMeasureSource = await readFile(
    new URL("../../core/src/engine/responsive-measure.js", import.meta.url),
    "utf8",
  );
  for (const shim of ["prepared-dom.js", "snapshot-client.js"]) {
    const shimSource = await readFile(new URL(`../${shim}`, import.meta.url), "utf8");
    assert.match(shimSource, /export \* from "@tiqian\/core\/src\/sampler\/snapshot\//u);
  }
  for (const shim of ["precomputed.js", "snapshot-source.js"]) {
    await assert.rejects(() => readFile(new URL(`../../core/${shim}`, import.meta.url), "utf8"));
  }
  {
    const coreExports = JSON.parse(await readFile(new URL("../../core/package.json", import.meta.url), "utf8")).exports;
    assert.equal(coreExports["./precomputed"].default, "./src/sampler/snapshot/precomputed.js");
    assert.equal(coreExports["./snapshot-source"].default, "./src/sampler/snapshot/snapshot-source.js");
  }
  const fontLoaderSource = await readFile(
    new URL("../../core/src/engine/loaders/font-loader.js", import.meta.url),
    "utf8",
  );
  // Single source of truth: the stylesheet ships from @tiqian/core only;
  // @tiqian/web-component neither ships nor exports it.
  const webComponentManifestForStyles = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  assert.equal(webComponentManifestForStyles.exports["./styles.css"], undefined, "@tiqian/web-component must not export ./styles.css");
  assert.equal(webComponentManifestForStyles.files.includes("styles.css"), false, "styles.css must not be in @tiqian/web-component files");
  const coreStylesSource = await readFile(new URL("../../core/styles.css", import.meta.url), "utf8");
  assert.ok(coreStylesSource.length > 0);
  assert.match(coreStylesSource, /--tq-styles-ready:\s*1/u);
  const coreStylesResolution = import.meta.resolve("@tiqian/core/styles.css");
  assert.equal(coreStylesResolution, new URL("../../core/styles.css", import.meta.url).href);
  const coreResolvedSource = await readFile(new URL(coreStylesResolution), "utf8");
  assert.equal(coreResolvedSource, coreStylesSource);
  const stylesSource = coreStylesSource;
  const adoption = sessionSource.indexOf("snapshot = await env.adoptRequestedSnapshot(");
  const connectedStart = sessionSource.indexOf("    function mount() {");
  const initialSnapshotSource = sessionSource.slice(connectedStart, adoption);
  const invalidationStart = sessionSource.indexOf("    async function invalidateAndEnhance(");
  const invalidationEnd = sessionSource.indexOf(
    "    async function tryReadoptSnapshotAtMaximumMeasure() {",
    invalidationStart,
  );
  const invalidationSource = sessionSource.slice(invalidationStart, invalidationEnd);
  const readoptionStart = sessionSource.indexOf("    async function tryReadoptSnapshotAtMaximumMeasure() {");
  const readoptionEnd = sessionSource.indexOf("    function recoverRuntimeAfterSnapshotMiss(", readoptionStart);
  const readoptionSource = sessionSource.slice(readoptionStart, readoptionEnd);
  const mixedCompletionStart = sessionSource.indexOf("MixedSnapshotRuntimeCompletion");
  const mixedCompletionEnd = sessionSource.indexOf(
    "            if (!stateMachine.runtimeActive)",
    mixedCompletionStart,
  );
  const mixedCompletionSource = sessionSource.slice(mixedCompletionStart, mixedCompletionEnd);
  const viewportListenerStart = sessionSource.indexOf("    function ensureViewportResizeListener() {");
  const viewportListenerEnd = sessionSource.indexOf(
    "    function handleResponsiveGeometryChange() {",
    viewportListenerStart,
  );
  const viewportListenerSource = sessionSource.slice(viewportListenerStart, viewportListenerEnd);

  assert.ok(adoption >= 0);
  assert.match(initialSnapshotSource, /beginLayoutWork\(\{ captureSignatures: false \}\)/u);
  assert.doesNotMatch(initialSnapshotSource, /lastTypography = typographySignature\(root\)/u);
  assert.match(
    initialSnapshotSource,
    /bypassesFontWait: \(\) => root\.hasAttribute\("snapshot-ref"\) &&[\s\S]*?!strongEmphasisRuntimeRequired/u,
  );
  assert.match(
    sessionSource,
    /OptInStrongSnapshotExclusion[\s\S]*?optionsLedger\.strongAsEmphasisMarks && hasStrongEmphasis\(root\)/u,
  );
  assert.match(
    eligibilitySource,
    /function hasStrongEmphasis\(root\) \{[\s\S]*?querySelector\("strong"\)/u,
  );
  assert.doesNotMatch(initialSnapshotSource, /initialCompletionSelector/u);
  assert.match(
    sessionSource,
    /if \(!strongEmphasisRuntimeRequired\) \{[\s\S]*?adoptRequestedSnapshot\(/u,
  );
  assert.doesNotMatch(sessionSource, /from "\.\/runtime\/tiqian-web\.js"/u);
  assert.match(fontLoaderSource, /from "\.\.\/\.\.\/measurement\/browser-fonts\.js"/u);
  // The prepared-dom renderer is now imported directly from prepared-dom.js;
  // font-loader reaches it through the synchronous module import and no longer
  // installs the deleted prepared-dom bridge itself.
  assert.doesNotMatch(fontLoaderSource, /from "\.\.\/\.\.\/sampler\/snapshot\/prepared-dom\.js"/u);
  assert.doesNotMatch(fontLoaderSource, /installPreparedDomRendererBridge/u);
  assert.match(sessionSource, /import\("@tiqian\/core\/src\/engine\/web-worker\/worker-channel\.js"\)/u);
  assert.doesNotMatch(sessionSource, /from "\.\/browser-fonts\.js"/u);
  assert.doesNotMatch(sessionSource, /from "\.\/precomputed\.js"/u);
  assert.doesNotMatch(sessionSource, /from "\.\/font-shaping\.js"/u);
  assert.match(loadedSnapshotsSource, /from "\.\/precomputed\.js"/u);
  assert.doesNotMatch(loadedSnapshotsSource, /font-shaping\.js/u);
  assert.doesNotMatch(sessionSource, /lazy-capabilities/u);
  assert.doesNotMatch(layoutWorkerSource, /precompute-fonts\.js|harfbuzzjs|woff2-encoder/u);
  assert.match(layoutWorkerSource, /from "@tiqian\/ffi"/u);
  assert.doesNotMatch(layoutWorkerSource, /precompute-runtime/u);
  assert.match(layoutWorkerSource, /workerSnapshotSubsetSourceBoundaries\(session\.faces, request\)/u);
  assert.doesNotMatch(browserFontsSource, /harfbuzzjs|woff2-encoder/u);
  assert.doesNotMatch(sessionSource, /tiqian:retry-cjk-dash/u);
  assert.match(sessionSource, /BrowserDashCapabilityBeforeDispatch/u);
  assert.doesNotMatch(sessionSource, /snapshotFontSession\?\.reference === reference/u);
  assert.match(browserFontsSource, /await requirePreparedOrSnapshotContract\(root\)/u);
  assert.match(
    browserFontsSource,
    /if \(prepared\?\.matches\)\s*return prepared;[\s\S]*?return requireSnapshotContract\(root\)/u,
  );
  assert.match(browserFontsSource, /ExistingSessionLiveContractRevalidation/u);
  assert.match(browserFontsSource, /ServerReplayNeedsNoBrowserFontBytes/u);
  assert.doesNotMatch(browserFontsSource, /fetchImplementation|createRenderFontFace/u);
  assert.match(browserFontsSource, /export function prepareBrowserRenderFonts/u);
  assert.match(sessionSource, /SnapshotFontSessionLiveRevalidation/u);
  assert.match(sessionSource, /await existing\.revalidate\(root, existing\.handle\)/u);
  assert.match(
    sessionSource,
    /HostRenderFontReadyBeforeCommit[\s\S]*?await raceAbort\(signal, snapshotAdoption\.prepareSnapshotRenderFont\(snapshotFontSession\)\)/u,
  );
  assert.match(
    sessionSource,
    /await raceAbort\(signal, scheduler\.runPrepare\([\s\S]*?enhanceProgressively\(context, root, preparedOptions\)/u,
  );
  assert.match(
    sessionSource,
    /const layoutOperation = contextState\.beginLayoutWork\(\{ usesCapturedMeasure: true \}\)[\s\S]*?request === stateMachine\.transaction\.enhanceRequest &&[\s\S]*?layoutOperation === stateMachine\.transaction\.layoutOperation/u,
  );
  assert.match(
    sessionSource,
    /OBSERVED_ATTRIBUTES = \[[\s\S]*?"disabled",[\s\S]*?"emphasis-dot-gap-em",[\s\S]*?"strong-as-emphasis-marks",[\s\S]*?"snapshot-ref",[\s\S]*?\]/u,
  );
  assert.match(elementSource, /get disabled\(\)[\s\S]*?hasAttribute\("disabled"\)/u);
  assert.match(elementDeclarations, /get disabled\(\): boolean/u);
  assert.match(
    sessionSource,
    /ReversibleDisabledEnhancement[\s\S]*?if \(optionsLedger\.disabled\)\s*return/u,
  );
  assert.match(
    sessionSource,
    /DisabledAttributeOwnsTeardown[\s\S]*?restartConnectedLifecycle\(\)/u,
  );
  assert.match(elementSource, /get strongAsEmphasisMarks\(\)[\s\S]*?hasAttribute\("strong-as-emphasis-marks"\)/u);
  assert.match(elementDeclarations, /get strongAsEmphasisMarks\(\): boolean/u);
  assert.match(
    sessionSource,
    /UpgradeAttributeReactionGuard[\s\S]*?if \(stateMachine\.connected\)\s*mountLifecycle\.restartConnectedLifecycle\(\)/u,
  );
  assert.match(
    sessionSource,
    /SnapshotFontValidationRenderProjection[\s\S]*?root\.setAttribute\(SNAPSHOT_RENDER_FONT_ATTRIBUTE, "true"\)/u,
  );
  assert.match(
    sessionSource,
    /snapshotFontRejectedAttempt === snapshotFontAttemptSignatureOf\(root, reference\)/u,
  );
  assert.match(sessionSource, /restartConnectedLifecycle\(\)/u);
  assert.match(snapshotCompletionSource, /function snapshotCompletionSelector\(root\) \{/u);
  assert.match(snapshotCompletionSource, /:is\(p, li\):not\(\[data-tq-snapshot-key\]\)/u);
  assert.match(sessionSource, /!strongEmphasisRuntimeRequired\) \{/u);
  assert.match(
    sessionSource,
    /MixedSnapshotRuntimeCompletion[\s\S]*?dispatchProgressiveEnhance\(generation, \{[\s\S]*?paragraphSelector: completionSelector/u,
  );
  assert.match(sessionSource, /paragraphSelector:\s*completionSelector/u);
  assert.doesNotMatch(
    mixedCompletionSource,
    /restoreLoadedSnapshot\(root, context\)/u,
  );
  assert.doesNotMatch(sessionSource, /runtimeCoversSnapshotParagraphs|preserveSnapshotRenderFont/u);
  assert.match(
    sessionSource,
    /restoreImmediatelyBeforeDispatch[\s\S]*?stateMachine\.snapshotAdopted = false/u,
  );
  assert.match(
    readoptionSource,
    /const runtimeSnapshotBackingRestored = stateMachine\.runtimeActive/u,
  );
  assert.match(readoptionSource, /RuntimeSnapshotBackingRestore/u);
  assert.ok(
    readoptionSource.indexOf("hooks.destroyRuntimeRoot()") <
      readoptionSource.indexOf("adoptRequestedSnapshot("),
  );
  assert.match(
    sessionSource,
    /recoverRuntimeAfterSnapshotMiss\(operation, reason, runtimeSnapshotBackingRestored = false\)/u,
  );
  assert.doesNotMatch(sessionSource, /tq-inline-size-probe/u);
  const observersSource = await readFile(
    new URL("../../core/src/sampler/observers.js", import.meta.url),
    "utf8",
  );
  assert.match(observersSource, /observer\??\.observe\([^)]+, \{ box: "border-box" \}\)/u);
  assert.match(
    sessionSource,
    /ResponsiveInlineSizeObservation[\s\S]*?onWidthsChanged[\s\S]*?scheduleResponsiveGeometryCommit/u,
  );
  assert.match(observersSource, /Math\.abs\(width - previous\) >= 0\.5/u);
  assert.doesNotMatch(stylesSource, /tq-inline-size-probe/u);
  assert.match(sessionSource, /paragraphWidthSignature\(root\)/u);
  const signaturesSource = await readFile(
    new URL("../../core/src/sampler/signatures.js", import.meta.url),
    "utf8",
  );
  assert.match(signaturesSource, /function fragmentedBorderBoxInlineSize\(element\)/u);
  assert.match(
    signaturesSource,
    /responsiveGeometrySignature\(root\)[\s\S]*?fragmentedBorderBoxInlineSize\(root\)/u,
  );
  assert.doesNotMatch(sessionSource, /RESPONSIVE_LAYOUT_SETTLE_MS|resizeSettleTimer/u);
  assert.doesNotMatch(sessionSource, /RESPONSIVE_LATEST_RETARGET_QUIET_MS/u);
  assert.match(
    sessionSource,
    /scheduleResponsiveRetarget\(\)[\s\S]*?scheduler\.requestFrame\(retargetFrame\)/u,
  );
  assert.match(viewportListenerSource, /ViewportResizeValidatesCapturedLayoutInputs/u);
  assert.match(
    viewportListenerSource,
    /stateMachine\.workInFlight && stateMachine\.work\.usesCapturedMeasure[\s\S]*?invalidate\(InvalidationReason\.ResponsiveCommit\)[\s\S]*?scheduleResponsiveRetarget\(\)/u,
  );
  assert.doesNotMatch(
    viewportListenerSource,
    /cancelCapturedLayoutForLatestGeometry|cancelPendingLayoutForLatestGeometry|restoreRuntimeSourceForRetarget/u,
  );
  assert.match(
    sessionSource,
    /cancelCapturedLayoutForLatestGeometry\(\)[\s\S]*?hooks\.cancelRootLayoutWork\(\)[\s\S]*?invalidate\(InvalidationReason\.ResponsiveRelayout\)/u,
  );
  assert.match(
    sessionSource,
    /ProgressiveOutputTypographyBaseline[\s\S]*?stateMachine\.work\.typographySignature = typographySignature\(root\)/u,
  );
  assert.match(
    signaturesSource,
    /NativeSourceViewportTypographySignature[\s\S]*?!element\.isConnected[\s\S]*?element\.closest\("\[data-tq-rendered='true'\]"\)[\s\S]*?elementTypographySignature\(element, includeGenerated, properties\) !== signature/u,
  );
  assert.match(
    signaturesSource,
    /ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES = TYPOGRAPHY_PROPERTIES\.filter\([\s\S]*?property !== "margin-left" && property !== "margin-right"/u,
  );
  // ResponsiveRetargetNativeRollback retired: a typography change observed on
  // a captured job cancels through the typography chain instead of rolling the
  // root back to native source.
  assert.match(
    sessionSource,
    /layoutWorkViewportTypographyChanged\(root, work\.viewportTypographyEntries\)[\s\S]*?hooks\.cancelCapturedLayoutForTypographyChange\(\)/u,
  );
  assert.match(
    sessionSource,
    /function cancelCapturedLayoutForTypographyChange\(\)[\s\S]*?stateMachine\.invalidate\(InvalidationReason\.ResponsiveRelayout\)/u,
  );
  assert.match(
    sessionSource,
    /scheduleResponsiveGeometryCommit\(\) \{[\s\S]*?scheduler\.requestFrame/u,
  );
  const dispatchStart = sessionSource.indexOf("async function dispatchProgressiveEnhance(");
  const dispatchSource = sessionSource.slice(dispatchStart);
  const dispatchRuntimeLoad = dispatchSource.indexOf(
    'import("@tiqian/core/src/engine/web-worker/worker-channel.js")',
  );
  assert.ok(dispatchStart >= 0);
  assert.ok(dispatchSource.indexOf("beforeDispatch?.();") >= 0);
  assert.ok(dispatchRuntimeLoad >= 0);
  assert.ok(dispatchSource.indexOf("beforeDispatch?.();") < dispatchRuntimeLoad);
  assert.equal(invalidationSource.match(/hooks\.restoreLoadedSnapshot\(\)/gu)?.length, 1);
  assert.match(
    invalidationSource,
    /const restoreImmediatelyBeforeDispatch = \(\) => \{[\s\S]*?hooks\.restoreLoadedSnapshot\(\)/u,
  );
  assert.match(invalidationSource, /beforeDispatch: restoreImmediatelyBeforeDispatch/u);
  assert.match(
    sessionSource,
    /ResponsiveSnapshotRollbackAtFirstSafeSignal[\s\S]*?snapshotInvalidateAndEnhance\(\{ restoreBeforeLoad: true \}\)/u,
  );
  assert.match(
    sessionSource,
    /ResponsiveRuntimeDirectInPlaceRelayout[\s\S]*?scheduleResponsiveGeometryCommit\(\)/u,
  );
  assert.match(
    sessionSource,
    /MixedSnapshotCompletionResume[\s\S]*?completionSelector && !stateMachine\.runtimeActive[\s\S]*?paragraphSelector: completionSelector/u,
  );
  assert.match(
    sessionSource,
    /if \(!stateMachine\.runtimeActive\) \{[\s\S]*?ReadoptionMissMustReclaimSource[\s\S]*?dispatchProgressiveEnhance\(generation\)/u,
  );
  assert.match(sessionSource, /PreparedSnapshotTransition/u);
  assert.match(
    sessionSource,
    /beforeDispatch\?\.\(\);[\s\S]*?usesCapturedMeasure: true[\s\S]*?enhanceProgressively\(context, root, preparedOptions\)/u,
  );
  assert.match(
    sessionSource,
    /ResponsiveNativeBacking[\s\S]*?hooks\.destroyRuntimeRoot\(\)[\s\S]*?dispatchProgressiveEnhance\(generation, \{ revalidateSnapshotFont \}\)/u,
  );
  assert.match(
    sessionSource,
    /const snapshotFontSessionAlreadyPrepared = !revalidateSnapshotFont[\s\S]*?snapshotFontSessionReference\(\)/u,
  );
  assert.match(
    sessionSource,
    /WidthOnlySnapshotFontSessionReuse[\s\S]*?if \(!snapshotFontSessionAlreadyPrepared\)/u,
  );
  assert.match(
    sessionSource,
    /ResponsiveNativeRetargetSingleFlight[\s\S]*?isInvalidated\(InvalidationReason\.ResponsiveRelayout\) && !stateMachine\.runtimeActive/u,
  );
  assert.match(sessionSource, /root\.addEventListener\("tiqian:relayout-ready"/u);
  assert.match(sessionSource, /loadedSnapshotMaximumMeasureMatches\(root\)/u);
  assert.match(sessionSource, /transaction\.geometryRevision !== transaction\.layoutWorkRevision/u);
  assert.match(sessionSource, /paragraphMeasureSignature\(\)/u);
  assert.match(sessionSource, /ObserverBaselineAfterUncapturedLayout/u);
  assert.match(
    sessionSource,
    /const currentParagraphWidths =[\s\S]*?hooks\.paragraphWidthSignature\(\)/u,
  );
  assert.match(
    sessionSource,
    /settleFinishedWork\(currentMeasures, currentParagraphWidths\)[\s\S]*?lastParagraphWidths = currentParagraphWidths/u,
  );
  assert.match(sessionSource, /!widthsChanged && !measuresChanged/u);
  assert.match(
    sessionSource,
    /hostInlineSizeRefresh = widthsChanged && hasHostInlineSizeParagraph\(root\)[\s\S]*?!hostInlineSizeRefresh/u,
  );
  assert.match(
    responsiveMeasureSource,
    /querySelector\("\[data-tq-host-inline-size\]"\)/u,
  );
  assert.match(sessionSource, /usesCapturedMeasure: true/u);
  assert.match(sessionSource, /currentMeasures !== work\.measureSignature/u);
  assert.match(sessionSource, /RenderOutputTypographyIsNotAnInputChange/u);
  assert.match(
    sessionSource,
    /RendererOwnedProgressiveStyleMutation[\s\S]*?rendererOwnedProgressiveStyleMutation\(record, root\)/u,
  );
  assert.match(observersSource, /attributeOldValue: true/u);
  assert.doesNotMatch(
    sessionSource,
    /const capturedTypographyChanged = this\.#layoutWorkUsesCapturedMeasure/u,
  );
  assert.match(
    sessionSource,
    /work\.usesCapturedMeasure\)\s*stateMachine\.clearInvalidation\(InvalidationReason\.ResponsiveRelayout\);[\s\S]*?stateMachine\.invalidate\(InvalidationReason\.ResponsiveRelayout\);/u,
  );
  assert.match(sessionSource, /RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES/u);
  assert.match(sessionSource, /if \(stale\)\s*stateMachine\.invalidate\(InvalidationReason\.ResponsiveCommit\)/u);
  assert.doesNotMatch(sessionSource, /tiqian:enhance-atomically/u);
  assert.match(sessionSource, /hooks\.cancelRootLayoutWork\(\)/u);
  assert.match(sessionSource, /dispatchProgressiveEnhance\(generation\)/u);
  assert.match(sessionSource, /responsiveGeometrySignature\(root\) !== work\.geometrySignature/u);
  assert.match(sessionSource, /stateMachine\.runtimeActive = false/u);
  assert.match(sessionSource, /operation === stateMachine\.transaction\.layoutOperation/u);
  assert.doesNotMatch(sessionSource, /snapshotBackedByRuntime/u);
  assert.match(sessionSource, /let initialReadyReported = false/u);
  assert.match(
    sessionSource,
    /if \(!initialReadyReported\)[\s\S]*?diagnosis\.set\("tiqianLoadMs"/u,
  );
  assert.doesNotMatch(sessionSource, /addEventListener\("DOMContentLoaded"/u);
  assert.doesNotMatch(sessionSource, /\.then\(\(\) => document\.fonts\?\.ready/u);
  assert.match(sessionSource, /forceTypographyStyleRecompute\(root\);[\s\S]*?awaitInitialTypographyFonts/u);
  assert.match(fontLoaderSource, /waitForTypographyFonts/u);
  assert.match(fontLoaderSource, /DEFAULT_TYPOGRAPHY_FONT_WAIT_MS = 3_000/u);
  assert.match(
    fontLoaderSource,
    /fontWait\.status !== "timeout"[\s\S]*?diagnosis\.set\("tiqianFontWait", "timeout"\)[\s\S]*?deferUntilFontsSettle/u,
  );
  assert.match(
    fontLoaderSource,
    /deferUntilFontsSettle[\s\S]*?"loadingdone"[\s\S]*?"loadingerror"[\s\S]*?Promise\.resolve\(completion\)\.then\(restart\)/u,
  );
  assert.match(
    sessionSource,
    /LatestObservedAttributeGeneration[\s\S]*?if \(!stateMachine\.dispatched\) \{[\s\S]*?mountLifecycle\.restartConnectedLifecycle\(\)/u,
  );
  assert.match(
    sessionSource,
    /optionsChangedReaction = \(name, oldValue, newValue\) => \{[\s\S]*?stateMachine\.snapshotAdopted \|\| isLoadedSnapshotAdopted\(root\)[\s\S]*?snapshotAdoption\.invalidateAndEnhance\(\)[\s\S]*?contextState\.refreshRuntimeFromSource\(\)/u,
  );
  assert.match(
    sessionSource,
    /function scheduleTypographyCheck\(force = false\) \{[\s\S]*?stateMachine\.snapshotAdopted \|\| isLoadedSnapshotAdopted\(root\)[\s\S]*?snapshotAdoption\.invalidateAndEnhance\(\)[\s\S]*?hooks\.refreshRuntimeFromSource\(\)/u,
  );
  assert.match(
    sessionSource,
    /function settleDisconnection\(\)[\s\S]*?context\.diagnosis\.dispose\(\)[\s\S]*?typography\.clearInitialFontRetry\(\)/u,
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
    /\[data-tq-rendered="true"\] \{[\s\S]*?text-align: start !important;[\s\S]*?text-justify: none !important;/u,
  );
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
  assert.match(
    stylesSource,
    /font-feature-settings: "halt" 0, "chws" 0, "palt" 1 !important/u,
  );

  // Thin shell contract (wc-s5 R1): the element keeps only attribute
  // reflection into context.updateOptions and the mount/unmount lifecycle
  // delegation; every behavior lives in the core EnhancedElementContext.
  assert.match(elementSource, /class TiqianProseElement/u);
  assert.match(elementSource, /connectedCallback\(\) \{\s*this\.#context\.mount\(\);/u);
  assert.match(elementSource, /disconnectedCallback\(\) \{\s*this\.#context\.unmount\(\);/u);
  assert.match(elementSource, /this\.#context\.updateOptions\(\{ disabled: newValue != null \}\)/u);
  assert.match(elementSource, /this\.#context\.updateOptions\(\{ snapshotRef: newValue \}\)/u);
  assert.match(elementSource, /this\.#context\.updateOptions\(\{ strongAsEmphasisMarks: newValue != null \}\)/u);
  assert.match(elementSource, /this\.#context\.updateOptions\(\{ emphasisDotGapEm: this\.emphasisDotGapEm \}\)/u);
  assert.match(elementSource, /static observedAttributes = \[\.\.\.OBSERVED_ATTRIBUTES\]/u);
  assert.doesNotMatch(elementSource, /#dispatchProgressiveEnhance|#beginLayoutWork|tryAdoptRequestedSnapshot/u);
});

test("layout coordinator implements visual prominence scoring, proportional backoff and anti-starvation aging", async () => {
  // The monolithic host session dissolved: the completion-event synthesis
  // baseline lives in the event channel (the element shell's dispatcher slot
  // mirrors it), and the scroll-anchoring handover lives in the progressive
  // dispatch commit bracket.
  const eventChannelSource = await readFile(
    new URL("../../core/src/engine/enhance/event-channel.js", import.meta.url),
    "utf8",
  );
  const dispatchSource = await readFile(
    new URL("../../core/src/engine/enhance/lifecycle/progressive-dispatch.js", import.meta.url),
    "utf8",
  );
  const elementShellSource = await readFile(new URL("../element.js", import.meta.url), "utf8");
  const coordinatorSource = await readFile(
    new URL("../../core/src/engine/coordination/coordination-service.js", import.meta.url),
    "utf8",
  );

  // 1. Visual prominence scoring formula: visibleArea * (1 + ratio) + inlineSize
  assert.match(
    coordinatorSource,
    /visibleScore[AB] = entry[AB][\s\S]*?\(entry[AB]\.visibleArea \|\| entry[AB]\.area \|\| 0\) \* \(1\.0 \+ \(entry[AB]\.intersectionRatio \|\| 0\)\) \+ \(entry[AB]\.inlineSize \|\| 0\)/u,
  );

  // 2. VisibleClassBeforeScore: visibility is a strict class comparison —
  // the off-screen `visibleArea || area` fallback can exceed any additive
  // in-viewport bonus, and pollWorkers derives visibleCount from the sorted
  // prefix — with anti-starvation aging ordering only within a class.
  assert.match(
    coordinatorSource,
    /if \(inViewA !== inViewB\)\s*return inViewB - inViewA;/u,
  );
  assert.match(
    coordinatorSource,
    /priority[AB] = visibleScore[AB] \+ \([ab]\.deferCount \|\| 0\) \* 50000/u,
  );
  assert.match(
    coordinatorSource,
    /priority[AB] = visibleScore[AB] \+ Math\.min\([ab]\.deferCount \* 50000, 900000\)/u,
  );

  // 3. RefreshAnchoredFrameBudget: the budget follows the measured cadence
  // only; the event-driven regulator and the shared slice EMA are gone.
  assert.match(
    coordinatorSource,
    /this\.#budgetMs = Math\.min\(6\.0, Math\.max\(2\.5, this\.#measuredFrameInterval \* 0\.4\)\);/u,
  );
  assert.doesNotMatch(coordinatorSource, /#estimatedSliceMs/u);
  assert.doesNotMatch(coordinatorSource, /#consecutiveIdleFrames/u);

  // 4. DeadlineGate: grants stop on the real deadline, and a workless frame
  // still grants once so oversized slices keep making progress.
  assert.match(
    coordinatorSource,
    /const guaranteeForwardProgress = workDone === 0;/u,
  );
  assert.match(
    coordinatorSource,
    /if \(!guaranteeForwardProgress && now >= deadline\) \{/u,
  );

  // 5. Lifecycle ready events bubble up for document-level observation.
  // Synthesis is parameterized by event kind; both the core baseline and the
  // element shell dispatcher mark the events bubbles + composed.
  assert.match(
    eventChannelSource,
    /new CustomEvent\(kind, \{ bubbles: true, composed: true, detail: detail \}\)/u,
  );
  assert.match(
    elementShellSource,
    /new CustomEvent\(kind, \{ bubbles: true, composed: true, detail \}\)/u,
  );

  // 6. SliceCommitAnchorCompensation: both grant rounds bracket their slice
  // drains with a same-task viewport anchor capture/compensate pair, and the
  // element excludes itself from native scroll anchoring while a worker is
  // attached.
  assert.match(
    coordinatorSource,
    /const viewportAnchor = captureViewportAnchor\(element\);[\s\S]*?compensateViewportAnchor\(element, viewportAnchor\);/u,
  );
  assert.match(
    coordinatorSource,
    /viewportAnchor = captureViewportAnchor\(element\);[\s\S]*?const processed = this\.layoutJobPool\.runSlice\(\{/u,
  );
  assert.match(
    coordinatorSource,
    /if \(grantProcessed > 0\)\s*compensateViewportAnchor\(element, viewportAnchor\);/u,
  );
  // NativeAnchoringHandover: capture holds the scroller's native anchoring
  // for the job window; every path that ends or abandons a job releases it.
  assert.match(coordinatorSource, /if \(!slot\.active\)\s*releaseNativeScrollAnchoring\(element\);/u);
  assert.match(coordinatorSource, /releaseNativeScrollAnchoring\(element\);/u);
  assert.match(dispatchSource, /releaseNativeScrollAnchoring\(root\);/u);
});

test("offscreen deferred queue keeps every pending callback per element", async () => {
  const coordinatorSource = await readFile(
    new URL("../../core/src/engine/coordination/coordination-service.js", import.meta.url),
    "utf8",
  );

  // OffscreenRequestQueue: an element can queue distinct callbacks while off
  // screen (initial enhance plus responsive commits). The deferred queue must
  // bucket tasks per element; a single task per element lets the newest
  // request silently drop the older ones, which stalled initial enhancement
  // for every root below the fold when a resize re-queued a commit.
  // 1. A request lands in the element's bucket, not a single task slot.
  assert.match(coordinatorSource, /bucket\.tasks\.set\(callback, task\);/u);
  // 2. A due or promoted bucket moves every task it holds.
  const promoted = coordinatorSource.match(
    /for \(const task of bucket\.tasks\.values\(\)\) \{\s*this\.#callbacks\.set\(task\.callback, task\);/gu,
  );
  assert.ok(
    promoted && promoted.length >= 2,
    "flush and promote must both drain the whole bucket",
  );
  // 3. Cancelling one callback must not drop the element's other tasks.
  assert.match(coordinatorSource, /bucket\.tasks\.delete\(callback\);/u);
  // 4. The single-slot regression must stay gone.
  assert.doesNotMatch(coordinatorSource, /this\.#deferred\.set\(element, task\);/u);
});
