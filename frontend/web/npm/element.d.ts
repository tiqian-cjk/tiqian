export declare class TiqianProseElement extends HTMLElement {
  emphasisDotGapEm: number | null;
  strongAsEmphasisMarks: boolean;
  snapshotRef: string | null;
}

declare global {
  interface HTMLElementTagNameMap {
    "tiqian-prose": TiqianProseElement;
  }
}
