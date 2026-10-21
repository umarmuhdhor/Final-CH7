import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
    readonly retryAfter?: number,
  ) {
    super(message);
  }
}

export const errors = {
  badJson: () => new ApiError(400, "bad_json", "Body is not valid JSON"),
  unauthorized: (retryAfter?: number) => new ApiError(401, "unauthorized", "Missing or unknown device token", retryAfter),
  forbidden: (message = "Not allowed for this device mode") => new ApiError(403, "forbidden", message),
  notFound: () => new ApiError(404, "not_found", "Not found"),
  tooLarge: () => new ApiError(413, "too_large", "Body too large"),
  invalidBody: (message: string) => new ApiError(422, "invalid_body", message),
  rateLimited: (retryAfter: number) => new ApiError(429, "rate_limited", "Too many requests", retryAfter),
  internal: () => new ApiError(500, "internal", "Internal error"),
  // Family (contracts/api.md "Join errors", R3 §1)
  codeInvalid: () => new ApiError(404, "code_invalid", "Unknown family code"),
  codeExpired: () => new ApiError(410, "code_expired", "Family code expired"),
  familyFull: () => new ApiError(409, "family_full", "Guardian already has 3 protected devices"),
  alreadyConnected: () => new ApiError(409, "already_connected", "Device already has a guardian"),
  tooManyAttempts: (retryAfter: number) =>
    new ApiError(429, "too_many_attempts", "Too many join attempts", retryAfter),
  codeUnavailable: () => new ApiError(503, "code_unavailable", "No free family code, try again"),
  // Verdicts (contracts/api.md, R3 §1): 403 not the owner's guardian, 409 scan is not blocked.
  verdictNotAllowed: (status: 403 | 409, message: string) => new ApiError(status, "verdict_not_allowed", message),
};

export function errorResponse(c: Context, err: ApiError): Response {
  if (err.retryAfter !== undefined) c.header("Retry-After", String(err.retryAfter));
  return c.json({ error: { code: err.code, message: err.message } }, err.status);
}
