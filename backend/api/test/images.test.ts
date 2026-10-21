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
