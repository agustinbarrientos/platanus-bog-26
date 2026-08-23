"use client";

import { pinStyle, shallowEqual, useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { ArrowRightIcon } from "./icons";
import { Mascot } from "./mascot";

/**
 * "Pregúntame lo que quieras" — a pinned conversation that types
 * itself out as you scroll. The whole exchange is one continuous character
 * budget, so bubbles appear in order and the last one lands at the bottom
 * of the section.
 */

const F = "var(--font-fredoka), system-ui, sans-serif";

const SCRIPT = [
  { from: "user", text: "No puedo con las dos: ¿camino o cuido la comida?" },
  {
    from: "moirai",
    text: "Caminar. En tus futuros suma +3,1 años sanos y bajar la sal suma +0,9, porque hoy tu presión pesa más que tu colesterol.",
  },
  { from: "user", text: "¿Y si solo lo sostengo tres meses?" },
  { from: "moirai", text: "Te quedan +0,6 años sanos. Es poco, pero no es cero: nunca es cero." },
] as const;

const TOTAL = SCRIPT.reduce((n, m) => n + m.text.length, 0);
/** Character index each bubble starts at within the running total. */
const OFFSETS = SCRIPT.map((_, i) =>
  SCRIPT.slice(0, i).reduce((n, m) => n + m.text.length, 0),
);

const PROMPTS = ["¿Por dónde empiezo?", "¿Cuánto pesa mi presión?", "¿Y si no lo sostengo?"];

export function ChatSection() {
  const { prog, pin3 } = useMoiraiScroll(
    (s) => ({ prog: s.prog.chat, pin3: s.pin3 }),
    shallowEqual,
  );

  // A gap of 6 characters between bubbles reads as a pause before replying.
  const budget = prog * TOTAL * 1.18;

  return (
    <section id="chat" className="mo-pin-sec" style={{ height: "300vh" }}>
      <div className="mo-pin-panel" style={{ ...pinStyle(pin3), padding: "74px 28px 22px" }}>
        <div
          className="mo-pin-panel__inner"
          style={{ flexDirection: "row", gap: 40, alignItems: "center", flexWrap: "wrap" }}
        >
          <div className="mo-col" style={{ minWidth: 340, gap: 12 }}>
            <h2 className="mo-h2" style={{ fontSize: 44, lineHeight: 1.06, maxWidth: 520 }}>
              Pregúntame lo que quieras
            </h2>
            <p className="mo-lede" style={{ fontSize: 16.5, lineHeight: 1.55, maxWidth: 470 }}>
              Respondo con tu simulación, no con consejos genéricos.
            </p>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, paddingTop: 6 }}>
              {PROMPTS.map((q) => (
                <span key={q} className="mo-chip">
                  {q}
                </span>
              ))}
            </div>
          </div>

          <div className="mo-chat__card">
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 11,
                paddingBottom: 12,
                borderBottom: "1px solid #E9EFF3",
              }}
            >
              <Mascot size={54} />
              <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
                <span style={{ fontFamily: F, fontWeight: 500, fontSize: 15, color: "#232D35" }}>
                  Moirai
                </span>
                <span style={{ fontWeight: 600, fontSize: 11.5, color: "#8D9BA8" }}>
                  sobre tus diez mil futuros
                </span>
              </div>
            </div>

            <div className="mo-chat__log">
              {SCRIPT.map((m, i) => {
                const shown = Math.max(
                  0,
                  Math.min(m.text.length, Math.round(budget - OFFSETS[i] - i * 6)),
                );
                const typing = shown > 0 && shown < m.text.length;
                const isUser = m.from === "user";
                return (
                  <div
                    key={i}
                    style={{
                      display: "flex",
                      justifyContent: isUser ? "flex-end" : "flex-start",
                      opacity: shown > 0 ? 1 : 0,
                    }}
                  >
                    <div
                      className="mo-chat__bubble"
                      style={{
                        borderRadius: isUser ? "20px 20px 6px 20px" : "20px 20px 20px 6px",
                        background: isUser ? "#DBEEFB" : "#F4F8FA",
                        color: isUser ? "#1E6EA9" : "#232D35",
                        fontWeight: isUser ? 600 : 400,
                        fontSize: isUser ? 14 : 14.5,
                      }}
                    >
                      {m.text.slice(0, shown)}
                      <span style={{ opacity: typing ? 0.6 : 0 }}>|</span>
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="mo-chat__input">
              <span style={{ flex: 1, fontSize: 14, color: "#B5C2CC" }}>Pregúntale</span>
              <span
                style={{
                  width: 34,
                  height: 34,
                  borderRadius: 17,
                  background: "#2C8BCF",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: "#fff",
                }}
              >
                <ArrowRightIcon width={17} height={17} />
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
