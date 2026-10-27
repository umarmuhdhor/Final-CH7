// node --test ios/ShooExtension/Tests
import { test } from "node:test";
import assert from "node:assert/strict";
import { PSL_RULES } from "../Resources/psl.js";
import { parseRules, registrableDomain, naiveDomain, shareableUrl } from "../Resources/domain.js";

const rules = parseRules(PSL_RULES);
const cases = {
    "www.bca.co.id": "bca.co.id",
    "a.b.co.id": "b.co.id",
    "klikbca.com": "klikbca.com",
    "M.KlikBCA.com.": "klikbca.com",
    "bca-verifikasi.site": "bca-verifikasi.site",
    "login.bca-verifikasi.site": "bca-verifikasi.site",
    "promo.shopee.co.id": "shopee.co.id",
    "kemensos.go.id": "kemensos.go.id",
    "toko.my.id": "toko.my.id",
    "www.bbc.co.uk": "bbc.co.uk",
    // Private suffixes: each customer site is its own domain, so one verdict never blocks the platform.
    "bca-verify.github.io": "bca-verify.github.io",
    "scam.vercel.app": "scam.vercel.app",
    "a.scam.pages.dev": "scam.pages.dev",
    "x.blogspot.com": "x.blogspot.com",
    // Wildcard + exception rules (*.ck, !www.ck)
    "a.b.ck": "a.b.ck",
    "www.ck": "www.ck",
    // Not domains
    "192.168.1.1": "192.168.1.1",
    "[::1]": "[::1]",
    localhost: "localhost",
    "co.id": "co.id",
};

for (const [host, expected] of Object.entries(cases)) {
    test(`${host} → ${expected}`, () => assert.equal(registrableDomain(host, rules), expected));
}

test("unknown TLD falls back to the default * rule", () => {
    assert.equal(registrableDomain("a.b.notatld", rules), "b.notatld");
});

test("naive fallback strips www only", () => {
    assert.equal(naiveDomain("WWW.a.b.co.id"), "a.b.co.id");
});

test("shareableUrl keeps scheme, host and path only: no query, fragment or credentials leave the phone (/analyze)", () => {
    assert.equal(shareableUrl("https://bca-verify.top/login?token=abc&otp=123#code=xyz"), "https://bca-verify.top/login");
    assert.equal(shareableUrl("https://user:pass@scam.example:8443/a/b"), "https://scam.example:8443/a/b");
    assert.equal(shareableUrl("http://scam.example"), "http://scam.example/");
    assert.equal(shareableUrl("not a url?x=1"), "not a url");
});
