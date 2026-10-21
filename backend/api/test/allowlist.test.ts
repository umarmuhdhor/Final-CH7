import { describe, expect, it } from "vitest";
import { isAllowlisted, neverQueue } from "../src/data/allowlist";

describe("allowlist (R2 §5, SECURITY T5)", () => {
  it.each(["klikbca.com", "sub.klikbca.com", "pajak.go.id", "a.b.ac.id", "google.co.id"])("%s is allowlisted", (d) => {
    expect(isAllowlisted(d)).toBe(true);
  });

  it.each(["bca.co.id.evil.com", "notgoogle.com", "klikbca-login.com", "go-id.com", "id"])("%s is not", (d) => {
    expect(isAllowlisted(d)).toBe(false);
  });

  it("shared roots never queue, but their subdomains may", () => {
    expect(neverQueue("github.io")).toBe(true);
    expect(neverQueue("co.in")).toBe(true);
    expect(neverQueue("evil.github.io")).toBe(false);
  });
});
