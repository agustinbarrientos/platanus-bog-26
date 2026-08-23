"use client";

import { shallowEqual, useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { LockIcon, TickIcon } from "./icons";
import { clamp, reveal } from "./reveal";

/**
 * "Si me equivoco, te muestro cuánto" — the calibration receipt and the
 * privacy promise, side by side. The ring counts up to 88%, 176 of 200 dots
 * light up behind it, and the padlock snaps shut as the second card fills in.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

const PRIVACY = [
  "La foto viaja cifrada, solo para extraer tus biomarcadores",
  "No se guarda, no entrena a nadie, y se borra al terminar",
  "Sin cuenta ni correo, y borras todo en dos toques",
];

const TAGS = ["NHANES · CDC", "seguimiento hasta 2019", "caso a caso, auditable"];

export function ProofSection() {
  const { respaldo, proof } = useMoiraiScroll(
    (s) => ({ respaldo: s.prog.respaldo, proof: s.prog.proof }),
    shallowEqual,
  );

  const rp = clamp((proof - 0.04) / 0.62);
  const lit = Math.round(rp * 176);
  const rows = [clamp((rp - 0.28) / 0.14), clamp((rp - 0.28) / 0.14), clamp((rp - 0.46) / 0.14)];

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
          alignItems: "flex-end",
          gap: 24,
          flexWrap: "wrap",
          transition: "opacity .55s ease, transform .75s cubic-bezier(.2,.75,.2,1)",
          ...reveal({ respaldo }, "respaldo", 0.02, 40),
        }}
      >
        <div className="mo-col" style={{ minWidth: 340 }}>
          <div
            style={{
              fontWeight: 700,
              fontSize: 11.5,
              letterSpacing: "0.06em",
              color: "#1E6EA9",
              paddingBottom: 10,
            }}
          >
            LA PARTE QUE NADIE MUESTRA
          </div>
          <h2 className="mo-h2" style={{ fontSize: 44, lineHeight: 1.08, maxWidth: 680 }}>
            Si me equivoco, te muestro cuánto
          </h2>
        </div>
        <p
          className="mo-lede"
          style={{ flex: "none", width: 330, fontSize: 15, lineHeight: 1.6 }}
        >
          Cualquiera puede darte un número. Yo te digo qué tan seguido acierto.
        </p>
      </div>

      <div className="mo-proof__grid">
        <div
          className="mo-proof__card mo-proof__card--soft"
          style={reveal({ respaldo }, "respaldo", 0.02, 40)}
        >
          <div style={{ display: "flex", alignItems: "flex-end", gap: 16 }}>
            <div style={{ position: "relative", width: 104, height: 104, flex: "none" }}>
              <svg width={104} height={104} viewBox="0 0 104 104" style={{ display: "block", transform: "rotate(-90deg)" }}>
                <circle cx={52} cy={52} r={45} fill="none" stroke="#DBEEFB" strokeWidth={10} />
                <circle
                  cx={52}
                  cy={52}
                  r={45}
                  fill="none"
                  stroke="#2C8BCF"
                  strokeWidth={10}
                  strokeLinecap="round"
                  strokeDasharray={283}
                  strokeDashoffset={(283 * (1 - rp * 0.88)).toFixed(1)}
                />
              </svg>
              <div
                className="mo-tnum"
                style={{
                  position: "absolute",
                  inset: 0,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontFamily: F,
                  fontWeight: 600,
                  fontSize: 27,
                  color: "#1E6EA9",
                }}
              >
                {Math.round(rp * 88)}%
              </div>
            </div>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4, paddingBottom: 6 }}>
              <div style={{ fontWeight: 700, fontSize: 14.5, lineHeight: 1.4, color: "#232D35" }}>
                de las veces acerté dentro de mi rango
              </div>
              <div style={{ fontWeight: 600, fontSize: 12.5, color: "#8D9BA8" }}>
                El objetivo es 90%: me faltan dos puntos.
              </div>
            </div>
          </div>

          <div style={{ display: "flex", flexWrap: "wrap", gap: 4, padding: "2px 0" }}>
            {Array.from({ length: 200 }, (_, i) => (
              <span
                key={i}
                style={{
                  width: 9,
                  height: 9,
                  borderRadius: 5,
                  background: i < lit ? "#2C8BCF" : "#D7E0E7",
                }}
              />
            ))}
          </div>

          <div style={{ fontSize: 13.5, lineHeight: 1.5, color: "#4F5D69", textWrap: "pretty" }}>
            Cada punto son 25 personas. Los azules cayeron dentro de mi rango.
          </div>

          <div style={{ display: "flex", gap: 7, flexWrap: "wrap" }}>
            {TAGS.map((t) => (
              <span key={t} className="mo-proof__tag" style={{ opacity: clamp((rp - 0.52) / 0.2) }}>
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
