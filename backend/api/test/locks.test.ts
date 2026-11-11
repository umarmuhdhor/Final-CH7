import { describe, expect, it } from "vitest";
import { LOCK } from "../src/db/locks";

// Fase 27k F-B12: pg_advisory_xact_lock(class, key) shares one key space per class. Two purposes on
// one class make unrelated work wait on each other whenever their keys hash alike (a favicon reserve
// for owner X and a verdict on domain Y), and could close a lock cycle nobody planned.

const workerSources = import.meta.glob(["../src/**/*.ts", "!../src/db/locks.ts"], { query: "?raw", import: "default", eager: true });
const migrations = import.meta.glob("../../db/supabase/migrations/*.sql", { query: "?raw", import: "default", eager: true });

/**
 * Classes of the two-argument forms (pg_advisory_xact_lock, pg_try_advisory_lock, …_shared, …) with an
 * int literal as class, in SQL text. Comments count too: a stale class number fails loudly.
 */
const literalClasses = (text: string): number[] =>
  [...text.matchAll(/pg_(?:try_)?advisory_(?:xact_)?lock(?:_shared)?\(\s*(\d+)\s*,/g)].map((m) => Number(m[1]));

describe("advisory lock classes (db/locks.ts)", () => {
  it("one class per purpose", () => {
    const classes = Object.values(LOCK);
    expect(new Set(classes).size).toBe(classes.length);
  });

  it("no Worker class is one the SQL functions in the migrations use", () => {
    expect(Object.keys(migrations).length).toBeGreaterThan(30);
    const sqlClasses = new Set(Object.values(migrations).flatMap(literalClasses));
    // The admin functions: blocklist decisions (7, …), API keys (8, 0), Worker secrets (9, …).
    expect([...sqlClasses]).toEqual(expect.arrayContaining([7, 8, 9]));
    expect(Object.entries(LOCK).filter(([, c]) => sqlClasses.has(c))).toEqual([]);
  });

  it("the Worker names every class through LOCK, never a number", () => {
    expect(Object.keys(workerSources).length).toBeGreaterThan(5);
    const literal = Object.entries(workerSources)
      .filter(([, text]) => literalClasses(text).length > 0)
      .map(([file]) => file);
    expect(literal).toEqual([]);
  });
});
