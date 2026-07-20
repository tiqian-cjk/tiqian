# ADR 0036: Compose TextStyle interop and rich-text capability report

- Status: Accepted
- Date: 2026-06-24
- Amendment 2026-07-07: `LinkAnnotation` pointer clicks are supported by hit-testing Tiqian's
  own `LayoutResult` geometry; URL links fall back to `LocalUriHandler`.
- Amendment 2026-07-07: `SpanStyle.baselineShift` is supported by lowering it to
  `TextStyle.baselineShift` and stacking that explicit author shift on the engine's cluster
  baseline geometry.

## Context

ADR 0030 deliberately kept `CjkTextStyle` narrow: author-written Tiqian text should only expose
fields the engine actually consumes. Dogfooding Tiqian inside a real Compose application exposed a
different migration problem: application text rarely starts as `String + CjkTextStyle`. It often
already exists as `AnnotatedString + androidx.compose.ui.text.TextStyle`, plus renderer-owned
links, inline widgets, string annotations, and span styles.

If the integration point is Markdown/HTML/AST, Tiqian must reconstruct a reduced `AnnotatedString`
and will inevitably drop renderer semantics. The application then cannot tell whether Tiqian
preserved the paragraph or merely drew a similar-looking subset. That is not a real migration path.

## Decision

Keep the explicit Tiqian-native API, and add a Compose interop API beside it:

- `Compose TextStyle -> CjkTextStyle` bridge via `TextStyle.toCjkTextStyle()`:
  paragraph-level `.sp` font sizes pass through, and paragraph-level `.em` font
  sizes resolve against the bridge's explicit default `CjkTextStyle.fontSize`
  before entering the engine;
- `CjkText` overloads that accept Compose `style: TextStyle`;
- `CjkText(text: String | AnnotatedString, ...)` as the source-faithful Compose Text replacement
  facade (see ADR 0037). It accepts the Compose Text call-site shape Tiqian can own without routing
  back to host text (`modifier`, `color`, `fontSize`, `fontStyle`, `fontWeight`, `fontFamily`,
  `textDecoration`, `textAlign`, `lineHeight`, `overflow`, `softWrap`, `maxLines`, `minLines`,
  `style`, `onTextLayout`). Source `\n`, CRLF, and Unicode mandatory breaks are hard breaks inside
  this plain-text flow, not a request to enter the structured block/list API. The implemented
  overflow modes are `TextOverflow.Clip` and `TextOverflow.Visible`; `Ellipsis` is reported as a
  capability gap until Tiqian has an explicit overflow-marker model instead of a renderer-side text
  rewrite;
- `CjkText(blocks = ...)` remains the explicit block/list document API. It is not the migration path
  for renderer-produced Compose rich text;
- `ParagraphMeasurer.measure(AnnotatedString, ..., style: TextStyle)` for pre-layout;
- `AnnotatedString.cjkTextCompatibility(style)` returning structured
  `CjkTextCapabilityIssue`s.

The compatibility report is the renderer boundary, but it is not a host-renderer switch.
Tiqian accepts the input shape; the report returns `canPreserveAllKnownSemantics = true` only when
the current Compose frontend can preserve every detected feature. Legacy URL/TTS annotations,
inline placeholders, unknown string annotations, brush foregrounds, shadows, draw styles,
geometric transforms, locale lists, synthesis, font-feature settings, letter spacing,
non-generic font families, platform styles, paragraph style ranges, and Compose paragraph controls
are reported as Tiqian capability issues.

Supported Compose rich text remains the subset already wired through the real pipeline:

- source text unchanged;
- paragraph `TextStyle` color, font size, line height, generic font family, weight, and italic
  lowered through `CjkTextStyle`;
- `SpanStyle.color` as render-only `ColorSpan`;
- `SpanStyle.fontSize` / `fontWeight` / `fontStyle` / generic `fontFamily` as layout-affecting
  `TextSpan`s; span-level `.em` font size remains relative to the resolved paragraph font size;
- `SpanStyle.baselineShift` as layout-affecting `TextSpan.baselineShift`: Compose multipliers
  resolve against the span's final font size, flip into Tiqian's +down coordinates, and stack with
  the engine's metric baseline alignment;
