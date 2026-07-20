const SNAPSHOT_ID = /^[A-Za-z][A-Za-z0-9_-]*$/u;

function requireBundle(bundle) {
  if (!bundle || typeof bundle !== "object" || Array.isArray(bundle)) {
    throw new Error("SnapshotBundleInvalid");
  }
  const id = String(bundle.id ?? "").trim();
  if (!SNAPSHOT_ID.test(id)) throw new Error("SnapshotBundleIdInvalid");
  if (typeof bundle.clientTemplate !== "string" || bundle.clientTemplate.trim() === "") {
    throw new Error("SnapshotClientTemplateMissing");
  }
  if (typeof bundle.initialStyle !== "string") throw new Error("SnapshotInitialStyleInvalid");
  const fontPreloads = Array.from(bundle.fontPreloads ?? []);
  if (fontPreloads.some((url) => typeof url !== "string" || url.trim() === "")) {
    throw new Error("SnapshotFontPreloadsInvalid");
  }
  return { id, clientTemplate: bundle.clientTemplate, initialStyle: bundle.initialStyle, fontPreloads };
}

function parsedTemplate(documentObject, id, html) {
  const parser = documentObject.createElement("template");
  parser.innerHTML = html.trim();
  const template = parser.content.firstElementChild;
  if (
    !template || template.tagName !== "TEMPLATE" || template.id !== id ||
    parser.content.childElementCount !== 1
  ) throw new Error("SnapshotClientTemplateInvalid");
  return template;
}

function manifestText(template) {
  return template?.content?.querySelector?.("[data-tq-snapshot-manifest]")?.textContent ?? null;
}

function installInitialStyle(documentObject, id, css) {
  const selector = `style[data-tq-initial-snapshot="${id}"],style[data-tq-client-snapshot="${id}"]`;
  if (documentObject.querySelector(selector)) return;
  const style = documentObject.createElement("style");
  style.setAttribute("data-tq-client-snapshot", id);
  style.textContent = css;
  documentObject.head.append(style);
}

function installFontPreloads(documentObject, urls) {
  const existing = new Set(Array.from(
    documentObject.querySelectorAll('link[rel="preload"][as="font"]'),
    (link) => link.href,
  ));
  for (const value of urls) {
    const href = new URL(value, documentObject.baseURI).href;
    if (existing.has(href)) continue;
    const link = documentObject.createElement("link");
    link.rel = "preload";
    link.as = "font";
    link.type = "font/woff2";
    link.crossOrigin = "anonymous";
    link.href = value;
    documentObject.head.append(link);
    existing.add(href);
  }
}

/**
 * Registers the compact exact-font manifest before a client-routed article
 * creates its <tiqian-prose>. Client navigation keeps native source DOM and
 * uses the manifest-backed server-replay runtime path instead of duplicating the
 * prepared paragraph HTML in page data.
 */
export function registerSnapshotBundle(bundle, documentObject = globalThis.document) {
  if (!documentObject?.head || typeof documentObject.createElement !== "function") {
    throw new Error("SnapshotDocumentUnavailable");
  }
  const normalized = requireBundle(bundle);
  const template = parsedTemplate(
    documentObject,
    normalized.id,
    normalized.clientTemplate,
  );
  const existing = documentObject.getElementById(normalized.id);
  const sameManifestAlreadyRegistered = existing?.tagName === "TEMPLATE" &&
    manifestText(existing) != null && manifestText(existing) === manifestText(template);
  if (!sameManifestAlreadyRegistered) {
    if (existing) existing.replaceWith(template);
    else documentObject.head.append(template);
  }
  installInitialStyle(documentObject, normalized.id, normalized.initialStyle);
  installFontPreloads(documentObject, normalized.fontPreloads);
  return normalized.id;
}
