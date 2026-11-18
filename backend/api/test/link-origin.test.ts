import { describe, expect, it } from "vitest";
import { linkOrigin } from "../src/services/screenshotLinks";

// PR-03 moved INVITE_BASE_URL to join.shoo.ai.id; signed screenshot, favicon and replica links must
// stay on the API host, the only host the app loads them from (SiteIcon, ScreenshotView, ReplicaLoader).
describe("linkOrigin", () => {
  it("uses API_BASE_URL, not the invite host", () => {
    const env = { API_BASE_URL: "https://shoo-api.example.workers.dev/", INVITE_BASE_URL: "https://join.example.id" };
    expect(linkOrigin(env)).toBe("https://shoo-api.example.workers.dev");
  });

  it("falls back to INVITE_BASE_URL when API_BASE_URL is unset or empty", () => {
    expect(linkOrigin({ INVITE_BASE_URL: "http://localhost:8787/" })).toBe("http://localhost:8787");
    expect(linkOrigin({ API_BASE_URL: "", INVITE_BASE_URL: "http://localhost:8787" })).toBe("http://localhost:8787");
  });
});
