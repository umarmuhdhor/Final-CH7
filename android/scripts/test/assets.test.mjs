// node --test android/scripts/test/*.test.mjs
// Fails when an iOS imageset has no converted Android drawable: run `node android/scripts/sync-ios-assets.mjs`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { plan, RES, snakeCase, svgToVectorDrawable } from "../sync-ios-assets.mjs";

test("every imageset has its converted drawable", () => {
    const { sets, appIcon } = plan();
    assert.ok(sets.length > 40, `found only ${sets.length} imagesets`);
    const missing = [];
    for (const { name, plan: items } of sets) {
        if (items.length === 0) missing.push(`${name} (no file in the imageset)`);
        for (const item of items) if (!existsSync(item.target)) missing.push(`${name} → ${item.target}`);
    }
    if (!existsSync(appIcon.target)) missing.push(`AppIcon → ${appIcon.target}`);
    assert.deepEqual(missing, [], "run node android/scripts/sync-ios-assets.mjs");
});

test("copied images are byte-identical to the iOS ones", () => {
    for (const { plan: items } of plan().sets) {
        for (const item of items) {
            if (item.kind !== "copy") continue;
            assert.ok(readFileSync(item.target).equals(readFileSync(item.source)), `${item.target} is stale`);
        }
    }
});

test("drawable names are valid Android resource names", () => {
    for (const { name } of plan().sets) {
        assert.match(snakeCase(name), /^[a-z][a-z0-9_]*$/, name);
    }
    assert.equal(snakeCase("HeroGradientBlue"), "hero_gradient_blue");
    assert.equal(snakeCase("Memoji01"), "memoji01");
    assert.equal(snakeCase("OnboardingSlide1"), "onboarding_slide1");
});

test("svg imagesets become vector drawables with the same paths", () => {
    const svgs = plan().sets.flatMap((s) => s.plan).filter((i) => i.kind === "svg");
    assert.equal(svgs.length, 2);
    for (const item of svgs) {
        const xml = readFileSync(item.target, "utf8");
        assert.equal(xml, svgToVectorDrawable(readFileSync(item.source, "utf8")));
        assert.match(xml, /<vector /);
    }
});

test("launcher icon uses the iOS artwork", () => {
    const icon = readFileSync(join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), "utf8");
    assert.match(icon, /@drawable\/ic_launcher_foreground/);
    assert.match(readFileSync(join(RES, "drawable", "ic_launcher_foreground.xml"), "utf8"), /ic_launcher_artwork/);
    assert.ok(existsSync(join(RES, "drawable", "ic_launcher_monochrome.xml")));
});
