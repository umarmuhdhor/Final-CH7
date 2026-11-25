import React from "react";
import { Img, staticFile } from "remotion";
import { UI_FONT } from "../fonts";
import { easeInOut, lerp, prog, punch, snap } from "../motion";
import { BEAT, BRAND, EV, INK, INK_2, SCENE, b } from "../timing";
import { At, Scene, Words, glass } from "../ui";

const URL = "mybank-poin.top/klaim-hadiah";
// Beats: caption 8–9, URL typed on 16ths 9–11.75, enter on the kick at 12 (click + thock), scan 12–14.
const TYPE_AT = b(EV.type_start);
const TYPE_END = b(EV.type_end);
const TAP_AT = b(EV.enter);
const SCAN_END = b(EV.scan_end);

export const LinkScene: React.FC<{ f: number }> = ({ f }) => {
  const { in: inBeat, out } = SCENE.link;
  if (f < b(inBeat) - 4 || f > b(out) + 4) return null;

  // one key tick per 16th in the music (type_start → type_end); the URL fills in on each tick
  const tick = Math.floor((f - TYPE_AT) / (BEAT / 4));
  const ticks = Math.round((TYPE_END - TYPE_AT) / (BEAT / 4)) + 1;
  const typed = f < TYPE_AT ? 0 : Math.min(URL.length, Math.round((URL.length * (tick + 1)) / ticks));
  const typing = f >= TYPE_AT && typed < URL.length;
  const caret = typing || Math.floor(f / 30) % 2 === 0;
  const tap = punch(f, TAP_AT - 1);
  const press = f >= TAP_AT - 1 ? Math.max(0, 1 - tap) * 0.6 : 0;
  const scan = prog(f, TAP_AT, SCAN_END, easeInOut);
  const scanning = f >= TAP_AT;
  const status = prog(f, b(12.5) - 2, b(12.5) + 14, snap);
  // slow push-in across the whole scene
  const push = lerp(1, 1.05, prog(f, b(inBeat), b(out), easeInOut));

  return (
    <Scene f={f} inBeat={inBeat} outBeat={out}>
      <div style={{ position: "absolute", inset: 0, transform: `scale(${push})` }}>
        <At y={-190}>
          <Words f={f} text="Satu link mencurigakan…" beats={[8, 8.5, 9]} size={72} out={12.5} />
        </At>
        <At y={-190}>
          <Words f={f} text="Shoo memeriksanya seketika." beats={[13, 13.5, 14]} size={72} />
        </At>

        {/* Safari address bar */}
        <At y={20}>
          <div
            style={{
              ...glass,
              width: 1080,
              height: 128,
              borderRadius: 40,
              display: "flex",
              alignItems: "center",
              padding: "0 40px",
              gap: 26,
              position: "relative",
              overflow: "hidden",
              transform: `scale(${1 - press * 0.04})`,
              fontFamily: UI_FONT,
            }}
          >
            <div style={{ fontSize: 34, fontWeight: 600, color: INK_2, width: 56 }}>aA</div>
            <div
              style={{
                flex: 1,
                fontSize: 44,
                fontWeight: 500,
                color: INK,
                letterSpacing: -0.4,
                whiteSpace: "nowrap",
                display: "flex",
                alignItems: "center",
              }}
            >
              {URL.slice(0, typed)}
              <span
                style={{
                  display: "inline-block",
                  width: 3.5,
                  height: 50,
                  marginLeft: 3,
                  borderRadius: 2,
                  background: BRAND.dark,
                  opacity: caret && !scanning ? 1 : 0,
                }}
              />
            </div>
            {/* Shoo badge on the right, lights up on the tap and pulses on each beat while checking */}
            <div
              style={{
                width: 70,
                height: 70,
                borderRadius: 22,
                background: "white",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                boxShadow: `0 0 ${36 * status}px rgba(30,120,190,${0.55 * status})`,
                transform: `scale(${1 + 0.15 * (scanning ? Math.max(0, 1 - tap) : 0) + 0.06 * status * (1 - scan) * Math.abs(Math.sin(((f - TAP_AT) / (b(13) - b(12))) * Math.PI))})`,
              }}
            >
              <Img src={staticFile("shoo-logo-3x.png")} style={{ height: 46 }} />
            </div>
            {/* scan sweep */}
            {scanning && scan < 1 && (
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  bottom: 0,
                  left: `${lerp(-30, 110, scan)}%`,
                  width: 260,
                  background:
                    "linear-gradient(90deg, rgba(104,205,250,0) 0%, rgba(104,205,250,0.38) 50%, rgba(104,205,250,0) 100%)",
                }}
              />
            )}
            {/* progress line */}
            <div
              style={{
                position: "absolute",
                left: 0,
                bottom: 0,
                height: 5,
                width: `${scan * 100}%`,
                background: `linear-gradient(90deg, ${BRAND.light}, ${BRAND.dark})`,
                opacity: scanning ? 1 - prog(f, SCAN_END, SCAN_END + 16) : 0,
              }}
            />
          </div>
        </At>

        {/* status line under the bar */}
        <At y={150}>
          <div
            style={{
              fontFamily: UI_FONT,
              fontSize: 30,
              fontWeight: 500,
              color: INK_2,
              display: "flex",
              alignItems: "center",
              gap: 14,
              opacity: status,
              transform: `translateY(${(1 - status) * 18}px)`,
              whiteSpace: "nowrap",
            }}
          >
            <svg width={30} height={30} viewBox="0 0 30 30">
              <circle cx={15} cy={15} r={11} fill="none" stroke="rgba(30,120,190,0.18)" strokeWidth={4} />
              <circle
                cx={15}
                cy={15}
                r={11}
                fill="none"
                stroke={BRAND.dark}
                strokeWidth={4}
                strokeLinecap="round"
                strokeDasharray={`${18 + 40 * scan} 100`}
                transform={`rotate(${f * 9} 15 15)`}
              />
            </svg>
            Memeriksa alamat, isi halaman, dan pola penipuan
          </div>
        </At>
      </div>
    </Scene>
  );
};
