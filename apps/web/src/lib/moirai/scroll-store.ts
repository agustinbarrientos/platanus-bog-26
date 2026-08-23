"use client";

import { useCallback, useRef, useSyncExternalStore } from "react";

/**
 * One scroll driver for the whole landing page.
 *
 * Three sections are pinned (`#motor`, `#chat`, `#rvA`): they are tall, and the
 * panel inside them stays fixed while the scroll distance drives an animation.
 * Everything else gets a plain 0..1 reveal progress. Below 900px nothing is
 * pinned, so each section instead plays its animation once when it comes into
 * view. Components subscribe with a selector so a frame only re-renders the
 * sections whose numbers actually moved.
 */

export type PinMode = "pre" | "fixed" | "post";
export type Stage = 1 | 2 | 3;

export type ProgKey =
  | "stats"
  | "rvA"
  | "story"
  | "chat"
  | "gal"
  | "respaldo"
  | "proof"
  | "descargar"
  | "motor";

export interface MoiraiState {
  /** Eased motor progress; trails the raw scroll target. */
  p: number;
  prog: Record<ProgKey, number>;
  pin: PinMode;
  pin2: PinMode;
  pin3: PinMode;
  /** Which of the three hero screens is showing. */
  scr: number;
  /** Stage chosen by tapping a pill, which overrides scroll for a few seconds. */
  man: { v: Stage; t: number } | null;
  /** 0..1 playback position of that manual stage. */
  manLocal: number;
  android: boolean;
  nav: boolean;
  mobile: boolean;
}

const PROG_KEYS: ProgKey[] = [
  "stats",
  "rvA",
  "story",
  "chat",
  "gal",
  "respaldo",
  "proof",
  "descargar",
  "motor",
];

const zeroProg = () =>
  PROG_KEYS.reduce((o, k) => ((o[k] = 0), o), {} as Record<ProgKey, number>);

const INITIAL: MoiraiState = {
  p: 0,
  prog: zeroProg(),
  pin: "pre",
  pin2: "pre",
  pin3: "pre",
  scr: 0,
  man: null,
  manLocal: 0,
  android: false,
  nav: false,
  mobile: false,
};

const clamp = (x: number) => Math.max(0, Math.min(1, x));

let state: MoiraiState = INITIAL;
const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

function set(patch: Partial<MoiraiState>) {
  state = { ...state, ...patch };
  emit();
}

const subscribe = (fn: () => void) => {
  listeners.add(fn);
  return () => void listeners.delete(fn);
};

const getSnapshot = () => state;
const getServerSnapshot = () => INITIAL;

/** Read a slice of the driver state. Re-renders only when the slice changes. */
export function useMoiraiScroll<T>(
  selector: (s: MoiraiState) => T,
  isEqual: (a: T, b: T) => boolean = Object.is,
): T {
  const cache = useRef<{ value: T } | null>(null);
  const read = useCallback(
    (s: MoiraiState) => {
      const next = selector(s);
      if (!cache.current || !isEqual(cache.current.value, next)) cache.current = { value: next };
      return cache.current.value;
    },
    // Selectors are declared inline at call sites; they are pure and stable in
    // behaviour, so re-subscribing on every render would only add churn.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  return useSyncExternalStore(
    subscribe,
    () => read(getSnapshot()),
    () => read(getServerSnapshot()),
  );
}

export function shallowEqual<T extends Record<string, unknown>>(a: T, b: T): boolean {
  const ka = Object.keys(a);
  if (ka.length !== Object.keys(b).length) return false;
  return ka.every((k) => Object.is(a[k], b[k]));
}

export const toggleNav = () => set({ nav: !state.nav });
export const closeNav = () => set({ nav: false });

/* ---------------------------------------------------------------- actions */

let manualRaf = 0;

/** Tapping a stage pill takes over from scroll and replays that stage. */
export function pickStage(v: Stage) {
  cancelAnimationFrame(manualRaf);
  const t0 = performance.now();
  set({ man: { v, t: target }, manLocal: 0 });
  const step = () => {
    const elapsed = performance.now() - t0;
    set({ manLocal: clamp(elapsed / 4200) });
    if (elapsed < 4500) manualRaf = requestAnimationFrame(step);
  };
  manualRaf = requestAnimationFrame(step);
}

