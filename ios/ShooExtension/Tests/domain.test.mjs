// node --test ios/ShooExtension/Tests
import { test } from "node:test";
import assert from "node:assert/strict";
import { PSL_RULES } from "../Resources/psl.js";
import { parseRules, registrableDomain, naiveDomain, pageDomain, isHostPathHost, shareableUrl } from "../Resources/domain.js";

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

test("naive fallback keeps a www that leaves a single label (www.com)", () => {
    assert.equal(naiveDomain("www.com."), "www.com");
});

// #487, #495: the `domain` the extension sends (POST /scans, GET /verdicts, POST /live) and files block memory under.
const domainOfUrl = (url) => pageDomain(new URL(url).hostname, (host) => registrableDomain(host, rules));
const sent = {
    // #487: no registrable domain → the full host, lowercase
    "http://[2001:db8::1]/login": "[2001:db8::1]",
    "http://[2001:DB8::1]:8080/login": "[2001:db8::1]",
    "http://router/login": "router",
    "http://ROUTER./login": "router",
    "http://www.co.id/x": "www.co.id",
    "http://www.com/x": "www.com",
    "http://co.id/x": "co.id",
    // IPv4 as before
    "http://192.168.1.1/login": "192.168.1.1",
    // #450: a trailing dot never reaches `domain`
    "https://bca-verifikasi.site./login": "bca-verifikasi.site",
    "https://login.bca.co.id./": "bca.co.id",
    // #495: a shared host_path platform → the full host, so every screen shows the real host
    "https://sites.google.com/view/x": "sites.google.com",
    "https://docs.google.com/forms/d/x": "docs.google.com",
    "https://forms.office.com/r/x": "forms.office.com",
    "https://sway.cloud.microsoft/AbCdEf123": "sway.cloud.microsoft",
    "https://SITES.google.com./view/x": "sites.google.com",
    "https://www.sites.google.com/view/x": "sites.google.com",
    "https://1drv.ms/f/s!x": "1drv.ms",
    "https://firebasestorage.googleapis.com/v0/b/x": "firebasestorage.googleapis.com",
    // the rest of the platform's registrable domain is unchanged
    "https://accounts.google.com/signin": "google.com",
    "https://www.office.com/": "office.com",
    // a normal subdomain still gives its registrable domain
    "https://login.bca.co.id/": "bca.co.id",
    "https://www.bca.co.id/": "bca.co.id",
    "https://scam.vercel.app/": "scam.vercel.app",
};
for (const [url, expected] of Object.entries(sent)) {
    test(`domain of ${url} → ${expected}`, () => assert.equal(domainOfUrl(url), expected));
}

test("pageDomain on the naive fallback (no PSL) keeps the same rule for shared and odd hosts", () => {
    const naive = (url) => pageDomain(new URL(url).hostname, naiveDomain);
    assert.equal(naive("https://sites.google.com/view/x"), "sites.google.com");
    assert.equal(naive("http://[2001:db8::1]/"), "[2001:db8::1]");
    assert.equal(naive("http://router./"), "router");
    assert.equal(naive("https://www.bca.co.id/"), "bca.co.id");
});

test("isHostPathHost: on or under a host_path platform, never a lookalike", () => {
    assert.equal(isHostPathHost("docs.google.com"), true);
    assert.equal(isHostPathHost("sway.cloud.microsoft"), true);
    assert.equal(isHostPathHost("cloud.microsoft"), true);
    assert.equal(isHostPathHost("google.com"), false);
    assert.equal(isHostPathHost("evildocs.google.com"), false);
    assert.equal(isHostPathHost("docs.google.com.evil.site"), false);
});

test("shareableUrl keeps scheme, host and path only: no query, fragment or credentials leave the phone (/analyze)", () => {
    assert.equal(shareableUrl("https://bca-verify.top/login?token=abc&otp=123#code=xyz"), "https://bca-verify.top/login");
    assert.equal(shareableUrl("https://user:pass@scam.example:8443/a/b"), "https://scam.example:8443/a/b");
    assert.equal(shareableUrl("http://scam.example"), "http://scam.example/");
    assert.equal(shareableUrl("not a url?x=1"), "not a url");
});
