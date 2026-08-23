"use client";

import { type ReactNode, useSyncExternalStore } from "react";

export const STAGE_W = 1920;
export const STAGE_H = 1080;

const subscribe = (onChange: () => void) => {
  window.addEventListener("resize", onChange);
  return () => window.removeEventListener("resize", onChange);
};
const readScale = () => Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H);
const serverScale = () => 1;

/** A 1920×1080 canvas scaled to fit the viewport; slides lay out in stage pixels. */
export function Stage({ children }: { children: ReactNode }) {
  const scale = useSyncExternalStore(subscribe, readScale, serverScale);
  return (
    <div className="sl-stage" style={{ transform: `scale(${scale.toFixed(4)})` }}>
      {children}
    </div>
  );
}
