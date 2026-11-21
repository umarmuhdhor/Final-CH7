// Copies the iOS images into the Android app (PORTING.md: same images, `Image("Name")` → `R.drawable.<snake_case>`).
//
//   node android/scripts/sync-ios-assets.mjs
//
// Source: ios/ShooApp/Resources/Assets.xcassets (read only, never edited from here). Every `*.imageset`:
//   @3x → res/drawable-xxhdpi, @2x → res/drawable-xhdpi, @1x → res/drawable-mdpi,
//   no scale (gradients, textures: drawn stretched to a frame) → res/drawable-nodpi,
//   .svg → res/drawable/<name>.xml (Android VectorDrawable, paths translated as they are).
// The name is the imageset's in snake_case: HeroGradientBlue → hero_gradient_blue, Memoji01 → memoji01.
// AppIcon-1024 → drawable-nodpi/ic_launcher_artwork.png, the adaptive icon's foreground (inset to the visible area).
// No dependencies; run it again after the iOS assets change. test/assets.test.mjs fails when an output is missing.

import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
export const REPO = resolve(here, "..", "..");
export const XCASSETS = join(REPO, "ios", "ShooApp", "Resources", "Assets.xcassets");
export const RES = join(REPO, "android", "app", "src", "main", "res");

/** HeroGradientBlue → hero_gradient_blue; OnboardingSlide1 → onboarding_slide1; Memoji01 → memoji01. */
export function snakeCase(name) {
    return name
        .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
        .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
        .replace(/[^A-Za-z0-9_]/g, "_")
        .toLowerCase();
}

const SCALE_DIRS = { "1x": "drawable-mdpi", "2x": "drawable-xhdpi", "3x": "drawable-xxhdpi" };

/** Every `*.imageset` under the catalog, depth first. */
export function findImageSets(root = XCASSETS) {
    const found = [];
    for (const entry of readdirSync(root)) {
        const path = join(root, entry);
        if (!statSync(path).isDirectory()) continue;
        if (entry.endsWith(".imageset")) found.push(path);
        else found.push(...findImageSets(path));
    }
    return found.sort();
}

/** [{ source, target, kind }] for one imageset: what the sync writes. */
export function planImageSet(dir) {
    const name = basename(dir, ".imageset");
    const contents = JSON.parse(readFileSync(join(dir, "Contents.json"), "utf8"));
    const plan = [];
    for (const image of contents.images ?? []) {
        if (!image.filename) continue;
        const source = join(dir, image.filename);
        const ext = extname(image.filename).toLowerCase();
        if (ext === ".svg") {
            plan.push({ source, target: join(RES, "drawable", `${snakeCase(name)}.xml`), kind: "svg" });
            continue;
        }
        const folder = image.scale ? SCALE_DIRS[image.scale] : "drawable-nodpi";
        if (!folder) throw new Error(`${name}: unsupported scale ${image.scale}`);
        plan.push({ source, target: join(RES, folder, `${snakeCase(name)}${ext === ".jpeg" ? ".jpg" : ext}`), kind: "copy" });
    }
    return { name, plan };
}

/** The app icon: the 1024 px artwork, used by the adaptive icon. */
export function planAppIcon() {
    const source = join(XCASSETS, "AppIcon.appiconset", "AppIcon-1024.png");
    return { source, target: join(RES, "drawable-nodpi", "ic_launcher_artwork.png"), kind: "copy" };
}

// MARK: SVG → VectorDrawable

function attributes(tag) {
    const result = {};
    for (const match of tag.matchAll(/([a-zA-Z:-]+)="([^"]*)"/g)) result[match[1]] = match[2];
    return result;
}

