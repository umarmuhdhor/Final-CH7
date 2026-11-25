import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { DotsScene } from "./scenes/DotsScene";
import { EndScene } from "./scenes/EndScene";
import { LayersScene } from "./scenes/LayersScene";
import { LinkScene } from "./scenes/LinkScene";
import { PhoneScene } from "./scenes/PhoneScene";
import { Backdrop } from "./ui";
import "./fonts";

export const Loop: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      {/* music synthesized from the same beat map (scripts/make-music.py) */}
      <Audio src={staticFile("audio/music.wav")} />
      <Backdrop f={f} />
      <DotsScene f={f} />
      <LinkScene f={f} />
      <LayersScene f={f} />
      <PhoneScene f={f} />
      <EndScene f={f} />
    </AbsoluteFill>
  );
};
