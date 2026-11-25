import React from "react";
import { Img, staticFile } from "remotion";
import { BRAND_FONT } from "../fonts";
import { easeInOut, lerp, prog, punch, snap, soft } from "../motion";
import { BEAT, EV, INK_2, SCENE, b } from "../timing";
import SHIELD from "../shieldDots.json";
import { At, Letters, Scene, Words } from "../ui";

// The dots are a halftone of the real logo (scripts/make-shield-dots.py → src/shieldDots.json): one dot
// per grid cell inside its silhouette, in the logo's colour there, sized by how dark it is.
const DOTS = SHIELD.dots.map((p) => ({ ...p, d: Math.hypot(p.x / (SHIELD.w / 2), p.y / (SHIELD.h / 2)) }));
const BIG = 1.18; // the dot shield is a little bigger than the logo it becomes

const LOGO_H = 340;
const LOGO_W = (LOGO_H * 408) / 456;

// Beats (breakdown, before the drop on beat 8)
const LOGO = EV.logo; // logo lands
const SHIFT = 4; // logo slides left
const WORD = EV.wordmark; // S·H·O·O, a quarter beat apart
const LINE = EV.tagline; // tagline word by word

/** A ring that runs out from the centre on every beat: how strongly it lifts a dot at distance d. */
const beatWave = (f: number, d: number) => {
  const since = (f % BEAT) / BEAT; // 0 → 1 within the beat
  const front = since * 1.8;
  return Math.exp(-((front - d) ** 2) / 0.03) * (1 - since);
};

export const DotsScene: React.FC<{ f: number }> = ({ f }) => {
  const { in: inBeat, out } = SCENE.dots;

  // grid tightens from BIG to the logo's size, then fades as the logo lands on top of it
  const tighten = prog(f, b(LOGO - 0.75), b(LOGO), easeInOut);
  const S = lerp(BIG, LOGO_H / SHIELD.h, tighten);
  const morph = prog(f, b(LOGO) - 2, b(LOGO) + 10);
  const logoIn = punch(f, b(LOGO) - 1);
  const shift = prog(f, b(SHIFT) - 2, b(SHIFT) + 16, snap);
  const sheen = prog(f, b(LOGO + 0.5), b(LOGO + 1.5), easeInOut);
  const logoX = lerp(0, -308, shift);
  const logoScale = lerp(0.92, 1, logoIn) * lerp(1, 0.62, shift);
  // keeps drifting toward the viewer through the hold, so the frame never sits still
  const drift = lerp(1, 1.06, prog(f, b(LOGO), b(out), easeInOut));

  return (
    <Scene f={f} inBeat={inBeat} outBeat={out}>
      <div style={{ position: "absolute", inset: 0, transform: `scale(${drift})` }}>
        {/* the dot shield (a halftone of the logo): pops in from the centre, a ring runs through it on
            every beat, then the grid tightens onto the logo's size and hands over to the real logo */}
        {morph < 1 && (
          <At y={-20}>
            <svg width={640} height={700} viewBox="-320 -350 640 700" style={{ overflow: "visible" }}>
              {DOTS.map((p, i) => {
                const born = soft(f, 2 + p.d * b(1.2), 14, 160);
                const lift = 1 + 0.55 * beatWave(f, p.d) * prog(f, b(0.75), b(1));
                const r = (SHIELD.pitch / 2) * S * 0.92 * p.s * born * lift;
                if (r < 0.05) return null;
                return (
                  <circle
                    key={i}
                    cx={p.x * S}
                    cy={p.y * S}
                    r={r}
                    fill={p.c}
                    opacity={(0.35 + 0.65 * born) * (1 - morph)}
                  />
                );
              })}
            </svg>
          </At>
        )}

        {/* the logo, punched in on the beat */}
        {f >= b(LOGO) - 2 && (
          <At x={logoX} y={-20}>
            <div
              style={{
                position: "relative",
                width: LOGO_W,
                height: LOGO_H,
                transform: `scale(${logoScale})`,
                opacity: Math.min(1, logoIn * 2),
                filter: logoIn < 0.97 ? `blur(${Math.max(0, 1 - logoIn) * 26}px)` : undefined,
              }}
            >
              <Img
                src={staticFile("shoo-logo-3x.png")}
                style={{
                  width: "100%",
                  height: "100%",
                  filter: "drop-shadow(0 24px 40px rgba(30,120,190,0.35))",
                }}
              />
              {/* glossy sweep, clipped to the logo's own alpha */}
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  WebkitMaskImage: `url(${staticFile("shoo-logo-3x.png")})`,
                  WebkitMaskSize: "100% 100%",
                  background: `linear-gradient(115deg, rgba(255,255,255,0) ${lerp(-40, 110, sheen) - 18}%, rgba(255,255,255,0.75) ${lerp(-40, 110, sheen)}%, rgba(255,255,255,0) ${lerp(-40, 110, sheen) + 18}%)`,
                }}
              />
            </div>
          </At>
        )}

        {/* wordmark + line */}
        <At x={115} y={-34}>
          <Letters f={f} text="SHOO" beat={WORD} step={0.25} size={190} />
        </At>
        <At y={150}>
          <div style={{ fontFamily: BRAND_FONT, color: INK_2 }}>
            <Words
              f={f}
              text="Pelindung keluarga dari situs penipuan"
              beats={[LINE, LINE + 0.25, LINE + 0.5, LINE + 1, LINE + 1.25]}
              size={40}
              weight={700}
              color={INK_2}
            />
          </div>
        </At>
      </div>
    </Scene>
  );
};
