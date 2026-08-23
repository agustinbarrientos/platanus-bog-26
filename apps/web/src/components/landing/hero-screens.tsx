"use client";

import { bigCurves, miniCurves } from "@/lib/moirai/curves";
import { formatEsCO1 } from "@/lib/moirai/format";

import { Mascot } from "./mascot";
import { LeversIcon, MoiraiGlyph, PulseIcon, ShieldIcon } from "./icons";

/**
 * The three app screens that cycle inside the hero phone.
 *
 * Drawn at their native 246x468 and scaled up by the device frame, so every
 * size in here is in screen units, not page units.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

function TabBar({ active }: { active: "futuro" | "moirai" }) {
  const tab = (on: boolean) => ({
    color: on ? "#1E6EA9" : "#8D9BA8",
    fontSize: 7.5,
  });
  return (
    <div className="mo-screen__tabbar" style={{ height: 44 }}>
      <div className="mo-screen__tab" style={tab(active === "futuro")}>
        <PulseIcon width={15} height={15} />
        <span>Futuro</span>
      </div>
      <div className="mo-screen__tab" style={tab(active === "moirai")}>
        <MoiraiGlyph width={15} height={15} />
        <span>Moirai</span>
      </div>
      <div className="mo-screen__tab" style={tab(false)}>
        <LeversIcon width={15} height={15} />
        <span>Simular</span>
      </div>
    </div>
  );
}

function ScreenTitle({ children, extra }: { children: string; extra?: React.ReactNode }) {
  return (
    <>
      <div style={{ flex: "none", height: 34 }} />
      <div
        style={{
          flex: "none",
          height: 34,
          display: "flex",
          alignItems: "center",
          gap: 6,
          padding: "0 14px",
        }}
      >
        <span style={{ flex: 1, fontFamily: F, fontWeight: 500, fontSize: 14, color: "#232D35" }}>
          {children}
        </span>
        {extra}
      </div>
    </>
  );
}

/** A delta always carries its sign, so a range reads as a range of gains. */
const signed = (n: number) => (n > 0 ? "+" : "") + formatEsCO1(n);

const leverRow = {
  border: "1.5px solid #E9EFF3",
  borderRadius: 16,
  background: "#FFFFFF",
  padding: "9px 11px",
  display: "flex",
  alignItems: "center",
  gap: 8,
} as const;

