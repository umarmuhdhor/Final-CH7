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
  unauthorized: () => new ApiError(401, "unauthorized", "Missing or unknown device token"),
  forbidden: (message = "Not allowed for this device mode") => new ApiError(403, "forbidden", message),
  notFound: () => new ApiError(404, "not_found", "Not found"),
  tooLarge: () => new ApiError(413, "too_large", "Body too large"),
  invalidBody: (message: string) => new ApiError(422, "invalid_body", message),
  rateLimited: (retryAfter: number) => new ApiError(429, "rate_limited", "Too many requests", retryAfter),
  internal: () => new ApiError(500, "internal", "Internal error"),
};

export function errorResponse(c: Context, err: ApiError): Response {
  if (err.retryAfter !== undefined) c.header("Retry-After", String(err.retryAfter));
  return c.json({ error: { code: err.code, message: err.message } }, err.status);
}
