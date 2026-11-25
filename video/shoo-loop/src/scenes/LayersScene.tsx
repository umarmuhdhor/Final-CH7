import React from "react";
import { Img, staticFile } from "remotion";
import { BRAND_FONT, UI_FONT } from "../fonts";
import { Icon, IconName } from "../icons";
import { easeIn, easeInOut, lerp, prog, punch, snap } from "../motion";
import { BRAND, EV, INK, INK_2, SCENE, b } from "../timing";
import { At, Scene, Words } from "../ui";

/*
 * "Diperiksa 4 lapis." — after the Cycode "Layered Stack for Security Platform" diagram (Moty Weiss,
 * Dribbble shot 23407362): an isometric stack of plates in the middle of the frame, closed at first,
 * then opening into evenly spaced layers, each with its name on the left and a dotted leader line.
 *
 *   16      the closed stack punches in under the title
 *   17      it opens: the Shoo plate on top, the four detection layers under it
 *   18–24   one layer per two beats lights up and lifts; its finding appears on the right on the
 *           next 8th, and its points add to the score beside the Shoo plate one beat later
 *   25.5    the stack snaps shut again (on the music's dropout)
 *   26      red floods out of it: "Diblokir."
 *
 * The story follows the real pipeline (detector/ = layers 1–2 on the phone, ai/ = 3–4 on the server):
 * a new scam is not in the database yet (0), the link gives it away (+45), the card + OTP form adds +30
 * (75: inside 30–79, so the AI check runs), and the AI confirms it (+17 → 92 ≥ 80: blocked).
 */

type Layer = {
  name: string;
  icon: IconName;
  face: string;
  finding: string;
  points: number;
};
const LAYERS: Layer[] = [
  {
    name: "Database penipuan",
    icon: "database",
    face: "DATABASE",
    finding: "Belum terdaftar, situs baru",
    points: 0,
  },
  {
    name: "Bedah link",
    icon: "link",
    face: "LINK",
    finding: "mybank + poin + .top",
    points: 45,
  },
  {
    name: "Isi & formulir",
    icon: "form",
    face: "FORMULIR",
    finding: "Minta nomor kartu & OTP",
    points: 30,
  },
  {
    name: "Cek realita AI",
    icon: "sparkle",
    face: "AI",
    finding: "Meniru MyBank",
    points: 17,
  },
];

const L = EV.layers;
const BLOCK = b(EV.blocked);
const RED = BRAND.red;
const MUTED = "rgba(25,29,47,0.45)";

// geometry: a square plate turned 45° and tipped 60° back reads as an isometric diamond
const SIZE = 250; // the square's side before the tilt
const HALF_W = (SIZE * Math.SQRT2) / 2; // half the diamond's width on screen (≈ 177)
const THICK = 16; // slab thickness in px
const GAP = 118; // spacing between open plates
const CY = 40; // centre of the stack
const OPEN_Y = [-2, -1, 0, 1, 2].map((k) => CY + k * GAP); // 0 = Shoo plate, 1–4 = layers
const SHUT_Y = [0, 1, 2, 3, 4].map((k) => CY - 36 + k * 18);
const ISO = "rotateX(60deg) rotateZ(45deg)";
const STACK_SCALE = 1.22;

const on = (f: number, at: number) => prog(f, b(at) - 2, b(at) + 12, snap);

/** One isometric slab: THICK stacked copies for the side, then the face with its content. */
const Plate: React.FC<{
  y: number;
  face: React.CSSProperties;
  side: string;
  edge: string;
  children?: React.ReactNode;
}> = ({ y, face, side, edge, children }) => {
  const sq: React.CSSProperties = {
    position: "absolute",
    left: -SIZE / 2,
    top: -SIZE / 2,
    width: SIZE,
    height: SIZE,
    borderRadius: 44,
    boxSizing: "border-box",
    transform: ISO,
  };
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: `translate(0px, ${y}px)`,
      }}
    >
      {Array.from({ length: THICK }).map((_, k) => (
        <div
          key={k}
          style={{
            ...sq,
            top: -SIZE / 2 + THICK - k,
            background: k === 0 ? edge : side,
          }}
        />
      ))}
      <div
        style={{
          ...sq,
          ...face,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {children}
      </div>
    </div>
  );
};

/** A label row: text block + dotted leader to the plate's edge. side = -1 (left) or 1 (right). */
const Leader: React.FC<{
  y: number;
  side: -1 | 1;
  t: number;
  children: React.ReactNode;
}> = ({ y, side, t, children }) => {
  const start = HALF_W + 26;
  const len = 80;
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: `translate(0px, ${y}px)`,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: -1,
          left: side > 0 ? start : -start - len * t,
          width: len * t,
          borderTop: "2.5px dotted rgba(25,29,47,0.3)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 0,
          [side > 0 ? "left" : "right"]: start + len + 22,
          transform: `translateY(-50%) translateX(${side * (1 - t) * 24}px)`,
          opacity: t,
          textAlign: side > 0 ? "left" : "right",
          whiteSpace: "nowrap",
        }}
      >
        {children}
      </div>
    </div>
  );
};