/** Screen 1 — the headline number with the levers that move it. */
export function ScreenFuture() {
  const mini = miniCurves();
  const B = bigCurves();
  return (
    <>
      <ScreenTitle
        extra={
          <span
            style={{
              height: 26,
              display: "flex",
              alignItems: "center",
              gap: 4,
              padding: "0 9px",
              borderRadius: 13,
              background: "#DBEEFB",
              color: "#1E6EA9",
              fontWeight: 700,
              fontSize: 9.5,
            }}
          >
            <ShieldIcon width={10} height={10} />
            Respaldo
          </span>
        }
      >
        Tu futuro
      </ScreenTitle>

      <div
        className="mo-screen__body"
        style={{ gap: 7, padding: "6px 14px 0" }}
      >
        <div style={{ fontWeight: 700, fontSize: 8.5, letterSpacing: "0.05em", color: "#8D9BA8" }}>
          EDAD BIOLÓGICA EN 10 AÑOS
        </div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
          <span style={{ fontFamily: F, fontWeight: 600, fontSize: 44, lineHeight: 1, color: "#1E6EA9" }}>
            {formatEsCO1(B.p50)}
          </span>
          <span style={{ fontFamily: F, fontWeight: 500, fontSize: 16, color: "#4F5D69" }}>años</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
          <span style={{ width: 22, height: 3, borderRadius: 2, background: "rgba(82,169,226,.45)" }} />
          <span style={{ fontWeight: 600, fontSize: 11, color: "#4F5D69" }}>
            entre {formatEsCO1(B.p10)} y {formatEsCO1(B.p90)}
          </span>
        </div>

        <div
          style={{
            background: "#FFFFFF",
            border: "1px solid #E9EFF3",
            borderRadius: 18,
            padding: "10px 11px",
          }}
        >
          <svg viewBox="0 0 196 78" style={{ width: "100%", display: "block" }}>
            <path
              d={mini.band}
              fill="#52A9E2"
              style={{
                opacity: 0.2,
                transformBox: "fill-box",
                transformOrigin: "center",
                animation: "moMiniBandIn 8s cubic-bezier(.2,.7,.2,1) infinite",
              }}
            />
            {mini.lines.map((l, i) => (
              <path
                key={i}
                d={l.d}
                fill="none"
                stroke="#8AC7EF"
                strokeWidth={0.9}
                style={{
                  opacity: 0.32,
                  animation: "moMiniFan 8s ease-out infinite",
                  animationDelay: `${l.delay}s`,
                }}
              />
            ))}
            <path
              d={mini.med}
              fill="none"
              stroke="#1E6EA9"
              strokeWidth={2}
              strokeLinecap="round"
              style={{
                strokeDasharray: 520,
                animation: "moMiniDraw 8s cubic-bezier(.3,.7,.2,1) infinite",
              }}
            />
          </svg>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              paddingTop: 5,
              fontWeight: 600,
              fontSize: 8,
              color: "#8D9BA8",
            }}
          >
            <span>hoy</span>
            <span>5</span>
            <span>10 años</span>
          </div>
        </div>

        <div style={{ fontFamily: F, fontWeight: 500, fontSize: 12.5, color: "#232D35", paddingTop: 2 }}>
          Lo que puedes mover
        </div>
        {[
          {
            name: "Caminar 30 min al día",
            range: `entre ${signed(B.deltaLo)} y ${signed(B.deltaHi)} · ${B.pctMejoran}%`,
            gain: `+${formatEsCO1(B.delta)}`,
          },
          { name: "Dieta mediterránea", range: "entre -0,2 y +1,4 · 66%", gain: "+0,5" },
        ].map((l) => (
          <div key={l.name} style={leverRow}>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 1 }}>
              <div style={{ fontWeight: 700, fontSize: 11, color: "#232D35" }}>{l.name}</div>
              <div style={{ fontWeight: 600, fontSize: 8.5, color: "#8D9BA8" }}>{l.range}</div>
            </div>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
              <div style={{ fontFamily: F, fontWeight: 600, fontSize: 16, lineHeight: 1, color: "#1B8659" }}>
                {l.gain}
              </div>
              <div style={{ fontWeight: 700, fontSize: 7, color: "#8D9BA8" }}>años menos</div>
            </div>
          </div>
        ))}
      </div>
      <TabBar active="futuro" />
    </>
  );
}

