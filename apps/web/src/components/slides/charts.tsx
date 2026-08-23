"use client";

import { bigCurves, gapY, HIST_HI, HIST_LO } from "@/lib/moirai/curves";
import { formatEsCO1 } from "@/lib/moirai/format";

import { clamp } from "./use-clock";

/**
 * The landing's three engine drawings on a dark stage. Same `bigCurves()`
 * data, same choreography over `lo` (0→1); only the colours and the type size
 * differ, so the deck and the landing can never disagree on a number.
 */

export interface ChartPalette {
  grid: string;
  axis: string;
  label: string;
  labelMuted: string;
  line: string;
  lineLive: string;
  band: string;
  median: string;
  bar: string;
  guide: string;
  baseBand: string;
  baseMedian: string;
  leverBand: string;
  leverMedian: string;
  chipBg: string;
}

export const DARK: ChartPalette = {
  grid: "rgba(255,255,255,.06)",
  axis: "rgba(255,255,255,.14)",
  label: "#B5C2CC",
  labelMuted: "#8D9BA8",
  line: "#8AC7EF",
  lineLive: "#DBEEFB",
  band: "#52A9E2",
  median: "#FFFFFF",
  bar: "#52A9E2",
  guide: "#B9DEF7",
  baseBand: "#8AC7EF",
  baseMedian: "#DBEEFB",
  leverBand: "#7ED9AC",
  leverMedian: "#7ED9AC",
  chipBg: "#151C22",
};

export interface ChartProps {
  /** Playback position 0→1, what the landing calls `localOf(stage)`. */
  lo: number;
  palette: ChartPalette;
}

const F = "var(--font-fredoka), system-ui, sans-serif";

/** Labels are 2.2× the landing's desktop size, the scale its phone layout uses: they have to read from the back of a room. */
const TS = 2.2;
const TOP = 48;
const BOTTOM = TOP + 360;
const AXIS_Y = BOTTOM + 1;
const TICK_Y = BOTTOM + 14 + 8 * TS;
const BOX = `0 0 1040 ${(TICK_Y + 8).toFixed(0)}`;
const PLOT = `translate(12,${TOP})`;
const GRID = [40, 120, 200, 280];
const XTICKS: [number, string][] = [
  [12, "hoy"],
  [215, "2"],
  [418, "4"],
  [622, "6"],
  [825, "8"],
  [1028, "10 años"],
];
const axisLabel = { fontWeight: 600, fontSize: 12 * TS } as const;
const svgStyle = { width: "100%", display: "block" } as const;

function XAxis({ c }: { c: ChartPalette }) {
  return (
    <>
      <path d={`M12 ${AXIS_Y} L1028 ${AXIS_Y}`} stroke={c.axis} strokeWidth={1.6} />
      {XTICKS.map(([x, label], i) => (
        <text
          key={label}
          x={x}
          y={TICK_Y}
          fill={c.label}
          textAnchor={i === 0 ? "start" : i === XTICKS.length - 1 ? "end" : "middle"}
          style={axisLabel}
        >
          {label}
        </text>
      ))}
    </>
  );
}

