"use client";

import { COPY } from "./copy";
import { rise } from "./ui";
import { useClock } from "./use-clock";

const PLAY_MS = 4500;
/** The first signal lights at 1,4 s, the next ones 220 ms apart. */
const FIRST_SIGNAL_MS = 1400;
const SIGNAL_GAP_MS = 220;
const LINE2_S = 3.2;

/** Row index → order in which it lights up, or −1 for ordinary lines. */
const SIGNAL_ORDER = COPY.examen.rows.map((row, i, rows) =>
  row.signal ? rows.slice(0, i).filter((r) => r.signal).length : -1,
);

export function SlideExam() {
  const t = useClock(true, PLAY_MS) * PLAY_MS;
  return (
    <div className="sl-exam">
      <div className="sl-exam__card" style={rise(0)}>
        <div className="sl-exam__head">{COPY.examen.header}</div>
        {COPY.examen.rows.map((row, i) => {
          const k = SIGNAL_ORDER[i];
          const lit = k >= 0 && t >= FIRST_SIGNAL_MS + k * SIGNAL_GAP_MS;
          return (
            <div
              key={row.label}
              className={`sl-exam__row${lit ? " sl-exam__row--lit" : ""}`}
              style={rise(0.1 + i * 0.07)}
            >
              <span className="sl-exam__label">{row.label}</span>
              <span className="sl-exam__val sl-tnum">
                {row.value}
                <span className="sl-exam__unit">{row.unit}</span>
              </span>
            </div>
          );
        })}
      </div>
      <div className="sl-exam__text">
        <div className="sl-exam__line" style={rise(0.4)}>
          {COPY.examen.line1}
        </div>
        <div className="sl-exam__line sl-exam__line--2" style={rise(LINE2_S)}>
          {COPY.examen.line2}
        </div>
      </div>
    </div>
  );
}
