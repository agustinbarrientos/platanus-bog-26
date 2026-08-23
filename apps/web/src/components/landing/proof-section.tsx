"use client";

import { bigCurves } from "@/lib/moirai/curves";
import { formatEsCO1 } from "@/lib/moirai/format";
import { shallowEqual, useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { LockIcon, TickIcon } from "./icons";
import { clamp, reveal } from "./reveal";

/**
 * "No te pido que confíes a ciegas" — where every number comes from, and the
 * privacy promise, side by side. The range opens out from its median as the
 * biomarkers come in, the three layers deal themselves out underneath, and the
 * padlock snaps shut as the second card fills in.
 *
 * There is deliberately no calibration figure here. The engine has no coverage
 * study behind it yet, and `chat_rag/knowledge.py` says so in the product's own
 * words; the honest asset is the P10-P90 band, not a number nobody can check.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

const PRIVACY = [
  "La foto viaja cifrada, solo para extraer tus biomarcadores",
  "No se guarda, no entrena a nadie, y se borra al terminar",
  "Sin cuenta ni correo, y borras todo en dos toques",
];

const TAGS = ["PhenoAge · Levine 2018", "NHANES · CDC", "sin calibración formal todavía"];

const LAYERS: [string, string, string][] = [
  ["1", "Mido tu edad biológica de hoy", "PhenoAge, con los pesos publicados de Levine 2018"],
  ["2", "La proyecto a diez años", "Efectos de literatura epidemiológica, aproximados y citables"],
  ["3", "Repito diez mil veces con ruido", "De ahí sale el abanico P10–P90 que te muestro"],
];

/* ------------------------------------------------------- the range figure */

/** Plot geometry, in the same units the SVG is drawn in. */
const PLOT = { x0: 116, x1: 470, lo: 47, hi: 63 };
const sx = (v: number) => PLOT.x0 + ((v - PLOT.lo) / (PLOT.hi - PLOT.lo)) * (PLOT.x1 - PLOT.x0);

export function ProofSection() {
  const { respaldo, proof } = useMoiraiScroll(
    (s) => ({ respaldo: s.prog.respaldo, proof: s.prog.proof }),
    shallowEqual,
  );
  const B = bigCurves();

  const rp = clamp((proof - 0.04) / 0.62);
  const layerRows = LAYERS.map((_, i) => clamp((rp - 0.34 - i * 0.11) / 0.15));
  const rows = [clamp((rp - 0.28) / 0.14), clamp((rp - 0.28) / 0.14), clamp((rp - 0.46) / 0.14)];

  const xMed = sx(B.p50);
  /**
   * Two rows, one median. The top row is the real P10-P90 the engine returns
   * with all nine biomarkers in hand. The bottom row is the same estimate made
   * on a third of them — wider, and deliberately unlabelled: the engine does
   * widen when it has to impute, but no run behind this page measured by how
   * much, and inventing that number is the thing this whole section is against.
   */
  const BANDS = [
    { label: "con 9 de 9 datos", lo: B.p10, hi: B.p90, fill: "#2C8BCF", y: 30, numbers: true },
    {
      label: "con 3 de 9 datos",
      lo: B.p50 - (B.p50 - B.p10) * 2,
      hi: B.p50 + (B.p90 - B.p50) * 2,
      fill: "#8AC7EF",
      y: 72,
      numbers: false,
    },
  ];

  return (
    <section
      id="respaldo"
      style={{
        maxWidth: 1140,
        margin: "0 auto",
        padding: "96px 28px",
        minHeight: "84vh",
        boxSizing: "border-box",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 26,
      }}
    >
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 10,
          transition: "opacity .55s ease, transform .75s cubic-bezier(.2,.75,.2,1)",
          ...reveal({ respaldo }, "respaldo", 0.02, 40),
        }}
      >
        <div style={{ fontWeight: 700, fontSize: 11.5, letterSpacing: "0.06em", color: "#1E6EA9" }}>
          LA PARTE QUE NADIE MUESTRA
        </div>
        <h2 className="mo-h2" style={{ fontSize: 44, lineHeight: 1.08, maxWidth: 680 }}>
          No te pido que confíes a ciegas
        </h2>
        <p className="mo-lede" style={{ fontSize: 16.5, lineHeight: 1.55, maxWidth: 560 }}>
          Cualquiera puede darte un número. Yo te muestro el rango, y de dónde sale.
        </p>
      </div>

      <div className="mo-proof__grid">
        <div
          className="mo-proof__card mo-proof__card--soft"
          style={reveal({ respaldo }, "respaldo", 0.02, 40)}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <svg viewBox="0 0 480 150" style={{ width: "100%", height: "auto", display: "block" }}>
              <text
                x={xMed}
                y={14}
                fill="#1E6EA9"
                textAnchor="middle"
                style={{ fontFamily: F, fontWeight: 600, fontSize: 16 }}
                opacity={clamp((rp - 0.06) / 0.2).toFixed(2)}
              >
                {formatEsCO1(B.p50)}
              </text>
              <line
                x1={xMed}
                y1={20}
                x2={xMed}
                y2={116}
                stroke="#1E6EA9"
                strokeWidth={1.6}
                strokeDasharray="3 5"
                opacity={(clamp((rp - 0.06) / 0.2) * 0.7).toFixed(2)}
              />

              {BANDS.map((b, i) => {
                const g = clamp((rp - 0.12 - i * 0.16) / 0.3);
                const x = xMed - (xMed - sx(b.lo)) * g;
                const w = (sx(b.hi) - sx(b.lo)) * g;
                const num = clamp((rp - 0.44) / 0.2);
                return (
                  <g key={b.label}>
                    <text
                      x={100}
                      y={b.y + 15}
                      fill="#4F5D69"
                      textAnchor="end"
                      style={{ fontWeight: 700, fontSize: 12.5 }}
                      opacity={g.toFixed(2)}
                    >
                      {b.label}
                    </text>
                    <rect x={x.toFixed(1)} y={b.y} width={w.toFixed(1)} height={22} rx={11} fill={b.fill} />
                    {b.numbers && (
                      <>
                        <text
                          x={sx(b.lo) - 9}
                          y={b.y + 16}
                          fill="#8D9BA8"
                          textAnchor="end"
                          style={{ fontWeight: 700, fontSize: 12.5 }}
                          opacity={num.toFixed(2)}
                        >
                          {formatEsCO1(b.lo)}
                        </text>
                        <text
                          x={sx(b.hi) + 9}
                          y={b.y + 16}
                          fill="#8D9BA8"
                          style={{ fontWeight: 700, fontSize: 12.5 }}
                          opacity={num.toFixed(2)}
                        >
                          {formatEsCO1(b.hi)}
                        </text>
                      </>
                    )}
                  </g>
                );
              })}

              <line x1={PLOT.x0} y1={120} x2={PLOT.x1} y2={120} stroke="#C9DEEC" strokeWidth={1.6} />
              <text
                x={(PLOT.x0 + PLOT.x1) / 2}
                y={141}
                fill="#8D9BA8"
                textAnchor="middle"
                style={{ fontWeight: 700, fontSize: 12 }}
              >
                edad biológica en 10 años
              </text>
            </svg>

            <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
              <div style={{ fontFamily: F, fontWeight: 500, fontSize: 25, lineHeight: 1.2, color: "#232D35" }}>
                El rango es el mensaje
              </div>
              <div style={{ fontSize: 13.5, lineHeight: 1.5, color: "#4F5D69", textWrap: "pretty" }}>
                Con tus 9 biomarcadores se angosta a {formatEsCO1(B.spread)} años. Con menos, se
                ensancha, porque mi estimación se vuelve más amplia, no más falsa.
              </div>
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 12, padding: "2px 0" }}>
            {LAYERS.map(([n, title, src], i) => (
              <div
                key={n}
                style={{
                  display: "flex",
                  gap: 12,
                  alignItems: "flex-start",
                  opacity: layerRows[i],
                  transform: `translateY(${((1 - layerRows[i]) * 10).toFixed(1)}px)`,
                  transition: "opacity .5s ease, transform .6s cubic-bezier(.2,.75,.2,1)",
                }}
              >
                <span
                  style={{
                    flex: "none",
                    width: 26,
                    height: 26,
                    borderRadius: 13,
                    background: "#DBEEFB",
                    color: "#1E6EA9",
                    fontFamily: F,
                    fontWeight: 600,
                    fontSize: 14,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  {n}
                </span>
                <span style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                  <span style={{ fontWeight: 700, fontSize: 14, lineHeight: 1.35, color: "#232D35" }}>
                    {title}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: 12.5, lineHeight: 1.45, color: "#8D9BA8" }}>
                    {src}
                  </span>
                </span>
              </div>
            ))}
          </div>

          <div style={{ display: "flex", gap: 7, flexWrap: "wrap" }}>
            {TAGS.map((t) => (
              <span key={t} className="mo-proof__tag" style={{ opacity: clamp((rp - 0.62) / 0.2) }}>
                {t}
              </span>
            ))}
          </div>
        </div>

        <div
          className="mo-proof__card mo-proof__card--plain"
          style={reveal({ respaldo }, "respaldo", 0.14, 40)}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div
              style={{
                width: 64,
                height: 64,
                flex: "none",
                borderRadius: 22,
                background: "#DBEEFB",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#1E6EA9",
              }}
            >
              <LockIcon
                width={30}
                height={30}
                shackleStyle={{
                  transformOrigin: "12px 10.5px",
                  transform: rp > 0.35 ? "translateY(0px) scaleY(1)" : "translateY(5px) scaleY(0.5)",
                  transition: "transform .6s cubic-bezier(.3,1.4,.4,1)",
                }}
              />
            </div>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 3 }}>
              <div style={{ fontWeight: 700, fontSize: 11.5, letterSpacing: "0.06em", color: "#1E6EA9" }}>
                TUS DATOS NO SON EL NEGOCIO
              </div>
              <div style={{ fontFamily: F, fontWeight: 500, fontSize: 25, lineHeight: 1.2, color: "#232D35" }}>
                Tu examen se lee una vez, y no se guarda
              </div>
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 1 }}>
            {PRIVACY.map((text, i) => (
              <div
                key={text}
                className="mo-proof__row"
                style={{
                  borderBottom: i < PRIVACY.length - 1 ? "1px solid #E9EFF3" : undefined,
                  opacity: rows[i],
                  transform: `translateX(${((1 - rows[i]) * -12).toFixed(1)}px)`,
                }}
              >
                <span className="mo-proof__check">
                  <TickIcon width={14} height={14} stroke="#1B8659" />
                </span>
                <span style={{ flex: 1 }}>{text}</span>
              </div>
            ))}
          </div>

          <div className="mo-note" style={{ marginTop: "auto", opacity: clamp((rp - 0.6) / 0.2) }}>
            Esto orienta, no diagnostica. Llévale los resultados a tu médico.
          </div>
        </div>
      </div>
    </section>
  );
}