/** Ten thousand futures drawing themselves, the band, the median landing on its number. */
export function TrajectoriesChart({ lo, palette: c }: ChartProps) {
  const B = bigCurves();
  const st = (a: number, b: number) => clamp((lo - a) / (b - a));
  return (
    <svg viewBox={BOX} style={svgStyle}>
      <g transform={PLOT}>
        {GRID.map((y) => (
          <line key={y} x1={0} y1={y} x2={1016} y2={y} stroke={c.grid} strokeWidth={1.4} />
        ))}
        <path d={B.band} fill={c.band} opacity={(st(0.64, 0.76) * 0.2).toFixed(3)} />
        {B.lines.map((o, i) => {
          const lp = clamp((lo - (i / B.lines.length) * 0.8) / 0.2);
          const live = lp > 0.02 && lp < 0.999;
          const drawing = lp > 0 && lp < 0.999;
          return (
            <path
              key={i}
              d={o.d}
              fill="none"
              stroke={live ? c.lineLive : c.line}
              strokeWidth={live ? 2.8 : 1.5}
              strokeLinecap="round"
              strokeDasharray={drawing ? o.len.toFixed(0) : undefined}
              strokeDashoffset={drawing ? (o.len * (1 - lp)).toFixed(0) : undefined}
              opacity={lp > 0 ? (live ? 0.9 : 0.35) : 0}
            />
          );
        })}
        {B.lines.map((o, i) => {
          const lp = clamp((lo - (i / B.lines.length) * 0.8) / 0.2);
          return (
            <circle
              key={i}
              cx={o.end[0].toFixed(1)}
              cy={o.end[1].toFixed(1)}
              r={3.4}
              fill={c.line}
              opacity={lp > 0.999 ? 0.45 : 0}
            />
          );
        })}
        <path
          d={B.med}
          fill="none"
          stroke={c.median}
          strokeWidth={3.4}
          strokeLinecap="round"
          strokeDasharray={B.medLen.toFixed(0)}
          strokeDashoffset={(B.medLen * (1 - st(0.68, 0.88))).toFixed(0)}
        />
        <circle
          cx={B.markX}
          cy={B.markY}
          r={15}
          fill={c.median}
          opacity={(st(0.9, 0.99) * 0.22).toFixed(3)}
        />
        <circle cx={B.markX} cy={B.markY} r={7} fill={c.median} opacity={st(0.9, 0.99).toFixed(2)} />
        <text
          x={1000}
          y={+B.markY - 22}
          fill={c.median}
          textAnchor="end"
          style={{ fontFamily: F, fontWeight: 600, fontSize: 17 * TS }}
          opacity={st(0.9, 0.99).toFixed(2)}
        >
          {formatEsCO1(B.p50)}
        </text>
      </g>
      <text x={12} y={TOP - 6} fill={c.labelMuted} style={{ fontWeight: 700, fontSize: 11 * TS }}>
        edad biológica
      </text>
      <XAxis c={c} />
    </svg>
  );
}

/** Where the ten thousand land at year ten: bars grow, then median and P10/P90. */
export function HistogramChart({ lo, palette: c }: ChartProps) {
  const B = bigCurves();
  const st = (a: number, b: number) => clamp((lo - a) / (b - a));
  const marks = st(0.66, 0.86).toFixed(2);
  return (
    <svg viewBox={BOX} style={svgStyle}>
      <g transform={PLOT}>
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
              fill={c.bar}
              opacity={0.85}
            />
          );
        })}
        <line x1={B.x50} y1={0} x2={B.x50} y2={360} stroke={c.median} strokeWidth={3} opacity={marks} />
        {[B.x10, B.x90].map((x) => (
          <line
            key={x}
            x1={x}
            y1={40}
            x2={x}
            y2={360}
            stroke={c.guide}
            strokeWidth={1.6}
            strokeDasharray="4 6"
            opacity={marks}
          />
        ))}
        <text
          x={B.x50}
          y={-8}
          fill={c.median}
          textAnchor="middle"
          style={{ fontFamily: F, fontWeight: 600, fontSize: 15 * TS }}
          opacity={marks}
        >
          {formatEsCO1(B.p50)}
        </text>
        {([[B.x10, B.p10], [B.x90, B.p90]] as const).map(([x, v]) => (
          <text
            key={x}
            x={x}
            y={30}
            fill={c.label}
            textAnchor="middle"
            style={{ fontWeight: 700, fontSize: 11.5 * TS }}
            opacity={marks}
          >
            {formatEsCO1(v)}
          </text>
        ))}
      </g>
      <path d={`M12 ${AXIS_Y} L1028 ${AXIS_Y}`} stroke={c.axis} strokeWidth={1.6} />
      <text x={12} y={TICK_Y} fill={c.label} style={axisLabel}>
        {HIST_LO}
      </text>
      <text x={520} y={TICK_Y} fill={c.label} textAnchor="middle" style={axisLabel}>
        edad biológica en 10 años
      </text>
      <text x={1028} y={TICK_Y} fill={c.label} textAnchor="end" style={axisLabel}>
        {HIST_HI}
      </text>
    </svg>
  );
}