function color(value) {
    if (!value || value === "none") return null;
    if (/^#[0-9a-fA-F]{6}$/.test(value)) return value.toUpperCase();
    if (/^#[0-9a-fA-F]{3}$/.test(value)) return "#" + [...value.slice(1)].map((c) => c + c).join("").toUpperCase();
    if (value === "black") return "#000000";
    if (value === "white") return "#FFFFFF";
    throw new Error(`unsupported colour ${value}`);
}

/**
 * The two SVGs in the catalog (HomeAlertCircle, HomeSwitch) are plain `<svg>` with `<path>` children: their `d` is the
 * same path language as VectorDrawable's `pathData`, so it is carried over unchanged. Anything else fails loudly.
 */
export function svgToVectorDrawable(svg) {
    const root = svg.match(/<svg\b[^>]*>/);
    if (!root) throw new Error("not an svg");
    const rootAttrs = attributes(root[0]);
    const [, , vbWidth, vbHeight] = (rootAttrs.viewBox ?? `0 0 ${rootAttrs.width} ${rootAttrs.height}`).split(/[\s,]+/).map(Number);
    const width = parseFloat(rootAttrs.width ?? vbWidth);
    const height = parseFloat(rootAttrs.height ?? vbHeight);
    const elements = [...svg.matchAll(/<(\w+)\b[^>]*\/?>/g)].map((m) => m[1]).filter((n) => n !== "svg");
    const unsupported = elements.filter((n) => n !== "path");
    if (unsupported.length) throw new Error(`unsupported svg elements: ${unsupported.join(", ")}`);
    const rootFill = rootAttrs.fill;
    const paths = [...svg.matchAll(/<path\b[^>]*\/?>/g)].map((m) => {
        const a = attributes(m[0]);
        const lines = [`        android:pathData="${a.d}"`];
        const fill = color(a.fill ?? (rootFill === "none" ? "none" : rootFill ?? "#000000"));
        if (fill) lines.push(`        android:fillColor="${fill}"`);
        const stroke = color(a.stroke);
        if (stroke) {
            lines.push(`        android:strokeColor="${stroke}"`);
            lines.push(`        android:strokeWidth="${a["stroke-width"] ?? 1}"`);
            if (a["stroke-linecap"]) lines.push(`        android:strokeLineCap="${a["stroke-linecap"]}"`);
            if (a["stroke-linejoin"]) lines.push(`        android:strokeLineJoin="${a["stroke-linejoin"]}"`);
        }
        if (a["fill-rule"] === "evenodd") lines.push(`        android:fillType="evenOdd"`);
        return `    <path\n${lines.join("\n")} />`;
    });
    return [
        `<?xml version="1.0" encoding="utf-8"?>`,
        `<!-- Generated by android/scripts/sync-ios-assets.mjs from the iOS asset catalog. Do not edit. -->`,
        `<vector xmlns:android="http://schemas.android.com/apk/res/android"`,
        `    android:width="${width}dp"`,
        `    android:height="${height}dp"`,
        `    android:viewportWidth="${vbWidth}"`,
        `    android:viewportHeight="${vbHeight}">`,
        ...paths,
        `</vector>`,
        ``,
    ].join("\n");
}

// MARK: Launcher icon

/** Adaptive icon: the iOS artwork inset to the 72 of 108 dp the launcher shows, so it fills the mask like on iOS. */
export const LAUNCHER_FOREGROUND = `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by android/scripts/sync-ios-assets.mjs: the iOS AppIcon-1024 artwork, inset to the visible 72 of 108 dp. -->
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/ic_launcher_artwork"
    android:inset="16.667%" />
`;

export const LAUNCHER_ICON = `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by android/scripts/sync-ios-assets.mjs. Foreground: the iOS app icon artwork. Monochrome: the shield
     glyph for themed icons (Android 13+). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/shoo_blue" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
`;

/** Everything the sync writes (used by the test). */
export function plan() {
    const sets = findImageSets().map(planImageSet);
    return { sets, appIcon: planAppIcon() };
}

function write(target, text) {
    mkdirSync(dirname(target), { recursive: true });
    if (existsSync(target) && readFileSync(target, "utf8") === text) return false;
    writeFileSync(target, text);
    return true;
}

function copy(source, target) {
    mkdirSync(dirname(target), { recursive: true });
    if (existsSync(target) && readFileSync(target).equals(readFileSync(source))) return false;
    copyFileSync(source, target);
    return true;
}

export function sync() {
    const { sets, appIcon } = plan();
    let written = 0;
    const seen = new Map();
    for (const { name, plan: items } of sets) {
        if (items.length === 0) throw new Error(`${name}: imageset without a file`);
        for (const item of items) {
            const clash = seen.get(item.target);
            if (clash) throw new Error(`${name} and ${clash} both map to ${item.target}`);
            seen.set(item.target, name);
            if (item.kind === "svg") {
                if (write(item.target, svgToVectorDrawable(readFileSync(item.source, "utf8")))) written++;
            } else if (copy(item.source, item.target)) {
                written++;
            }
        }
    }
    if (copy(appIcon.source, appIcon.target)) written++;
    // The old shield glyph stays as the themed (monochrome) icon.
    const oldForeground = join(RES, "drawable", "ic_launcher_foreground.xml");
    const monochrome = join(RES, "drawable", "ic_launcher_monochrome.xml");
    if (!existsSync(monochrome) && existsSync(oldForeground) && readFileSync(oldForeground, "utf8").includes("<vector")) {
        copyFileSync(oldForeground, monochrome);
        written++;
    }
    if (write(oldForeground, LAUNCHER_FOREGROUND)) written++;
    if (write(join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), LAUNCHER_ICON)) written++;
    return { sets: sets.length, written };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const { sets, written } = sync();
    console.log(`sync-ios-assets: ${sets} imagesets, ${written} files written`);
}
