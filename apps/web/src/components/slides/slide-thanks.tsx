"use client";

import { Mascot } from "@/components/landing/mascot";

import { COPY } from "./copy";
import { rise } from "./ui";

export function SlideThanks() {
  return (
    <div className="sl-center" style={{ gap: 24 }}>
      <Mascot size={380} />
      <div className="sl-big" style={rise(0.4)}>
        {COPY.gracias.word}
      </div>
    </div>
  );
}
