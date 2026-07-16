function resolvedStyleAt(textOffset, spans, typography) {
  const span = [...spans].reverse().find((candidate) =>
    Number.isSafeInteger(candidate?.start) && Number.isSafeInteger(candidate?.end) &&
    textOffset >= candidate.start && textOffset < candidate.end);
  return {
    fontFamilies: Array.isArray(span?.fontFamilies)
      ? span.fontFamilies.map(String)
      : [...typography.fontFamilies],
    fontSizePx: Number(span?.fontSizePx ?? typography.fontSizePx),
    fontWeight: Number(span?.fontWeight ?? typography.fontWeight),
    italic: span?.italic ?? typography.italic,
    baselineShiftPx: Number(span?.baselineShiftPx ?? 0),
  };
}

/**
 * RequiredCjkDashReplayCorpus: ordinary missing exact runs can fall back to the
 * browser shaper independently, but `——` / `⸺` require server evidence. When a
 * larger runtime-only paragraph cannot be fully precomputed, retain a minimal
 * probe for every style that actually owns one of those source sequences.
 */
export function requiredCjkDashContractInput(input, typography) {
  const text = String(input?.text ?? "");
  const spans = Array.isArray(input?.textSpans) ? input.textSpans : [];
  const styleGroups = [];
  const groupsBySignature = new Map();
  for (const match of text.matchAll(/——|⸺/gu)) {
    const style = resolvedStyleAt(match.index, spans, typography);
    const signature = JSON.stringify(style);
    let group = groupsBySignature.get(signature);
    if (group == null) {
      group = { style, dashes: [] };
      groupsBySignature.set(signature, group);
      styleGroups.push(group);
    }
    if (!group.dashes.includes(match[0])) group.dashes.push(match[0]);
  }
  if (styleGroups.length === 0) return null;

  let probeText = "";
  const textSpans = [];
  for (const { style, dashes } of styleGroups) {
    for (const dash of dashes) {
      const start = probeText.length;
      probeText += dash;
      textSpans.push({ start, end: probeText.length, ...style });
    }
  }
  return {
    key: String(input.key ?? ""),
    text: probeText,
    maxWidthPx: input.maxWidthPx,
    textSpans,
  };
}
