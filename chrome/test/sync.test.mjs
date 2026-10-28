// node --test chrome/test/*.test.mjs
// The shared files are copies of the Safari extension's (chrome/scripts/sync.sh); a copy that drifts fails here.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { build } from "../../detector/scripts/build.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const shared = read("../scripts/shared-files.txt")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));

test("shared files list is not empty", () => {
    assert.ok(shared.includes("pipeline.js") && shared.includes("content.js"));
});

for (const file of shared) {
    test(`${file} matches ios/ShooExtension/Resources/${file} (run chrome/scripts/sync.sh)`, () => {
        assert.equal(read(`../extension/${file}`), read(`../../ios/ShooExtension/Resources/${file}`));
    });
}

test("detector.js is the current build of detector/ (run chrome/scripts/sync.sh)", () => {
    const [header, ...body] = read("../extension/detector.js").split("\n");
    assert.match(header, /GENERATED from detector\/ by chrome\/scripts\/sync\.sh/);
    assert.equal(body.join("\n"), build().replace(/\n*$/, "\n")); // the shell drops trailing newlines, then adds one
});
