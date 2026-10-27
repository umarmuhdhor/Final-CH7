// Owner: lead. Evidence screenshot for EX-07 (PRD §10: evidence area only, typed input blurred by report.js).
// ES module, used by background.js.

// contracts/api.md: longest side ≤ 1280 px, ≤ 150 KB, else the backend drops the screenshot.
const MAX_SIDE = 1280;
const MAX_BYTES = 150 * 1024;
const QUALITIES = [0.6, 0.45, 0.3]; // try in order until it fits
// report.js shows a paint marker with the blur. No marker in the capture → that frame may predate the
// blur, so capture again; still none → send without a screenshot rather than one with readable fields.
const CAPTURE_ATTEMPTS = 3;
const RETRY_MS = 80;
const SEARCH_FRACTION = 0.4; // the viewport starts in the top part of the capture (under the status bar)

const isMagenta = ([r, g, b]) => r > 180 && g < 100 && b > 180;
const isCyan = ([r, g, b]) => r < 100 && g > 180 && b > 180;

/**
 * Where the viewport's top-left corner is in the capture, found by report.js's marker: a magenta band
 * of `bandPx` image px over a cyan one, 2 bands wide. Safari iOS captures the area under the status bar
 * (and the side insets in landscape) too, so viewport (0, 0) is not image (0, 0).
 * @param {(x: number, y: number) => number[]} pixel  [r, g, b] of the capture
 * @returns {{x: number, y: number} | null} null when the marker isn't in the capture
 */
export function findMarker(pixel, imageWidth, imageHeight, bandPx) {
    if (!(bandPx >= 1)) return null;
    const maxX = Math.floor(imageWidth * SEARCH_FRACTION);
    const maxY = Math.floor(imageHeight * SEARCH_FRACTION);
    const inside = (dx, dy) => [Math.round(dx * bandPx), Math.round(dy * bandPx)];
    for (let y = 0; y < maxY; y++) {
        for (let x = 0; x < maxX; x++) {
            if (!isMagenta(pixel(x, y))) continue;
            // Middle of both bands must match too, so a page's own magenta pixel isn't taken for it.
            const [mx, my] = inside(1, 0.5);
            const [cx, cy] = inside(1, 1.5);
            if (isMagenta(pixel(x + mx, y + my)) && isCyan(pixel(x + cx, y + cy))) return { x, y };
        }
    }
    return null;
}

/**
 * Maps the evidence rect (viewport CSS px) onto the captured image (device px) and picks the output size.
 * @param {{x: number, y: number}} origin  viewport's top-left corner in the image (findMarker)
 * @returns {{sx, sy, sw, sh, width, height} | null} null when the rect is empty
 */
export function cropBox(evidence, imageWidth, imageHeight, maxSide = MAX_SIDE, origin = { x: 0, y: 0 }) {
    const scale = imageWidth / evidence.viewportWidth;
    const sx = Math.max(0, Math.round(origin.x + evidence.x * scale));
    const sy = Math.max(0, Math.round(origin.y + evidence.y * scale));
    const sw = Math.min(imageWidth - sx, Math.round(evidence.width * scale));
    const sh = Math.min(imageHeight - sy, Math.round(evidence.height * scale));
    if (!(sw > 0 && sh > 0)) return null;
    const out = Math.min(1, maxSide / Math.max(sw, sh));
    return { sx, sy, sw, sh, width: Math.round(sw * out), height: Math.round(sh * out) };
}

const makeCanvas = (width, height) =>
    typeof OffscreenCanvas !== "undefined"
        ? new OffscreenCanvas(width, height)
        : Object.assign(document.createElement("canvas"), { width, height });

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** One capture plus where the marker is in it; marker null when report.js's change isn't painted yet. */
async function captureOnce(windowId, bandCss, viewportWidth) {
    const dataUrl = await browser.tabs.captureVisibleTab(windowId, { format: "jpeg", quality: 80 });
    const bitmap = await createImageBitmap(await (await fetch(dataUrl)).blob());
    const bandPx = (bandCss * bitmap.width) / viewportWidth;
    const searchHeight = Math.max(1, Math.floor(bitmap.height * SEARCH_FRACTION));
    const probe = makeCanvas(bitmap.width, searchHeight).getContext("2d", { willReadFrequently: true });
    probe.drawImage(bitmap, 0, 0);
    const { data } = probe.getImageData(0, 0, bitmap.width, searchHeight);
    const pixel = (x, y) => {
        if (x < 0 || y < 0 || x >= bitmap.width || y >= searchHeight) return [0, 0, 0];
        const i = (y * bitmap.width + x) * 4;
        return [data[i], data[i + 1], data[i + 2]];
    };
    const marker = findMarker(pixel, bitmap.width, bitmap.height, bandPx);
    // What was under the marker's right edge, to paint over the marker if it lands in the crop.
    const cover = marker ? pixel(Math.round(marker.x + 2 * bandPx + 2), Math.round(marker.y + bandPx)) : null;
    return { bitmap, bandPx, marker, cover };
}

/** Captures the visible tab and returns the cropped evidence as base64 JPEG (no data: prefix), or null. */
export async function captureEvidence(windowId, evidence) {
    if (!browser.tabs?.captureVisibleTab) return null; // not every Safari build has it — send without screenshot
    let shot = null;
    for (let attempt = 0; attempt < CAPTURE_ATTEMPTS; attempt++) {
        if (attempt > 0) await wait(RETRY_MS);
        shot = await captureOnce(windowId, evidence.markerBand, evidence.viewportWidth);
        if (shot.marker) break;
    }
    if (!shot?.marker) return null; // blur not proven painted → no screenshot (PRD §10)

    const { bitmap, bandPx, marker, cover } = shot;
    const box = cropBox(evidence, bitmap.width, bitmap.height, MAX_SIDE, marker);
    if (!box) return null;

    const canvas = makeCanvas(box.width, box.height);
    const context = canvas.getContext("2d");
    context.drawImage(bitmap, box.sx, box.sy, box.sw, box.sh, 0, 0, box.width, box.height);
    const k = box.width / box.sw;
    context.fillStyle = `rgb(${cover.join(",")})`;
    context.fillRect((marker.x - box.sx) * k, (marker.y - box.sy) * k, Math.ceil(2 * bandPx * k) + 1, Math.ceil(2 * bandPx * k) + 1);

    const encode = (quality) =>
        canvas.convertToBlob
            ? canvas.convertToBlob({ type: "image/jpeg", quality })
            : new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
    const blob = await smallestFitting(encode);
    return blob ? toBase64(new Uint8Array(await blob.arrayBuffer())) : null;
}

/** First encoding that fits MAX_BYTES, trying lower JPEG qualities; null if none fits (send without screenshot). */
export async function smallestFitting(encode, qualities = QUALITIES, maxBytes = MAX_BYTES) {
    for (const quality of qualities) {
        const blob = await encode(quality);
        if (blob && blob.size <= maxBytes) return blob;
    }
    return null;
}

function toBase64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
}
