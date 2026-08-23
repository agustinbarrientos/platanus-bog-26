"use client";

import { COPY } from "./copy";
import { rise } from "./ui";
import { easeOut, useClock } from "./use-clock";

const COUNT_MS = 900;
const ENTRANCE_MS = 500;

export function SlideProblem() {
  const t = useClock(true, COUNT_MS, ENTRANCE_MS);
  const n = Math.round(COPY.problema.bigN * easeOut(t));
  return (
    <div className="sl-center" style={{ gap: 40 }}>
      <div className="sl-big sl-tnum">
        {n} {COPY.problema.bigRest}
      </div>
      <div className="sl-title" style={rise(0.5)}>
        {COPY.problema.rest}
      </div>
      <div className="sl-source" style={rise(0.8)}>
        {COPY.problema.source}
      </div>
    </div>
  );
}
