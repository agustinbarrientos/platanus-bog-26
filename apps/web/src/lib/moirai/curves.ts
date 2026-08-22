/**
 * Seeded trajectory math behind every chart on the landing page.
 *
 * Same seeds, same curves on every render — the fan charts, the histogram and
 * the calibration curve all come from one deterministic xorshift stream so the
 * server and the client agree and the visuals never jitter between reloads.
 */

export type Point = [age: number, value: number];

function rng(seed: number) {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    return s / 4294967296;
  };
}

/** One possible life: health decays from 42 to 96 at a seeded rate. */
function traj(r: () => number, soft = 0): Point[] {
  const pts: Point[] = [];
  let v = 1;
  const d = (0.006 + r() * 0.032) * (1 - soft);
  for (let a = 42; a <= 96; a++) {
    pts.push([a, v]);
    v -= d * (0.3 + Math.pow((a - 42) / 54, 1.6) * 2.4) * (0.55 + r() * 0.9);
    if (v <= 0) {
      pts.push([Math.min(96, a + 1), 0]);
      break;
    }
  }
  return pts;
}

/** Project age/value points onto an SVG path in a w x h box. */
function path(pts: Point[], w: number, h: number): string {
  return (
    "M" +
    pts
      .map((q) => (((q[0] - 42) / 54) * w).toFixed(1) + " " + ((1 - q[1]) * h).toFixed(1))
      .join(" L")
  );
}

function at(pts: Point[], a: number): number {
  for (const p of pts) if (p[0] === a) return p[1];
  return 0;
}

function qtl(arr: number[], pr: number): number {
  const s = arr.slice().sort((x, y) => x - y);
  return s[Math.max(0, Math.min(s.length - 1, Math.floor(pr * s.length)))];
}

/** Median / P05 / P95 envelopes across a bundle of trajectories. */
function envelope(sample: Point[][]) {
  const hi: Point[] = [];
  const lo: Point[] = [];
  const mid: Point[] = [];
  for (let a = 42; a <= 96; a++) {
    const vs = sample.map((x) => at(x, a));
    hi.push([a, qtl(vs, 0.95)]);
    lo.push([a, qtl(vs, 0.05)]);
    mid.push([a, qtl(vs, 0.5)]);
  }
  return { hi, lo, mid };
}

/** The calibration curve: predicted decile vs. what actually happened. */
function calibrationPoints(x0: number, y0: number, span: number) {
  return Array.from({ length: 10 }, (_, i) => {
    const pr = (i + 0.5) / 10;
    const ob = Math.max(0.02, Math.min(0.98, pr * 0.94 + 0.03 + Math.sin(i * 1.7) * 0.03));
    return { i, cx: (x0 + pr * span).toFixed(1), cy: (y0 - ob * span).toFixed(1) };
  });
}

export interface MiniCurves {
  lines: { d: string; delay: string }[];
  band: string;
  med: string;
  wide: string;
  narrow: string;
  bandWide: string;
  medWide: string;
  cal: string;
}

/** Curves for the small in-phone charts and the onboarding fan. */
function buildMini(): MiniCurves {
  const W = 196;
  const H = 78;
  const lines = Array.from({ length: 14 }, (_, i) => ({
    d: path(traj(rng(9000 + i * 131), 0.3), W, H),
    delay: (i * 0.07).toFixed(2),
  }));

  const sample = Array.from({ length: 140 }, (_, i) => traj(rng(4100 + i * 17), 0.3));
  const { hi, lo, mid } = envelope(sample);

  // The same envelope pulled 34% toward the median: the "fan closing" state.
  const nb: Point[] = [];
  const nl: Point[] = [];
  for (let a = 42; a <= 96; a++) {
    const m = at(mid, a);
    nb.push([a, m + (at(hi, a) - m) * 0.34]);
    nl.push([a, m + (at(lo, a) - m) * 0.34]);
  }

  const closed = hi.concat(lo.slice().reverse());
  const cal = calibrationPoints(20, 230, 210);

  return {
    lines,
    band: path(closed, W, H) + "Z",
    med: path(mid, W, H),
    wide: path(closed, 108, 54) + "Z",
    narrow: path(nb.concat(nl.slice().reverse()), 108, 54) + "Z",
    bandWide: path(closed, 260, 92) + "Z",
    medWide: path(mid, 260, 92),
    cal: "M" + cal.map((q) => q.cx + " " + q.cy).join(" L"),
  };
}

