import type { Env } from "../../env";
import { ApnsSender, apnsConfig } from "./apns";

export interface PushMessage {
  toDeviceId: string;
  apnsToken: string;
  body: string;
  scanId: string;
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

/** Logs instead of sending: local dev and tests without APNs secrets. */
export class LogSender implements PushSender {
  async send(_message: PushMessage): Promise<SendResult> {
    console.log(JSON.stringify({ event: "push_logged" }));
    return { result: "logged" };
  }
}

let warned = false;

/** ApnsSender straight from the Worker (D-alief-B01) when every APNs value is set, else LogSender. */
export function pushSender(env: Env): PushSender {
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
