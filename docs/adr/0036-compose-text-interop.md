# ADR 0036: Compose TextStyle interop and rich-text capability report

- Status: Accepted
- Date: 2026-06-24

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
- `CjkParagraph` / `CjkText` overloads that accept Compose `style: TextStyle`;
- `ParagraphMeasurer.measure(AnnotatedString, ..., style: TextStyle)` for pre-layout;
- `AnnotatedString.cjkTextCompatibility(style)` returning structured
  `CjkTextCapabilityIssue`s.

The compatibility report is the renderer boundary, but it is not a host-renderer switch.
Tiqian accepts the input shape; the report returns `canPreserveAllKnownSemantics = true` only when
the current Compose frontend can preserve every detected feature. Links, URL/TTS annotations, inline
placeholders, unknown string annotations, brush foregrounds, backgrounds, text decorations, shadows,
draw styles, baseline shifts, geometric transforms, locale lists, synthesis, font-feature settings,
letter spacing, non-generic font families, platform styles, paragraph style ranges, and Compose
paragraph controls are reported as Tiqian capability issues.

Supported Compose rich text remains the subset already wired through the real pipeline:

- source text unchanged;
- paragraph `TextStyle` color, font size, line height, generic font family, weight, and italic
  lowered through `CjkTextStyle`;
- `SpanStyle.color` as render-only `ColorSpan`;
- `SpanStyle.fontSize` / `fontWeight` / `fontStyle` / generic `fontFamily` as layout-affecting
  `TextSpan`s; span-level `.em` font size remains relative to the resolved paragraph font size;
- Tiqian builders for emphasis, proper noun, mourning, book title, ruby, and bopomofo.

## Integration rule

Applications should integrate Tiqian after their rich-text renderer has produced its Compose
paragraph model, not before. A Markdown renderer should hand Tiqian the same `AnnotatedString` and
style it would hand to Compose text, then use `cjkTextCompatibility` to expose what Tiqian still
needs to implement:

```kotlin
val compatibility = annotated.cjkTextCompatibility(style)
check(compatibility.canPreserveAllKnownSemantics) { compatibility.issues }
CjkParagraph(annotated, style = style)
```

Inline widgets need a future explicit Tiqian inline-object contract; until then, paragraphs carrying
object replacement characters or renderer-owned placeholder annotations are accepted but reported as
model gaps. A Markdown AST or HTML wrapper may still provide application-owned emergency containment,
but Tiqian itself must not route around its own renderer during dogfooding.

## Consequences

- Existing `CjkTextStyle` call sites keep their narrow, honest authoring surface.
- Compose applications get a low-friction migration shape without pretending Tiqian supports every
  Compose text feature.
- Capability gaps become explainable and testable instead of being hidden by a host-renderer detour.
- Frontend modules still do not make CLREQ/font-fallback/glue/kinsoku/justification decisions; they only
  lower style values and expose capability reports.
- `CjkParagraph` exposes the source `AnnotatedString` to Compose semantics for baseline screen-reader
  text. Geometry-sensitive actions (links, selection, TalkBack character boxes) must be backed by
  Tiqian `LayoutResult` queries such as offset/line/box/range hit testing, not by a hidden Compose
  Text layout.
- Vertical writing and JLREQ remain out of scope. The compatibility report can grow new reasons or
  supported features without changing source text semantics.

## Verification

```shell
./gradlew :tiqian-compose:jvmTest --tests 'org.tiqian.compose.CjkTextCompatibilityTest'
```