export interface DrawnLine {
  d: string;
  /** Total path length, for the stroke-dash draw-on effect. */
  len: number;
  /** Coordinates of the last point, where the head dot lands. */
  end: [number, number];
}

export interface BigCurves {
  w: number;
  h: number;
  lines: DrawnLine[];
  band: string;
  med: string;
  medLen: number;
  markX: string;
  markY: string;
  bars: { x: string; w: string; h: number }[];
  cal: { d: string; len: number; pts: { i: number; cx: string; cy: string }[] };
  x05: string;
  x50: string;
  x95: string;
}

/** Curves for the full-width engine visualisation. */
function buildBig(): BigCurves {
  const W = 1016;
  const H = 360;

  const lines: DrawnLine[] = Array.from({ length: 58 }, (_, i) => {
    const t = traj(rng(1201 + i * 977), 0);
    let len = 0;
    let px = 0;
    let py = 0;
    const xy = t.map((q, j) => {
      const x = ((q[0] - 42) / 54) * W;
      const y = (1 - q[1]) * H;
      if (j) len += Math.hypot(x - px, y - py);
      px = x;
      py = y;
      return [x, y] as [number, number];
    });
    return { d: path(t, W, H), len, end: xy[xy.length - 1] };
  });

  const sample = Array.from({ length: 400 }, (_, i) => traj(rng(3301 + i * 131), 0));
  const { hi, lo, mid } = envelope(sample);

  let medLen = 0;
  for (let i = 1; i < mid.length; i++) {
    const ax = ((mid[i - 1][0] - 42) / 54) * W;
    const ay = (1 - mid[i - 1][1]) * H;
    const bx = ((mid[i][0] - 42) / 54) * W;
    const by = (1 - mid[i][1]) * H;
    medLen += Math.hypot(bx - ax, by - ay);
  }

  // Age of first chronic event per life, rescaled onto the 61 / 68 / 75 story.
  const raw = sample.map((t) => t.find((q) => q[1] <= 0.35)?.[0] ?? 96);
  const r05 = qtl(raw, 0.05);
  const r50 = qtl(raw, 0.5);
  const r95 = qtl(raw, 0.95);
  const fit = (a: number) =>
    a <= r50
      ? 61 + ((a - r05) / Math.max(1, r50 - r05)) * 7
      : 68 + ((a - r50) / Math.max(1, r95 - r50)) * 7;

  const B = 22;
  const a0 = 52;
  const a1 = 92;
  const step = (a1 - a0) / B;
  const bins = new Array(B).fill(0);
  raw.forEach((a) => {
    const v = Math.max(52, Math.min(92, fit(a)));
    bins[Math.max(0, Math.min(B - 1, Math.floor((v - a0) / step)))]++;
  });
  const mx = Math.max(...bins);
  const bw = W / B;
  const bars = bins.map((c, i) => ({
    x: (i * bw + 3).toFixed(1),
    w: (bw - 6).toFixed(1),
    h: (c / mx) * 300,
  }));

  const xOnScale = (age: number) =>
    Math.max(14, Math.min(W - 14, ((age - a0) / (a1 - a0)) * W)).toFixed(1);

  const calPts = calibrationPoints(338, 348, 340);

  return {
    w: W,
    h: H,
    lines,
    band: path(hi.concat(lo.slice().reverse()), W, H) + "Z",
    med: path(mid, W, H),
    medLen,
    markX: (((68 - 42) / 54) * W).toFixed(1),
    markY: ((1 - at(mid, 68)) * H).toFixed(1),
    bars,
    cal: { d: "M" + calPts.map((q) => q.cx + " " + q.cy).join(" L"), len: 500, pts: calPts },
    x05: xOnScale(61),
    x50: xOnScale(68),
    x95: xOnScale(75),
  };
}

let miniCache: MiniCurves | undefined;
let bigCache: BigCurves | undefined;

export const miniCurves = (): MiniCurves => (miniCache ??= buildMini());
export const bigCurves = (): BigCurves => (bigCache ??= buildBig());