/* ----------------------------------------------------------------- driver */

let target = 0;
let eased = 0;
let easing = false;
let signature = "";
let started = 0;

const el = (id: string) => document.getElementById(id);

/** Pinned-section progress plus which of the three pin phases it is in. */
function pinned(id: string): { prog: number; mode: PinMode } {
  const node = el(id);
  if (!node) return { prog: 0, mode: "pre" };
  const rect = node.getBoundingClientRect();
  const span = node.offsetHeight - window.innerHeight;
  const gone = -rect.top;
  return {
    prog: clamp(gone / (span > 0 ? span : 1)),
    mode: gone <= 0 ? "pre" : gone >= span ? "post" : "fixed",
  };
}

/** Scroll positions worth landing on when the user presses the arrow keys. */
function checkpoints(): number[] {
  const out: number[] = [];
  const motor = el("motor");
  if (motor) {
    const span = motor.offsetHeight - window.innerHeight;
    out.push(
      motor.offsetTop + Math.round(span * 0.415),
      motor.offsetTop + Math.round(span * 0.705),
      motor.offsetTop + Math.round(span * 0.999),
    );
  }
  for (const id of ["chat", "rvA"]) {
    const node = el(id);
    if (node) out.push(node.offsetTop + Math.round((node.offsetHeight - window.innerHeight) * 0.999));
  }
  for (const id of ["gal", "respaldo", "descargar"]) {
    const node = el(id);
    if (node) out.push(node.offsetTop - 40);
  }
  return out.sort((a, b) => a - b);
}

