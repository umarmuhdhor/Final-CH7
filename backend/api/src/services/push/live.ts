import type { Sql } from "postgres";
import type { LiveSender, SendResult } from "./sender";

/** POST /live body (EX-03, #49). Registrable domain only, never the full URL. */
export interface LiveUpdate {
  domain: string;
  score: number;
  status: "normal" | "warning" | "blocked";
  analyzing: boolean;
  /** false: the page left the screen, end the island. */
  open: boolean;
}

/**
 * How long a start push waits for the app to send the activity's update token (PATCH /devices/me)
 * before the next page may start a new island. Without it, fast tab switching after one start push
 * would stack islands. After it, the per-page fallback of #49 Q1 applies: a new start, and the old
 * island goes stale.
 */
export const LIVE_START_WAIT_SECONDS = 30;

/** stale-date of every start/update: the island dims if no update came for this long. */
export const LIVE_STALE_SECONDS = 600;

/** What happened, for the log line. `none`: no token to push to; `waiting`: a start is in flight. */
export type LiveKind = "start" | "update" | "end" | "none" | "waiting";

interface Tokens {
  startToken: string | null;
  updateToken: string | null;
}

/**
 * ScoreActivityAttributes.ContentState (ios/ShooShared). The island is reused across pages, so the
 * domain is in the content state too; `attributes.domain` keeps today's ShooShared shape decodable
 * (Codable ignores unknown keys, so both shapes work until #49's contract settles it).
 */
function contentState(u: LiveUpdate) {
  return { domain: u.domain, score: u.score, isAnalyzing: u.analyzing, isBlocked: u.status === "blocked" };
}

const ok = (r: SendResult) => r.result === "sent" || r.result === "logged";

/**
 * Forwards one live score to the Dynamic Island (#49): start with the push-to-start token when no
 * activity runs, update while one runs, end when the page left the screen. Domain and score only
 * travel in the APNs payload; nothing about the page is written to the database or the log
 * (#49 decision 3). Token clears are compare-and-clear, so a token the app sent meanwhile stays.
 */
export async function relayLive(
  sql: Sql,
  sender: LiveSender,
  deviceId: string,
  u: LiveUpdate,
  nowMs = Date.now(),
): Promise<{ kind: LiveKind; result?: string }> {
  const [d] = await sql<Tokens[]>`
    select live_start_token as "startToken", live_update_token as "updateToken"
    from devices where id = ${deviceId}`;
  if (!d) return { kind: "none" };
  const timestamp = Math.floor(nowMs / 1000);

  if (!u.open) {
    if (!d.updateToken) return { kind: "none" };
    const r = await sender.sendLive({
      token: d.updateToken,
      priority: 10,
      payload: { aps: { timestamp, event: "end", "content-state": contentState(u), "dismissal-date": timestamp } },
    });
    // Ended or gone either way: the next page starts a new island.
    await clearUpdateToken(sql, deviceId, d.updateToken);
    return { kind: "end", result: r.result };
  }

  if (d.updateToken) {
    const r = await sender.sendLive({
      token: d.updateToken,
      // Score-only changes on a normal page are the bulk of updates: low priority keeps them within
      // Apple's budget. Warnings and blocks go out right away.
      priority: u.status === "normal" ? 5 : 10,
      payload: {
        aps: { timestamp, event: "update", "content-state": contentState(u), "stale-date": timestamp + LIVE_STALE_SECONDS },
      },
    });
    if (r.clearToken) await clearUpdateToken(sql, deviceId, d.updateToken);
    return { kind: "update", result: r.result };
  }

  if (!d.startToken) return { kind: "none" };
  // Claim the start atomically: two parallel requests must not both start an island.
  const claimed = await sql`
    update devices set live_started_at = now()
    where id = ${deviceId} and live_start_token = ${d.startToken} and live_update_token is null
      and (live_started_at is null or live_started_at < now() - make_interval(secs => ${LIVE_START_WAIT_SECONDS}))
    returning id`;
  if (!claimed.length) return { kind: "waiting" };

  const r = await sender.sendLive({
    token: d.startToken,
    priority: 10,
    payload: {
      aps: {
        timestamp,
        event: "start",
        "content-state": contentState(u),
        "attributes-type": "ScoreActivityAttributes",
        attributes: { domain: u.domain },
        "stale-date": timestamp + LIVE_STALE_SECONDS,
      },
    },
  });
  if (r.clearToken) {
    await sql`
      update devices set live_start_token = null, live_started_at = null
      where id = ${deviceId} and live_start_token = ${d.startToken}`;
  } else if (!ok(r)) {
    // Nothing started: let the next page try again instead of waiting out LIVE_START_WAIT_SECONDS.
    await sql`
      update devices set live_started_at = null
      where id = ${deviceId} and live_start_token = ${d.startToken} and live_update_token is null`;
  }
  return { kind: "start", result: r.result };
}

async function clearUpdateToken(sql: Sql, deviceId: string, token: string): Promise<void> {
  await sql`
    update devices set live_update_token = null, live_activity_id = null, live_started_at = null
    where id = ${deviceId} and live_update_token = ${token}`;
}
