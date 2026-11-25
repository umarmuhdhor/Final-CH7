import React from "react";
import { Img, staticFile } from "remotion";
import { easeInOut, lerp, prog, punch } from "../motion";
import { BRAND, EV, INK_2, SCENE, TOTAL, b } from "../timing";
import { BRAND_FONT } from "../fonts";
import { At, Letters, Scene, Words } from "../ui";

export const EndScene: React.FC<{ f: number }> = ({ f }) => {
  // Beats: mascot on 34, logo 34.5 (sparkle), S·H·O·O from 35, tagline from 36, badge on 37.
  // The fade runs with the music's low-pass close (38 → 40) into the empty sky the loop starts on.
  const { in: inBeat, out } = SCENE.end;
  const inAt = b(inBeat);
  if (f < inAt - 4) return null;

  const owl = punch(f, inAt - 1);
  // gentle float; fully settled long before the fade so the loop seam stays clean
  const bob = 10 * Math.sin(((f - inAt) / b(2)) * Math.PI * 2); // one bob per two beats
  const logo = punch(f, b(EV.end_logo) - 1);
  const badge = punch(f, b(EV.end_badge) - 1);
  // final fade into the same empty sky the loop starts on (ends exactly at TOTAL)
  const fade = prog(f, b(out), TOTAL - 4, easeInOut);

  return (
    <Scene f={f} inBeat={inBeat} outBeat={1000}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 1 - fade,
          filter: fade > 0 ? `blur(${fade * 20}px)` : undefined,
          transform: `scale(${lerp(1, 0.94, fade)})`,
        }}
      >
        {/* mascot */}
        <At x={-470} y={30 + bob * owl + (1 - owl) * 120}>
          <Img
            src={staticFile("mascot/wave.png")}
            style={{
              height: 560,
              opacity: Math.min(1, owl * 1.5),
              filter: `drop-shadow(0 30px 40px rgba(11,60,110,0.25))${owl < 0.98 ? ` blur(${(1 - owl) * 16}px)` : ""}`,
              transform: `rotate(${(1 - owl) * -8}deg)`,
            }}
          />
        </At>

        {/* lockup */}
        <At x={230} y={-110}>
          <div style={{ display: "flex", alignItems: "center", gap: 30 }}>
            <Img
              src={staticFile("shoo-logo-3x.png")}
              style={{
                height: 190,
                opacity: Math.min(1, logo * 1.5),
                transform: `scale(${lerp(0.6, 1, logo)})`,
                filter: `drop-shadow(0 18px 30px rgba(30,120,190,0.35))${logo < 0.98 ? ` blur(${(1 - logo) * 18}px)` : ""}`,
              }}
            />
            <Letters f={f} text="SHOO" beat={EV.end_word} step={0.25} size={170} />
          </div>
        </At>

        <At x={230} y={70}>
          <Words f={f} text="Bersama, kita usir penipuan." beats={[EV.end_line, EV.end_line + 0.25, EV.end_line + 0.5, EV.end_line + 0.75]} size={52} weight={800} color={BRAND.deep} />
        </At>

        <At x={230} y={200}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 26,
              opacity: Math.min(1, badge * 1.5),
              transform: `translateY(${(1 - badge) * 24}px)`,
            }}
          >
            <Img
              src={staticFile("app-store-badge.svg")}
              style={{ height: 78 }}
            />
            <div
              style={{
                fontFamily: BRAND_FONT,
                fontSize: 30,
                fontWeight: 700,
                color: INK_2,
                whiteSpace: "nowrap",
              }}
            >
              Untuk iPhone · Safari
            </div>
          </div>
        </At>
      </div>
    </Scene>
  );
};
