import { globalServices } from "../services/global-services.js";

/** Return null to use the browser's native loading for this request. */
export type BrowserFontFaceLoader = (
  fonts: FontFaceSet,
  descriptor: string,
  text: string,
) => Promise<FontFace[] | null>;

export async function loadBrowserFontFaces(
  fonts: FontFaceSet,
  descriptor: string,
  text: string,
): Promise<FontFace[]> {
  // Hosts may supply equivalent, already-loaded faces; CSS and geometry
  // evidence still pass through the normal snapshot validation pipeline.
  try {
    const faces = await globalServices().coordination.fonts.fontFaceLoader?.(fonts, descriptor, text);
    if (faces) return faces;
  } catch {
    // Optional cache failures retain the ordinary CSS font-loading path.
  }
  return fonts.load(descriptor, text);
}
