import type { Sql, TransactionSql } from "postgres";

export const CODE_TTL_SECONDS = 60;

export interface FamilyCode {
  code: string;
  expiresAt: string;
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
    returning code, to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as "expiresAt"`;
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
