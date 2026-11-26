// Browser build of the generated TypeScript trees.
//
// The web demo serves the working tree to a real Chromium, so the engine,
// protocol and shared packages (workspace members whose manifests point at
// .ts sources) are compiled to ESM JavaScript once per process and served
// from the generated-tree directories.

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import ts from "typescript";

const TREES = { engine: "ts", protocol: "protocol-ts", shared: "shared-ts" } as const;
export type GeneratedTree = keyof typeof TREES;

const TREE_PREFIXES: ReadonlyArray<{ tree: GeneratedTree; prefix: string }> = [
  { tree: "engine", prefix: "/engine/" },
  { tree: "protocol", prefix: "/protocol/" },
  { tree: "shared", prefix: "/shared/" },
];

/** The generated-tree module the path addresses, or null. */
export function browserTreePrefix(path: string): { tree: GeneratedTree; prefix: string } | null {
  for (const entry of TREE_PREFIXES) {
    if (path.startsWith(entry.prefix)) return entry;
  }
  return null;
}

/** Directory that holds one tree's browser build. */
export function browserTreeDirectory(repoRoot: string, tree: GeneratedTree): string {
  return join(repoRoot, "engine-haxe", "out", TREES[tree], "browser");
}

function sourceFiles(directory: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) files.push(...sourceFiles(path));
    else if (path.endsWith(".ts")) files.push(path);
  }
  return files;
}

/** Compiles the three generated trees for the browser (idempotent). */
export function buildBrowserTrees(repoRoot: string): void {
  for (const tree of Object.keys(TREES) as GeneratedTree[]) {
    const sourceRoot = join(repoRoot, "engine-haxe", "out", TREES[tree], "gen");
    const outRoot = browserTreeDirectory(repoRoot, tree);
    if (existsSync(join(outRoot, ".built"))) continue;
    const program = ts.createProgram(sourceFiles(sourceRoot), {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      moduleResolution: ts.ModuleResolutionKind.Bundler,
      allowImportingTsExtensions: true,
      rewriteRelativeImportExtensions: true,
      outDir: outRoot,
      rootDir: sourceRoot,
      declaration: false,
      sourceMap: false,
      skipLibCheck: true,
      strict: false,
      types: [],
    });
    const result = program.emit();
    if (result.emitSkipped) throw new Error(`BrowserTreeBuildFailed:${tree}`);
    mkdirSync(outRoot, { recursive: true });
    writeFileSync(join(outRoot, ".built"), "");
  }
}

/** Rewrites the worker's bare engine specifiers to served URLs. */
export function rewriteWorkerEngineSpecifiers(source: string): string {
  return source
    .replaceAll('from "@tiqian/engine/', 'from "/engine/')
    .replaceAll('from "@tiqian/protocol/', 'from "/protocol/')
    .replaceAll('from "@tiqian/shared/', 'from "/shared/');
}
