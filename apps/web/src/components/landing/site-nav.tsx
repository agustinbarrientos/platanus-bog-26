"use client";

import { closeNav, toggleNav, useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { MoiraiLogo } from "./brand";
import { BurgerIcon } from "./icons";

const APK = "/downloads/moirai.apk";

const LINKS = [
  { href: "#motor", label: "Cómo funciona" },
  { href: "#chat", label: "Pregúntale a Moirai" },
  { href: "#respaldo", label: "Respaldo" },
];

export function SiteNav() {
  const open = useMoiraiScroll((s) => s.nav);

  return (
    <div className="mo-nav">
      <div className="mo-nav__inner">
        <a href="#top" style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <MoiraiLogo aria-label="Moirai" style={{ height: 30, width: "auto", display: "block" }} />
        </a>
        <div style={{ flex: 1 }} />
        <a className="mo-nav__link" href="#motor">
          Cómo funciona
        </a>
        <a className="mo-nav__link" href="#respaldo">
          Respaldo
        </a>
        <button
          type="button"
          className="mo-nav__burger"
          aria-label="Abrir menú"
          aria-expanded={open}
          onClick={toggleNav}
        >
          <BurgerIcon width={20} height={20} />
        </button>
        <a className="mo-nav__link mo-nav__cta" href={APK} download>
          Descargar
        </a>
      </div>

      <div className="mo-nav__sheet" style={{ display: open ? "flex" : "none" }}>
        {LINKS.map((l) => (
          <a key={l.href} href={l.href} onClick={closeNav}>
            {l.label}
          </a>
        ))}
        <a href={APK} download onClick={closeNav}>
          Descargar
        </a>
      </div>
    </div>
  );
}
