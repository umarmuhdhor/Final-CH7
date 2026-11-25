import React from "react";
import { Img, staticFile } from "remotion";
import { UI_FONT } from "../fonts";
import { easeInOut, lerp, prog, punch, soft } from "../motion";
import { BRAND, EV, INK, SCENE, b } from "../timing";
import { At, Scene, Words } from "../ui";

const PHONE_W = 400;
const PHONE_H = (PHONE_W * 2532) / 1170 + 28; // screen ratio of blocked.png + bezel
// Beats: phone slams up on 28, headline one line per beat (29, 30), the family push + chime + caption on 31.5.
const PUSH_AT = b(EV.push);

export const PhoneScene: React.FC<{ f: number }> = ({ f }) => {
  const { in: inBeat, out } = SCENE.phone;
  const inAt = b(inBeat);
  if (f < inAt - 4 || f > b(out) + 4) return null;

  // phone stands up out of the bottom, tilted back (the promo's entrance), then sways gently
  const e = soft(f, inAt - 2, 18, 170);
  const k = 1 - e;
  const sway =
    5 *
    Math.sin(((f - inAt) / 200) * Math.PI * 2) *
    prog(f, inAt + 20, inAt + 60);
  const push = punch(f, PUSH_AT - 1);
  const glow = 0.75 + 0.25 * Math.sin((f - inAt) * 0.09);
  const drift = lerp(1, 1.04, prog(f, inAt, b(out), easeInOut));

  return (
    <Scene f={f} inBeat={inBeat} outBeat={out}>
      <div
        style={{ position: "absolute", inset: 0, transform: `scale(${drift})` }}
      >
        {/* copy on the left */}
        <At x={-400} y={-110}>
          <div
            style={{
              width: 760,
              display: "flex",
              flexDirection: "column",
              gap: 0,
            }}
          >
            <Words f={f} text="Situs penipuan" beats={[EV.phone_line1, EV.phone_line1]} size={84} weight={900} />
            <Words f={f} text="langsung diblokir." beats={[EV.phone_line2, EV.phone_line2]} size={84} weight={900} color={BRAND.red} />
            <div style={{ height: 28 }} />
            <Words f={f} text="Keluarga ikut dikabari." beats={[EV.push, EV.push, EV.push]} size={46} weight={700} color={BRAND.dark} />
          </div>
        </At>

        {/* red glow behind the phone */}
        <At x={430} y={10}>
          <div
            style={{
              width: 760,
              height: 760,
              borderRadius: "50%",
              background:
                "radial-gradient(circle, rgba(229,72,77,0.38) 0%, rgba(229,72,77,0) 62%)",
              opacity: e * glow,
            }}
          />
        </At>

        {/* the phone */}
        <At x={430} y={30 + 760 * k}>
          <div style={{ perspective: 1800 }}>
            <div
              style={{
                width: PHONE_W,
                height: PHONE_H,
                borderRadius: 66,
                background: "#111",
                padding: 14,
                boxSizing: "border-box",
                boxShadow:
                  "0 60px 120px rgba(11,60,110,0.35), 0 0 0 2px #2a2a2e inset",
                transform: `rotateX(${55 * k}deg) rotateY(${sway}deg) scale(${(1 + 0.5 * k) * 0.82})`,
                filter: k > 0.01 ? `blur(${10 * k * k}px)` : undefined,
                opacity: Math.min(1, e * 3),
              }}
            >
              <div
                style={{
                  width: "100%",
                  height: "100%",
                  borderRadius: 52,
                  overflow: "hidden",
                  position: "relative",
                }}
              >
                <Img
                  src={staticFile("blocked.png")}
                  style={{ width: "100%", height: "100%", display: "block" }}
                />
                {/* dynamic island */}
                <div
                  style={{
                    position: "absolute",
                    top: 12,
                    left: "50%",
                    width: 118,
                    height: 34,
                    marginLeft: -59,
                    borderRadius: 17,
                    background: "#000",
                  }}
                />
              </div>
            </div>
          </div>
        </At>

        {/* the family's push, slides in under the copy */}
        <At x={-500} y={190 + (1 - push) * 50}>
          <div
            style={{
              width: 560,
              boxSizing: "border-box",
              borderRadius: 34,
              padding: "22px 26px",
              background: "rgba(250,250,252,0.94)",
              boxShadow:
                "0 30px 70px rgba(11,60,110,0.28), 0 4px 14px rgba(0,0,0,0.08)",
              display: "flex",
              gap: 18,
              alignItems: "center",
              fontFamily: UI_FONT,
              opacity: Math.min(1, push * 1.6),
              filter: push < 0.98 ? `blur(${(1 - push) * 12}px)` : undefined,
              transform: `scale(${lerp(0.9, 1, push)})`,
            }}
          >
            <div
              style={{
                width: 76,
                height: 76,
                borderRadius: 18,
                background: `linear-gradient(160deg, ${BRAND.light}, ${BRAND.dark})`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
              }}
            >
              <Img
                src={staticFile("shoo-logo-3x.png")}
                style={{ height: 54 }}
              />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  fontSize: 24,
                  color: "rgba(0,0,0,0.5)",
                  fontWeight: 500,
                }}
              >
                <span
                  style={{ color: INK, fontWeight: 700, letterSpacing: 0.3 }}
                >
                  SHOO
                </span>
                <span>sekarang</span>
              </div>
              <div
                style={{
                  fontSize: 27,
                  color: INK,
                  fontWeight: 600,
                  marginTop: 4,
                  lineHeight: 1.25,
                }}
              >
                Mama membuka situs yang diblokir · 92%
              </div>
            </div>
          </div>
        </At>
      </div>
    </Scene>
  );
};
