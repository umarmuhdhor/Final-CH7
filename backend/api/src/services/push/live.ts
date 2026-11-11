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

/** Why nothing was sent (`kind: "none"`), so the device test shows how often an island could not be ended (#356 review). */
export type LiveNoneReason = "no_update_token" | "no_start_token" | "no_device";

/**
 * An end must still arrive after the phone was offline for a while, or the island stays (#356
 * review): APNs keeps it for an hour. Starts and updates are useless after a minute.
 */
export const LIVE_END_EXPIRY_SECONDS = 3600;
export const LIVE_EXPIRY_SECONDS = 60;

interface Tokens {
  startToken: string | null;
  updateToken: string | null;
}

/**
 * ScoreActivityAttributes.ContentState (ios/ShooShared, contracts/api.md "Live score"). The island
 * follows the page, so the domain lives in the content state; the attributes are empty.
 */
function contentState(u: LiveUpdate) {
  // status (#383): copied as is, so the island's colour follows what the phone did, not a fixed band.
  return { domain: u.domain, score: u.score, isAnalyzing: u.analyzing, isBlocked: u.status === "blocked", status: u.status };
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
): Promise<{ kind: LiveKind; result?: string; reason?: LiveNoneReason }> {
  const [d] = await sql<Tokens[]>`
    select live_start_token as "startToken", live_update_token as "updateToken"
    from devices where id = ${deviceId}`;
  if (!d) return { kind: "none", reason: "no_device" };
  const timestamp = Math.floor(nowMs / 1000);

  if (!u.open) {
    // Before the app sent the update token there is no way to end the island from here; the app
    // ends older activities itself when a new one starts (#356 review, app PR).
    if (!d.updateToken) return { kind: "none", reason: "no_update_token" };
    const r = await sender.sendLive({
      token: d.updateToken,
      priority: 10,
      expiresInSeconds: LIVE_END_EXPIRY_SECONDS,
      payload: { aps: { timestamp, event: "end", "content-state": contentState(u), "dismissal-date": timestamp } },
    });
    // Ended or gone either way: the next page starts a new island.
    await clearUpdateToken(sql, deviceId, d.updateToken);
    return { kind: "end", result: r.result };
  }

  if (d.updateToken) {
    const r = await sender.sendLive({
      token: d.updateToken,
      // Score-only changes on a settled normal page are the bulk of updates: low priority keeps them
      // within Apple's budget. A new page always starts with analyzing, so a domain change goes out
      // right away without storing the last domain (#356 review); warnings and blocks too.
      priority: u.status === "normal" && !u.analyzing ? 5 : 10,
      expiresInSeconds: LIVE_EXPIRY_SECONDS,
      payload: {
        aps: { timestamp, event: "update", "content-state": contentState(u), "stale-date": timestamp + LIVE_STALE_SECONDS },
      },
    });
    if (r.clearToken) await clearUpdateToken(sql, deviceId, d.updateToken);
    return { kind: "update", result: r.result };
  }

  if (!d.startToken) return { kind: "none", reason: "no_start_token" };
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
    expiresInSeconds: LIVE_EXPIRY_SECONDS,
    payload: {
      aps: {
        timestamp,
        event: "start",
        "content-state": contentState(u),
        "attributes-type": "ScoreActivityAttributes",
        attributes: {},
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
