// Shared test types for the npm package.
// Consolidates test-side shapes used across multiple test files.

export interface GlobalEntry {
  readonly name: string;
  readonly own: boolean;
  readonly value: unknown;
}

export interface FakeClock {
  pendingTimerCount(): number;
  advance(ms: number): void;
}

export interface PreserveGlobalsFn {
  (names: readonly string[]): GlobalEntry[];
}

export interface RestoreGlobalsFn {
  (entries: readonly GlobalEntry[]): void;
}

export interface InstallFakeClockFn {
  (): FakeClock;
}

// ---- Fake DOM shapes (Pick-based, all members public) ----

export interface FakeNodeBase {
  readonly nodeType: number;
  readonly childNodes: FakeNode[];
  readonly parentNode: FakeNode | null;
  readonly parentElement: FakeElement | null;
  readonly firstChild: FakeNode | null;
  readonly nextSibling: FakeNode | null;
  append(...nodes: FakeNode[]): void;
  appendChild(node: FakeNode): FakeNode;
  insertBefore(node: FakeNode, reference: FakeNode | null): FakeNode;
  replaceChild(next: FakeNode, previous: FakeNode): FakeNode;
  removeChild(node: FakeNode): FakeNode;
  remove(): void;
  textContent: string;
  querySelectorAll(selector: string): FakeElement[];
  querySelector(selector: string): FakeElement | null;
  cloneNode(deep?: boolean): FakeNode;
}

export interface FakeNode extends FakeNodeBase {}

export interface FakeText extends FakeNodeBase {
  readonly nodeType: 3;
  readonly value: string;
  cloneNode(): FakeText;
}

export type FixtureProbeMeasureFn = (cssText: string) => void;

export interface FakeAttributeEntry {
  readonly name: string;
  readonly value: string;
}

export interface FakeElement extends FakeNodeBase {
  readonly nodeType: 1;
  readonly tagName: string;
  readonly attributes: Map<string, string> | FakeAttributesMap;
  readonly dataset: Record<string, string | undefined>;
  readonly style: FakeInlineStyle;
  readonly ownerDocument: FakeDocument | null;
  readonly width: number;
  readonly height: number;
  readonly left: number;
  readonly top: number;
  setAttribute(name: string, value: string): void;
  getAttribute(name: string): string | null;
  hasAttribute(name: string): boolean;
  removeAttribute(name: string): void;
  innerText: string;
  getBoundingClientRect(): DOMRect;
  getClientRects(): DOMRect[];
  closest(selector: string): FakeElement | null;
  _innerText: string | null;
  _fixtureProbeWidth?: number;
  _onFixtureProbeMeasure?: FixtureProbeMeasureFn;
}

export interface FakeFragment extends FakeNodeBase {
  readonly nodeType: 11;
  cloneNode(deep?: boolean): FakeFragment;
}

export type FakeAttributeTuple = [string, string] & FakeAttributeEntry;

/**
 * A DOM attribute list iterates [name, value] tuples that also carry name and
 * value properties. Declaring that richer tuple as the Map iterator makes the
 * fake structurally incompatible with Map<string, string>, which every
 * consumer here expects, so the interface keeps the Map shape and the fake
 * supplies the extra properties at run time.
 */
export interface FakeAttributesMap extends Map<string, string> {}

export interface FakeInlineStyle {
  _values: Map<string, string>;
  _priorities: Map<string, string>;
  getPropertyValue(name: string): string;
  getPropertyPriority(name: string): string;
  setProperty(name: string, value: string | null, priority?: string): void;
  removeProperty(name: string): string;
  cssText: string;
}

export type FakeFontLoadFn = (descriptor: unknown, text: string) => Promise<unknown[]>;
export type FakeFontEventListenerFn = () => void;

export interface FakeFonts {
  readonly load: FakeFontLoadFn;
  readonly addEventListener: FakeFontEventListenerFn;
  readonly removeEventListener: FakeFontEventListenerFn;
}

export interface FakeRangeRect {
  readonly width: number;
}

export interface FakeRange {
  selectNodeContents(node: FakeNode): void;
  getBoundingClientRect(): FakeRangeRect;
}

export interface FakeDocument {
  readonly baseURI: string;
  readonly elements: Map<string, unknown>;
  readonly styleSheets: unknown[];
  readonly listeners: Map<string, unknown>;
  readonly fonts: FakeFonts;
  createDocumentFragment(): FakeFragment;
  createElement(tagName: string): FakeElement;
  createRange(): FakeRange;
  getElementById(id: string): FakeElement | null;
  querySelector(selector: string): FakeElement | null;
  querySelectorAll(selector: string): FakeElement[];
  addEventListener(name: string, listener: unknown): void;
  removeEventListener(name: string, listener: unknown): void;
  dispatchEvent(event: FakeEvent): boolean;
  readonly body: FakeElement;
  readonly head: FakeElement;
  readonly documentElement: FakeElement;
}

export interface FakeEvent {
  readonly type: string;
  readonly bubbles: boolean;
  readonly cancelable: boolean;
  readonly defaultPrevented: boolean;
  readonly detail: unknown;
  readonly target: FakeNode | null;
  readonly currentTarget: FakeNode | null;
  preventDefault(): void;
}

export interface FakeCustomEvent extends FakeEvent {
  readonly detail: unknown;
}

export interface FakeDataTransfer {
  _data: Record<string, string>;
  setData(type: string, value: string): void;
  getData(type: string): string;
}

