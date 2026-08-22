# @tiqian/precompute

Native font session and precompute entry points for
[Tiqian](https://github.com/tiqian-cjk/tiqian), the CJK paragraph layout
engine. The layout rules live in the Kotlin core; this package runs the font
session (decoding, shaping, coverage, metrics) in a Rust addon built with
[Neon](https://neon-rs.dev).

Status: the font session API (`createFontSession`) is implemented against the
same byte-level contract as the Kotlin/JS implementation, which remains the
parity oracle. The precompute entry points (`createPrecomputer`,
`createHtmlPreparer`, bundle rendering) land slice by slice; see
`docs/adr/0050-native-precompute-rust-bindings.md` and `docs/roadmap.md` in
the repository.

## Install

```sh
npm install @tiqian/precompute
```

Platform binaries arrive as optional dependencies for `linux-x64-gnu`,
`linux-arm64-gnu`, `darwin-arm64`, and `win32-x64-msvc`. Loading on any other
platform reports `UnsupportedPrecomputePlatform:<platform>`.

## Font session

```js
import { createFontSession } from "@tiqian/precompute";

const session = await createFontSession(
  [
    {
      family: "Han Sans",
      publicUrl: "/fonts/han-sans.woff2",
      source: await readFile("./han-sans.woff2"),
    },
  ],
  { sessionPrefix: "site" },
);

session.faces;
session.shape("提椠排版", ["Han Sans"], 20, 400, false, "zh-CN", "body");
session.metrics(["Han Sans"], 20, 400, false);
session.renderFamilies(["Han Sans"]);
session.sourceBoundaries(text, baseStyle, textSpans);
session.beginCapture();
session.captureEvidence();
session.close();
```

## Worker threads

The batch entries (`prepareParagraphs`, `prepareFontContracts`, `prepareHtml`)
spread their items over worker threads. `TIQIAN_PRECOMPUTE_THREADS` sets the
worker count:

- unset or malformed: the machine's available parallelism
- `1`: the plain sequential loop
- `n > 1`: at most `n` scoped threads; batches smaller than two items always
  run inline

Every value produces identical output. Results land in input order, the
reported error is the one of the lowest failing index, and a worker panic
leaves the batch instead of vanishing. Paragraph-level evidence capture and
the metric cache are shared across workers; each paragraph owns its capture
window.

```js
import { createPrecomputer } from "@tiqian/precompute/precompute";

const precomputer = await createPrecomputer({ typography, fonts });
const entries = await precomputer.prepareParagraphs(paragraphs);
const contracts = await precomputer.prepareFontContracts(contractInputs);
```

`prepareHtml` spreads inside one call: the document walk, the projection, and
the output reassembly stay sequential in document order, while each element's
snapshot attempt and contract fallback run over the workers with the same
guarantees as the explicit batch entries.

Singular entries (`prepareParagraph`, `prepareFontContract`) stay sequential;
font contract retries are rare and their evidence windows belong to one
paragraph each.

## Local development

From this directory:

```sh
npm install
npm run debug:native   # cargo build + neon dist into platforms/<current>/
npm run lint           # bans `any` and `as unknown`; no inline disable
npm run build          # tsc emit into lib/
npm run typecheck      # src + test against the built lib/, no emit
npm test               # node --test over test/, against the built lib/
```

`npm run build:native` produces the release build. The sources are TypeScript
(`src/`); the published package ships the compiled `lib/`, and the tests run
against that output. The CI lane (`build-neon-precompute.yml`) builds every
supported platform and uploads the platform packages as artifacts; publishing
is a separate workflow.

Releases go to npmjs.org from annotated `@tiqian/precompute@<version>` tags
(`publish-precompute.yml`). Snapshot publication is manual-only
(`snapshot-precompute.yml`): each dispatch stamps its own
`precompute-snapshot-<UTC timestamp>` tag, temporarily swaps the five
manifests to the running repository owner's scope (GitHub Packages requires
the npm scope to equal the owner; `@tiqian-cjk` on the canonical
repository), publishes `<base>-snapshot.<timestamp>` versions with the
`snapshot` dist-tag to GitHub Packages, and restores the
manifests. The addon loader resolves the platform packages under whatever
scope its own manifest carries, so the swapped packages load without a source
patch. Consumers install by exact version with
`--registry=https://npm.pkg.github.com` and a token carrying `read:packages`.
