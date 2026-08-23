"use client";

import { bigCurves } from "@/lib/moirai/curves";
import { formatEsCO1 } from "@/lib/moirai/format";

import { DARK, PairedChart } from "./charts";
import { COPY } from "./copy";
import { Chips } from "./ui";
import { easeOut, useClock } from "./use-clock";

const PLAY_MS = 6000;
const COUNT_MS = 900;
/** The crossfade hides the first half second, so the number climbs after it. */
const ENTRANCE_MS = 500;

/** −0,3 with a real minus sign, +4,3 with its plus. */
const signed = (n: number) => (n < 0 ? "−" : "+") + formatEsCO1(Math.abs(n));

export function SlideImpact() {
  const play = useClock(true, PLAY_MS);
  const B = bigCurves();
  const delta = B.delta * easeOut((play * PLAY_MS - ENTRANCE_MS) / COUNT_MS);
  return (
    <>
      <div className="sl-top">
        <div className="sl-top__text">
          <div className="sl-title sl-tnum">{COPY.impacto.title(signed(delta))}</div>
          <Chips items={COPY.impacto.chips(signed(B.deltaLo), signed(B.deltaHi), B.pctMejoran)} />
        </div>
      </div>
      <div className="sl-chart">
        <PairedChart lo={play} palette={DARK} />
      </div>
    </>
  );
}
