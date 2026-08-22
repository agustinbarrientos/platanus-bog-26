"use client";

import { type CSSProperties, useEffect, useRef } from "react";
import type { AnimationItem } from "lottie-web";

/**
 * Moirai, the Turritopsis dohrnii mascot, as a Lottie animation.
 *
 * Two cuts of the same jellyfish: `travel` swims across a wide box (used once,
 * beside the hero headline), everything else hovers in place inside a square.
 * Both files carry a large soft glow that has to be cropped out of the viewBox
 * after load, otherwise the creature renders tiny in the middle of its halo.
 */

interface MascotProps {
  /** Square edge in px. Ignored when `travel` is set — that one fills its box. */
  size?: number;
  /** Wide swimming cut for the hero. */
  travel?: boolean;
  className?: string;
  style?: CSSProperties;
}

const HOVER = "moMascotHover 6s ease-in-out infinite";
/** How far the travel animation drifts sideways, in Lottie units. */
const TRAVEL_REACH = 580;

export function Mascot({ size = 140, travel = false, className, style }: MascotProps) {
  const host = useRef<HTMLDivElement>(null);
  const mount = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = mount.current;
    if (!container) return;

    let anim: AnimationItem | null = null;
    let observer: IntersectionObserver | null = null;
    let cancelled = false;

    void import("lottie-web/build/player/lottie_svg").then(({ default: lottie }) => {
      if (cancelled || !mount.current) return;

      anim = lottie.loadAnimation({
        container,
        renderer: "svg",
        loop: true,
        autoplay: true,
        path: travel ? "/moirai/moirai-mascot.json" : "/moirai/moirai-plain.json",
        rendererSettings: { preserveAspectRatio: "xMidYMid meet", progressiveLoad: false },
      });
      anim.setSpeed(travel ? 0.75 : 0.85);
      anim.addEventListener("DOMLoaded", () => cropGlow(container, travel));

      // Offscreen mascots stop costing frames.
      if (host.current && "IntersectionObserver" in window) {
        observer = new IntersectionObserver(
          ([entry]) => (entry.isIntersecting ? anim?.play() : anim?.pause()),
          { rootMargin: "200px" },
        );
        observer.observe(host.current);
      }
    });

    return () => {
      cancelled = true;
      observer?.disconnect();
      anim?.destroy();
    };
  }, [travel]);

  const box = travel ? "100%" : `${size}px`;

  return (
    <div
      ref={host}
      className={className}
      style={{ width: box, height: box, maxWidth: "100%", position: "relative", ...style }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          animation: travel ? "none" : HOVER,
          willChange: "transform",
        }}
      >
        <div ref={mount} style={{ width: "100%", height: "100%" }} />
      </div>
    </div>
  );
}

/**
 * Tighten the viewBox onto the jellyfish itself.
 *
 * The plain cut has no halo, so a simple centred crop is enough. The travel cut
 * does: its glow layers are measured by hiding them, cropping to what is left,
 * then fading the edges back in with a radial mask so the halo does not end in
 * a hard rectangle.
 */
function cropGlow(container: HTMLElement, travel: boolean) {
  const svg = container.querySelector("svg");
  if (!svg) return;

  let full: DOMRect;
  try {
    full = svg.getBBox();
  } catch {
    return;
  }
  if (!full.width) return;

  const fill = () => {
    svg.style.width = "100%";
    svg.style.height = "100%";
  };

  if (!travel) {
    const side = Math.max(full.width, full.height) * 1.16;
    const cx = full.x + full.width / 2;
    const cy = full.y + full.height / 2;
    svg.setAttribute(
      "viewBox",
      `${(cx - side / 2).toFixed(1)} ${(cy - side / 2).toFixed(1)} ${side.toFixed(1)} ${side.toFixed(1)}`,
    );
    fill();
    return;
  }

  const groups = Array.from(svg.querySelectorAll<SVGGElement>(":scope > g > g"));
  const glow = groups.filter((g) => {
    try {
      return g.getBBox().width > full.width * 0.7;
    } catch {
      return false;
    }
  });

  glow.forEach((g) => (g.style.display = "none"));
  let core: DOMRect;
  try {
    core = svg.getBBox();
  } catch {
    core = full;
  }
  glow.forEach((g) => (g.style.display = ""));
  if (!core.width || !core.height) return;

  const cx = core.x + core.width / 2;
  const cy = core.y + core.height / 2;
  const reach = Math.max(
    Math.abs(full.x - cx),
    Math.abs(full.x + full.width - cx),
    Math.abs(full.y - cy),
    Math.abs(full.y + full.height - cy),
  );
  const side = Math.max(Math.max(core.width, core.height) * 1.28, reach * 2.06);
  const vw = side + TRAVEL_REACH * 2.1;
  const vx = cx - side / 2 - TRAVEL_REACH * 1.05;
  const vy = cy - side / 2;
  svg.setAttribute("viewBox", `${vx.toFixed(1)} ${vy.toFixed(1)} ${vw.toFixed(1)} ${side.toFixed(1)}`);
  fill();

  const NS = "http://www.w3.org/2000/svg";
  const id = `moiraiFade${Math.random().toString(36).slice(2, 8)}`;
  let defs = svg.querySelector("defs");
  if (!defs) {
    defs = document.createElementNS(NS, "defs");
    svg.insertBefore(defs, svg.firstChild);
  }

  const grad = document.createElementNS(NS, "radialGradient");
  grad.setAttribute("id", `${id}g`);
  grad.setAttribute("r", "0.72");
  for (const [offset, opacity] of [
    ["0", "1"],
    ["0.74", "1"],
    ["0.9", "0.5"],
    ["1", "0"],
  ]) {
    const stop = document.createElementNS(NS, "stop");
    stop.setAttribute("offset", offset);
    stop.setAttribute("stop-color", "#fff");
    stop.setAttribute("stop-opacity", opacity);
    grad.appendChild(stop);
  }

  const mask = document.createElementNS(NS, "mask");
  mask.setAttribute("id", id);
  mask.setAttribute("maskUnits", "userSpaceOnUse");
  const rect = document.createElementNS(NS, "rect");
  rect.setAttribute("x", vx.toFixed(1));
  rect.setAttribute("y", vy.toFixed(1));
  rect.setAttribute("width", vw.toFixed(1));
  rect.setAttribute("height", side.toFixed(1));
  rect.setAttribute("fill", `url(#${id}g)`);
  mask.appendChild(rect);

  defs.appendChild(grad);
  defs.appendChild(mask);
  svg.querySelector(":scope > g")?.setAttribute("mask", `url(#${id})`);
}
