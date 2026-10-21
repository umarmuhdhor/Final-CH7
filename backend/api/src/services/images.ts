export interface ImageInfo {
  type: "jpeg" | "png";
  width: number;
  height: number;
}

/** Strict base64 (no `data:` prefix, no whitespace). Undefined when malformed or longer than maxBytes. */
export function decodeBase64(text: string, maxBytes: number): Uint8Array | undefined {
  if (text.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) return undefined;
  if ((text.length / 4) * 3 - 2 > maxBytes) return undefined;
  let bin: string;
  try {
    bin = atob(text);
  } catch {
    return undefined;
  }
  if (bin.length > maxBytes) return undefined;
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** Type and pixel size from the JPEG/PNG headers (magic bytes, SOFn / IHDR). Undefined for anything else. */
export function sniffImage(b: Uint8Array): ImageInfo | undefined {
  if (b.length >= 24 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
      b[12] === 0x49 && b[13] === 0x48 && b[14] === 0x44 && b[15] === 0x52) {
    const u32 = (o: number) => ((b[o]! << 24) | (b[o + 1]! << 16) | (b[o + 2]! << 8) | b[o + 3]!) >>> 0;
    return { type: "png", width: u32(16), height: u32(20) };
  }
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8 || b[2] !== 0xff) return undefined;

  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return undefined;
    const marker = b[i + 1]!;
    if (marker === 0xff) {
      i += 1; // fill byte
      continue;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      i += 2; // markers without a length
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) return undefined; // no frame header before the scan data
    const len = (b[i + 2]! << 8) | b[i + 3]!;
    const isSof = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isSof) {
      if (i + 9 > b.length) return undefined;
      return { type: "jpeg", height: (b[i + 5]! << 8) | b[i + 6]!, width: (b[i + 7]! << 8) | b[i + 8]! };
    }
    i += 2 + len;
  }
  return undefined;
}
