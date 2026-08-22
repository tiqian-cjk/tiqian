import { fileURLToPath } from "node:url";

import { hoistTiqianAstroDirectory } from "./transport.js";

const VIRTUAL_MODULE_ID = "virtual:@tiqian/astro/preparer";
const RESOLVED_VIRTUAL_MODULE_ID = `\0${VIRTUAL_MODULE_ID}`;

function serializableSource(source) {
  if (source instanceof URL) return source.href;
  if (typeof source === "string") return source;
  throw new Error("TiqianAstroFontSourceMustBePathOrUrl");
}

function serializableOptions(options) {
  if (options.projectSnapshotParagraph != null || options.precomputer != null) {
    throw new Error("TiqianAstroNonSerializableHtmlPreparerOption");
  }
  return {
    typography: options.typography,
    ...(options.paragraphSelector == null ? {} : { paragraphSelector: options.paragraphSelector }),
    ...(options.skippedAncestorSelector == null
      ? {}
      : { skippedAncestorSelector: options.skippedAncestorSelector }),
    ...(options.fontStylesheets == null ? {} : {
      fontStylesheets: options.fontStylesheets.map((stylesheet) => ({
        ...stylesheet,
        source: serializableSource(stylesheet.source),
      })),
    }),
    ...(options.faces == null ? {} : {
      faces: options.faces.map((face) => ({ ...face, source: serializableSource(face.source) })),
    }),
  };
}

export function tiqian(options = {}) {
  const precomputeEnabled = options.typography != null;
  if (!precomputeEnabled && (options.fontStylesheets != null || options.faces != null || options.snapshot != null)) {
    throw new Error("TiqianAstroPrecomputeTypographyRequired");
  }
  const htmlOptions = precomputeEnabled ? serializableOptions(options) : null;
  const defaultSnapshot = options.snapshot == null ? null : {
    maxWidthPx: Number(options.snapshot.maxWidthPx),
  };
  if (defaultSnapshot && (!Number.isFinite(defaultSnapshot.maxWidthPx) || defaultSnapshot.maxWidthPx <= 0)) {
    throw new Error("InvalidMaximumMeasure");
  }
  const virtualSource = precomputeEnabled ? `
      import { createHtmlPreparer } from "@tiqian/precompute/precompute-html";
      const preparer = await createHtmlPreparer(${JSON.stringify(htmlOptions)});
      const defaultSnapshot = ${JSON.stringify(defaultSnapshot)};
      export async function prepareTiqianHtml(html, options = {}) {
        const snapshot = options.snapshot === undefined ? defaultSnapshot : options.snapshot;
        return preparer.prepare(html, { ...options, ...(snapshot == null ? {} : { snapshot }) });
      }
    ` : `
      export async function prepareTiqianHtml(html) {
        return {
          html: String(html),
          rootAttributes: {},
          bundle: null,
          clientBundle: null,
          serverAssets: null,
          issues: [],
        };
      }
    `;
  let buildOutput = "static";

  return {
    name: "@tiqian/astro",
    hooks: {
      "astro:config:setup": ({ updateConfig }) => {
        updateConfig({
          vite: {
            plugins: [{
              name: "@tiqian/astro-preparer",
              enforce: "pre",
              // `@tiqian/precompute` reads font and style files relative to
              // its own modules and loads a native addon at first use.
              // Inlining it into a server chunk moves those lookups onto the
              // chunk path. The top-level `ssr.external` key reaches only the
              // `ssr` environment; the prerendered chunks come from the
              // `prerender` environment, so every server environment names
              // the package here.
              configEnvironment(name) {
                if (name !== "ssr" && name !== "prerender" && name !== "astro") return undefined;
                return { resolve: { external: ["@tiqian/precompute"] } };
              },
              resolveId(id) {
                return id === VIRTUAL_MODULE_ID ? RESOLVED_VIRTUAL_MODULE_ID : null;
              },
              load(id) {
                return id === RESOLVED_VIRTUAL_MODULE_ID ? virtualSource : null;
              },
            }],
          },
        });
      },
      "astro:config:done": ({ buildOutput: output, injectTypes }) => {
        // `astro check` currently invokes this hook without a build output.
        // Enforce the transport boundary only when Astro is actually
        // configuring a static or server build.
        if (output != null) buildOutput = output;
        if (output != null && output !== "static") {
          throw new Error("TiqianAstroStaticOutputRequired");
        }
        injectTypes({
          filename: "tiqian-astro.d.ts",
          content: `
            declare module "virtual:@tiqian/astro/preparer" {
              import type { HtmlPrepareOptions, PreparedHtml } from "@tiqian/precompute/precompute-html";
              export function prepareTiqianHtml(
                html: string,
                options?: HtmlPrepareOptions,
              ): Promise<PreparedHtml>;
            }
          `,
        });
      },
      "astro:build:done": async ({ dir, logger }) => {
        if (buildOutput !== "static") return;
        const result = await hoistTiqianAstroDirectory(fileURLToPath(dir));
        if (result.snapshotCount > 0) {
          logger.info(`hoisted ${result.snapshotCount} Tiqian snapshots across ${result.pageCount} pages`);
        }
      },
    },
  };
}

export default tiqian;
