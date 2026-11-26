import type { DecorationSpan, TextSpan, TextStyle } from "./lowered-paragraph.js";
import { textStylesEqual } from "./lowered-paragraph.js";

import type { FontRole } from "@tiqian/engine/org/tiqian/font/FontRole";

function isCjkRole(role: FontRole): boolean {
  return role.kind === "CjkText" || role.kind === "CjkPunctuation";
}

export type ClassifyRolesFn = (
  text: string,
  starts: number[],
  ends: number[],
  locale: string,
) => FontRole[];

export interface PendingStrongTextRange {
  start: number;
  end: number;
  style: TextStyle;
  strongBaseWeight: number;
}

interface ProjectedStrongCluster {
  start: number;
  end: number;
  pendingIndex: number;
}

type ProjectRangeFn = (start: number, end: number) => [number, number] | null;

let graphemeSegmenter: Intl.Segmenter | null = null;
if (typeof Intl !== "undefined" && Intl.Segmenter) {
  try {
    graphemeSegmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  } catch (error) {
    graphemeSegmenter = null;
  }
}

function graphemeBoundaries(value: string): number[] {
  const boundaries = [0];
  if (graphemeSegmenter) {
    const items = graphemeSegmenter.segment(value);
    const iterator = items[Symbol.iterator]();
    for (let step = iterator.next(); !step.done; step = iterator.next()) {
      const index = step.value.index;
      if (index > 0 && index < value.length) boundaries.push(index);
    }
  } else {
    let offset = 0;
    const points = Array.from(value);
    for (let index = 0; index < points.length; index++) {
      offset += points[index].length;
      if (offset < value.length) boundaries.push(offset);
    }
  }
  boundaries.push(value.length);
  return boundaries;
}

/**
 * Applies deferred strong-as-emphasis semantics after the complete paragraph
 * and its whitespace projection are available. Role classification therefore
 * sees context across DOM text-node boundaries and runs once per locale.
 */
export function appendProjectedStrongStyles(
  pendingRanges: PendingStrongTextRange[],
  loweredText: string,
  projectRange: ProjectRangeFn,
  classifyRoles: ClassifyRolesFn,
  baseStyle: TextStyle,
  spans: TextSpan[],
  decorations: DecorationSpan[],
): void {
  const clusters: ProjectedStrongCluster[] = [];
  for (let pendingIndex = 0; pendingIndex < pendingRanges.length; pendingIndex++) {
    const pending = pendingRanges[pendingIndex];
    const projected = projectRange(pending.start, pending.end);
    if (!projected) continue;
    const value = loweredText.substring(projected[0], projected[1]);
    const boundaries = graphemeBoundaries(value);
    for (let boundaryIndex = 0; boundaryIndex + 1 < boundaries.length; boundaryIndex++) {
      const start = projected[0] + boundaries[boundaryIndex];
      const end = projected[0] + boundaries[boundaryIndex + 1];
      if (end > start) clusters.push({ start: start, end: end, pendingIndex: pendingIndex });
    }
  }
  if (clusters.length === 0) return;

  const roles: FontRole[] = new Array<FontRole>(clusters.length);
  const clusterIndexesByLocale = new Map<string, number[]>();
  for (let index = 0; index < clusters.length; index++) {
    const locale = pendingRanges[clusters[index].pendingIndex].style.locale;
    const existingIndexes = clusterIndexesByLocale.get(locale);
    const localeIndexes = existingIndexes !== undefined ? existingIndexes : [];
    localeIndexes.push(index);
    clusterIndexesByLocale.set(locale, localeIndexes);
  }
  for (const [locale, clusterIndexes] of clusterIndexesByLocale) {
    const starts = clusterIndexes.map(function (index) { return clusters[index].start; });
    const ends = clusterIndexes.map(function (index) { return clusters[index].end; });
    const localeRoles = classifyRoles(loweredText, starts, ends, locale);
    for (let index = 0; index < clusterIndexes.length; index++) {
      roles[clusterIndexes[index]] = localeRoles[index];
    }
  }

  const appendRun = function (firstCluster: number, endCluster: number, isCjk: boolean): void {
    const cluster = clusters[firstCluster];
    const pending = pendingRanges[cluster.pendingIndex];
    const start = cluster.start;
    const end = clusters[endCluster - 1].end;
    const style = isCjk
      ? {
          fontFamilies: pending.style.fontFamilies,
          fontSize: pending.style.fontSize,
          fontWeight: pending.strongBaseWeight,
          italic: pending.style.italic,
          baselineShift: pending.style.baselineShift,
          locale: pending.style.locale,
        }
      : pending.style;
    if (!textStylesEqual(style, baseStyle)) spans.push({ start: start, end: end, style: style });
    if (isCjk) decorations.push({ start: start, end: end, kind: "Emphasis" });
  };

  let runStart = 0;
  let runIsCjk = isCjkRole(roles[0]);
  for (let index = 1; index <= clusters.length; index++) {
    const samePending = index < clusters.length &&
      clusters[index].pendingIndex === clusters[runStart].pendingIndex;
    const isCjk = index < clusters.length &&
      isCjkRole(roles[index]);
    if (!samePending || isCjk !== runIsCjk) {
      appendRun(runStart, index, runIsCjk);
      runStart = index;
      runIsCjk = isCjk;
    }
  }
}
