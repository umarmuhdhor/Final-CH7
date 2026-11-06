import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { sharedHostList } from "../scripts/build-shared-hosts.mjs";

const file = JSON.parse(readFileSync(new URL("../data/shared-hosts.json", import.meta.url), "utf8"));

test("shared-hosts.json matches the code lists", () => {
    assert.equal(file.version, 1);
    assert.deepEqual(file.hosts, sharedHostList());
});

test("every host passes the admin.shared_hosts check", () => {
    for (const h of file.hosts) {
        assert.match(h, /^[a-z0-9.-]{1,253}$/, h);
        assert.ok(!h.startsWith("www."), h);
    }
    assert.equal(new Set(file.hosts).size, file.hosts.length, "unique");
    assert.deepEqual(file.hosts, [...file.hosts].sort());
});

test("contains sites.google.com, docs.google.com, github.io", () => {
    for (const h of ["sites.google.com", "docs.google.com", "github.io"]) assert.ok(file.hosts.includes(h), h);
});
