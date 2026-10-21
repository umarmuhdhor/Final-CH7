import type { Sql, TransactionSql } from "postgres";
import { claimCode, deleteGuardianCodes, findCode, type FamilyCode } from "../db/repo/codes";
import { FAMILY_MAX, guardianOf, insertLink, lockGuardian, memberCount, type DeviceSummary } from "../db/repo/families";
import { attemptsRetryAfter, lockAttempts, recordAttempt } from "../db/repo/joinAttempts";
import { errors } from "../http/errors";
import { randomBytes } from "../http/crypto";

const CODE_TRIES = 20;

/** Uniform 0000–9999: reject values ≥ 2^32 - (2^32 mod 10000). */
export function randomCode(): string {
  const limit = 2 ** 32 - (2 ** 32 % 10000);
  for (;;) {
    const v = new DataView(randomBytes(4).buffer).getUint32(0);
    if (v < limit) return String(v % 10000).padStart(4, "0");
  }
}

/** R4 §1: replace the guardian's code with a free random one. */
export async function issueCode(sql: Sql, guardianId: string): Promise<FamilyCode> {
  const code = await sql.begin(async (tx) => {
    await deleteGuardianCodes(tx, guardianId);
    for (let i = 0; i < CODE_TRIES; i++) {
      const claimed = await claimCode(tx, guardianId, randomCode());
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
      if ((await memberCount(tx, found.guardianId)) >= FAMILY_MAX) return { fail: errors.familyFull };
      await insertLink(tx, protectedId, found.guardianId);
      await recordAttempt(tx, protectedId, ipHash, true);
      return { ok: (await guardianSummary(tx, found.guardianId))! };
    });
  } catch (err) {
    // Backstops for races the locks already prevent: PK (I2) and the I3 trigger.
    const e = err as { code?: string; message?: string };
    if (e.code === "23505") throw errors.alreadyConnected();
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
