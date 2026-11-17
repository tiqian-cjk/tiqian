# `@tiqian/sveltekit`

SvelteKit integration for `@tiqian/web-component`. Plain component usage keeps the
server-rendered semantic HTML and enhances it at the live browser width:

```shell
npm install @tiqian/web-component@alpha @tiqian/sveltekit@alpha
```

```svelte
<script>
  import TiqianProse from "@tiqian/sveltekit";
</script>

<TiqianProse html={post.renderedContent} />
```

`html` must be HTML the application already trusts or sanitizes. This path needs
no maximum width, font-file path, or server hook: SSR returns the original
semantic paragraphs, and Tiqian measures the real browser container before
enhancing them.

For exact build-time font evidence, create one server integration, pass its
`handle` from `hooks.server.ts`, and prepare the HTML in a server load:

```ts
// src/lib/server/tiqian.ts
import { createTiqianSvelteKit } from "@tiqian/sveltekit/server";

export const tiqian = createTiqianSvelteKit({
  fontStylesheets: [{ source: new URL("./article.css", import.meta.url), publicUrl: "/article.css" }],
  typography: { fontFamilies: ["Article Sans"], fontSizePx: 18, lineHeightPx: 32 },
});
```

```ts
// src/hooks.server.ts
import { tiqian } from "$lib/server/tiqian";

export const handle = tiqian.handle;
```

```ts
// src/routes/article/[slug]/+page.server.ts
import { tiqian } from "$lib/server/tiqian";

export async function load() {
  const post = await loadPost();
  return { post, prose: await tiqian.prepare(post.renderedContent) };
}
```

```svelte
<script>
  import TiqianProse from "@tiqian/sveltekit";
  let { data } = $props();
</script>

<TiqianProse prepared={data.prose} />
```

No maximum width is required. Pass `{ snapshot: { maxWidthPx } }` to
`prepare()` only when opting into fixed-measure prepared geometry. The server
hook puts full inert assets in the document head while route data carries only
the compact bundle needed by client navigation.

Explicit `id` values identify one server-asset payload within a request or the
retained fallback cache. Reusing an id for different content in the same scope
throws `ConflictingTiqianSvelteKitAssets`; omit `id` to use the default
content-derived identity.

## Snapshot tables

The preparer freezes a content-addressed snapshot table per `prepare` call
(ADR 0052 schema 2). A `tables` option writes each table file to the
configured directory and stamps the root element with a `tq-tables` URL
pointing at it:

```ts
export const tiqian = createTiqianSvelteKit({
  typography: { fontFamilies: ["Article Sans"], fontSizePx: 18, lineHeightPx: 32 },
  tables: { directory: ".cache/tiqian/tables" },
});
```

`directory` is required (`urlPrefix` defaults to `tiqian-tables`, `extension`
to `.tiqtbl`). A `devDirectory` option redirects every non-production write:
only a build running with `NODE_ENV=production` writes `directory`, so the
committed directory changes only through a build. The integration exposes its
transport as `tiqian.tables`; a prerendered route serves the URLs and the
adapter step ships the written files:

```ts
// src/routes/tiqian-tables/[sha].tiqtbl/+server.ts
import { tiqian } from "$lib/server/tiqian";

export const GET = ({ params }) =>
  new Response(tiqian.tables.read(params.sha), {
    headers: { "content-type": "application/octet-stream", "cache-control": "public, max-age=31536000, immutable" },
  });

export const entries = async () =>
  (await import("$lib/server/tiqian-session")).tableEntries();
```

Run the whole build through one session (see
`@tiqian/precompute/transport`) so the route's `entries` generator sees every
table before the pages that reference them prerender.

Hosts that own their preparation pipeline and never call `prepare` through
this integration can create the transport on its own:

```ts
import { createTiqianTables } from "@tiqian/sveltekit/server";

export const tables = createTiqianTables({
  directory: "src/lib/data/tiqian-tables",
  devDirectory: "node_modules/.cache/tiqian-tables-dev",
});
```

The option set and the directory selection are the ones documented above; the
returned transport backs the same prerendered route shape through the host's
own helpers.
