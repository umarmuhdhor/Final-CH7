import postgres, { type Sql, type TransactionSql } from "postgres";
import { deleteDeviceInTx, insertProtectedCopy } from "../db/repo/devices";
import { insertLink, memberCount, type DeviceSummary } from "../db/repo/families";
import { errors } from "../http/errors";
import { guardianSummary, validateJoinInTx } from "./family";

export interface BecomeProtectedInput {
  /** The guardian device that becomes protected. */
  oldId: string;
  ipHash: Uint8Array;
  code: string;
  /** sha256 of the new device's token. */
  tokenHash: Uint8Array;
}

/**
 * Test-only pause and failure points (fase 27a race tests). Never set in the route. A retry
 * (deadlock or lock timeout) runs the whole transaction again, hooks included.
 */
export interface BecomeProtectedHooks {
  /** At the start of the transaction, before any lock. */
  beforeValidate?: () => Promise<void>;
  /** After validation, with the attempt and guardian locks held, before the copy exists. */
  afterValidate?: () => Promise<void>;
  /** After the old device is deleted, before the link. */
  beforeLink?: () => Promise<void>;
}

export interface BecameProtected {
  deviceId: string;
  avatarId: string;
  guardian: DeviceSummary;
  /** Storage/R2 paths of the old device's scans, to remove after commit. */
  paths: string[];
}

type Result = { ok: BecameProtected } | { fail: () => Error };

/**
 * Fase 27 K1, inside the caller's transaction:
 * (1–6) validateJoinInTx with the old device's attempt budget, its own code refused, and both
 * guardians locked in id order; then the old guardian must still have no members.
 * (7) the protected copy, (8) the old device deleted (links, codes, verdicts, scans, tombstones),
 * (9) the link. No success row: success rows never count, and the old id is gone.
 * Failed attempts are written in this transaction, so a `fail` result must be committed.
 */
export async function becomeProtectedTx(
  tx: TransactionSql,
  input: BecomeProtectedInput,
  hooks: BecomeProtectedHooks = {},
): Promise<Result> {
  const { oldId, ipHash, code } = input;
  await hooks.beforeValidate?.();
  const valid = await validateJoinInTx(tx, {
    attemptDeviceId: oldId,
    ipHash,
    code,
    excludeGuardianId: oldId,
    alsoLockGuardianId: oldId,
  });
  if ("fail" in valid) return valid;
  // Under the old guardian's lock nobody can join it until commit, and by then it is deleted (F-B2).
  if ((await memberCount(tx, oldId)) > 0) return { fail: errors.hasMembers };
  await hooks.afterValidate?.();

  const copy = await insertProtectedCopy(tx, oldId, input.tokenHash);
  // Throw, not `fail`: a fail result commits. Nothing is written yet here, but keep one rule.
  if (!copy) throw errors.unauthorized(); // the old device was deleted meanwhile
  const paths = await deleteDeviceInTx(tx, oldId);
  await hooks.beforeLink?.();
  // Last: the FK share lock on the target guardian's row comes after the domain locks of the
  // delete, the same order as that guardian's own DELETE /devices/me (K3).
  await insertLink(tx, copy.id, valid.guardianId);
  // The link's FK holds a share lock on the guardian's row, so it exists until commit.
  const guardian = (await guardianSummary(tx, valid.guardianId))!;
  return { ok: { deviceId: copy.id, avatarId: copy.avatarId, guardian, paths } };
}

const RETRYABLE = new Set(["40P01", "40001", "55P03"]);

/**
 * PF-01 "Punya kode undangan?" as one transaction (fase 27a: F-B1, F-B2, F-B3, F-B6). Retried once
 * on a deadlock, serialization failure or lock timeout (the lock order prevents them, K3).
 */
export async function becomeProtected(
  sql: Sql,
  input: BecomeProtectedInput,
  hooks?: BecomeProtectedHooks,
): Promise<BecameProtected> {
  let result: Result | undefined;
  for (let attempt = 1; !result; attempt++) {
    try {
      result = await sql.begin((tx) => becomeProtectedTx(tx, input, hooks));
    } catch (err) {
      const code = err instanceof postgres.PostgresError ? err.code : undefined;
      if (code !== undefined && RETRYABLE.has(code) && attempt < 2) {
        await new Promise((r) => setTimeout(r, 100));
        continue;
      }
      throw mapJoinError(err);
    }
  }
  if ("fail" in result) throw result.fail();
  return result.ok;
}

/** Backstops for races the locks already prevent. Every check_violation from the link is the target's fault. */
function mapJoinError(err: unknown): unknown {
  if (!(err instanceof postgres.PostgresError)) return err;
  if (err.code === "23505") return errors.alreadyConnected();
  if (err.code === "23503") return errors.codeInvalid(); // the target guardian deleted itself meanwhile
  // joinFamily rethrows other check violations; here the old device's own checks passed under its
  // lock, so a check failure on the link means the target is no longer a guardian (init.sql I3).
  if (err.code === "23514") return err.message === "family_full" ? errors.familyFull() : errors.codeInvalid();
  return err;
}
