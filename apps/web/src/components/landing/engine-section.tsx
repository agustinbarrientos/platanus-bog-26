"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { bigCurves, gapY, HIST_HI, HIST_LO, type BigCurves } from "@/lib/moirai/curves";
import { formatEsCO, formatEsCO1 } from "@/lib/moirai/format";
import {
  pickStage,
  pinStyle,
  shallowEqual,
  type Stage,
  useMoiraiScroll,
} from "@/lib/moirai/scroll-store";

import { ChevronLeftIcon, ChevronRightIcon, NudgeArrowIcon } from "./icons";

/**
 * "Qué edad tendrá tu cuerpo en diez años" — the pinned engine scene.
 *
 * Scrolling through the section walks three views of the same simulation:
 * the biological-age trajectories drawn one by one, the distribution they
 * collapse into at the ten-year horizon, and the paired counterfactual —
 * the same futures re-run with one lever changed. Every number in the
 * captions is read off the curves, so the words cannot drift from the chart.
 * Tapping a pill hands control to that stage for a few seconds.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";
const clamp = (x: number) => Math.max(0, Math.min(1, x));

const PILLS: { stage: Stage; label: string }[] = [
  { stage: 1, label: "Tus diez mil futuros" },
  { stage: 2, label: "Dónde caes" },
  { stage: 3, label: "Qué cambia si cambias algo" },
];

const CAPTIONS: Record<Stage, (local: number, c: BigCurves) => string> = {
  1: (l, c) =>
    l < 0.45
      ? "Cada trazo es un futuro posible tuyo."
      : l < 0.8
        ? "En unos tu cuerpo envejece más rápido que en otros."
        : `A diez años, tu edad biológica mediana es ${formatEsCO1(c.p50)}.`,
  2: (l, c) =>
    l < 0.6
      ? "Los diez mil futuros, en un solo gráfico."
      : `Casi siempre caes entre ${formatEsCO1(c.p10)} y ${formatEsCO1(c.p90)}.`,
  3: (l, c) =>
    l < 0.55
      ? "Ahora repito esos mismos futuros, cambiando una sola cosa."
      : `Te ahorras ${formatEsCO1(c.delta)} años, y mejora en ${c.pctMejoran} de cada 100.`,
};

/**
 * Where each stage starts in the section's scroll, and how much of that scroll
 * its animation takes. The two never add up to the next stage's start, and the
 * leftover is the point: once a stage has finished drawing, scrolling further
 * does nothing for most of a viewport. Without that dwell the counter flicks
 * past 10.000 in the same frame the section hands over to the next stage, and
 * nobody ever sees the finished picture they just scrolled through.
 */
const WINDOWS: Record<Stage, [from: number, span: number]> = {
  1: [0, 0.29],
  2: [0.4, 0.21],
  3: [0.7, 0.21],
};

/**
 * Type scale for text drawn inside the chart. The wide viewBox is squeezed to
 * phone width, which shrinks every glyph in it by the same factor the layout
 * gains; without this the axis reads at about five pixels.
 */
const textScale = (narrow: boolean) => (narrow ? 2.2 : 1);

const axisLabel = (ts: number) => ({ fontWeight: 600, fontSize: 12 * ts }) as const;

/** Matches the breakpoint where the stages become a carousel. */
const NARROW = "(max-width: 820px)";

function useNarrow() {
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia(NARROW);
    const sync = () => setNarrow(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);
  return narrow;
}

