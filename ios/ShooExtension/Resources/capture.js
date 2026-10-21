// Owner: lead. Evidence screenshot for EX-07 (PRD §10: evidence area only, typed input blurred by report.js).
// ES module, used by background.js.

// contracts/api.md: longest side ≤ 1280 px, ≤ 150 KB, else the backend drops the screenshot.
const MAX_SIDE = 1280;
const MAX_BYTES = 150 * 1024;
const QUALITIES = [0.6, 0.45, 0.3]; // try in order until it fits

/**
 * Maps the evidence rect (viewport CSS px) onto the captured image (device px) and picks the output size.
 * @returns {{sx, sy, sw, sh, width, height} | null} null when the rect is empty
 */
export function cropBox(evidence, imageWidth, imageHeight, maxSide = MAX_SIDE) {
    const scale = imageWidth / evidence.viewportWidth;
    const sx = Math.max(0, Math.round(evidence.x * scale));
    const sy = Math.max(0, Math.round(evidence.y * scale));
    const sw = Math.min(imageWidth - sx, Math.round(evidence.width * scale));
    const sh = Math.min(imageHeight - sy, Math.round(evidence.height * scale));
    if (!(sw > 0 && sh > 0)) return null;
    const out = Math.min(1, maxSide / Math.max(sw, sh));
    return { sx, sy, sw, sh, width: Math.round(sw * out), height: Math.round(sh * out) };
}

/** Captures the visible tab and returns the cropped evidence as base64 JPEG (no data: prefix), or null. */
export async function captureEvidence(windowId, evidence) {
    if (!browser.tabs?.captureVisibleTab) return null; // not every Safari build has it — send without screenshot
    const dataUrl = await browser.tabs.captureVisibleTab(windowId, { format: "jpeg", quality: 80 });
    const bitmap = await createImageBitmap(await (await fetch(dataUrl)).blob());
    const box = cropBox(evidence, bitmap.width, bitmap.height);
    if (!box) return null;

    const canvas =
        typeof OffscreenCanvas !== "undefined"
            ? new OffscreenCanvas(box.width, box.height)
            : Object.assign(document.createElement("canvas"), { width: box.width, height: box.height });
    canvas.getContext("2d").drawImage(bitmap, box.sx, box.sy, box.sw, box.sh, 0, 0, box.width, box.height);
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
