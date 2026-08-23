"use client";

import Image from "next/image";

import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { ScreenAdherenceHero, ScreenCalibrationHero, ScreenFuture } from "./hero-screens";
import { AppleIcon, GooglePlayIcon, StarIcon } from "./icons";
import { Mascot } from "./mascot";

const SCREENS = [ScreenFuture, ScreenAdherenceHero, ScreenCalibrationHero];

export function Hero() {
  const scr = useMoiraiScroll((s) => s.scr);
  const android = useMoiraiScroll((s) => s.android);

  return (
    <div id="top" className="mo-hero">
      <div
        className="mo-hero__blob"
        style={{
          width: 660,
          height: 660,
          top: -230,
          left: -170,
          background:
            "radial-gradient(circle,rgba(138,199,239,.32),rgba(138,199,239,0) 68%)",
        }}
      />
      <div
        className="mo-hero__blob"
        style={{
          width: 520,
          height: 520,
          bottom: -170,
          right: -110,
          background: "radial-gradient(circle,rgba(76,196,140,.15),rgba(76,196,140,0) 66%)",
          animationDuration: "30s",
          animationDelay: "-12s",
        }}
      />

      <div className="mo-hero__row">
        <div className="mo-hero__col">
          <h1 className="mo-hero__title">
            Conoce tus años sanos, <span style={{ color: "#2C8BCF" }}>y cómo sumar más.</span>
          </h1>
          <p className="mo-hero__lede">
            Sube tu examen y contesta unas preguntas. Simulo tu vida diez mil veces, te digo qué
            enfermedades son probables y qué puedes hacer.
          </p>

          <div className="mo-hero__actions">
            <a className="mo-store" href="/downloads/moirai.apk" download>
              <GooglePlayIcon width={23} height={23} />
              <span style={{ display: "flex", flexDirection: "column" }}>
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
              <span style={{ display: "flex", flexDirection: "column" }}>
                <span className="mo-store__eyebrow">PRONTO EN</span>
                <span className="mo-store__name">App Store</span>
              </span>
            </div>
          </div>

          <div className="mo-testi">
            <div style={{ display: "flex", gap: 3 }}>
              {[0, 1, 2, 3, 4].map((i) => (
                <StarIcon
                  key={i}
                  width={24}
                  height={24}
                  style={{ animation: `moStarPop .45s ease-out ${(0.6 + i * 0.08).toFixed(2)}s both` }}
                />
              ))}
            </div>
            <div
              style={{
                fontStyle: "italic",
                fontSize: 16.5,
                lineHeight: 1.5,
                color: "#8D9BA8",
                maxWidth: 520,
              }}
            >
              &ldquo;Llevaba años guardando exámenes que nadie me explicaba&rdquo; · Camila R., 47
              años
            </div>
          </div>
        </div>

        <div className="mo-stage">
          <div className="mo-hand">
            <div className="mo-hand__scale">
              <div className="mo-hand__screen">
                {SCREENS.map((Screen, i) => (
                  <div
                    key={i}
                    className="mo-screen"
                    aria-hidden={scr !== i}
                    style={{
                      opacity: scr === i ? 1 : 0,
                      transform: scr === i ? "translateY(0) scale(1)" : "translateY(14px) scale(.97)",
                    }}
                  >
                    <Screen />
                  </div>
                ))}
              </div>
              <Image
                className="mo-hand__photo"
                src="/moirai/phone.png"
                alt=""
                width={1254}
                height={1254}
                priority
              />
            </div>
          </div>

          <div className="mo-pill-float" style={{ left: 34, top: 118 }}>
            <div className="mo-pill">
              <span className="mo-pill__dot" style={{ background: "#4CC48C" }} />
              <span className="mo-pill__num" style={{ color: "#1B8659" }}>
                +4,2
              </span>
              <span>años sanos</span>
            </div>
          </div>
          <div
            className="mo-pill-float"
            style={{ right: 2, bottom: 150, animationDuration: "8.5s", animationDelay: "-3s" }}
          >
            <div className="mo-pill">
              <span className="mo-pill__num" style={{ color: "#1E6EA9" }}>
                87%
              </span>
              <span>de tus futuros mejoran</span>
            </div>
          </div>
          <div
            className="mo-pill-float"
            style={{ left: 22, bottom: 56, animationDuration: "9.5s", animationDelay: "-5s" }}
          >
            <div className="mo-pill">
              <span className="mo-pill__dot" style={{ background: "#8AC7EF" }} />
              <span>todos tus biomarcadores</span>
            </div>
          </div>

          <div
            className="mo-mascot-desktop"
            style={{
              position: "absolute",
              left: -16,
              top: -26,
              width: 300,
              height: 168,
              zIndex: 9,
              animation: "moFloatY 9s ease-in-out infinite",
              animationDelay: "-1.4s",
            }}
          >
            <Mascot travel />
          </div>
          <div
            className="mo-mascot-mobile"
            style={{
              position: "absolute",
              left: 10,
              top: 2,
              zIndex: 9,
              animation: "moFloatY 9s ease-in-out infinite",
              animationDelay: "-1.4s",
            }}
          >
            <Mascot size={104} />
          </div>
        </div>
      </div>
    </div>
  );
}
