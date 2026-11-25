import React from "react";
import { AbsoluteFill } from "remotion";
import { BRAND_FONT } from "./fonts";
import { accent, envelope, prog, snap } from "./motion";
import { INK, TOTAL, b } from "./timing";

/**
 * Soft sky backdrop. Every moving part is periodic over TOTAL, so the last frame matches the first
 * and the loop has no seam. It brightens a touch on each hit.
 */
export const Backdrop: React.FC<{ f: number }> = ({ f }) => {
  const t = (f / TOTAL) * Math.PI * 2;
  const ax = 22 + 8 * Math.sin(t);
  const ay = 18 + 6 * Math.cos(t);
  const bx = 80 + 7 * Math.cos(t + 1.2);
  const by = 30 + 8 * Math.sin(t + 1.2);
  const k = accent(f);
  return (
    <AbsoluteFill
      style={{
        background: [
          `radial-gradient(60% 55% at ${ax}% ${ay}%, rgba(140,205,245,${0.75 + 0.15 * k}) 0%, rgba(140,205,245,0) 70%)`,
          `radial-gradient(55% 50% at ${bx}% ${by}%, rgba(170,228,240,${0.7 + 0.15 * k}) 0%, rgba(170,228,240,0) 70%)`,
          "radial-gradient(90% 45% at 50% 108%, rgba(255,255,255,1) 0%, rgba(255,255,255,0) 70%)",
          "linear-gradient(180deg, #CFE9FA 0%, #E3F3FC 55%, #F6FBFE 100%)",
        ].join(","),
      }}
    />
  );
};

/** A scene layer that lands on `inBeat` and zooms through the viewer just before `outBeat`. */
export const Scene: React.FC<{
  f: number;
  inBeat: number;
  outBeat: number;
  children: React.ReactNode;
}> = ({ f, inBeat, outBeat, children }) => {
  const e = envelope(f, inBeat, outBeat);
  if (!e.visible) return null;
  const bump = 1 + 0.018 * accent(f);
  return (
    <AbsoluteFill
      style={{
        opacity: e.opacity,
        transform: `scale(${e.scale * bump})`,
        filter: e.blur > 0.05 ? `blur(${e.blur}px)` : undefined,
        willChange: "transform, filter, opacity",
      }}
    >
      {children}
    </AbsoluteFill>
  );
};

/** Centre-anchored absolute box: (x, y) are offsets from the frame centre. */
export const At: React.FC<{
  x?: number;
  y?: number;
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({ x = 0, y = 0, style, children }) => (
  <div
    style={{
      position: "absolute",
      left: "50%",
      top: "50%",
      transform: `translate(-50%, -50%) translate(${x}px, ${y}px)`,
      ...style,
    }}
  >
    {children}
  </div>
);

/** One word (or letter) snapping in: up out of blur, fast in and slow out. */
const Pop: React.FC<{ f: number; at: number; children: React.ReactNode; dy?: number }> = ({
  f,
  at,
  children,
  dy = 36,
}) => {
  const t = prog(f, at - 2, at + 16, snap);
  return (
    <span
      style={{
        display: "inline-block",
        opacity: Math.min(1, t * 1.8),
        transform: `translateY(${(1 - t) * dy}px) scale(${0.92 + 0.08 * t})`,
        filter: t < 0.995 ? `blur(${(1 - t) * 12}px)` : undefined,
        whiteSpace: "pre",
      }}
    >
      {children}
    </span>
  );
};

/**
 * A headline that lands word by word on the beat grid. `beats` gives the beat for each word
 * (like the Moolah reference: "Your" · "new" · "money" · "app").
 */
export const Words: React.FC<{
  f: number;
  text: string;
  beats: number[];
  size?: number;
  weight?: number;
  color?: string;
  out?: number; // beat on which it blurs away
}> = ({ f, text, beats, size = 64, weight = 800, color = INK, out }) => {
  const gone = out === undefined ? 0 : prog(f, b(out) - 10, b(out) + 6);
  const words = text.split(" ");
  return (
    <div
      style={{
        fontFamily: BRAND_FONT,
        fontSize: size,
        fontWeight: weight,
        color,
        letterSpacing: -0.5,
        lineHeight: 1.08,
        whiteSpace: "pre",
        display: "flex",
        opacity: 1 - gone,
        filter: gone > 0 ? `blur(${gone * 14}px)` : undefined,
        transform: `translateY(${-gone * 18}px)`,
      }}
    >
      {words.map((w, i) => (
        <Pop key={i} f={f} at={b(beats[Math.min(i, beats.length - 1)])}>
          {i < words.length - 1 ? `${w} ` : w}
        </Pop>
      ))}
    </div>
  );
};

/** A word whose letters land one by one, `step` beats apart (for the SHOO wordmark). */
export const Letters: React.FC<{
  f: number;
  text: string;
  beat: number;
  step: number;
  size: number;
  weight?: number;
  color?: string;
}> = ({ f, text, beat, step, size, weight = 900, color = INK }) => (
  <div
    style={{
      fontFamily: BRAND_FONT,
      fontSize: size,
      fontWeight: weight,
      color,
      letterSpacing: -0.5,
      display: "flex",
    }}
  >
    {[...text].map((ch, i) => (
      <Pop key={i} f={f} at={b(beat + i * step)} dy={60}>
        {ch}
      </Pop>
    ))}
  </div>
);

export const glass: React.CSSProperties = {
  background: "rgba(255,255,255,0.82)",
  border: "1.5px solid rgba(255,255,255,0.95)",
  boxShadow:
    "0 30px 80px rgba(30,120,190,0.18), 0 6px 18px rgba(30,120,190,0.10), inset 0 1px 0 rgba(255,255,255,1)",
};
