"use client";

import { type ComponentType, useCallback, useEffect, useRef, useState } from "react";

import {
  formatHash,
  jump,
  keyAction,
  next,
  parseHash,
  prev,
  SLIDES,
  type SlideId,
  type SlideProps,
  type View,
} from "./deck-logic";
import { SlideClose } from "./slide-close";
import { SlideDemo } from "./slide-demo";
import { SlideExam } from "./slide-exam";
import { SlideImpact } from "./slide-impact";
import { SlideIntro } from "./slide-intro";
import { SlideProblem } from "./slide-problem";
import { SlideSolution } from "./slide-solution";
import { SlideThanks } from "./slide-thanks";
import { Stage } from "./stage";
import { Glows } from "./ui";

const VIEWS: Record<SlideId, ComponentType<SlideProps>> = {
  intro: SlideIntro,
  problema: SlideProblem,
  examen: SlideExam,
  solucion: SlideSolution,
  impacto: SlideImpact,
  demo: SlideDemo,
  gracias: SlideThanks,
  cierre: SlideClose,
};

/** How long the outgoing slide stays while the incoming one fades over it. */
const FADE_MS = 500;

/** Two clicks closer than this are one nervous click, not two slides. */
const CLICK_GUARD_MS = 350;

/** Later slides' jellyfish should come from cache, not from the venue wifi. */
const PREFETCH = ["/moirai/moirai-mascot.json", "/moirai/moirai-plain.json", "/moirai/qr.png"];

interface Layers {
  cur: View;
  out: View | null;
}

function toggleFullscreen() {
  if (document.fullscreenElement) void document.exitFullscreen();
  else void document.documentElement.requestFullscreen();
}

export function Deck() {
  const [ui, setUi] = useState<Layers>(() => ({
    cur: jump(parseHash(window.location.hash)),
    out: null,
  }));
  const fadeTimer = useRef(0);
  const lastClick = useRef(0);

  const move = useCallback((fn: (v: View) => View) => {
    setUi((u) => {
      const n = fn(u.cur);
      if (n.slide === u.cur.slide) return n.step === u.cur.step ? u : { ...u, cur: n };
      return { cur: n, out: u.cur };
    });
    window.clearTimeout(fadeTimer.current);
    fadeTimer.current = window.setTimeout(
      () => setUi((u) => (u.out ? { ...u, out: null } : u)),
      FADE_MS,
    );
  }, []);

  // The URL is output, not input, after load: a reload lands on the same slide.
  useEffect(() => {
    window.history.replaceState(null, "", formatHash(ui.cur.slide));
  }, [ui.cur.slide]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.repeat) return;
      const action = keyAction(e);
      if (!action) return;
      e.preventDefault();
      if (action === "fullscreen") toggleFullscreen();
      else if (action === "next") move(next);
      else if (action === "prev") move(prev);
      else if (action === "first") move(() => jump(0));
      else move(() => jump(SLIDES.length - 1));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [move]);

  useEffect(() => {
    for (const path of PREFETCH) void fetch(path);
    void import("lottie-web/build/player/lottie_svg");
  }, []);

  const current = SLIDES[ui.cur.slide];
  const onClick = () => {
    if (current.clickLocked) return;
    const now = performance.now();
    if (now - lastClick.current < CLICK_GUARD_MS) return;
    lastClick.current = now;
    move(next);
  };

  return (
    <div
      className={`sl-viewport${current.id === "cierre" ? " sl-viewport--blue" : ""}`}
      onClick={onClick}
    >
      <Glows />
      <Stage>
        {ui.out && <Layer key={`s-${ui.out.slide}`} view={ui.out} out />}
        <Layer key={`s-${ui.cur.slide}`} view={ui.cur} />
      </Stage>
    </div>
  );
}

/** One mounted slide. Keyed by slide index so a slide keeps its state while it fades out. */
function Layer({ view, out = false }: { view: View; out?: boolean }) {
  const Slide = VIEWS[SLIDES[view.slide].id];
  return (
    <div className={`sl-slide ${out ? "sl-slide--out" : "sl-slide--in"}`}>
      <Slide step={view.step} />
    </div>
  );
}
