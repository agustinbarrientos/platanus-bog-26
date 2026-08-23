"use client";

import { useEffect, useState } from "react";

export const clamp = (x: number) => Math.max(0, Math.min(1, x));

export const easeOut = (t: number) => 1 - Math.pow(1 - clamp(t), 3);

/**
 * 0→1 over `durationMs`, counted from the moment `active` becomes true, after
 * an optional `delayMs`. The landing's charts take this number from scroll;
 * the deck takes it from time. State only changes inside animation frames,
 * never synchronously in the effect.
 */
export function useClock(active: boolean, durationMs: number, delayMs = 0): number {
  const [local, setLocal] = useState(0);

  useEffect(() => {
    if (!active) return;
    let raf = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const e = clamp((now - t0 - delayMs) / durationMs);
      setLocal(e);
      if (e < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [active, durationMs, delayMs]);

  return active ? local : 0;
}
