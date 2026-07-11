let stylesheetPromise;
let stylesheetElement;

export function ensureTiqianStyles() {
  const existing = document.querySelector("link[data-tiqian-stylesheet]");
  if (existing?.sheet) {
    stylesheetElement = existing;
    return Promise.resolve(existing);
  }
  if (existing && existing === stylesheetElement && stylesheetPromise) {
    return stylesheetPromise;
  }

  const link = existing ?? document.createElement("link");
  if (!existing) {
    link.rel = "stylesheet";
    link.href = new URL("./styles.css", import.meta.url).href;
    link.dataset.tiqianStylesheet = "true";
  }
  stylesheetElement = link;
  stylesheetPromise = new Promise((resolve, reject) => {
    link.addEventListener("load", () => resolve(link), { once: true });
    link.addEventListener(
      "error",
      () => reject(new Error("Tiqian stylesheet failed to load")),
      { once: true },
    );
    if (!existing) document.head.append(link);
  }).catch((error) => {
    if (stylesheetElement === link) {
      stylesheetElement = undefined;
      stylesheetPromise = undefined;
    }
    throw error;
  });
  return stylesheetPromise;
}
