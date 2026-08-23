"use client";

import { type ReactNode, useCallback, useRef } from "react";

import { miniCurves } from "@/lib/moirai/curves";
import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { ChevronLeftIcon, ChevronRightIcon, NudgeArrowIcon, TinyCheckIcon } from "./icons";
import { Mascot } from "./mascot";
import { reveal } from "./reveal";

/**
 * "De la foto de tu examen a un plan que puedes sostener" — four real screens
 * in device frames. On desktop they sit in a grid; below 820px the grid turns
 * into a snapping carousel with arrows.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

const CAPTIONS = [
  "Ocho preguntas, y el abanico se cierra",
  "Leo tu examen, y tú corriges",
  "¿Y si no lo sostienes?",
  "La prueba, dentro de la app",
];

const card = {
  display: "flex",
  alignItems: "center",
  gap: 8,
  padding: "6px 11px",
  borderRadius: 14,
  background: "#FFFFFF",
  border: "1px solid #E9EFF3",
} as const;

const badge = (bg: string, color: string) =>
  ({
    display: "inline-flex",
    height: 17,
    alignItems: "center",
    padding: "0 7px",
    borderRadius: 9,
    background: bg,
    color,
    fontWeight: 700,
    fontSize: 8.5,
  }) as const;

function Screen({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="mo-device">
      <div className="mo-device__screen">
        <div className="mo-device__notch" />
        <div style={{ flex: "none", height: 30 }} />
        <div
          style={{
            flex: "none",
            height: 30,
            display: "flex",
            alignItems: "center",
            padding: "0 13px",
            fontFamily: F,
            fontWeight: 500,
            fontSize: 13,
          }}
        >
          {title}
        </div>
        {children}
      </div>
    </div>
  );
}

function PrimaryAction({ children }: { children: string }) {
  return (
    <div style={{ flex: "none", padding: "0 13px 14px" }}>
      <div
        style={{
          height: 40,
          borderRadius: 20,
          background: "#2C8BCF",
          color: "#fff",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: F,
          fontWeight: 500,
          fontSize: 13,
        }}
      >
        {children}
      </div>
    </div>
  );
}

/** 1 — the eight basics, with the fan of futures closing as you answer. */
function OnboardingScreen() {
  const mini = miniCurves();
  const answered = (label: string, value: string) => (
    <div
      key={label}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "0 12px",
        minHeight: 38,
        borderRadius: 14,
        background: "#FFFFFF",
        border: "1px solid #E9EFF3",
      }}
    >
      <span
        style={{
          width: 16,
          height: 16,
          flex: "none",
          borderRadius: 8,
          background: "#2C8BCF",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <TinyCheckIcon width={10} height={10} />
      </span>
      <span style={{ flex: 1, fontWeight: 600, fontSize: 10.5, color: "#4F5D69", whiteSpace: "nowrap" }}>
        {label}
      </span>
      <span style={{ fontFamily: F, fontWeight: 600, fontSize: 13, color: "#1E6EA9" }}>{value}</span>
    </div>
  );

  return (
    <Screen title="Cuéntame lo básico">
      <div className="mo-screen__body" style={{ gap: 6, padding: "4px 13px 0" }}>
        <div style={{ fontSize: 11, color: "#4F5D69" }}>Voy en el dato 4 de 8.</div>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "10px 12px",
            borderRadius: 18,
            background: "#FFFFFF",
            border: "1px solid #E9EFF3",
          }}
        >
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 700, fontSize: 8, letterSpacing: "0.04em", color: "#8D9BA8" }}>
              TUS FUTUROS POSIBLES
            </div>
            <div style={{ fontSize: 9.5, lineHeight: 1.3, color: "#4F5D69" }}>
              Se van cerrando
              <br />
              con cada dato.
            </div>
          </div>
          <svg width={70} height={36} viewBox="0 0 108 54">
            <path d={mini.wide} fill="#8AC7EF" opacity={0.28} />
            <path d={mini.narrow} fill="#52A9E2" opacity={0.5} />
          </svg>
        </div>

        {answered("Edad", "42")}
        {answered("Estatura", "1,64 m")}

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 9,
            padding: "0 12px",
            minHeight: 38,
            borderRadius: 14,
            background: "#FFFFFF",
            border: "1.5px solid #52A9E2",
          }}
        >
          <span
            style={{ width: 16, height: 16, flex: "none", borderRadius: 8, border: "1.5px solid #52A9E2" }}
          />
          <span style={{ flex: 1, fontWeight: 700, fontSize: 10.5, whiteSpace: "nowrap" }}>
            Peso aproximado
          </span>
          <span style={{ fontSize: 9.5, color: "#8D9BA8", whiteSpace: "nowrap" }}>¿Cuánto pesas?</span>
        </div>

        {["¿Fumas?", "Presión arterial"].map((q) => (
          <div
            key={q}
            style={{ display: "flex", alignItems: "center", gap: 9, padding: "0 12px", minHeight: 34 }}
          >
            <span
              style={{ width: 16, height: 16, flex: "none", borderRadius: 8, border: "1.5px solid #D7E0E7" }}
            />
            <span style={{ fontSize: 10.5, color: "#8D9BA8", whiteSpace: "nowrap" }}>{q}</span>
          </div>
        ))}
      </div>
      <PrimaryAction>Siguiente</PrimaryAction>
    </Screen>
  );
}

