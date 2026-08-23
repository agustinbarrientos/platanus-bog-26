"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { bigCurves } from "@/lib/moirai/curves";
import { formatEsCO } from "@/lib/moirai/format";
import {
  pickStage,
  pinStyle,
  shallowEqual,
  type Stage,
  useMoiraiScroll,
} from "@/lib/moirai/scroll-store";

import { ChevronLeftIcon, ChevronRightIcon, NudgeArrowIcon } from "./icons";

/**
 * "Simulo tu vida diez mil veces" — the pinned engine scene.
 *
 * Scrolling through the section walks three views of the same simulation:
 * the trajectories being drawn one by one, the distribution they collapse
 * into, and the calibration curve that says how often the range was right.
 * Tapping a pill hands control to that stage for a few seconds.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";
const clamp = (x: number) => Math.max(0, Math.min(1, x));

const PILLS: { stage: Stage; label: string }[] = [
  { stage: 1, label: "Diez mil trayectorias" },
  { stage: 2, label: "Distribución" },
  { stage: 3, label: "Calibración" },
];

const CAPTIONS: Record<Stage, (local: number) => string> = {
  1: (l) =>
    l < 0.45
      ? "Cada trazo es una vida posible."
      : l < 0.8
        ? "Una enfermedad cambia todo lo que viene después."
        : "Mediana de 68 años sanos, con un rango de 61 a 75.",
  2: (l) =>
    l < 0.6
      ? "Las diez mil vidas, en un solo gráfico."
      : "Casi siempre caes entre los 61 y los 75 años.",
  3: () => "Me probé contra 5.000 personas que ya vivieron esto.",
};

const axisLabel = { fontWeight: 600, fontSize: 12 } as const;

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

  // The wide charts are 2.5:1, which is unreadable in a phone-width card, so
  // on narrow screens their drawing is stretched vertically. Only the graphics
  // group is scaled; the labels sit outside it and just move down.
  const K = useNarrow() ? 2.1 : 1;
  const EXTRA = 360 * (K - 1);
  const wideBox = `0 0 1040 ${(412 + EXTRA).toFixed(0)}`;
  const plot = `translate(12,22) scale(1,${K})`;

  // Manual picks take over from scroll; otherwise scroll picks the stage.
  const stage: Stage = man ? man.v : p < 0.42 ? 1 : p < 0.71 ? 2 : 3;

  // Every stage is laid out at once so the mobile carousel has no height jump;
  // each one reads the progress it would have had as the active stage.
  const localOf = (s: Stage): number => {
    if (man) return man.v === s ? manLocal : man.v > s ? 1 : 0;
    if (s === 1) return Math.max(0.05, clamp(p / 0.4));
    if (s === 2) return clamp((p - 0.42) / 0.26);
    return clamp((p - 0.71) / 0.26);
  };

  const simulated = Math.round(localOf(1) * 10000);

  const chart = (s: Stage) => {
    const lo = localOf(s);
    const st = (a: number, b: number) => clamp((lo - a) / (b - a));
    if (s === 1)
      return (
      <svg viewBox={wideBox} style={{ width: "100%", display: "block" }}>
        <g transform={plot}>
          {[90, 180, 270].map((y) => (
            <line key={y} x1={0} y1={y} x2={1016} y2={y} stroke="#F4F8FA" strokeWidth={1.4} />
          ))}
          <path d={B.band} fill="#52A9E2" opacity={(st(0.64, 0.76) * 0.18).toFixed(3)} />
          {B.lines.map((o, i) => {
            const lp = clamp((lo - (i / B.lines.length) * 0.8) / 0.2);
            const live = lp > 0.02 && lp < 0.999;
            return (
              <path
                key={i}
                d={o.d}
                fill="none"
                stroke={live ? "#2C8BCF" : "#8AC7EF"}
                strokeWidth={live ? 2.8 : 1.5}
                strokeLinecap="round"
                strokeDasharray={o.len.toFixed(0)}
                strokeDashoffset={(o.len * (1 - lp)).toFixed(0)}
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
          <line
            x1={B.markX}
            y1={0}
            x2={B.markX}
            y2={360}
            stroke="#1E6EA9"
            strokeWidth={1.6}
            strokeDasharray="4 6"
            opacity={st(0.9, 0.99).toFixed(2)}
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
        </g>
        <path d="M12 383 L1028 383" stroke="#E9EFF3" strokeWidth={1.6} />
        <text x={12} y={18} fill="#B5C2CC" style={{ fontWeight: 700, fontSize: 11 }}>
          sin enfermedad crónica
        </text>
        <text x={12} y={376 + EXTRA} fill="#B5C2CC" style={{ fontWeight: 700, fontSize: 11 }}>
          primer evento
        </text>
        <text x={12} y={404 + EXTRA} fill="#8D9BA8" style={axisLabel}>
          42
        </text>
        <text x={266} y={404 + EXTRA} fill="#8D9BA8" textAnchor="middle" style={axisLabel}>
          55
        </text>
        <text x={520} y={404 + EXTRA} fill="#8D9BA8" textAnchor="middle" style={axisLabel}>
          68
        </text>
        <text x={774} y={404 + EXTRA} fill="#8D9BA8" textAnchor="middle" style={axisLabel}>
          82
        </text>
        <text x={1028} y={404 + EXTRA} fill="#8D9BA8" textAnchor="end" style={axisLabel}>
          96 años
        </text>
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
          {[B.x05, B.x95].map((x) => (
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
            style={{ fontFamily: F, fontWeight: 600, fontSize: 15 }}
            opacity={st(0.66, 0.86).toFixed(2)}
          >
            68
          </text>
          <text
            x={B.x05}
            y={30 * K}
            transform={`scale(1,${1 / K})`}
            fill="#8D9BA8"
            textAnchor="middle"
            style={{ fontWeight: 700, fontSize: 11.5 }}
            opacity={st(0.66, 0.86).toFixed(2)}
          >
            61
          </text>
          <text
            x={B.x95}
            y={30 * K}
            transform={`scale(1,${1 / K})`}
            fill="#8D9BA8"
            textAnchor="middle"
            style={{ fontWeight: 700, fontSize: 11.5 }}
            opacity={st(0.66, 0.86).toFixed(2)}
          >
            75
          </text>
        </g>
        <path d="M12 383 L1028 383" stroke="#E9EFF3" strokeWidth={1.6} />
        <text x={12} y={404 + EXTRA} fill="#8D9BA8" style={axisLabel}>
          52
        </text>
        <text x={520} y={404 + EXTRA} fill="#8D9BA8" textAnchor="middle" style={axisLabel}>
          años sin enfermedad crónica
        </text>
        <text x={1028} y={404 + EXTRA} fill="#8D9BA8" textAnchor="end" style={axisLabel}>
          92 años
        </text>
      </svg>
      );
    return (
      <div
        style={{ display: "flex", gap: 34, alignItems: "center", flexWrap: "wrap", width: "100%" }}
      >
        <svg
          viewBox="326 10 388 400"
          preserveAspectRatio="xMidYMid meet"
          style={{
            flex: "1 1 300px",
            minWidth: 0,
            width: "100%",
            height: "auto",
            aspectRatio: "388/400",
            maxHeight: "var(--mo-cal-max, 52vh)",
            display: "block",
          }}
        >
          <g transform="translate(12,22)">
            <rect x={338} y={8} width={340} height={340} rx={18} fill="#F4F8FA" />
            {[93, 178, 263].map((y) => (
              <line key={y} x1={338} y1={y} x2={678} y2={y} stroke="#FFFFFF" strokeWidth={1.6} />
            ))}
            {[423, 508, 593].map((x) => (
              <line key={x} x1={x} y1={8} x2={x} y2={348} stroke="#FFFFFF" strokeWidth={1.6} />
            ))}
            <line
              x1={338}
              y1={348}
              x2={678}
              y2={8}
              stroke="#8D9BA8"
              strokeWidth={2}
              strokeDasharray="6 6"
              opacity={clamp(lo / 0.18).toFixed(2)}
            />
            <path
              d={B.cal.d}
              fill="none"
              stroke="#1E6EA9"
              strokeWidth={3.2}
              strokeLinecap="round"
              strokeDasharray={B.cal.len}
              strokeDashoffset={(B.cal.len * (1 - clamp((lo - 0.15) / 0.6))).toFixed(0)}
            />
            {B.cal.pts.map((q) => (
              <circle
                key={q.i}
                cx={q.cx}
                cy={q.cy}
                r={5.5}
                fill="#FFFFFF"
                stroke="#1E6EA9"
                strokeWidth={2.6}
                opacity={clamp((lo - 0.4 - q.i * 0.05) / 0.12).toFixed(2)}
              />
            ))}
            <text
              x={508}
              y={372}
              fill="#8D9BA8"
              textAnchor="middle"
              style={{ fontWeight: 700, fontSize: 12 }}
            >
              lo que predije
            </text>
            <text
              x={322}
              y={178}
              fill="#8D9BA8"
              textAnchor="middle"
              transform="rotate(-90 322 178)"
              style={{ fontWeight: 700, fontSize: 12 }}
            >
              lo que pasó
            </text>
          </g>
        </svg>
        <div
          className="mo-eng__proof"
          style={{
            flex: "0 0 336px",
            minWidth: 0,
            maxWidth: "100%",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            opacity: clamp((lo - 0.72) / 0.2).toFixed(2),
            transition: "opacity .5s ease",
          }}
        >
          <div style={{ fontFamily: F, fontWeight: 600, fontSize: 64, lineHeight: 1, color: "#1E6EA9" }}>
            88%
          </div>
          <div style={{ fontWeight: 700, fontSize: 15, lineHeight: 1.45, color: "#4F5D69", maxWidth: 340 }}>
            de las veces acerté dentro de mi rango
          </div>
        </div>
      </div>
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
    <section id="motor" className="mo-pin-sec" style={{ height: "520vh" }}>
      <div
        className="mo-pin-panel"
        style={{ ...pinStyle(pin), gap: 16, padding: "80px 28px 24px" }}
      >
        <div className="mo-pin-panel__inner" style={{ gap: 16 }}>
          <div style={{ display: "flex", alignItems: "flex-end", gap: 20, flexWrap: "wrap" }}>
            <div className="mo-col" style={{ gap: 7 }}>
              <h2 className="mo-h2" style={{ fontSize: 40, lineHeight: 1.1 }}>
                Simulo tu vida diez mil veces
              </h2>
              <p className="mo-lede" style={{ fontSize: 15.5, lineHeight: 1.55, maxWidth: 600 }}>
                Cada vida avanza año por año con tus números. Luego repito todo cambiando una sola
                cosa, y esa diferencia es tu respuesta.
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
                  <div className="mo-eng__cap">{CAPTIONS[s](localOf(s))}</div>
                </div>
              ))}
            </div>
          </div>

        </div>
      </div>
    </section>
  );
}