export function EngineSection() {
  const { p, man, manLocal, pin } = useMoiraiScroll(
    (s) => ({ p: s.p, man: s.man, manLocal: s.manLocal, pin: s.pin }),
    shallowEqual,
  );
  const B = bigCurves();
  // Where each arm's median lands at the horizon, on the gap axis. The third
  // view plots distance from the calendar rather than absolute age, so this
  // difference gets the full height of the chart instead of a sliver of it.
  const baseY = gapY(B.base.p50, 360);
  const leverY = gapY(B.lever.p50, 360);

  // The wide charts are 2.5:1, which is unreadable in a phone-width card, so
  // on narrow screens their drawing is stretched vertically. Only the graphics
  // group is scaled; the labels sit outside it and just move down.
  const narrow = useNarrow();
  const K = narrow ? 2.1 : 1;
  const TS = textScale(narrow);
  // Everything below is derived from the stretch rather than hard-coded, so a
  // baseline stays on the baseline and a label above the plot keeps its
  // headroom when the type doubles. Phone screens get extra room at the top
  // for the median label, which is 2.2x bigger there.
  const TOP = narrow ? 56 : 22;
  const BOTTOM = TOP + 360 * K;
  const plot = `translate(12,${TOP}) scale(1,${K})`;
  const axisY = BOTTOM + 1;
  // The tick row clears the baseline by its own cap height, which grows with
  // the type scale, so the labels never crowd the bottom of the bars.
  const tickY = BOTTOM + 14 + 8 * TS;
  const wideBox = `0 0 1040 ${(tickY + 8).toFixed(0)}`;

  // Manual picks take over from scroll; otherwise scroll picks the stage.
  const stage: Stage = man ? man.v : p < WINDOWS[2][0] ? 1 : p < WINDOWS[3][0] ? 2 : 3;

  // Every stage is laid out at once so the mobile carousel has no height jump;
  // each one reads the progress it would have had as the active stage.
  const localOf = (s: Stage): number => {
    if (man) return man.v === s ? manLocal : man.v > s ? 1 : 0;
    const [from, span] = WINDOWS[s];
    const local = clamp((p - from) / span);
    return s === 1 ? Math.max(0.05, local) : local;
  };

  const simulated = Math.round(localOf(1) * 10000);

  /** Ticks along the shared ten-year x axis. */
  const XTICKS: [number, string][] = [
    [12, "hoy"],
    [215, "2"],
    [418, "4"],
    [622, "6"],
    [825, "8"],
    [1028, "10 años"],
  ];

  const xAxis = () => (
    <>
      <path d={`M12 ${axisY} L1028 ${axisY}`} stroke="#E9EFF3" strokeWidth={1.6} />
      {XTICKS.map(([x, label], i) => (
        <text
          key={label}
          x={x}
          y={tickY}
          fill="#8D9BA8"
          textAnchor={i === 0 ? "start" : i === XTICKS.length - 1 ? "end" : "middle"}
          style={axisLabel(TS)}
        >
          {label}
        </text>
      ))}
    </>
  );

  const chart = (s: Stage) => {
    const lo = localOf(s);
    const st = (a: number, b: number) => clamp((lo - a) / (b - a));

    if (s === 1)
      return (
        <svg viewBox={wideBox} style={{ width: "100%", display: "block" }}>
          <g transform={plot}>
            {[40, 120, 200, 280].map((y) => (
              <line key={y} x1={0} y1={y} x2={1016} y2={y} stroke="#F4F8FA" strokeWidth={1.4} />
            ))}
            <path d={B.band} fill="#52A9E2" opacity={(st(0.64, 0.76) * 0.18).toFixed(3)} />
            {B.lines.map((o, i) => {
              const lp = clamp((lo - (i / B.lines.length) * 0.8) / 0.2);
              const live = lp > 0.02 && lp < 0.999;
              // Measuring a dash pattern along a forty-segment spline is the
              // expensive part of this frame, and a finished line does not
              // need one, so drop the attributes once it is fully drawn.
              const drawing = lp > 0 && lp < 0.999;
              return (
                <path
                  key={i}
                  d={o.d}
                  fill="none"
                  stroke={live ? "#2C8BCF" : "#8AC7EF"}
                  strokeWidth={live ? 2.8 : 1.5}
                  strokeLinecap="round"
                  strokeDasharray={drawing ? o.len.toFixed(0) : undefined}
                  strokeDashoffset={drawing ? (o.len * (1 - lp)).toFixed(0) : undefined}
                  opacity={lp > 0 ? (live ? 0.8 : 0.3) : 0}
                />
              );
            })}
            {B.lines.map((o, i) => {
              const lp = clamp((lo - (i / B.lines.length) * 0.8) / 0.2);
              return (
                <ellipse
                  key={i}
                  cx={o.end[0].toFixed(1)}
                  cy={o.end[1].toFixed(1)}
                  rx={3.4}
                  ry={3.4 / K}
                  fill="#8AC7EF"
                  opacity={lp > 0.999 ? 0.4 : 0}
                />
              );
            })}
            <path
              d={B.med}
              fill="none"
              stroke="#1E6EA9"
              strokeWidth={3.4}
              strokeLinecap="round"
              strokeDasharray={B.medLen.toFixed(0)}
              strokeDashoffset={(B.medLen * (1 - st(0.68, 0.88))).toFixed(0)}
            />
            <ellipse
              cx={B.markX}
              cy={B.markY}
              rx={15}
              ry={15 / K}
              fill="#1E6EA9"
              opacity={(st(0.9, 0.99) * 0.22).toFixed(3)}
            />
            <ellipse
              cx={B.markX}
              cy={B.markY}
              rx={7}
              ry={7 / K}
              fill="#1E6EA9"
              opacity={st(0.9, 0.99).toFixed(2)}
            />
            <text
              x={1000}
              y={+B.markY * K - 22}
              transform={`scale(1,${1 / K})`}
              fill="#1E6EA9"
              textAnchor="end"
              style={{ fontFamily: F, fontWeight: 600, fontSize: 17 * TS }}
              opacity={st(0.9, 0.99).toFixed(2)}
            >
              {formatEsCO1(B.p50)}
            </text>
          </g>
          <text x={12} y={TOP - 4} fill="#B5C2CC" style={{ fontWeight: 700, fontSize: 11 * TS }}>
            edad biológica
          </text>
          {xAxis()}
        </svg>
      );

    if (s === 2)
      return (
        <svg viewBox={wideBox} style={{ width: "100%", display: "block" }}>
          <g transform={plot}>
            {B.bars.map((b, i) => {
              const grow = clamp((lo - (i / B.bars.length) * 0.5) / 0.18);
              return (
                <rect
                  key={i}
                  x={b.x}
                  y={(360 - b.h * grow).toFixed(1)}
                  width={b.w}
                  height={(b.h * grow).toFixed(1)}
                  rx={7}
                  fill="#8AC7EF"
                />
              );
            })}
            <line
              x1={B.x50}
              y1={0}
              x2={B.x50}
              y2={360}
              stroke="#1E6EA9"
              strokeWidth={3}
              opacity={st(0.66, 0.86).toFixed(2)}
            />
            {[B.x10, B.x90].map((x) => (
              <line
                key={x}
                x1={x}
                y1={40}
                x2={x}
                y2={360}
                stroke="#1E6EA9"
                strokeWidth={1.6}
                strokeDasharray="4 6"
                opacity={st(0.66, 0.86).toFixed(2)}
              />
            ))}
            <text
              x={B.x50}
              y={-4 * K}
              transform={`scale(1,${1 / K})`}
              fill="#1E6EA9"
              textAnchor="middle"
              style={{ fontFamily: F, fontWeight: 600, fontSize: 15 * TS }}
              opacity={st(0.66, 0.86).toFixed(2)}
            >
              {formatEsCO1(B.p50)}
            </text>
            {([[B.x10, B.p10], [B.x90, B.p90]] as const).map(([x, v]) => (
              <text
                key={x}
                x={x}
                y={30 * K}
                transform={`scale(1,${1 / K})`}
                fill="#8D9BA8"
                textAnchor="middle"
                style={{ fontWeight: 700, fontSize: 11.5 * TS }}
                opacity={st(0.66, 0.86).toFixed(2)}
              >
                {formatEsCO1(v)}
              </text>
            ))}
          </g>
          <path d={`M12 ${axisY} L1028 ${axisY}`} stroke="#E9EFF3" strokeWidth={1.6} />
          <text x={12} y={tickY} fill="#8D9BA8" style={axisLabel(TS)}>
            {HIST_LO}
          </text>
          <text x={520} y={tickY} fill="#8D9BA8" textAnchor="middle" style={axisLabel(TS)}>
            edad biológica en 10 años
          </text>
          <text x={1028} y={tickY} fill="#8D9BA8" textAnchor="end" style={axisLabel(TS)}>
            {HIST_HI}
          </text>
        </svg>
      );

    return (
      <svg viewBox={wideBox} style={{ width: "100%", display: "block" }}>
        <g transform={plot}>
          {[40, 120, 200, 280].map((y) => (
            <line key={y} x1={0} y1={y} x2={1016} y2={y} stroke="#F4F8FA" strokeWidth={1.4} />
          ))}
          <path d={B.base.band} fill="#8AC7EF" opacity={(st(0.06, 0.26) * 0.3).toFixed(3)} />
          <path d={B.lever.band} fill="#4CC48C" opacity={(st(0.42, 0.62) * 0.3).toFixed(3)} />

          {/* Each pair is one life run twice: the grey is what happens anyway. */}
          {B.pairs.map((q, i) => {
            const a = clamp((lo - 0.08 - i * 0.045) / 0.16);
            const b = clamp((lo - 0.44 - i * 0.045) / 0.16);
            return (
              <g key={i}>
                <path
                  d={q.base.d}
                  fill="none"
                  stroke="#8AC7EF"
                  strokeWidth={1.7}
                  strokeLinecap="round"
                  strokeDasharray={q.base.len.toFixed(0)}
                  strokeDashoffset={(q.base.len * (1 - a)).toFixed(0)}
                  opacity={0.65}
                />
                <path
                  d={q.lever.d}
                  fill="none"
                  stroke="#4CC48C"
                  strokeWidth={1.7}
                  strokeLinecap="round"
                  strokeDasharray={q.lever.len.toFixed(0)}
                  strokeDashoffset={(q.lever.len * (1 - b)).toFixed(0)}
                  opacity={0.75}
                />
              </g>
            );
          })}

          <path
            d={B.base.med}
            fill="none"
            stroke="#1E6EA9"
            strokeWidth={3.4}
            strokeLinecap="round"
            strokeDasharray={B.base.medLen.toFixed(0)}
            strokeDashoffset={(B.base.medLen * (1 - st(0.12, 0.36))).toFixed(0)}
          />
          <path
            d={B.lever.med}
            fill="none"
            stroke="#1B8659"
            strokeWidth={3.4}
            strokeLinecap="round"
            strokeDasharray={B.lever.medLen.toFixed(0)}
            strokeDashoffset={(B.lever.medLen * (1 - st(0.48, 0.72))).toFixed(0)}
          />

          {/* The gap between the two medians at the horizon is the answer. */}
          <line
            x1={1004}
            y1={baseY}
            x2={1004}
            y2={leverY}
            stroke="#1B8659"
            strokeWidth={2.4}
            strokeLinecap="round"
            opacity={st(0.74, 0.9).toFixed(2)}
          />
          {/* On a phone the plot is stretched vertically and the type with it,
              so this annotation can land on top of a median. Give it a chip. */}
          {(() => {
            const label = `+${formatEsCO1(B.delta)} años`;
            const fs = 19 * TS;
            const w = label.length * fs * 0.52;
            const y = ((baseY + leverY) / 2) * K;
            return (
              <g transform={`scale(1,${1 / K})`} opacity={st(0.78, 0.94).toFixed(2)}>
                <rect
                  x={(992 - w).toFixed(1)}
                  y={(y - fs * 0.72).toFixed(1)}
                  width={(w + 6).toFixed(1)}
                  height={(fs * 1.44).toFixed(1)}
                  rx={(fs * 0.72).toFixed(1)}
                  fill="#FFFFFF"
                  opacity={0.9}
                />
                <text
                  x={988}
                  y={(y + fs * 0.36).toFixed(1)}
                  fill="#1B8659"
                  textAnchor="end"
                  style={{ fontFamily: F, fontWeight: 600, fontSize: fs }}
                >
                  {label}
                </text>
              </g>
            );
          })()}
        </g>
        <text x={12} y={TOP - 4} fill="#B5C2CC" style={{ fontWeight: 700, fontSize: 11 * TS }}>
          años que tu cuerpo se adelanta al calendario
        </text>
        {xAxis()}
      </svg>
    );
  };


  const track = useRef<HTMLDivElement>(null);
  const step = useCallback((dir: -1 | 1) => {
    const t = track.current;
    if (!t) return;
    const slide = t.querySelector<HTMLElement>(".mo-eng__slide");
    t.scrollBy({
      left: dir * (slide ? slide.getBoundingClientRect().width + 16 : t.clientWidth),
      behavior: "smooth",
    });
  }, []);

  return (
    <section id="motor" className="mo-pin-sec" style={{ height: "640vh" }}>
      <div
        className="mo-pin-panel"
        style={{ ...pinStyle(pin), gap: 16, padding: "80px 28px 24px" }}
      >
        <div className="mo-pin-panel__inner" style={{ gap: 16 }}>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 20, flexWrap: "wrap" }}>
            <div className="mo-col" style={{ gap: 7 }}>
              <h2 className="mo-h2" style={{ fontSize: 40, lineHeight: 1.1 }}>
                Qué edad tendrá tu cuerpo en diez años
              </h2>
              <p className="mo-lede" style={{ fontSize: 15.5, lineHeight: 1.55, maxWidth: 600 }}>
                Simulo diez mil futuros tuyos. Luego repito los mismos cambiando una sola cosa, y
                esa diferencia es lo que ganas.
              </p>
            </div>
            <div className="mo-eng__counter">
              <div
                className="mo-tnum"
                style={{ fontFamily: F, fontWeight: 600, fontSize: 50, lineHeight: 1, color: "#1E6EA9" }}
              >
                {formatEsCO(simulated)}
              </div>
              <div
                style={{ fontWeight: 700, fontSize: 11.5, letterSpacing: "0.05em", color: "#8D9BA8" }}
              >
                DE 10.000 VIDAS SIMULADAS
              </div>
              <div
                style={{
                  width: 190,
                  height: 7,
                  borderRadius: 4,
                  background: "#E9EFF3",
                  marginTop: 9,
                  overflow: "hidden",
                }}
              >
                <div
                  style={{
                    height: 7,
                    borderRadius: 4,
                    background: "#2C8BCF",
                    boxShadow: "0 0 10px rgba(44,139,207,.5)",
                    width: `${(localOf(1) * 100).toFixed(1)}%`,
                  }}
                />
              </div>
            </div>
          </div>

          <div className="mo-stage-pills">
            {PILLS.map((pill) => (
              <button
                key={pill.stage}
                type="button"
                onClick={() => pickStage(pill.stage)}
                aria-pressed={stage === pill.stage}
                className={`mo-stage-pill${stage === pill.stage ? " mo-stage-pill--on" : ""}`}
              >
                <span className="mo-stage-pill__idx">0{pill.stage}</span>
                {pill.label}
              </button>
            ))}
          </div>

          <div className="mo-eng__wrap">
            <div className="mo-eng__hint">
              <span>Desliza para ver las tres vistas</span>
              <NudgeArrowIcon
                width={15}
                height={15}
                style={{ animation: "moHintNudge 1.8s ease-in-out infinite" }}
              />
            </div>
            <button
              type="button"
              className="mo-eng__arrow mo-eng__arrow--prev"
              aria-label="Vista anterior"
              onClick={() => step(-1)}
            >
              <ChevronLeftIcon width={22} height={22} />
            </button>
            <button
              type="button"
              className="mo-eng__arrow mo-eng__arrow--next"
              aria-label="Vista siguiente"
              onClick={() => step(1)}
            >
              <ChevronRightIcon width={22} height={22} />
            </button>

            <div className="mo-eng__track" ref={track}>
              {PILLS.map(({ stage: s }) => (
                <div
                  key={s}
                  className={`mo-card mo-eng__slide${stage === s ? " mo-eng__slide--on" : ""}`}
                >
                  <div className="mo-eng__figure">{chart(s)}</div>
                  <div className="mo-eng__cap">{CAPTIONS[s](localOf(s), B)}</div>
                </div>
              ))}
            </div>
          </div>

        </div>
      </div>
    </section>
  );
}
