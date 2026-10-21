// Owner: lead. Evidence screenshot for EX-07 (PRD §10: evidence area only, typed input blurred by report.js).
// ES module, used by background.js.

const MAX_WIDTH = 900; // px of the stored image — enough for DT-04 zoom, small enough to upload
const JPEG_QUALITY = 0.6;

/**
 * Maps the evidence rect (viewport CSS px) onto the captured image (device px) and picks the output size.
 * @returns {{sx, sy, sw, sh, width, height} | null} null when the rect is empty
 */
export function cropBox(evidence, imageWidth, imageHeight, maxWidth = MAX_WIDTH) {
    const scale = imageWidth / evidence.viewportWidth;
    const sx = Math.max(0, Math.round(evidence.x * scale));
    const sy = Math.max(0, Math.round(evidence.y * scale));
    const sw = Math.min(imageWidth - sx, Math.round(evidence.width * scale));
    const sh = Math.min(imageHeight - sy, Math.round(evidence.height * scale));
    if (!(sw > 0 && sh > 0)) return null;
    const out = Math.min(1, maxWidth / sw);
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
    const blob = canvas.convertToBlob
        ? await canvas.convertToBlob({ type: "image/jpeg", quality: JPEG_QUALITY })
        : await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY));
    return toBase64(new Uint8Array(await blob.arrayBuffer()));
}

function toBase64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
}