/** Adherence slider: how long you keep it up changes the payoff. */
export function ScreenAdherence({ scale = 1 }: { scale?: number }) {
  const s = (n: number) => n * scale;
  return (
    <>
      <div style={{ flex: "none", height: s(34) }} />
      <div
        style={{
          flex: "none",
          height: s(34),
          display: "flex",
          alignItems: "center",
          padding: `0 ${s(14)}px`,
        }}
      >
        <span
          style={{ flex: 1, fontFamily: F, fontWeight: 500, fontSize: s(14), color: "#232D35" }}
        >
          Dejar de fumar
        </span>
      </div>
      <div
        className="mo-screen__body"
        style={{ gap: s(11), padding: `${s(8)}px ${s(16)}px 0`, alignItems: "center" }}
      >
        <Mascot size={s(92)} />
        <div
          style={{
            fontFamily: F,
            fontWeight: 500,
            fontSize: s(18),
            lineHeight: 1.2,
            textAlign: "center",
            color: "#232D35",
          }}
        >
          ¿Cuánto tiempo
          <br />
          lo sostienes?
        </div>

        <div style={{ width: "100%", position: "relative", paddingTop: 4 }}>
          <div
            style={{
              position: "absolute",
              left: s(24),
              right: s(24),
              top: 8,
              height: 5,
              borderRadius: 3,
              background: "#E9EFF3",
            }}
          />
          <div
            style={{
              position: "absolute",
              left: s(24),
              top: 8,
              height: 5,
              borderRadius: 3,
              background: "#2C8BCF",
              width: s(64),
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
                style={{
                  width: s(48),
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 8,
                }}
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
                <span
                  style={{
                    fontWeight: 700,
                    fontSize: 9,
                    color: stop.current ? "#1E6EA9" : "#8D9BA8",
                  }}
                >
                  {stop.label}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div
          style={{
            width: "100%",
            padding: `${s(16)}px ${s(14)}px`,
            borderRadius: 20,
            background: "#DBEEFB",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 3,
          }}
        >
          <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
            <span
              style={{ fontFamily: F, fontWeight: 600, fontSize: s(36), lineHeight: 1, color: "#1E6EA9" }}
            >
              +1,3
            </span>
            <span style={{ fontFamily: F, fontWeight: 500, fontSize: s(13), color: "#1E6EA9" }}>
              años menos
            </span>
          </div>
          <div style={{ fontWeight: 700, fontSize: s(11), color: "#1E6EA9" }}>
            te ayuda en 61% de tus futuros
          </div>
          <div
            style={{ fontSize: s(10.5), lineHeight: 1.4, color: "#4F5D69", textAlign: "center" }}
          >
            Aunque aflojes después, esto se te queda.
          </div>
        </div>
      </div>
    </>
  );
}

export function ScreenAdherenceHero() {
  return (
    <>
      <ScreenAdherence />
      <TabBar active="futuro" />
    </>
  );
}

/** The calibration receipt, shown inside the app rather than hidden away. */
export function ScreenCalibration({ note }: { note: string }) {
  const mini = miniCurves();
  return (
    <>
      <ScreenTitle>De dónde sale el número</ScreenTitle>
      <div className="mo-screen__body" style={{ gap: 9, padding: "6px 14px 0" }}>
        <div style={{ fontSize: 10.5, lineHeight: 1.4, color: "#4F5D69" }}>
          Tres capas, y el ancho que todavía no puedo cerrar.
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <div style={{ flex: 1, padding: 11, borderRadius: 16, background: "#DBEEFB" }}>
            <div style={{ fontFamily: F, fontWeight: 600, fontSize: 24, lineHeight: 1, color: "#1E6EA9" }}>
              9
            </div>
            <div style={{ fontWeight: 700, fontSize: 7.5, lineHeight: 1.3, color: "#1E6EA9" }}>
              BIOMARCADORES QUE LEO DE TU EXAMEN
            </div>
          </div>
          <div style={{ flex: 1, padding: 11, borderRadius: 16, background: "#D6F5E5" }}>
            <div style={{ fontFamily: F, fontWeight: 600, fontSize: 24, lineHeight: 1, color: "#1B8659" }}>
              10.000
            </div>
            <div style={{ fontWeight: 700, fontSize: 7.5, lineHeight: 1.3, color: "#1B8659" }}>
              FUTUROS POR CADA ESCENARIO
            </div>
          </div>
        </div>
        <div
          style={{
            background: "#FFFFFF",
            border: "1px solid #E9EFF3",
            borderRadius: 18,
            padding: 11,
            display: "flex",
            flexDirection: "column",
            gap: 6,
          }}
        >
          <svg viewBox="0 0 260 92" style={{ width: "100%", height: "auto", display: "block" }}>
            <path d={mini.bandWide} fill="#8AC7EF" opacity={0.4} />
            <path
              d={mini.medWide}
              fill="none"
              stroke="#1E6EA9"
              strokeWidth={3}
              strokeLinecap="round"
            />
          </svg>
          <div style={{ fontWeight: 700, fontSize: 8, color: "#8D9BA8" }}>
            EL ANCHO ES LO QUE TODAVÍA NO SÉ DE TI
          </div>
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
          {note}
        </div>
      </div>
    </>
  );
}

export function ScreenCalibrationHero() {
  return (
    <>
      <ScreenCalibration note="Aprendí de NHANES (CDC). Orienta, no diagnostica." />
      <TabBar active="futuro" />
    </>
  );
}
