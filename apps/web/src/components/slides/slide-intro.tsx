"use client";

import { MoiraiLogo } from "@/components/landing/brand";

import { COPY } from "./copy";
import { rise } from "./ui";

export function SlideIntro() {
  return (
    <div className="sl-center" style={{ gap: 64 }}>
      <MoiraiLogo className="sl-intro__logo" role="img" aria-label="Moirai" style={rise(0)} />
      <div className="sl-line" style={rise(0.6)}>
        {COPY.intro.line}
      </div>
    </div>
  );
}
