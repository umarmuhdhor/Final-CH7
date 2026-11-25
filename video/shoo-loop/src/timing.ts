import MAP from "./beats.json";

// One beat map drives the picture and the music (scripts/make-music.py synthesizes the track from the
// same src/beats.json), so every hit is on the same frame in both. 120 BPM at 60 fps = 30 frames a beat.
export const FPS = 60;
export const W = 1920;
export const H = 1080;
export const BPM = MAP.bpm;
export const BEAT = (FPS * 60) / BPM;
export const b = (beats: number) => Math.round(beats * BEAT);
export const TOTAL = b(MAP.beats); // 1200 frames = 20 s

export const SCENE = MAP.scenes;
export const EV = MAP.events;
export const DROP = MAP.music.drop;
export const GROOVE_END = MAP.music.groove_end;

// Shoo's brand blues (ios/ShooApp/Features/Shield/HomeChrome.swift), same as video/shoo-promo.
export const BRAND = {
  dark: "#1E78BE",
  light: "#68CDFA",
  glow: "#8FE9EC",
  teal: "#3FB8A8",
  navy: "#191D2F",
  deep: "#0B3C6E",
  red: "#E5484D",
  orange: "#FF9F0A",
} as const;

export const INK = BRAND.navy;
export const INK_2 = "rgba(25,29,47,0.6)";
