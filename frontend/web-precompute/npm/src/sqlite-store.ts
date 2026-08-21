// The SQLite reference store (ADR 0052): one ready-made PersistentCacheStore
// over the host runtime's built-in SQLite. node:sqlite is probed first, then
// bun:sqlite; runtimes without either (including Deno, which ships no
// built-in sqlite module) reject the factory by name and their hosts bring
// their own store. Entry bytes stay opaque rows addressed by the SDK's
// address strings; write batches land in one transaction.

import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

import type { PersistentCacheStore } from "./persistence.js";

/** The shared surface of the probed sqlite modules. */
interface SqliteStatement {
  run(...parameters: unknown[]): { changes: number | bigint };
  all(...parameters: unknown[]): unknown[];
}

interface SqliteDatabase {
  prepare(sql: string): SqliteStatement;
  exec(sql: string): unknown;
  close(): void;
}

/** One sqlite-backed store plus its maintenance entries. */
export interface SqliteCacheStore extends PersistentCacheStore {
  /**
   * Drops entries of one context that are not in the keep list. Returns the
   * number of rows removed; other contexts are untouched.
   */
  prune(context: string, keep: readonly string[]): number;
  /** Closes the database; later calls report by name. */
  close(): void;
}

async function openDatabase(path: string): Promise<SqliteDatabase> {
  try {
    const mod = await import("node:sqlite");
    return new mod.DatabaseSync(path);
  } catch {
    // Fall through to the next runtime's module.
  }
  // The bun specifier rides in a variable so TypeScript does not resolve it
  // as a module this package cannot type; the probed module is structural.
  const bunSpecifier = "bun:sqlite";
  try {
    const mod = await import(bunSpecifier);
    return new mod.DatabaseSync(path);
  } catch {
    // No probed module loaded.
  }
  throw new Error("SqliteCacheStoreUnavailable");
}

const isBytes = (value: unknown): value is Uint8Array => value instanceof Uint8Array;

// The file's structure version, kept in SQLite's user_version. Content
// versioning does not live here: record bytes are opaque and invalidate
// through the context fingerprint. A structure mismatch refuses by name;
// the file is a cache, so the host may delete it and rebuild.
const SCHEMA_VERSION = 1;

function migrate(db: SqliteDatabase): void {
  const row = db.prepare("PRAGMA user_version;").all()[0];
  const version = (row as { user_version?: unknown }).user_version;
  const current = typeof version === "number" ? version : 0;
  if (current === SCHEMA_VERSION) {
    // Idempotent: a versioned file from this store keeps its rows.
    db.exec(
      "CREATE TABLE IF NOT EXISTS tiqian_cache_entries (" +
        "address TEXT PRIMARY KEY, bytes BLOB NOT NULL);",
    );
    return;
  }
  if (current === 0) {
    // A fresh file (or one written before versioning): create and stamp.
    db.exec(
      "CREATE TABLE IF NOT EXISTS tiqian_cache_entries (" +
        "address TEXT PRIMARY KEY, bytes BLOB NOT NULL);",
    );
    db.exec(`PRAGMA user_version = ${SCHEMA_VERSION};`);
    return;
  }
  // A future version means a newer host wrote this file; an unknown past
  // version has no migration yet. Neither is read on guesswork.
  throw new Error(
    current > SCHEMA_VERSION
      ? "SqliteCacheStoreSchemaNewer"
      : "SqliteCacheStoreSchemaUnknown",
  );
}

/**
 * Opens (or creates) the database at `path`. The parent directory is created
 * when missing; the file belongs to the caller's cache directory policy.
 */
export async function createSqliteCacheStore(path: string): Promise<SqliteCacheStore> {
  mkdirSync(dirname(path), { recursive: true });
  const db = await openDatabase(path);
  db.exec("PRAGMA journal_mode = WAL;");
  migrate(db);
  db.exec("CREATE TEMP TABLE IF NOT EXISTS keep_list (address TEXT PRIMARY KEY);");
  const readStatement = db.prepare("SELECT bytes FROM tiqian_cache_entries WHERE address = ?;");
  const writeStatement = db.prepare(
    "INSERT OR REPLACE INTO tiqian_cache_entries (address, bytes) VALUES (?, ?);",
  );
  const clearKeepStatement = db.prepare("DELETE FROM keep_list;");
  const keepStatement = db.prepare(
    "INSERT OR REPLACE INTO keep_list (address) VALUES (?);",
  );
  const pruneStatement = db.prepare(
    "DELETE FROM tiqian_cache_entries WHERE address LIKE ? AND address NOT IN " +
      "(SELECT address FROM keep_list);",
  );
  let closed = false;
  const guard = (): void => {
    if (closed) {
      throw new Error("SqliteCacheStoreClosed");
    }
  };
  return {
    read(addresses: readonly string[]): Map<string, Uint8Array> {
      guard();
      const found = new Map<string, Uint8Array>();
      for (const address of addresses) {
        const rows = readStatement.all(address);
        const row = rows[0];
        if (row === undefined) continue;
        // One row per primary key; a row without bytes cannot occur through
        // this store's writes, and an external edit is skipped rather than
        // trusted.
        const value = (row as { bytes?: unknown }).bytes;
        if (isBytes(value)) {
          found.set(address, value);
        }
      }
      return found;
    },
    write(entries: readonly (readonly [string, Uint8Array])[]): void {
      guard();
      db.exec("BEGIN IMMEDIATE;");
      try {
        for (const [address, blob] of entries) {
          writeStatement.run(address, blob);
        }
        db.exec("COMMIT;");
      } catch (error) {
        db.exec("ROLLBACK;");
        throw error;
      }
    },
    prune(context: string, keep: readonly string[]): number {
      guard();
      db.exec("BEGIN IMMEDIATE;");
      try {
        clearKeepStatement.run();
        for (const address of keep) {
          keepStatement.run(address);
        }
        // Context fingerprints are hex, so the prefix match carries no LIKE
        // wildcards of its own.
        const outcome = pruneStatement.run(`${context}:%`);
        db.exec("COMMIT;");
        return Number(outcome.changes);
      } catch (error) {
        db.exec("ROLLBACK;");
        throw error;
      }
    },
    close(): void {
      guard();
      closed = true;
      db.close();
    },
  };
}
