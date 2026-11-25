import { Easing, interpolate, spring } from "remotion";
import { BEAT, DROP, EV, FPS, b } from "./timing";

const CLAMP = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
/** Snappy: most of the move happens in the first few frames, then it glides (fast in, slow out). */
export const snap = Easing.bezier(0.05, 0.9, 0.1, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const easeIn = Easing.bezier(0.7, 0, 0.84, 0);

/** 0 → 1 between frames a and b. */
export const prog = (f: number, a: number, b: number, e = easeOut) =>
  interpolate(f, [a, b], [0, 1], { ...CLAMP, easing: e });

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** A soft spring (no visible overshoot) starting at `start`. */
export const soft = (f: number, start: number, damping = 22, stiffness = 110) =>
  spring({
    frame: f - start,
    fps: FPS,
    config: { damping, stiffness, mass: 0.9 },
  });

/** A quick spring that lands on the beat with a hint of bounce. */
export const punch = (f: number, start: number) =>
  spring({
    frame: f - start,
    fps: FPS,
    config: { damping: 15, stiffness: 260, mass: 0.7 },
  });

/**
 * Scene in/out, in beats. A scene lands on its `inBeat` (the kick) with a snappy zoom out of blur,
 * and leaves in the half beat before `outBeat` by zooming through the viewer, so the cut sits on the beat.
 */
export const envelope = (f: number, inBeat: number, outBeat: number) => {
  const inAt = b(inBeat) - 2; // starts 2 frames early so the hit reads on the kick
  const dIn = Math.round(BEAT * 0.75);
  const outAt = b(outBeat) - Math.round(BEAT * 0.5);
  const dOut = Math.round(BEAT * 0.5);
  const i = inBeat <= 0 ? 1 : prog(f, inAt, inAt + dIn, snap);
  const o = prog(f, outAt, outAt + dOut, easeIn);
  return {
    visible: f >= inAt - 1 && f <= outAt + dOut + 1,
    scale: lerp(0.86, 1, i) * lerp(1, 1.22, o),
    blur: 20 * (1 - i) + 24 * o,
    opacity: Math.min(i * 1.6, 1) * (1 - o),
  };
};

/** Beats where the camera punches: the big hits the music marks with an impact, crash or thock. */
const HITS: { beat: number; amp: number }[] = [
  { beat: DROP, amp: 1 },
  { beat: EV.enter, amp: 0.6 },
  ...EV.layers.map((beat) => ({ beat, amp: 0.45 })),
  { beat: EV.blocked, amp: 1 },
  { beat: EV.phone_slam, amp: 0.7 },
  { beat: EV.push, amp: 0.5 },
  { beat: EV.end_mascot, amp: 0.7 },
];

/**
 * Camera punch on the hits: rises over 2 frames into the beat, then decays over about half a beat.
 * Returns 0…1 (times the hit's amp).
 */
export const accent = (f: number) => {
  let v = 0;
  for (const h of HITS) {
    const since = f - b(h.beat) + 2;
    if (since < 0 || since > BEAT) continue;
    const a = Math.min(1, since / 2);
    v = Math.max(v, h.amp * a * a * (3 - 2 * a) * Math.exp(-Math.max(0, since - 2) / (BEAT * 0.2)));
  }
  return v;
};
