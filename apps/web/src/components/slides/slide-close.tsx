"use client";

import Image from "next/image";

import { MoiraiLogo } from "@/components/landing/brand";

import { COPY } from "./copy";
import { rise } from "./ui";

export function SlideClose() {
  return (
    <div className="sl-center" style={{ gap: 32 }}>
      <MoiraiLogo className="sl-close__logo" role="img" aria-label="Moirai" style={rise(0.1)} />
      <div className="sl-close__url" style={rise(0.35)}>
        {COPY.cierre.url}
      </div>
      <Image
        className="sl-close__qr"
        src="/moirai/qr.png"
        alt={COPY.cierre.qrAlt}
        width={460}
        height={460}
        unoptimized
        priority
        style={rise(0.55)}
      />
    </div>
  );
}
