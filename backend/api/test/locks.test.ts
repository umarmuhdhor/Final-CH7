import { describe, expect, it } from "vitest";
import { LOCK } from "../src/db/locks";

// Fase 27k F-B12: pg_advisory_xact_lock(class, key) shares one key space per class. Two purposes on
// one class make unrelated work wait on each other whenever their keys hash alike (a favicon reserve
// for owner X and a verdict on domain Y), and could close a lock cycle nobody planned.

const workerSources = import.meta.glob(["../src/**/*.ts", "!../src/db/locks.ts"], { query: "?raw", import: "default", eager: true });
const migrations = import.meta.glob("../../db/supabase/migrations/*.sql", { query: "?raw", import: "default", eager: true });

/** Classes of the two-argument form, pg_advisory_xact_lock(<int literal>, …), in SQL text. */
const literalClasses = (text: string): number[] =>
  [...text.matchAll(/pg_advisory_xact_lock\(\s*(\d+)\s*,/g)].map((m) => Number(m[1]));

describe("advisory lock classes (db/locks.ts)", () => {
  it("one class per purpose", () => {
    const classes = Object.values(LOCK);
    expect(new Set(classes).size).toBe(classes.length);
  });

  it("no Worker class is one the SQL functions in the migrations use", () => {
    const sqlClasses = new Set(Object.values(migrations).flatMap(literalClasses));
    expect(sqlClasses.size).toBeGreaterThan(0); // the admin functions take (7, 1), (8, 0), (9, …)
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
