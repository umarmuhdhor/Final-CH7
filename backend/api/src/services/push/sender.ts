import type { Env } from "../../env";
import { ApnsSender, apnsConfig } from "./apns";

export interface PushMessage {
  toDeviceId: string;
  apnsToken: string;
  body: string;
  /** The scan a tap opens (GD-06); absent for family pushes (reminder, disconnect), which just open the app. */
  scanId?: string;
}

/** result is a push_log code: sent | logged | failed:<status>[ <reason>] | failed:timeout|network|config. */
export interface SendResult {
  result: string;
  /** APNs said the token is gone (410): clear devices.apns_token. */
  clearToken?: boolean;
}

export interface PushSender {
  /** Never throws. */
  send(message: PushMessage): Promise<SendResult>;
}

/** EX-03 (#49): one Live Activity push. `payload` is the full APNs body ({ aps: { event, … } }). */
export interface LiveMessage {
  /** Push-to-start token for `start`, the activity's update token for `update`/`end`. */
  token: string;
  priority: 5 | 10;
  /** apns-expiration from now: how long APNs keeps it for an offline phone. */
  expiresInSeconds: number;
  payload: unknown;
}

export interface LiveSender {
  /** Never throws. */
  sendLive(message: LiveMessage): Promise<SendResult>;
}

/** Logs instead of sending: local dev and tests without APNs secrets. */
export class LogSender implements PushSender, LiveSender {
  async send(_message: PushMessage): Promise<SendResult> {
    console.log(JSON.stringify({ event: "push_logged" }));
    return { result: "logged" };
  }

  async sendLive(_message: LiveMessage): Promise<SendResult> {
    return { result: "logged" };
  }
}

let warned = false;

/** The Live Activity sender: the same ApnsSender / LogSender choice as pushSender. */
export function liveSender(env: Env): LiveSender {
  return pushSender(env);
}

/** ApnsSender straight from the Worker (D-alief-B01) when every APNs value is set, else LogSender. */
export function pushSender(env: Env): PushSender & LiveSender {
  const config = apnsConfig(env);
  if ("missing" in config) {
    if (!warned) {
      warned = true;
      // Names only, never values.
      console.log(JSON.stringify({ event: "push_config_incomplete", missing: config.missing }));
    }
    return new LogSender();
  }
  return new ApnsSender(config);
}
