import type { Sql, TransactionSql } from "postgres";

/** 30 min: long enough for a WhatsApp invite to be opened later (PR-03, issue #128). */
export const CODE_TTL_SECONDS = 30 * 60;

export interface FamilyCode {
  code: string;
  expiresAt: string;
}

const EXPIRES_AT = `to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`;

/** The guardian's code if it is still valid for more than `minSeconds`. Call under `lockGuardian`. */
export async function activeGuardianCode(tx: TransactionSql, guardianId: string, minSeconds: number): Promise<FamilyCode | undefined> {
  const [row] = await tx<FamilyCode[]>`
    select code, ${tx.unsafe(EXPIRES_AT)} as "expiresAt" from family_codes
    where guardian_id = ${guardianId} and expires_at > now() + make_interval(secs => ${minSeconds})`;
  return row;
}

/** Removes every code of this guardian (a new code replaces the old one, R4 §1). */
export async function deleteGuardianCodes(tx: TransactionSql, guardianId: string): Promise<void> {
  await tx`delete from family_codes where guardian_id = ${guardianId}`;
}

/**
 * Claims `code` for the guardian unless another guardian holds it and it is still active.
 * An expired row with the same code is taken over. Returns undefined on an active collision.
 */
export async function claimCode(tx: TransactionSql, guardianId: string, code: string): Promise<FamilyCode | undefined> {
  const [row] = await tx<FamilyCode[]>`
    insert into family_codes (code, guardian_id, expires_at)
    values (${code}, ${guardianId}, now() + make_interval(secs => ${CODE_TTL_SECONDS}))
    on conflict (code) do update
      set guardian_id = excluded.guardian_id, expires_at = excluded.expires_at, created_at = now()
      where family_codes.expires_at <= now()
    returning code, ${tx.unsafe(EXPIRES_AT)} as "expiresAt"`;
  return row;
}

export interface CodeLookup {
  guardianId: string;
  expired: boolean;
}

export async function findCode(sql: Sql | TransactionSql, code: string): Promise<CodeLookup | undefined> {
  const [row] = await sql<CodeLookup[]>`
    select guardian_id as "guardianId", expires_at <= now() as expired from family_codes where code = ${code}`;
  return row;
}