/** 2 — what the OCR read, and how sure it is about each value. */
function ReadingScreen() {
  const rows = [
    { name: "Colesterol total", value: "212", label: "alta", bg: "#D6F5E5", ink: "#1B8659" },
    { name: "Glucosa en ayunas", value: "104", label: "media", bg: "#DBEEFB", ink: "#1E6EA9" },
    {
      name: "Hemoglobina glicosilada",
      value: "5,7",
      label: "baja",
      bg: "#FFEFC9",
      ink: "#A56D00",
      flagged: true,
    },
    { name: "Triglicéridos", value: "158", label: "alta", bg: "#D6F5E5", ink: "#1B8659" },
  ];

  return (
    <Screen title="Esto es lo que leí">
      <div className="mo-screen__body" style={{ gap: 4, padding: "2px 13px 0" }}>
        <div style={{ fontSize: 10, lineHeight: 1.35, color: "#4F5D69" }}>
          Con los datos de confianza baja mi estimación se vuelve{" "}
          <strong style={{ color: "#232D35" }}>más amplia</strong>, no más falsa.
        </div>
        {rows.map((r) => (
          <div
            key={r.name}
            style={{ ...card, border: r.flagged ? "1.5px solid #F2AE2E" : card.border }}
          >
            <div style={{ flex: 1 }}>
              <div
                style={{
                  fontWeight: 600,
                  fontSize: r.flagged ? 10 : 10.5,
                  color: "#4F5D69",
                  whiteSpace: r.flagged ? "nowrap" : undefined,
                }}
              >
                {r.name}
              </div>
              <span style={badge(r.bg, r.ink)}>{r.label}</span>
            </div>
            <span style={{ fontFamily: F, fontWeight: 600, fontSize: 15 }}>{r.value}</span>
          </div>
        ))}
        <div
          style={{
            padding: "8px 11px",
            borderRadius: 14,
            background: "#FFEFC9",
            fontWeight: 600,
            fontSize: 9.5,
            lineHeight: 1.35,
            color: "#A56D00",
          }}
        >
          La glicosilada la leí borrosa. Si la corriges, mi estimación se angosta bastante.
        </div>
      </div>
      <PrimaryAction>Simular mis futuros</PrimaryAction>
    </Screen>
  );
}

