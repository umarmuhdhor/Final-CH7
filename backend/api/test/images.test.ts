import { describe, expect, it } from "vitest";
import { decodeBase64, sniffImage } from "../src/services/images";
import { b64, jpeg, png } from "./helpers/images";

const soi = [0xff, 0xd8];
const sof = (marker: number, w: number, h: number) =>
  [0xff, marker, 0x00, 0x11, 0x08, h >> 8, h & 0xff, w >> 8, w & 0xff, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01];

describe("sniffImage", () => {
  it("reads JPEG and PNG sizes", () => {
    expect(sniffImage(jpeg(640, 480))).toEqual({ type: "jpeg", width: 640, height: 480 });
    expect(sniffImage(png(800, 600))).toEqual({ type: "png", width: 800, height: 600 });
  });

  it("skips APPn segments, fill bytes and reads progressive SOF2", () => {
    const app1 = [0xff, 0xe1, 0x00, 0x06, 0x01, 0x02, 0x03, 0x04];
    const b = Uint8Array.from([...soi, ...app1, 0xff, ...sof(0xc2, 300, 200), 0xff, 0xd9]);
    expect(sniffImage(b)).toEqual({ type: "jpeg", width: 300, height: 200 });
  });

  it("rejects a segment length below 2 (cannot skip into the segment)", () => {
    const b = Uint8Array.from([...soi, 0xff, 0xe1, 0x00, 0x00, ...sof(0xc0, 100, 100), 0xff, 0xd9]);
    expect(sniffImage(b)).toBeUndefined();
  });

  it("rejects a truncated SOF and a PNG with a broken signature", () => {
    expect(sniffImage(Uint8Array.from([...soi, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x00]))).toBeUndefined();
    const bad = png(10, 10);
    bad[4] = 0x00;
    expect(sniffImage(bad)).toBeUndefined();
    expect(sniffImage(png(10, 10).subarray(0, 23))).toBeUndefined();
  });
});

describe("decodeBase64", () => {
  it("accepts exactly maxBytes, rejects maxBytes + 1", () => {
    expect(decodeBase64(b64(new Uint8Array(300)), 300)?.length).toBe(300);
    expect(decodeBase64(b64(new Uint8Array(301)), 300)).toBeUndefined();
  });

  it.each(["AAA", "AA=A", "data:image/jpeg;base64,AAAA", "AA AA", "AAAA\n"])("rejects %j", (s) => {
    expect(decodeBase64(s, 1000)).toBeUndefined();
  });
});

describe("decodeBase64: native fromBase64 and the fallback agree (fase 22 O4)", () => {
  type WithNative = typeof Uint8Array & { fromBase64?: unknown };
  const U8 = Uint8Array as WithNative;

  it("records whether this workerd has Uint8Array.fromBase64", () => {
    // Informational: the fallback keeps decodeBase64 working either way.
    expect(["function", "undefined"]).toContain(typeof U8.fromBase64);
  });

  const bytes = (n: number) => Uint8Array.from({ length: n }, (_, i) => (i * 37 + 11) & 0xff);
  const cases: [string, string, number][] = [
    ["empty", "", 10],
    ["padding 0", b64(bytes(3)), 10],
    ["padding 1", b64(bytes(2)), 10],
    ["padding 2", b64(bytes(1)), 10],
    ["exactly maxBytes", b64(bytes(300)), 300],
    ["maxBytes + 1", b64(bytes(301)), 300],
    ["wrong character", "AA-A", 10],
    ["url-safe underscore", "AA_A", 10],
    ["length not a multiple of 4", "AAAAA", 10],
    ["padding in the middle", "AA==AAAA", 10],
    ["three padding characters", "A===", 10],
    ["non-canonical last character", "AB==", 10],
    ["whitespace inside a 4-multiple", "AA A", 10],
    ["tab inside", "AAA\tAAAA", 10],
    ["padding first", "=AAA", 10],
    ["data: prefix", "data:image/png;base64,AAAA", 100],
  ];

  it.each(cases)("%s", (_name, text, max) => {
    const native = decodeBase64(text, max);
    const saved = Object.getOwnPropertyDescriptor(Uint8Array, "fromBase64");
    Object.defineProperty(Uint8Array, "fromBase64", { value: undefined, configurable: true, writable: true });
    let fallback: Uint8Array | undefined;
    try {
      fallback = decodeBase64(text, max);
    } finally {
      if (saved) Object.defineProperty(Uint8Array, "fromBase64", saved);
      else delete U8.fromBase64;
    }
    expect(native).toEqual(fallback);
  });

  it("decodes the exact bytes", () => {
    const b = bytes(1000);
    expect(decodeBase64(b64(b), 1000)).toEqual(b);
  });
});
