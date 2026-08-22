"use client";

import { miniCurves } from "@/lib/moirai/curves";
import { pinStyle, shallowEqual, useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { CheckIcon, LeversIcon, RangeIcon } from "./icons";
import { clamp } from "./reveal";

/**
 * "De ese papel que guardas en un cajón salen diez mil futuros".
 *
 * Three cards run in sequence off one pinned scroll: the photo straightens out
 * of a skewed blur, the biomarkers deblur in one by one, then the histogram and
 * median curve build under a scanning line.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

const BIOMARKERS = [
  { name: "Colesterol total", value: "212", dot: "#4CC48C" },
  { name: "Colesterol HDL", value: "48", dot: "#4CC48C" },
  { name: "Glucosa en ayunas", value: "104", dot: "#8AC7EF" },
  { name: "Hemoglobina glicosilada", value: "5,7", dot: "#F2AE2E" },
  { name: "Triglicéridos", value: "158", dot: "#4CC48C" },
];

const ASSURANCES = [
  { Icon: LeversIcon, text: "Cada cifra viene con la acción que la mueve" },
  { Icon: RangeIcon, text: "El rango se muestra tan grande como la cifra" },
  { Icon: CheckIcon, text: "Si no hay nada que hacer, te lo digo así" },
];

/** Fake scan lines on the photo of the lab report. */
const PAPER_LINES: [string, string][] = [
  ["70%", "#E9EFF3"],
  ["90%", "#E9EFF3"],
  ["52%", "#E9EFF3"],
  ["82%", "#FFEFC9"],
  ["64%", "#E9EFF3"],
  ["78%", "#E9EFF3"],
];

export function PipelineSection() {
  const { pr, pin2 } = useMoiraiScroll(
    (s) => ({ pr: s.prog.story, pin2: s.pin2 }),
    shallowEqual,
  );
  const mini = miniCurves();

  const flat = clamp(pr / 0.3);
  const skew = 1 - flat;
  const chart = clamp((pr - 0.48) / 0.42);
  const scanning = chart > 0.02 && chart < 0.99;

  return (
    <section id="rvA" className="mo-pin-sec" style={{ height: "340vh" }}>
      <div className="mo-pin-panel" style={{ ...pinStyle(pin2), padding: "70px 28px 18px" }}>
        <div className="mo-pin-panel__inner" style={{ gap: 10 }}>
          <div>
            <h2 className="mo-h2" style={{ fontSize: 44, lineHeight: 1.06, maxWidth: 700, marginBottom: 8 }}>
              De ese papel que guardas en un cajón salen diez mil futuros
            </h2>
            <p className="mo-lede" style={{ fontSize: 15, lineHeight: 1.5, maxWidth: 600 }}>
              Una foto de tu examen, todos sus biomarcadores, diez mil futuros simulados.
            </p>
          </div>

          <div id="pipe" className="mo-pipe">
            {/* 01 — the photo lands flat */}
            <div className="mo-pipe__card">
              <div className="mo-pipe__step">
                <span className="mo-mono" style={{ fontWeight: 600, fontSize: 11, color: "#8AC7EF" }}>
                  01
                </span>
                <span>La foto</span>
              </div>
              <div
                style={{
                  height: 196,
                  borderRadius: 20,
                  background: "#F4F8FA",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  overflow: "hidden",
                  perspective: "700px",
                  animation: "moFloatY 9s ease-in-out infinite",
                }}
              >
                <div
                  style={{
                    width: 212,
                    padding: 20,
                    borderRadius: 16,
                    background: "#FFFFFF",
                    boxShadow: "0 10px 26px rgba(44,110,140,.16)",
                    display: "flex",
                    flexDirection: "column",
                    gap: 10,
                    transformStyle: "preserve-3d",
                    opacity: clamp(pr / 0.12),
                    transform: `perspective(700px) rotateX(${(26 * skew).toFixed(1)}deg) rotateY(${(-22 * skew).toFixed(1)}deg) rotateZ(${(-14 * skew).toFixed(1)}deg) skewY(${(9 * skew).toFixed(1)}deg) scale(${(0.82 + 0.18 * flat).toFixed(3)})`,
                    filter: `blur(${(2.6 * skew).toFixed(2)}px)`,
                  }}
                >
                  {PAPER_LINES.map(([w, bg], i) => (
                    <div
                      key={i}
                      style={{
                        height: bg === "#FFEFC9" ? 12 : 8,
                        width: w,
                        borderRadius: bg === "#FFEFC9" ? 5 : 3,
                        background: bg,
                      }}
                    />
                  ))}
                </div>
              </div>
              <div className="mo-pipe__note">
                Basta una foto del examen, incluso torcida o con sombra.
              </div>
            </div>

            {/* 02 — the values sharpen one by one */}
            <div className="mo-pipe__card">
              <div className="mo-pipe__step">
                <span className="mo-mono" style={{ fontWeight: 600, fontSize: 11, color: "#8AC7EF" }}>
                  02
                </span>
                <span>Tus números, con su confianza</span>
              </div>
              <div
                style={{
                  height: 196,
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "center",
                  gap: 11,
                }}
              >
                {BIOMARKERS.map((b, i) => {
                  const e = clamp((pr - 0.22 - i * 0.055) / 0.16);
                  return (
                    <div
                      key={b.name}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 9,
                        opacity: e,
                        transform: `translateX(${((1 - e) * -16).toFixed(1)}px)`,
                        filter: `blur(${(3.4 * (1 - e)).toFixed(2)}px)`,
                      }}
                    >
                      <span style={{ width: 7, height: 7, borderRadius: 4, background: b.dot }} />
                      <span style={{ flex: 1, fontWeight: 600, fontSize: 14, color: "#4F5D69" }}>
                        {b.name}
                      </span>
                      <span style={{ fontFamily: F, fontWeight: 600, fontSize: 17, color: "#232D35" }}>
                        {b.value}
                      </span>
                    </div>
                  );
                })}
              </div>
              <div className="mo-pipe__note">
                El valor en ámbar quedó borroso: puedes corregirlo antes de simular.
              </div>
            </div>

            {/* 03 — the distribution builds */}
            <div className="mo-pipe__card">
              <div className="mo-pipe__step">
                <span className="mo-mono" style={{ fontWeight: 600, fontSize: 11, color: "#8AC7EF" }}>
                  03
                </span>
                <span>El análisis</span>
              </div>
              <div
                style={{
                  height: 196,
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "flex-end",
                  gap: 12,
                  overflow: "hidden",
                }}
              >
                <svg
                  viewBox="0 0 260 96"
                  preserveAspectRatio="none"
                  style={{ width: "100%", height: 130, display: "block" }}
                >
                  {Array.from({ length: 14 }, (_, i) => {
                    const be = clamp((chart - (i / 14) * 0.75) / 0.16);
                    const h = (18 + 62 * Math.pow(i / 13, 1.5)) * be;
                    return (
                      <rect
                        key={i}
                        x={(i * 18.6 + 2).toFixed(1)}
                        y={(96 - h).toFixed(1)}
                        width={14.6}
                        height={h.toFixed(1)}
                        rx={3}
                        fill="#8AC7EF"
                        opacity={(be * 0.5).toFixed(2)}
                      />
                    );
                  })}
                  <path
                    d={mini.bandWide}
                    fill="#52A9E2"
                    opacity={(clamp((chart - 0.55) / 0.4) * 0.18).toFixed(3)}
                  />
                  <path
                    d={mini.medWide}
                    fill="none"
                    stroke="#1E6EA9"
                    strokeWidth={3}
                    strokeLinecap="round"
                    strokeDasharray={420}
                    strokeDashoffset={(420 * (1 - clamp((chart - 0.45) / 0.5))).toFixed(0)}
                  />
                  <line
                    x1={(chart * 258).toFixed(1)}
                    y1={0}
                    x2={(chart * 258).toFixed(1)}
                    y2={96}
                    stroke="#2C8BCF"
                    strokeWidth={1.6}
                    opacity={scanning ? 0.85 : 0}
                  />
                  <circle
                    cx={(chart * 258).toFixed(1)}
                    cy={(14 + 66 * Math.pow(chart, 1.6)).toFixed(1)}
                    r={3.4}
                    fill="#2C8BCF"
                    opacity={scanning ? 0.85 : 0}
                  />
                </svg>
                <div style={{ display: "flex", alignItems: "baseline", gap: 7 }}>
                  <span
                    className="mo-tnum"
                    style={{ fontFamily: F, fontWeight: 600, fontSize: 40, lineHeight: 1, color: "#1E6EA9" }}
                  >
                    {Math.round(68 * clamp((chart - 0.5) / 0.45))}
                  </span>
                  <span style={{ fontFamily: F, fontWeight: 500, fontSize: 14, color: "#4F5D69" }}>
                    años sanos
                  </span>
                </div>
              </div>
              <div className="mo-pipe__note">
                Tu mediana, con su rango del 90%: entre 61 y 75 años.
              </div>
            </div>
          </div>

          <div className="mo-assure">
            {ASSURANCES.map(({ Icon, text }, i) => {
              const e = clamp((pr - (0.78 + i * 0.05)) / 0.09);
              return (
                <div
                  key={text}
                  className="mo-assure__row"
                  style={{ opacity: e, transform: `translateY(${((1 - e) * 20).toFixed(1)}px)` }}
                >
                  <span className="mo-assure__icon">
                    <Icon width={20} height={20} />
                  </span>
                  <span>{text}</span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