- `SpanStyle.background`, `TextDecoration.Underline`, and `TextDecoration.LineThrough` as
  `RichTextSpan`s painted from `LayoutResult` geometry; their source edges are also passed as
  cluster-boundary hints (`SourceRangeBoundaryClusterSplit`) so a link/underline ending before
  trailing punctuation such as `template.` does not fall back to proportional slicing through one
  Latin cluster. Underline reuses Tiqian's skip-ink primitive instead of drawing a raw line through
  glyph ink;
- `LinkAnnotation` ranges as `RichTextRole.Link` source ranges plus pointer click actions backed by
  Tiqian geometry: taps are mapped through `LayoutResult.getOffsetForPosition`, verified against
  `LayoutResult.getBoundingBoxes`, then dispatched to `linkInteractionListener` or, for
  `LinkAnnotation.Url`, `LocalUriHandler.openUri`. Accessibility link actions are not claimed
  beyond exposing the source `AnnotatedString` to semantics;
- paragraph-level `TextStyle.textDecoration` / background reach the same rich-text render-role path
  by wrapping the source `AnnotatedString` in an outer span; source text and existing annotations are
  preserved;
- `TextAlign.Start/Left/Justify/Center/End/Right` lowers only to Tiqian's existing
  `ParagraphStyle.lastLineAlignment` degree of freedom. Non-last lines remain CLREQ justified;
- `softWrap=false` measures with an unbounded line width; `maxLines` trims the visible line boxes;
  `minLines` reserves extra measured height without inventing hidden clusters; `TextOverflow.Clip`
  clips true overflow to the measured visible box but preserves engine-owned legal paint overhang
  (`LineEndHangingPunctuation`, `LineEndHangingHyphen`, and ink overhang from emitted clusters);
  `TextOverflow.Visible` leaves all overhang visible;
- source mandatory breaks (`\n`, coalesced CRLF, UAX#14 mandatory controls) create zero-advance,
  unshaped break clusters; consecutive and trailing breaks preserve blank lines, while long source
  lines still auto-wrap before the hard break;
- Tiqian `inlineCode { ... }` builder as `RichTextRole.InlineCode` plus generic monospace
  `TextSpan`; source text stays unchanged;
- Tiqian builders for emphasis, proper noun, mourning, book title, ruby, and bopomofo.

## Integration rule

Applications should integrate Tiqian after their rich-text renderer has produced its Compose
paragraph model, not before. A Markdown renderer should hand Tiqian the same `AnnotatedString` and
style it would hand to Compose text, then use `cjkTextCompatibility` to expose what Tiqian still
needs to implement:

```kotlin
val compatibility = annotated.cjkTextCompatibility(style, overflow = overflow)
check(compatibility.canPreserveAllKnownSemantics) { compatibility.issues }
CjkText(annotated, style = style, overflow = overflow)
```

Inline widgets need a future explicit Tiqian inline-object contract; until then, paragraphs carrying
object replacement characters or renderer-owned placeholder annotations are accepted but reported as
model gaps. Letter spacing needs to enter shaping/layout as a real advance-affecting text style,
not as renderer-side glyph spreading. A Markdown AST or HTML wrapper may still provide
application-owned emergency containment, but Tiqian itself must not route around its own renderer
during dogfooding.

## Consequences

- Existing `CjkTextStyle` call sites keep their narrow, honest authoring surface.
- Compose applications get a low-friction migration shape without pretending Tiqian supports every
  Compose text feature.
- Capability gaps become explainable and testable instead of being hidden by a host-renderer detour.
- Frontend modules still do not make CLREQ/font-fallback/glue/kinsoku/justification decisions; they only
  lower style values and expose capability reports.
- `CjkText` exposes the source `AnnotatedString` to Compose semantics for baseline screen-reader
  text. Link pointer actions are backed by Tiqian `LayoutResult` queries such as offset/box hit
  testing, not by a hidden Compose Text layout; selection and TalkBack character boxes remain future
  frontend work.
- Vertical writing and JLREQ remain out of scope. The compatibility report can grow new reasons or
  supported features without changing source text semantics.

## Verification

```shell
./gradlew :frontend:compose:jvmTest --tests 'org.tiqian.compose.CjkTextCompatibilityTest'
./gradlew :frontend:compose:jvmTest --tests 'org.tiqian.compose.CjkTextLinkClickTest'
./gradlew :frontend:compose:jvmTest --tests 'org.tiqian.compose.CjkTextRenderTest'
```
