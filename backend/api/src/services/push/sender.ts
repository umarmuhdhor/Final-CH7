import type { Env } from "../../env";

export interface PushMessage {
  toDeviceId: string;
  apnsToken: string;
  body: string;
  scanId: string;
}

export interface PushSender {
  send(message: PushMessage): Promise<{ result: string }>;
}

/** Logs instead of sending. The APNs sender comes in fase 11 (D-alief-B01: straight from the Worker). */
export class LogSender implements PushSender {
  async send(message: PushMessage): Promise<{ result: string }> {
    console.log(JSON.stringify({ event: "push_logged", scanId: message.scanId }));
    return { result: "logged" };
  }
}

export function pushSender(_env: Env): PushSender {
  // TODO(sync:alief): ApnsSender — replace in fase 11 (BE-push).
  return new LogSender();
}