export function startDriver(): () => void {
  if (started++) return () => void started--;

  const android =
    /android/i.test(navigator.userAgent) ||
    (navigator as { userAgentData?: { platform?: string } }).userAgentData?.platform === "Android";
  if (android) document.body.style.paddingBottom = "76px";
  set({ android, mobile: window.innerWidth <= 900 });

  /* -- desktop: everything is a function of where the page is scrolled to -- */

  const measureDesktop = () => {
    const vh = window.innerHeight;
    const prog = zeroProg();

    const motor = pinned("motor");
    target = motor.prog;
    prog.motor = motor.prog;

    for (const id of ["stats", "rvA", "gal", "respaldo", "descargar"] as const) {
      const node = el(id);
      if (node) prog[id] = clamp((vh * 0.92 - node.getBoundingClientRect().top) / (vh * 0.62));
    }

    const chat = pinned("chat");
    prog.chat = chat.prog;
    const story = pinned("rvA");
    prog.story = story.prog;

    const respaldo = el("respaldo");
    if (respaldo) {
      prog.proof = clamp((vh * 0.45 - respaldo.getBoundingClientRect().top) / (vh * 0.72));
    }

    commit(prog, motor.mode, story.mode, chat.mode);
  };

  /* -- mobile: no pinning, so each section plays its animation once ------- */

  const played = new Set<ProgKey>();
  const playProg = zeroProg();

  /** Mobile drives the motor directly; there is no scroll distance to ease. */
  const setP = (v: number) => {
    target = v;
    eased = v;
    if (state.p !== v) set({ p: v });
  };
  const DURATIONS: [ProgKey, number][] = [
    ["stats", 700],
    ["rvA", 3200],
    ["story", 3200],
    ["chat", 2600],
    ["gal", 900],
    ["respaldo", 1400],
    ["proof", 2200],
    ["descargar", 900],
    ["motor", 12000],
  ];
  const SECTION_OF: Partial<Record<ProgKey, string>> = { story: "rvA", proof: "respaldo" };

  const playOnce = (key: ProgKey, dur: number) => {
    if (played.has(key)) return;
    played.add(key);
    const t0 = performance.now();
    const step = () => {
      const e = Math.min(1, (performance.now() - t0) / dur);
      playProg[key] = e;
      if (key === "motor") setP(e);
      measureMobile();
      if (e < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  };

  const measureMobile = () => {
    const vh = window.innerHeight;
    for (const [key, dur] of DURATIONS) {
      const node = el(SECTION_OF[key] ?? key);
      if (!node) continue;
      const rect = node.getBoundingClientRect();
      if (rect.bottom <= vh * 0.1) {
        // Already scrolled past: show the finished state rather than replaying.
        played.add(key);
        playProg[key] = 1;
        if (key === "motor") setP(1);
      } else if (rect.top < vh * 0.8) {
        playOnce(key, dur);
      }
    }
    commit({ ...playProg }, "pre", "pre", "pre");
  };

  /* ----------------------------------------------------------------------- */

  function commit(prog: Record<ProgKey, number>, pin: PinMode, pin2: PinMode, pin3: PinMode) {
    const sig =
      PROG_KEYS.map((k) => prog[k].toFixed(3)).join(",") + "|" + pin + pin2 + pin3;
    if (sig !== signature) {
      signature = sig;
      set({ prog, pin, pin2, pin3 });
    }
    if (state.man && Math.abs(target - state.man.t) > 0.06) set({ man: null });
    if (!easing && Math.abs(target - eased) > 0.0004) {
      easing = true;
      requestAnimationFrame(frame);
    }
  }

  function frame() {
    const d = target - eased;
    eased += d * 0.14;
    if (Math.abs(d) < 0.0004) {
      eased = target;
      easing = false;
    }
    set({ p: eased });
    if (easing) requestAnimationFrame(frame);
  }

  const onScroll = () => {
    const mobile = window.innerWidth <= 900;
    if (mobile !== state.mobile) set({ mobile });
    if (mobile) measureMobile();
    else measureDesktop();
  };

  /* Arrow keys glide between section checkpoints instead of nudging pixels. */
  let glideRaf = 0;
  const glide = (to: number) => {
    cancelAnimationFrame(glideRaf);
    const from = window.pageYOffset;
    const dur = Math.max(1100, Math.min(6200, Math.abs(to - from) * 2.4));
    const t0 = performance.now();
    const ease = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
    const step = (t: number) => {
      const k = Math.min(1, (t - t0) / dur);
      window.scrollTo({ top: from + (to - from) * ease(k), behavior: "instant" });
      onScroll();
      if (k < 1) glideRaf = requestAnimationFrame(step);
    };
    glideRaf = requestAnimationFrame(step);
  };

  const onKey = (e: KeyboardEvent) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const down = e.key === "ArrowDown" || e.key === "PageDown";
    const up = e.key === "ArrowUp" || e.key === "PageUp";
    if (!down && !up) return;
    const cps = checkpoints();
    const y = window.pageYOffset;
    const next = down ? cps.find((c) => c > y + 40) : cps.reverse().find((c) => c < y - 40);
    if (next === undefined) return;
    e.preventDefault();
    glide(next);
  };

  const rotate = window.setInterval(() => set({ scr: (state.scr + 1) % 3 }), 8000);
  const poll = window.setInterval(onScroll, 120);

  window.addEventListener("scroll", onScroll, { passive: true });
  document.addEventListener("scroll", onScroll, { passive: true, capture: true });
  window.addEventListener("resize", onScroll);
  window.addEventListener("keydown", onKey);
  onScroll();

  return () => {
    started--;
    cancelAnimationFrame(glideRaf);
    cancelAnimationFrame(manualRaf);
    clearInterval(rotate);
    clearInterval(poll);
    window.removeEventListener("scroll", onScroll);
    document.removeEventListener("scroll", onScroll, { capture: true });
    window.removeEventListener("resize", onScroll);
    window.removeEventListener("keydown", onKey);
  };
}

/** `position` / `top` / `bottom` for a pinned panel in each phase. */
export function pinStyle(mode: PinMode) {
  if (mode === "fixed") return { position: "fixed" as const, top: 0, bottom: "auto" as const };
  if (mode === "post") return { position: "absolute" as const, top: "auto" as const, bottom: 0 };
  return { position: "absolute" as const, top: 0, bottom: "auto" as const };
}
