import { describe, expect, it } from "vitest";

import { formatHash, jump, keyAction, next, parseHash, prev, SLIDES } from "./deck-logic";

describe("SLIDES", () => {
  it("is the eight-slide order the pitch follows", () => {
    expect(SLIDES.map((s) => s.id)).toEqual([
      "intro",
      "problema",
      "examen",
      "solucion",
      "impacto",
      "demo",
      "gracias",
      "cierre",
    ]);
  });

  it("only the closing slide ignores clicks", () => {
    expect(SLIDES.filter((s) => s.clickLocked).map((s) => s.id)).toEqual(["cierre"]);
  });
});

describe("next", () => {
  it("advances a step before leaving a multi-step slide", () => {
    const solucion = SLIDES.findIndex((s) => s.id === "solucion");
    expect(next({ slide: solucion, step: 0 })).toEqual({ slide: solucion, step: 1 });
    expect(next({ slide: solucion, step: 1 })).toEqual({ slide: solucion + 1, step: 0 });
  });

  it("moves to the next slide from a single-step slide", () => {
    expect(next({ slide: 0, step: 0 })).toEqual({ slide: 1, step: 0 });
  });

  it("stays on the last slide", () => {
    const last = SLIDES.length - 1;
    expect(next({ slide: last, step: 0 })).toEqual({ slide: last, step: 0 });
  });
});

describe("prev", () => {
  it("goes to the previous slide's first step, never back through steps", () => {
    expect(prev({ slide: 3, step: 0 })).toEqual({ slide: 2, step: 0 });
    expect(prev({ slide: 2, step: 1 })).toEqual({ slide: 1, step: 0 });
  });

  it("stays on the first slide", () => {
    expect(prev({ slide: 0, step: 0 })).toEqual({ slide: 0, step: 0 });
  });
});

describe("jump", () => {
  it("clamps into range and resets the step", () => {
    expect(jump(-4)).toEqual({ slide: 0, step: 0 });
    expect(jump(99)).toEqual({ slide: SLIDES.length - 1, step: 0 });
    expect(jump(3.7)).toEqual({ slide: 3, step: 0 });
  });
});

describe("hash", () => {
  it("round-trips a slide index", () => {
    expect(formatHash(3)).toBe("#3");
    expect(parseHash("#3")).toBe(3);
  });

  it("falls back to the first slide for anything else", () => {
    expect(parseHash("")).toBe(0);
    expect(parseHash("#")).toBe(0);
    expect(parseHash("#intro")).toBe(0);
    expect(parseHash("#99")).toBe(0);
    expect(parseHash("#-1")).toBe(0);
  });
});

describe("keyAction", () => {
  const k = (
    key: string,
    mods: Partial<{ metaKey: boolean; ctrlKey: boolean; altKey: boolean }> = {},
  ) => keyAction({ key, metaKey: false, ctrlKey: false, altKey: false, ...mods });

  it("maps clicker and arrow keys", () => {
    expect(k("ArrowRight")).toBe("next");
    expect(k("ArrowDown")).toBe("next");
    expect(k(" ")).toBe("next");
    expect(k("PageDown")).toBe("next");
    expect(k("Enter")).toBe("next");
    expect(k("ArrowLeft")).toBe("prev");
    expect(k("ArrowUp")).toBe("prev");
    expect(k("PageUp")).toBe("prev");
    expect(k("Backspace")).toBe("prev");
    expect(k("Home")).toBe("first");
    expect(k("End")).toBe("last");
    expect(k("f")).toBe("fullscreen");
    expect(k("F")).toBe("fullscreen");
  });

  it("leaves browser shortcuts and other keys alone", () => {
    expect(k("ArrowRight", { metaKey: true })).toBeNull();
    expect(k("f", { ctrlKey: true })).toBeNull();
    expect(k(" ", { altKey: true })).toBeNull();
    expect(k("x")).toBeNull();
  });
});
