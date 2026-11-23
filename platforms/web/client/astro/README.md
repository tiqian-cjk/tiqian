# `@tiqian/astro`

Static Astro integration for `@tiqian/web-component`.

```shell
npm install @tiqian/web-component@alpha @tiqian/astro@alpha
```

For semantic SSR plus live-width browser enhancement, add `tiqian()` to
`astro.config.mjs` with no font configuration. Configure the exact host font
only when build-time replay evidence is wanted:

```js
import { tiqian } from "@tiqian/astro";

export default defineConfig({
  integrations: [tiqian()],
});
```

For width-independent exact-font replay, add the host font contract without a
maximum width:

```js
export default defineConfig({
  integrations: [tiqian({
    fontStylesheets: [{ source: new URL("./src/article.css", import.meta.url), publicUrl: "/article.css" }],
    typography: { fontFamilies: ["Article Sans"], fontSizePx: 18, lineHeightPx: 32 },
  })],
});
```

Then wrap the existing rendered content:

```astro
---
import TiqianProse from "@tiqian/astro/TiqianProse.astro";
---

<TiqianProse><Content /></TiqianProse>
```

The configured font path emits semantic HTML plus width-independent exact-font
replay. With plain `tiqian()` it emits semantic HTML and uses the live browser
font path. `snapshotMaxWidthPx` is an optional fixed-measure optimization. This alpha
integration supports Astro static/prerender output; on-demand SSR is not yet
advertised.

Hosts with an existing richer server projector can pass its `{ html,
rootAttributes, serverAssets }` result through the `prepared` prop. The adapter
still owns component rendering and build-time asset hoisting, while the host
keeps only its product-specific inline metric projection.

## Snapshot tables

The preparer freezes a content-addressed snapshot table per `prepare` call
(ADR 0052 schema 2). A `tables` option turns on delivery end to end: each
table file lands in the configured directory, the root element carries a
`tq-tables` URL pointing at it, the dev server serves those URLs, and the
build ships exactly the tables the built pages reference:

```js
export default defineConfig({
  integrations: [tiqian({
    typography: { fontFamilies: ["Article Sans"], fontSizePx: 18, lineHeightPx: 32 },
    tables: { directory: ".cache/tiqian/tables" },
  })],
});
```

`directory` is required (`urlPrefix` defaults to `tiqian-tables`, `extension`
to `.tiqtbl`). Hosts running their own shaping pipeline configure `tables`
alone, without `typography`; the shipping and dev-serving hooks work the
same for both steps.
