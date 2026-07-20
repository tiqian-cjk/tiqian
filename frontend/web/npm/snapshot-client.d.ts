export interface ClientSnapshotBundle {
  readonly id: string;
  readonly clientTemplate: string;
  readonly initialStyle: string;
  readonly fontPreloads: readonly string[];
}

export declare function registerSnapshotBundle(
  bundle: ClientSnapshotBundle,
  documentObject?: Document,
): string;
