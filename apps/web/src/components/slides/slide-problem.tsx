"use client";

import { COPY } from "./copy";
import { rise } from "./ui";

export function SlideProblem() {
  return (
    <div className="sl-center" style={{ gap: 40 }}>
      <div className="sl-big" style={rise(0.35)}>
        {COPY.problema.bigN} {COPY.problema.bigRest}
      </div>
      <div className="sl-title" style={rise(0.6)}>
        {COPY.problema.rest}
      </div>
      <div className="sl-source" style={rise(0.9)}>
        {COPY.problema.source}
      </div>
    </div>
  );
}
