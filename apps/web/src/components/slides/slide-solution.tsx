"use client";

import { formatEsCO } from "@/lib/moirai/format";

import { DARK, HistogramChart, TrajectoriesChart } from "./charts";
import { COPY } from "./copy";
import type { SlideProps } from "./deck-logic";
import { Chips, rise } from "./ui";
import { useClock } from "./use-clock";

const DRAW_MS = 6000;
const HIST_MS = 3000;
const FUTURES = 10000;

export function SlideSolution({ step }: SlideProps) {
  const draw = useClock(true, DRAW_MS);
  const hist = useClock(step >= 1, HIST_MS);
  const simulated = Math.round(draw * FUTURES);
  return (
    <>
      <div className="sl-top">
        <div className="sl-top__text">
          <div className="sl-title" style={rise(0.1)}>
            {COPY.solucion.title}
          </div>
          <Chips items={COPY.solucion.chips} />
        </div>
        <div className="sl-counter" style={rise(0.3)}>
          <div className="sl-counter__num sl-tnum">{formatEsCO(simulated)}</div>
          <div className="sl-counter__label">{COPY.solucion.counterLabel}</div>
          <div className="sl-counter__bar">
            <div className="sl-counter__fill" style={{ width: `${(draw * 100).toFixed(1)}%` }} />
          </div>
        </div>
      </div>
      <div className="sl-chart">
        <div style={{ opacity: step >= 1 ? 0 : 1, transition: "opacity .5s ease" }}>
          <TrajectoriesChart lo={draw} palette={DARK} />
        </div>
        <div className="sl-chart__layer" style={{ opacity: step >= 1 ? 1 : 0 }}>
          <HistogramChart lo={hist} palette={DARK} />
        </div>
      </div>
    </>
  );
}
