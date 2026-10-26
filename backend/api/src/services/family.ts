import type { Sql, TransactionSql } from "postgres";
import { activeGuardianCode, claimCode, deleteGuardianCodes, findCode, type FamilyCode } from "../db/repo/codes";
import { FAMILY_MAX, guardianOf, insertLink, lockGuardian, memberCount, type DeviceSummary } from "../db/repo/families";
import { attemptsRetryAfter, lockAttempts, recordAttempt } from "../db/repo/joinAttempts";
import { errors } from "../http/errors";
import { randomBytes } from "../http/crypto";

const CODE_TRIES = 20;
const CODE_SPACE = 1_000_000;
/** A code with less time left than this is replaced, so a shared link isn't dead before it is opened (issue #128). */
export const REUSE_MIN_SECONDS = 5 * 60;

/** Uniform 000000–999999: reject values ≥ 2^32 - (2^32 mod 10^6). */
export function randomCode(): string {
  const limit = 2 ** 32 - (2 ** 32 % CODE_SPACE);
  for (;;) {
    const v = new DataView(randomBytes(4).buffer).getUint32(0);
    if (v < limit) return String(v % CODE_SPACE).padStart(6, "0");
  }
}

/**
 * R4 §1, issue #128: the guardian's active code while it has more than 5 min left, else a new free
 * random one. `refresh` always makes a new one; the old code stops working at once.
 * `nextCode` is swapped only in tests, to reach the 503 path without filling all 10^6 codes.
 */
export async function issueCode(
  sql: Sql,
  guardianId: string,
  refresh = false,
  nextCode: () => string = randomCode,
): Promise<FamilyCode> {
  const code = await sql.begin(async (tx) => {
    // Parallel requests (sheet opened twice, share tap) must agree on one code: serialize per guardian.
    await lockGuardian(tx, guardianId);
    if (!refresh) {
      const active = await activeGuardianCode(tx, guardianId, REUSE_MIN_SECONDS);
      if (active) return active;
    }
    await deleteGuardianCodes(tx, guardianId);
    for (let i = 0; i < CODE_TRIES; i++) {
      const claimed = await claimCode(tx, guardianId, nextCode());
      if (claimed) return claimed;
    }
    return null;
  });
  if (!code) throw errors.codeUnavailable();
  return code;
}

type JoinResult = { ok: DeviceSummary } | { fail: () => Error };

/**
 * R4 §2, in one transaction. Only code_invalid and code_expired count as failed
 * attempts; they are recorded inside the transaction that holds the attempt locks,
 * then the error is raised after commit.
 */
export async function joinFamily(sql: Sql, protectedId: string, ipHash: Uint8Array, code: string): Promise<DeviceSummary> {
  let result: JoinResult;
  try {
    result = await sql.begin(async (tx): Promise<JoinResult> => {
      await lockAttempts(tx, protectedId, ipHash);
      const retry = await attemptsRetryAfter(tx, protectedId, ipHash);
      if (retry !== null) return { fail: () => errors.tooManyAttempts(retry) };
      if (await guardianOf(tx, protectedId)) return { fail: errors.alreadyConnected };

      const found = await findCode(tx, code);
      if (!found || found.expired) {
        await recordAttempt(tx, protectedId, ipHash, false);
        return { fail: found ? errors.codeExpired : errors.codeInvalid };
      }

      await lockGuardian(tx, found.guardianId);
      // The guardian may have rotated the code while we waited for its lock.
      const still = await findCode(tx, code);
      if (!still || still.guardianId !== found.guardianId) return { fail: errors.codeInvalid };
      if ((await memberCount(tx, found.guardianId)) >= FAMILY_MAX) return { fail: errors.familyFull };
      await insertLink(tx, protectedId, found.guardianId);
      await recordAttempt(tx, protectedId, ipHash, true);
      return { ok: (await guardianSummary(tx, found.guardianId))! };
    });
  } catch (err) {
    // Backstops for races the locks already prevent: PK (I2), the I3 trigger, guardian FK.
    const e = err as { code?: string; message?: string };
    if (e.code === "23505") throw errors.alreadyConnected();
    if (e.code === "23503") throw errors.codeInvalid(); // guardian deleted itself meanwhile
    if (e.code === "23514" && e.message === "family_full") throw errors.familyFull();
    throw err;
  }
  if ("fail" in result) throw result.fail();
  return result.ok;
}

async function guardianSummary(tx: TransactionSql, id: string): Promise<DeviceSummary | undefined> {
  const [row] = await tx<DeviceSummary[]>`select id as "deviceId", name, avatar_id as "avatarId" from devices where id = ${id}`;
  return row;
}
