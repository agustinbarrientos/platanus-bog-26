"use client";

import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { MoiraiIcon } from "./brand";
import { GooglePlayIcon } from "./icons";

/** Sticky install prompt, shown only where the app actually exists. */
export function AndroidBar() {
  const android = useMoiraiScroll((s) => s.android);

  return (
    <div className="mo-androidbar" style={{ display: android ? "flex" : "none" }}>
      <MoiraiIcon width={34} height={34} style={{ flex: "none" }} />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", lineHeight: 1.25 }}>
        <span
          style={{
            fontFamily: "var(--font-fredoka), system-ui, sans-serif",
            fontWeight: 500,
            fontSize: 15,
            color: "#232D35",
          }}
        >
          Moirai para Android
        </span>
        <span style={{ fontWeight: 600, fontSize: 11.5, color: "#8D9BA8" }}>
          Simula tu salud en minutos
        </span>
      </div>
      <a
        href="https://play.google.com/store"
        target="_blank"
        rel="noopener noreferrer"
        style={{
          flex: "none",
          height: 46,
          display: "flex",
          alignItems: "center",
          gap: 9,
          padding: "0 18px",
          borderRadius: 23,
          background: "#151C22",
          color: "#fff",
          fontFamily: "var(--font-fredoka), system-ui, sans-serif",
          fontWeight: 500,
          fontSize: 15,
        }}
      >
        <GooglePlayIcon width={19} height={19} style={{ flex: "none" }} />
        Descargar
      </a>
    </div>
  );
}
