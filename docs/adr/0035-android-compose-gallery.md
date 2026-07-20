# ADR 0035: Android Compose gallery frontend

- Status: Accepted
- Date: 2026-06-22

> [!NOTE]
> 2026-07-11：Compose 示例界面已从库模块与独立 gallery 收拢到共享的
> `demo`。Desktop 由该模块直接启动，`demo/android` 只保留 Android
> application 壳。下文的 `tiqian-gallery-android` 是本 ADR 落地时的历史名称。

## Context

ADR 0017 deliberately shipped `frontend/compose` as Desktop/JVM first: the renderer
used Skia `TextBlob`s and the module had no Android target. The next useful
gallery surface is Android Compose, because Android is one of the real platform
text stacks Tiqian already measures through `AndroidPaintTextShaper`, and the
app can showcase and validate the Compose API in one place.

This must be a real platform frontend, not a demo shortcut:

- Compose API must remain the same public surface (`CjkParagraph`, `CjkText`,
  rich text builders, list blocks).
- Compose must not make CLREQ, fallback, glue, kinsoku, justification, or
  paragraph decisions.
- Android measuring and Android drawing must use the same typeface resolver and
  context-shaped text path.
- AGP 9 must use the official Android-KMP library plugin for KMP library modules;
  the Android application stays in a separate app module.

## Decision

Add Android variants to the layout dependency chain:

```text
core / font / shaping-api / linebreak / clreq / layout / compose
```

These modules use `com.android.kotlin.multiplatform.library` and declare their
Android target inside the Kotlin block. The gallery entry point is a separate
`tiqian-gallery-android` application module, so app packaging does not leak into
shared library modules.

Move the Compose-facing API from `jvmMain` to `commonMain`. The common
`CjkParagraph` node owns measure and draw invalidation; platform code supplies:

- the default `ParagraphMeasurer`;
- the concrete renderer for `LayoutResult`.

Desktop keeps the existing Skia backend. Android uses:

- `AndroidPaintTextShaper` for real advances / glyph ids / halt measurement;
- `AndroidFontMetricsResolver` for Android `TextPaint` raw metrics plus the
  existing explicit CJK ideographic box fallback;
- `Canvas.drawTextRun` with Han context (`中<cluster>中`) for CJK roles, mirroring
  the Android shaper's `HanContextShaping`;
- Android `Paint`/`Path` drawing for emphasis dots, frames, interlinear lines,
  ruby, and Bopomofo placements.

Android default western hyphenation uses the same bundled
`EnglishHyphenation.enUs` TeX/Liang pattern source as JVM. Android's public
`LineBreaker` can report a platform-chosen hyphen edit for a concrete width
when `MeasuredText.Builder.setComputeHyphenation(...)` is enabled, but it does
not enumerate all dictionary opportunities. Tiqian pre-splits Latin words into
candidate clusters before its own line breaker scores lines, so the default
hyphenator must return enumerable opportunities rather than a single
width-specific platform choice.

## Consequences

- `frontend/compose` now produces an Android AAR and exposes the same public
  Compose API on Android and Desktop.
- Android gallery is a first-class Gradle module and can be launched as an app.
- Android rendering uses the same `LayoutResult` contract as Desktop, but the
  glyph backend is Android-native rather than Skia interop.
- CJK Android metrics remain honest about public API limits: raw metrics come
  from `TextPaint`; the ideographic box fallback is explicit until a table-backed
  Android resolver is justified.
- Android western hyphenation is deterministic en-US bundled data, matching JVM
  behaviour and enumerable for Tiqian's pre-split pipeline. Tests that need no
  hyphenation should continue to inject `NoHyphenator`.
- Android platform hyphenation remains a possible future comparison oracle, but
  it is not part of the default layout pipeline.

## Verification

```shell
./gradlew :frontend:compose:compileAndroidMain :demo:android:assembleDebug
./gradlew :frontend:compose:compileKotlinJvm :frontend:compose:jvmTest
```