/** 3 — the adherence slider, and what you keep if you let go. */
function AdherenceScreen() {
  return (
    <Screen title="Dejar de fumar">
      <div
        className="mo-screen__body"
        style={{ gap: 12, padding: "6px 15px 0", alignItems: "center" }}
      >
        <Mascot size={86} />
        <div style={{ fontFamily: F, fontWeight: 500, fontSize: 17, lineHeight: 1.2, textAlign: "center" }}>
          ¿Cuánto tiempo
          <br />
          lo sostienes?
        </div>

        <div style={{ width: "100%", position: "relative", paddingTop: 4 }}>
          <div
            style={{
              position: "absolute",
              left: 22,
              right: 22,
              top: 8,
              height: 5,
              borderRadius: 3,
              background: "#E9EFF3",
            }}
          />
          <div
            style={{
              position: "absolute",
              left: 22,
              top: 8,
              height: 5,
              borderRadius: 3,
              background: "#2C8BCF",
              width: 52,
            }}
          />
          <div style={{ position: "relative", display: "flex", justifyContent: "space-between" }}>
            {[
              { label: "3 m", on: true, current: false },
              { label: "8 m", on: true, current: true },
              { label: "2 a", on: false, current: false },
              { label: "Siempre", on: false, current: false },
            ].map((stop) => (
              <div
                key={stop.label}
                style={{ width: 44, display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}
              >
                <span
                  style={{
                    width: 14,
                    height: 14,
                    borderRadius: 7,
                    border: "2.5px solid #FFFFFF",
                    background: stop.on ? "#2C8BCF" : "#D7E0E7",
                    boxShadow: stop.on ? "0 0 0 1.5px #2C8BCF" : undefined,
                  }}
                />
                <span style={{ fontWeight: 700, fontSize: 9, color: stop.current ? "#1E6EA9" : "#8D9BA8" }}>
                  {stop.label}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div
          style={{
            width: "100%",
            padding: "16px 14px",
            borderRadius: 20,
            background: "#DBEEFB",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 3,
          }}
        >
          <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
            <span style={{ fontFamily: F, fontWeight: 600, fontSize: 34, lineHeight: 1, color: "#1E6EA9" }}>
              +1,3
            </span>
            <span style={{ fontFamily: F, fontWeight: 500, fontSize: 12, color: "#1E6EA9" }}>
              años sanos
            </span>
          </div>
          <div style={{ fontWeight: 700, fontSize: 10.5, color: "#1E6EA9" }}>
            te ayuda en 61% de tus futuros
          </div>
          <div style={{ fontSize: 10, lineHeight: 1.4, color: "#4F5D69", textAlign: "center" }}>
            Aunque aflojes después, esto se te queda.
          </div>
        </div>
      </div>
      <PrimaryAction>Guardar como mi plan</PrimaryAction>
    </Screen>
  );
}

/** 4 — the calibration receipt, shipped inside the product. */
function CalibrationScreen() {
  const mini = miniCurves();
  return (
    <Screen title="Qué tan bien acierto">
      <div className="mo-screen__body" style={{ gap: 8, padding: "4px 13px 0" }}>
        <div style={{ fontSize: 10.5, lineHeight: 1.4, color: "#4F5D69" }}>
          Me probé contra 5.000 personas cuyo desenlace ya se conoce.
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <div style={{ flex: 1, padding: 10, borderRadius: 16, background: "#D6F5E5" }}>
            <div style={{ fontFamily: F, fontWeight: 600, fontSize: 22, lineHeight: 1, color: "#1B8659" }}>
              88%
            </div>
            <div style={{ fontWeight: 700, fontSize: 7.5, lineHeight: 1.3, color: "#1B8659" }}>
              DE LAS VECES MI RANGO CONTUVO EL RESULTADO
            </div>
          </div>
          <div style={{ flex: 1, padding: 10, borderRadius: 16, background: "#DBEEFB" }}>
            <div style={{ fontFamily: F, fontWeight: 600, fontSize: 22, lineHeight: 1, color: "#1E6EA9" }}>
              5.000
            </div>
            <div style={{ fontWeight: 700, fontSize: 7.5, lineHeight: 1.3, color: "#1E6EA9" }}>
              PERSONAS QUE NUNCA VI AL APRENDER
            </div>
          </div>
        </div>
        <div
          style={{
            background: "#FFFFFF",
            border: "1px solid #E9EFF3",
            borderRadius: 18,
            padding: 10,
            display: "flex",
            justifyContent: "center",
          }}
        >
          <svg width={150} height={150} viewBox="0 0 250 250">
            <rect x={20} y={20} width={210} height={210} rx={14} fill="#F4F8FA" />
            <line x1={20} y1={230} x2={230} y2={20} stroke="#8D9BA8" strokeWidth={3} strokeDasharray="7 7" />
            <path d={mini.cal} fill="none" stroke="#1E6EA9" strokeWidth={4} strokeLinecap="round" />
          </svg>
        </div>
        <div
          style={{
            padding: "9px 11px",
            borderRadius: 15,
            background: "#FFEFC9",
            fontWeight: 600,
            fontSize: 9.5,
            lineHeight: 1.4,
            color: "#A56D00",
          }}
        >
          Aprendí de NHANES (CDC). Sirve para orientarte; no sirve como diagnóstico.
        </div>
      </div>
      <div
        style={{
          flex: "none",
          height: 36,
          display: "flex",
          background: "#FFFFFF",
          borderTop: "1px solid #E9EFF3",
        }}
      >
        {["Futuro", "Moirai", "Simular"].map((t) => (
          <div
            key={t}
            style={{
              flex: 1,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontWeight: 700,
              fontSize: 8,
              color: t === "Moirai" ? "#1E6EA9" : "#8D9BA8",
            }}
          >
            {t}
          </div>
        ))}
      </div>
    </Screen>
  );
}

const SCREENS = [OnboardingScreen, ReadingScreen, AdherenceScreen, CalibrationScreen];

export function GallerySection() {
  const prog = useMoiraiScroll((s) => s.prog.gal);
  const grid = useRef<HTMLDivElement>(null);

  const step = useCallback((dir: -1 | 1) => {
    const g = grid.current;
    if (!g) return;
    const slide = g.querySelector<HTMLElement>(".mo-gal__item");
    g.scrollBy({ left: dir * (slide ? slide.getBoundingClientRect().width + 16 : g.clientWidth), behavior: "smooth" });
  }, []);

  return (
    <section id="gal" className="mo-gal">
      <div
        style={{
          maxWidth: 1140,
          margin: "0 auto",
          padding: "96px 28px",
          minHeight: "84vh",
          boxSizing: "border-box",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          gap: 30,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "flex-end",
            gap: 24,
            flexWrap: "wrap",
            transition: "opacity .55s ease, transform .75s cubic-bezier(.2,.75,.2,1)",
            ...reveal({ gal: prog }, "gal", 0, 30),
          }}
        >
          <div className="mo-col" style={{ minWidth: 340 }}>
            <h2 className="mo-h2" style={{ fontSize: 44, lineHeight: 1.08, maxWidth: 700 }}>
              De la foto de tu examen a un plan que puedes sostener
            </h2>
          </div>
        </div>

        <div className="mo-gal__wrap">
          <div className="mo-gal__hint">
            <span>Desliza para ver las cuatro pantallas</span>
            <NudgeArrowIcon
              width={15}
              height={15}
              style={{ animation: "moHintNudge 1.8s ease-in-out infinite" }}
            />
          </div>
          <button
            type="button"
            className="mo-gal__arrow mo-gal__arrow--prev"
            aria-label="Pantalla anterior"
            onClick={() => step(-1)}
          >
            <ChevronLeftIcon width={22} height={22} />
          </button>
          <button
            type="button"
            className="mo-gal__arrow mo-gal__arrow--next"
            aria-label="Pantalla siguiente"
            onClick={() => step(1)}
          >
            <ChevronRightIcon width={22} height={22} />
          </button>

          <div className="mo-gal__grid" ref={grid}>
            {[0, 1].map((pair) => (
              <div key={pair} className="mo-gal__inner">
                {SCREENS.slice(pair * 2, pair * 2 + 2).map((ScreenBody, j) => {
                  const i = pair * 2 + j;
                  return (
                    <div
                      key={i}
                      className="mo-gal__item"
                      style={reveal({ gal: prog }, "gal", 0.04 + i * 0.09, 56, true)}
                    >
                      <ScreenBody />
                      <div className="mo-gal__caption">{CAPTIONS[i]}</div>
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