/** The same lives twice: without and with the lever. The gap at year ten is the answer. */
export function PairedChart({ lo, palette: c }: ChartProps) {
  const B = bigCurves();
  const st = (a: number, b: number) => clamp((lo - a) / (b - a));
  const baseY = gapY(B.base.p50, 360);
  const leverY = gapY(B.lever.p50, 360);
  const label = `+${formatEsCO1(B.delta)} años`;
  const fs = 19 * TS;
  const w = label.length * fs * 0.52;
  const y = (baseY + leverY) / 2;
  return (
    <svg viewBox={BOX} style={svgStyle}>
      <g transform={PLOT}>
        {GRID.map((g) => (
          <line key={g} x1={0} y1={g} x2={1016} y2={g} stroke={c.grid} strokeWidth={1.4} />
        ))}
        <path d={B.base.band} fill={c.baseBand} opacity={(st(0.06, 0.26) * 0.3).toFixed(3)} />
        <path d={B.lever.band} fill={c.leverBand} opacity={(st(0.42, 0.62) * 0.3).toFixed(3)} />
        {B.pairs.map((q, i) => {
          const a = clamp((lo - 0.08 - i * 0.045) / 0.16);
          const b = clamp((lo - 0.44 - i * 0.045) / 0.16);
          return (
            <g key={i}>
              <path
                d={q.base.d}
                fill="none"
                stroke={c.baseBand}
                strokeWidth={1.7}
                strokeLinecap="round"
                strokeDasharray={q.base.len.toFixed(0)}
                strokeDashoffset={(q.base.len * (1 - a)).toFixed(0)}
                opacity={0.7}
              />
              <path
                d={q.lever.d}
                fill="none"
                stroke={c.leverBand}
                strokeWidth={1.7}
                strokeLinecap="round"
                strokeDasharray={q.lever.len.toFixed(0)}
                strokeDashoffset={(q.lever.len * (1 - b)).toFixed(0)}
                opacity={0.8}
              />
            </g>
          );
        })}
        <path
          d={B.base.med}
          fill="none"
          stroke={c.baseMedian}
          strokeWidth={3.4}
          strokeLinecap="round"
          strokeDasharray={B.base.medLen.toFixed(0)}
          strokeDashoffset={(B.base.medLen * (1 - st(0.12, 0.36))).toFixed(0)}
        />
        <path
          d={B.lever.med}
          fill="none"
          stroke={c.leverMedian}
          strokeWidth={3.4}
          strokeLinecap="round"
          strokeDasharray={B.lever.medLen.toFixed(0)}
          strokeDashoffset={(B.lever.medLen * (1 - st(0.48, 0.72))).toFixed(0)}
        />
        <line
          x1={1004}
          y1={baseY}
          x2={1004}
          y2={leverY}
          stroke={c.leverMedian}
          strokeWidth={2.4}
          strokeLinecap="round"
          opacity={st(0.74, 0.9).toFixed(2)}
        />
        <g opacity={st(0.78, 0.94).toFixed(2)}>
          <rect
            x={(992 - w).toFixed(1)}
            y={(y - fs * 0.72).toFixed(1)}
            width={(w + 6).toFixed(1)}
            height={(fs * 1.44).toFixed(1)}
            rx={(fs * 0.72).toFixed(1)}
            fill={c.chipBg}
            opacity={0.92}
          />
          <text
            x={988}
            y={(y + fs * 0.36).toFixed(1)}
            fill={c.leverMedian}
            textAnchor="end"
            style={{ fontFamily: F, fontWeight: 600, fontSize: fs }}
          >
            {label}
          </text>
        </g>
      </g>
      <text x={12} y={TOP - 6} fill={c.labelMuted} style={{ fontWeight: 700, fontSize: 11 * TS }}>
        años que tu cuerpo se adelanta al calendario
      </text>
      <XAxis c={c} />
    </svg>
  );
}
