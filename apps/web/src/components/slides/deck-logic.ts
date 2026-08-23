/** The deck's navigation rules. Pure: no React, no DOM, so it is unit-tested. */

export type SlideId =
  | "intro"
  | "problema"
  | "examen"
  | "solucion"
  | "impacto"
  | "demo"
  | "gracias"
  | "cierre";

export interface SlideDef {
  id: SlideId;
  /** Clicks inside the slide before it hands over to the next one. */
  steps: number;
  /** Clicks are ignored here so the slide cannot be skipped by accident. */
  clickLocked?: boolean;
}

export const SLIDES: readonly SlideDef[] = [
  { id: "intro", steps: 1 },
  { id: "problema", steps: 1 },
  { id: "examen", steps: 1 },
  { id: "solucion", steps: 2 },
  { id: "impacto", steps: 1 },
  { id: "demo", steps: 1 },
  { id: "gracias", steps: 1 },
  { id: "cierre", steps: 1, clickLocked: true },
];

export interface View {
  slide: number;
  step: number;
}

/** What every slide component receives: which click within the slide we are on, from 0. */
export interface SlideProps {
  step: number;
}

export const jump = (slide: number): View => ({
  slide: Math.max(0, Math.min(SLIDES.length - 1, Math.trunc(slide))),
  step: 0,
});

/** The next step of the current slide, else the next slide; the last slide holds. */
export function next(v: View): View {
  if (v.step < SLIDES[v.slide].steps - 1) return { slide: v.slide, step: v.step + 1 };
  if (v.slide >= SLIDES.length - 1) return v;
  return jump(v.slide + 1);
}

/** The previous slide from its first step. Steps are not retraced. */
export const prev = (v: View): View => jump(v.slide - 1);

/** "#3" → 3. Anything that is not a slide index → 0. */
export function parseHash(hash: string): number {
  const m = /^#(\d{1,2})$/.exec(hash.trim());
  if (!m) return 0;
  const n = Number(m[1]);
  return n < SLIDES.length ? n : 0;
}

export const formatHash = (slide: number): string => `#${slide}`;

export type Action = "next" | "prev" | "first" | "last" | "fullscreen";

const NEXT_KEYS = new Set(["ArrowRight", "ArrowDown", " ", "PageDown", "Enter"]);
const PREV_KEYS = new Set(["ArrowLeft", "ArrowUp", "PageUp", "Backspace"]);

/** Which deck action a key press means, or null when the browser should keep the key. */
export function keyAction(e: {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
}): Action | null {
  if (e.metaKey || e.ctrlKey || e.altKey) return null;
  if (NEXT_KEYS.has(e.key)) return "next";
  if (PREV_KEYS.has(e.key)) return "prev";
  if (e.key === "Home") return "first";
  if (e.key === "End") return "last";
  if (e.key === "f" || e.key === "F") return "fullscreen";
  return null;
}
