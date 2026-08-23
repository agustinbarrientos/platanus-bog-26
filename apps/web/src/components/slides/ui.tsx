import type { CSSProperties } from "react";

/** The deck's one entrance: fade up, staggered by `delaySec`. */
export const rise = (delaySec: number): CSSProperties => ({
  animation: "slRise .8s cubic-bezier(.2,.75,.2,1) both",
  animationDelay: `${delaySec}s`,
});

/** The two short phrases under a title, the layout the organizers showed as the good example. */
export function Chips({ items, delay = 0.6 }: { items: readonly string[]; delay?: number }) {
  return (
    <div className="sl-chips">
      {items.map((text, i) => (
        <span key={text} className="sl-chip" style={rise(delay + i * 0.18)}>
          {text}
        </span>
      ))}
    </div>
  );
}

/** Two slow glows behind every slide: the landing's blob drift on a dark stage. */
export function Glows() {
  return (
    <>
      <div className="sl-glow sl-glow--sky" />
      <div className="sl-glow sl-glow--mint" />
    </>
  );
}
