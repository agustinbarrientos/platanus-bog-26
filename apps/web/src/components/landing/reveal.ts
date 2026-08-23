import type { CSSProperties } from "react";

import type { ProgKey } from "@/lib/moirai/scroll-store";

const clamp = (x: number) => Math.max(0, Math.min(1, x));

/**
 * The page's one reveal gesture: fade up, optionally with a slight scale.
 *
 * `delay` staggers siblings along the same section progress, so a row of cards
 * arrives one after another instead of all at once.
 */
export function reveal(
  prog: Partial<Record<ProgKey, number>>,
  key: ProgKey,
  delay = 0,
  dy = 26,
  scale = false,
): CSSProperties {
  const e = clamp(((prog[key] ?? 0) - delay) / 0.5);
  return {
    opacity: e,
    transform:
      `translateY(${((1 - e) * dy).toFixed(1)}px)` +
      (scale ? ` scale(${(0.94 + e * 0.06).toFixed(3)})` : ""),
  };
}

export { clamp };
