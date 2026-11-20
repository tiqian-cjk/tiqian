# @tiqian/ffi

Engine face for Tiqian paragraph precompute. The package carries the generated
TypeScript tree under `engine-gen/` and the hand-written facade modules under
`src/`; `npm run build:runtime` compiles the generated tree into `runtime/`
and copies the facade entries beside it.

`@tiqian/web-component` depends on this package for the layout worker engine. The two
packages release in lockstep from the same commit with exact-pinned versions, so
the worker engine and the browser runtime always come from one engine build.

## API

- `bopomofoParse(reading: string): string` — parse Bopomofo reading into symbols and tone.
- `numberSymbolCohesionUnbreakableRanges(text: string): string` — return inclusive index pairs for unbreakable number/symbol sequences.
- `fontMetricsResolve(requestJson: string): string` — resolve font metrics from JSON request.
- `fontFallbackResolve(text: string, start: number, end: number, requestJson: string): string` — resolve font fallback decision from JSON request.
- `liangHyphenate(word: string, patternsJson: string, exceptionsJson: string, leftMin?: number, rightMin?: number): string` — hyphenate a word using Liang patterns and exceptions.
- `unicodePunctuationLineBreakClassOf(codePoint: number): string` — return Unicode line break class name for a code point.
- `classifyFontRole(text: string, start: number, end: number, locale: string): string` — classify font role for a text range within the complete paragraph text.
- `classifyFontRoles(text: string, starts: Array<number>, ends: Array<number>, locale: string): Array<string>` — classify several ranges against one complete paragraph, resolving contextual quote/dash/ellipsis roles once.
- `unsupportedInlineShapingProperties(): Array<string>` — return ordered list of unsupported inline shaping CSS properties.
- `firstDivergentInlineShapingProperty(elementValues: Array<string>, paragraphValues: Array<string>): string | null` — find first divergent property between element and paragraph value arrays.
- `precomputePlainParagraph(...)` — plain paragraph plan; the full signature lives in `runtime/Tiqian-tiqian-ffi-js.d.mts`.
- `precomputeParagraph(...)` — paragraph plan with source semantics; the full signature lives in `runtime/Tiqian-tiqian-ffi-js.d.mts`.
- `precomputeParagraphWithDiagnostics(...)` — paragraph plan with diagnostics; the full signature lives in `runtime/Tiqian-tiqian-ffi-js.d.mts`.
- `precomputeParagraphWithBrowserMetrics(...)` — paragraph plan with browser shaping/metrics callbacks; the full signature lives in `runtime/Tiqian-tiqian-ffi-js.d.mts`.

## Build

The `runtime/` directory is generated. Rebuild it with:

```shell
npm run build:runtime
```

## Release

The first release ships the version already recorded in `package.json`
(`0.1.0-alpha.1`). Verify the package and create the annotated tag directly:

```shell
npm run verify:release
git tag -a "@tiqian/ffi@0.1.0-alpha.1" -m "@tiqian/ffi@0.1.0-alpha.1"
```

Later releases bump the version first:

```shell
npm run release:prepare -- 0.1.0-alpha.2
```

The command runs the same verification, commits the version bump, and creates
the annotated tag. Pushing a tag runs the publish workflow. Publish
`@tiqian/ffi` before the matching `@tiqian/web-component` release so the registry
dependency resolves.
