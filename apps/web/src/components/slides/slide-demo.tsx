"use client";

import { Mascot } from "@/components/landing/mascot";

import { COPY } from "./copy";
import { rise } from "./ui";

export function SlideDemo() {
  return (
    <>
      <div className="sl-demo__mascot">
        <Mascot travel />
      </div>
      <div className="sl-line sl-demo__line" style={rise(3.2)}>
        {COPY.demo.line}
      </div>
    </>
  );
}
