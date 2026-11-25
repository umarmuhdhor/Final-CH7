import React from "react";
import { Composition } from "remotion";
import { Loop } from "./Loop";
import { FPS, H, TOTAL, W } from "./timing";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="ShooLoop"
    component={Loop}
    durationInFrames={TOTAL}
    fps={FPS}
    width={W}
    height={H}
  />
);