export const LayersScene: React.FC<{ f: number }> = ({ f }) => {
  const { in: inBeat, out } = SCENE.layers;
  if (f < b(inBeat) - 4 || f > b(out) + 4) return null;

  const appear = punch(f, b(inBeat) - 1);
  const open =
    prog(f, b(17) - 2, b(17) + 16, snap) *
    (1 - prog(f, b(EV.blocked - 0.5), BLOCK - 2, easeIn));
  const labels =
    prog(f, b(17.5) - 2, b(17.5) + 12, snap) *
    (1 - prog(f, b(EV.blocked - 0.5) - 4, b(EV.blocked - 0.5) + 2));
  const drift = lerp(1, 1.04, prog(f, b(inBeat), b(out), easeInOut));

  // score: each layer's points land one beat after its plate lights up
  const score = LAYERS.reduce((s, l, i) => s + l.points * on(f, L[i] + 1), 0);
  const hot = score >= 80;

  // which layer is lit now (0…1 for each), and which ones are done
  const lit = L.map((t, i) => {
    const next = i < L.length - 1 ? L[i + 1] : EV.blocked - 0.5;
    return punch(f, b(t) - 1) * (1 - prog(f, b(next) - 4, b(next) + 4));
  });
  const done = L.map((t) => on(f, t + 0.5));

  const yOf = (k: number) => lerp(SHUT_Y[k], OPEN_Y[k], open);

  // the red flood at the block, out of the stack's middle
  const flood = f >= BLOCK - 2 ? prog(f, BLOCK - 2, BLOCK + 8, easeIn) : 0;
  const word = punch(f, BLOCK + 1);
  const sub = on(f, EV.blocked + 0.5);

  return (
    <Scene f={f} inBeat={inBeat} outBeat={out}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          transform: `scale(${drift * lerp(0.7, 1, Math.min(1, appear))})`,
          opacity: Math.min(1, appear * 2),
        }}
      >
        <At y={-450}>
          <Words
            f={f}
            text="Diperiksa 4 lapis."
            beats={[16, 16.5, 17]}
            size={72}
            weight={900}
          />
        </At>

        {/* the stack and its labels, a size up around the stack's centre */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            transform: `scale(${STACK_SCALE})`,
            transformOrigin: `50% ${((540 + CY) / 1080) * 100}%`,
          }}
        >
          {/* plates, bottom first so the upper ones overlap */}
          {/* bottom first, but the lit plate last so nothing covers it */}
          {[4, 3, 2, 1]
            .sort(
              (x, y) =>
                (lit[x - 1] > 0.05 ? 1 : 0) - (lit[y - 1] > 0.05 ? 1 : 0),
            )
            .map((k) => {
              const i = k - 1;
              const a = lit[i];
              const l = LAYERS[i];
              const flagged = l.points > 0 && done[i] > 0.5;
              return (
                <div
                  key={k}
                  style={{
                    position: "absolute",
                    inset: 0,
                    transform: `translateY(${-22 * a}px)`,
                  }}
                >
                  <Plate
                    y={yOf(k)}
                    side={a > 0.05 ? "#9CC9EE" : "#D3E4F4"}
                    edge={a > 0.05 ? BRAND.dark : "#9DBEDD"}
                    face={{
                      background: a > 0.05 ? "#EAF5FE" : "white",
                      border: `${3 + 3 * a}px solid ${a > 0.05 ? BRAND.dark : "#A9C8E6"}`,
                      boxShadow:
                        a > 0.05
                          ? `0 0 ${40 * a}px rgba(30,120,190,${0.45 * a})`
                          : undefined,
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        flexDirection: "column",
                        alignItems: "center",
                        gap: 10,
                        color: a > 0.05 ? BRAND.dark : "#6F9CCB",
                      }}
                    >
                      <Icon name={l.icon} size={80} stroke={2.3} />
                      <div
                        style={{
                          fontFamily: UI_FONT,
                          fontSize: 24,
                          fontWeight: 800,
                          letterSpacing: 2,
                        }}
                      >
                        {l.face}
                      </div>
                    </div>
                    {/* a small mark on the plate once the layer has spoken: red for flagged, grey for no match */}
                    <div
                      style={{
                        position: "absolute",
                        right: 22,
                        top: 22,
                        width: 30,
                        height: 30,
                        borderRadius: 15,
                        background: flagged ? RED : "#B7C4D2",
                        color: "white",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontFamily: UI_FONT,
                        fontSize: 20,
                        fontWeight: 800,
                        opacity: done[i],
                        transform: `scale(${lerp(0.4, 1, done[i])})`,
                      }}
                    >
                      {flagged ? "!" : "–"}
                    </div>
                  </Plate>
                </div>
              );
            })}
          {/* the Shoo plate on top */}
          <Plate
            y={yOf(0)}
            side={hot ? "#B8323A" : "#155F9C"}
            edge={hot ? "#8E1F27" : BRAND.deep}
            face={{
              background: hot
                ? `linear-gradient(160deg, #F06A6E, ${RED})`
                : `linear-gradient(160deg, ${BRAND.light}, ${BRAND.dark})`,
              border: "3px solid rgba(255,255,255,0.55)",
            }}
          >
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 6,
              }}
            >
              <Img
                src={staticFile("shoo-logo-3x.png")}
                style={{ height: 84 }}
              />
              <div
                style={{
                  fontFamily: BRAND_FONT,
                  fontSize: 40,
                  fontWeight: 900,
                  color: "white",
                  letterSpacing: 2,
                }}
              >
                SHOO
              </div>
            </div>
          </Plate>

          {/* left: layer names */}
          {LAYERS.map((l, i) => {
            const a = lit[i];
            return (
              <Leader key={l.name} y={yOf(i + 1) - 22 * a} side={-1} t={labels}>
                <div
                  style={{
                    fontFamily: UI_FONT,
                    fontSize: 18,
                    fontWeight: 700,
                    color: a > 0.3 ? BRAND.dark : MUTED,
                    letterSpacing: 3,
                  }}
                >
                  LAPIS {i + 1}
                </div>
                <div
                  style={{
                    fontFamily: BRAND_FONT,
                    fontSize: lerp(32, 42, a),
                    fontWeight: 900,
                    color: a > 0.3 ? INK : "rgba(25,29,47,0.55)",
                    lineHeight: 1.1,
                  }}
                >
                  {l.name}
                </div>
              </Leader>
            );
          })}
          {/* left of the Shoo plate: nothing; right of it: the score */}
          <Leader y={yOf(0)} side={1} t={labels}>
            <div
              style={{
                fontFamily: UI_FONT,
                fontSize: 22,
                fontWeight: 700,
                color: MUTED,
                letterSpacing: 3,
              }}
            >
              SKOR RISIKO
            </div>
            <div
              style={{
                fontFamily: BRAND_FONT,
                fontSize: 76,
                fontWeight: 900,
                color: hot ? RED : INK,
                lineHeight: 1,
              }}
            >
              {Math.round(score)}
              <span style={{ fontSize: 30, color: MUTED }}> / 100</span>
            </div>
          </Leader>

          {/* right: each layer's finding */}
          {LAYERS.map((l, i) => {
            const t = done[i] * labels;
            const a = lit[i];
            return (
              <Leader key={l.finding} y={yOf(i + 1) - 22 * a} side={1} t={t}>
                <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                  <span
                    style={{
                      fontFamily: BRAND_FONT,
                      fontSize: 26,
                      fontWeight: 900,
                      color: "white",
                      background: l.points ? RED : "#B7C4D2",
                      borderRadius: 999,
                      padding: "4px 14px",
                    }}
                  >
                    {l.points ? `+${l.points}` : "0"}
                  </span>
                  <span
                    style={{
                      fontFamily: UI_FONT,
                      fontSize: 28,
                      fontWeight: 600,
                      color: a > 0.3 ? INK : INK_2,
                    }}
                  >
                    {l.finding}
                  </span>
                </div>
              </Leader>
            );
          })}
        </div>
      </div>

      {/* beat 26: red floods out of the shut stack, "Diblokir." */}
      {flood > 0 && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: RED,
            clipPath: `circle(${flood * 2300}px at 960px ${540 + CY}px)`,
          }}
        >
          <At y={-40}>
            <div style={{ textAlign: "center" }}>
              <div
                style={{
                  fontFamily: BRAND_FONT,
                  fontSize: 240,
                  fontWeight: 900,
                  color: "white",
                  lineHeight: 1,
                  letterSpacing: -4,
                  transform: `scale(${lerp(1.5, 1, Math.min(1, word))})`,
                  opacity: Math.min(1, word * 2),
                }}
              >
                Diblokir.
              </div>
              <div
                style={{
                  fontFamily: BRAND_FONT,
                  fontSize: 54,
                  fontWeight: 800,
                  color: "rgba(255,255,255,0.9)",
                  marginTop: 24,
                  opacity: sub,
                  transform: `translateY(${(1 - sub) * 20}px)`,
                }}
              >
                Skor 92 dari 100.
              </div>
            </div>
          </At>
        </div>
      )}
    </Scene>
  );
};