export interface FakeSelection {
  _ranges: unknown[];
  readonly rangeCount: number;
  readonly isCollapsed: boolean;
  getRangeAt(index: number): unknown | null;
  removeAllRanges(): void;
  addRange(range: unknown): void;
  toString(): string;
}

export interface FakeDOMRectJSON {
  readonly x: number;
  readonly y: number;
  readonly top: number;
  readonly left: number;
  readonly right: number;
  readonly bottom: number;
  readonly width: number;
  readonly height: number;
}

export interface FakeDOMRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly top: number;
  readonly left: number;
  readonly right: number;
  readonly bottom: number;
  toJSON(): FakeDOMRectJSON;
}

// ---- snapshot-dom-fixtures exports ----

export interface CanonicalFixtureNode {
  (node: FakeNode): unknown;
}

export interface FixtureComputedStyle {
  (element: FakeElement | null, pseudo: string | null, overrides?: Record<string, string>): Record<string, string>;
}

export interface Sha256Fn {
  (value: string): string;
}

export interface FakeStyleDeclaration {
  getPropertyValue(name: string): string;
}

export interface StyleDeclarationFn {
  (values: Record<string, string>): FakeStyleDeclaration;
}

// ---- browser-fonts-fixtures exports ----

export interface FaceEvidenceFn {
  (sourceSha256: string, overrides?: Record<string, unknown>): Record<string, unknown>;
}

export interface ManifestWithFacesFn {
  (
    facesByEntry: Record<string, unknown>[][],
    versions?: string[],
    typography?: Record<string, unknown>,
    extras?: Record<string, unknown>
  ): Record<string, unknown>;
}

export interface SnapshotRootFn {
  (manifest: Record<string, unknown>, documentOverrides?: Record<string, unknown>): Record<string, unknown>;
}

export type VoidCountFn = () => number;

export interface HarnessResult {
  readonly loader: unknown;
  readonly root: Record<string, unknown>;
  readonly requests: unknown[];
  readonly createCalls: unknown[];
  readonly sessions: unknown[];
  readonly contractCalls: unknown[];
  readonly preparedContractCalls: unknown[];
  readonly renderFaceCreates: unknown[];
  readonly renderFaceAdds: unknown[];
  readonly renderFaceDeletes: unknown[];
  readonly renderFontSourceCreates: unknown[];
  readonly renderFontSourceReleases: unknown[];
  readonly fontLoads: unknown[];
  readonly closeCount: VoidCountFn;
}

export interface HarnessFn {
  (manifest: Record<string, unknown>, options?: Record<string, unknown>): HarnessResult;
}

export interface CurrentTableInfo {
  readonly url: string;
  readonly bytes: Uint8Array;
  readonly sha256: string;
}

export interface GetCurrentTableFn {
  (): CurrentTableInfo | null;
}

// ---- runtime-host exports ----

export type VoidFn = () => void;

export interface MountResult {
  readonly root: FakeElement;
  readonly cleanup: VoidFn;
}

export interface CleanupMountedFn {
  (): void;
}

export interface MountFn {
  (html: string): FakeElement;
}

export interface SetElementRectFn {
  (element: FakeElement, left: number, width: number): void;
}

export interface InstallTestAnimationFramesFn {
  (): void;
}

export type HostEnhanceFn = (root: Element, options?: unknown) => number;

export interface HostRuntime {
  readonly enhance: HostEnhanceFn;
}

export interface LoadHostRuntimeFn {
  (): Promise<HostRuntime>;
}

export interface DrainMicrotasksFn {
  (rounds?: number): Promise<void>;
}

export interface FlushAllTestAnimationFramesFn {
  (): void;
}

// ---- timing-golden-host exports ----

export interface ElementDriveGlobals {
  readonly FRAME_STEP_MS: number;
  readonly ELEMENT_DRIVE_GLOBALS: readonly string[];
}

export interface DriveElementTimelineFn {
  (clock: FakeClock, journeyKey: string, options?: Record<string, unknown>): Promise<Record<string, unknown>>;
}

export interface DriveDeclaredFaceWakeTimelineFn {
  (clock: FakeClock, journeyKey: string): Promise<Record<string, unknown>>;
}

// ---- Timing golden record shape ----

export interface TimingElementEvent {
  readonly phase: string;
  readonly type: string;
  readonly detail: Record<string, unknown>;
}

export interface TimingDocumentEvent {
  readonly phase: string;
  readonly type: string;
}

export interface TimingDatasetWrite {
  readonly phase: string;
  readonly op: string;
  readonly key: string;
  readonly value: string | null;
}

export interface TimingAttributeWrite {
  readonly phase: string;
  readonly name: string;
  readonly value: string | null;
}

export interface TimingObserverOp {
  readonly op: string;
  readonly target: string;
}

export interface TimingObserverActivity {
  readonly id: number;
  readonly ops: TimingObserverOp[];
}

export interface TimingGoldenRecord {
  readonly engineCalls: unknown[];
  readonly elementEvents: TimingElementEvent[];
  readonly documentEvents: TimingDocumentEvent[];
  readonly datasetWrites: TimingDatasetWrite[];
  readonly attributeWrites: TimingAttributeWrite[];
  readonly fetchCalls: string[];
  readonly observerActivity: TimingObserverActivity[];
  readonly frameAdvanceCounts: Record<string, number>;
  readonly paragraphStates: Record<string, Record<string, unknown>>;
  readonly declaredWake?: Record<string, unknown>;
}