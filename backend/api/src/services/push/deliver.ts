import type { Sql } from "postgres";
import { clearApnsToken, recordPush } from "../../db/repo/push";
import type { PushMessage, PushSender, SendResult } from "./sender";
import { errorInfo } from "../../http/logError";

/** Send, clear the token on 410, record the result. Runs in waitUntil after POST /scans answered. */
export async function deliverPush(sql: Sql, sender: PushSender, message: PushMessage): Promise<string> {
  let r: SendResult;
  try {
    r = await sender.send(message);
  } catch (err) {
    // Senders do not throw; if one does, its message may carry the token, so only the name is logged.
    console.error(JSON.stringify({ event: "push_send_threw", error: errorInfo(err) }));
    r = { result: "failed:network" };
  }
  if (r.clearToken) await clearApnsToken(sql, message.toDeviceId, message.apnsToken);
  await recordPush(sql, message.toDeviceId, message.scanId, r.result);
  console.log(JSON.stringify({ event: "push", result: r.result }));
  return r.result;
}
