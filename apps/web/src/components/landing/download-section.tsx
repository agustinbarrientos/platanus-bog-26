"use client";

import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { AppleIcon, GooglePlayIcon } from "./icons";
import { Mascot } from "./mascot";
import { reveal } from "./reveal";

/** The closing call to action. */
export function DownloadSection() {
  const prog = useMoiraiScroll((s) => s.prog.descargar);
  const android = useMoiraiScroll((s) => s.android);

  return (
    <section id="descargar" className="mo-cta">
      <div
        style={{
          maxWidth: 1140,
          margin: "0 auto",
          padding: "96px 28px",
          minHeight: "80vh",
          boxSizing: "border-box",
          display: "flex",
          flexDirection: "column",
          gap: 30,
          alignItems: "center",
          justifyContent: "center",
          textAlign: "center",
          transition: "opacity .55s ease, transform .75s cubic-bezier(.2,.75,.2,1)",
          ...reveal({ descargar: prog }, "descargar", 0.05, 40, true),
        }}
      >
        <Mascot size={150} />
        <h2 className="mo-h2" style={{ fontSize: 46, lineHeight: 1.1, maxWidth: 680 }}>
          Tu examen. Diez mil futuros. Un plan.
        </h2>
        <p className="mo-lede" style={{ fontSize: 17, lineHeight: 1.6, maxWidth: 520 }}>
          Sin cuenta, sin correo.
        </p>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap", justifyContent: "center" }}>
          <a
            className="mo-store"
            href="/downloads/moirai.apk"
        download
            target="_blank"
            rel="noopener noreferrer"
          >
            <GooglePlayIcon width={23} height={23} />
            <span style={{ display: "flex", flexDirection: "column", alignItems: "flex-start" }}>
              <span className="mo-store__eyebrow">DISPONIBLE EN</span>
              <span className="mo-store__name">Google Play</span>
            </span>
          </a>
          <div
            className="mo-store mo-store--soon"
            aria-disabled="true"
            style={{ display: android ? "none" : "flex" }}
          >
            <AppleIcon width={26} height={31} />
            <span style={{ display: "flex", flexDirection: "column", alignItems: "flex-start" }}>
              <span className="mo-store__eyebrow">PRONTO EN</span>
              <span className="mo-store__name">App Store</span>
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}
