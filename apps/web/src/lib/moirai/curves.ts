/**
 * Seeded trajectory math behind every chart on the landing page.
 *
 * Same seeds, same curves on every render — the fan charts, the histogram and
 * the paired counterfactual all come from one deterministic xorshift stream so
 * the server and the client agree and the visuals never jitter between reloads.
 *
 * What the curves represent matches what the engine actually returns from
 * `POST /me/health-context/montecarlo`: biological age (PhenoAge) per year over
 * a ten-year horizon, as a P10 / median / P90 envelope across trajectories.
 * Nothing here models disease incidence, because the engine does not either.
 */

/** `[chronological age, biological age]`. */
export type Point = [age: number, bio: number];

/** Chronological span of every chart: today, and the engine's ten-year horizon. */
export const A0 = 42;
export const A1 = 52;
/**
 * Biological-age range the vertical axis covers. The floor sits just below A0
 * because every trajectory starts at biological age == chronological age; a
 * floor of A0 or higher clamps the opening years flat against the bottom.
 */
export const Y0 = 41;
export const Y1 = 61;

/**
 * Samples per trajectory. More samples buy finer wobble and cost frame budget:
 * these strokes are re-dashed on every scroll frame, so this is a performance
 * number as much as a smoothness one. The wide charts get a denser grid than
 * the phone-sized ones because their wobble has to survive being drawn across
 * a thousand pixels.
 */
const N_BIG = 40;
const N_MINI = 26;

/**
 * Range of the *gap* axis — how far biological age runs ahead of the calendar.
 * The third view plots this instead of absolute age: both arms then start from
 * zero together, so the whole height of the chart is spent on the one thing
 * that view is about, which is how far apart they end up.
 */
export const G0 = -1;
export const G1 = 6.5;

function rng(seed: number) {
  // Avalanche the seed first. Raw xorshift gives closely-spaced seeds closely
  // correlated *first* draws, and each trajectory takes its drift rate from
  // that first draw — without mixing, a bundle of lives collapses onto one
  // line and the P10-P90 band comes out with no height at all.
  let s = seed >>> 0 || 1;
  s = Math.imul(s ^ 0x9e3779b9, 0x85ebca6b) >>> 0;
  s ^= s >>> 13;
  s = Math.imul(s, 0xc2b2ae35) >>> 0;
  s = ((s ^ (s >>> 16)) >>> 0) || 1;
  return () => {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    return s / 4294967296;
  };
}

/**
 * One possible future: biological age drifts away from (or back toward)
 * chronological age at a seeded rate. `soft` is the lever — the same seed with
 * a different `soft` gives the *paired* counterfactual, which is the whole
 * point of the third view: same future, one variable changed.
 *
 * On top of the drift rides a wobble: one slow seeded ripple plus a damped
 * random walk. A body does not age along a clean arc, and a stroke that glides
 * reads as a drawing of data rather than as data. `wob` scales it, because the
 * wobble is measured in years and the phone-sized charts are a fifth of the
 * height of the wide ones — the same amplitude would vanish there.
 */
function traj(r: () => number, soft = 0, n = N_BIG, wob = 1): Point[] {
  const pts: Point[] = [];
  const rate = (-0.1 + r() * 0.62) * (1 - soft);
  // A slow wave per life, so no two curves bend the same way.
  const phase = r() * Math.PI * 2;
  const amp = 0.14 + r() * 0.34;
  // The wobble's own ripple, at an unrelated frequency to the bend above.
  const wf = 3.5 + r() * 4;
  const wp = r() * Math.PI * 2;
  const wa = 0.1 + r() * 0.14;

  let gap = 0;
  let walk = 0;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const a = A0 + t * (A1 - A0);
    // Mean-reverting, so the texture stays texture: a plain random walk on the
    // increments (which is what makes a hand-drawn-looking line) would also
    // widen the horizon distribution the percentiles are read off.
    walk = walk * 0.78 + (r() - 0.5) * 0.22;
    // Every life starts at its measured age, so the wobble ramps in over the
    // first couple of samples instead of fraying the shared origin point.
    const ramp = Math.min(1, t * 4.5);
    const ripple = (Math.sin(wp + t * wf * Math.PI) * wa + walk) * wob * ramp;
    pts.push([a, a + gap + ripple]);
    // Ageing compounds: the drift starts gentle and steepens, which is what
    // bends the line. A flat drift would draw a straight ray.
    gap +=
      (rate * (A1 - A0)) /
      n *
      (0.4 + Math.pow(t, 1.6) * 2.9) *
      (0.82 + Math.sin(phase + t * 4.5) * amp + r() * 0.28);
  }
  return pts;
}

/** How a trajectory point becomes a plot coordinate. */
export type Proj = "bio" | "gap";

/**
 * Project onto an SVG path in a w x h box, as a Catmull-Rom spline rendered
 * with cubic Béziers. Straight `L` segments between samples read as harsh on
 * a chart this wide; the spline keeps the same points and softens the joins.
 */
function path(pts: Point[], w: number, h: number, proj: Proj = "bio"): string {
  return spline(pts.map((q) => numXY(q, w, h, proj)));
}

function spline(p: [number, number][]): string {
  if (p.length < 2) return "";
  const f = (n: number) => n.toFixed(1);
  let d = `M${f(p[0][0])} ${f(p[0][1])}`;
  for (let i = 0; i < p.length - 1; i++) {
    const p0 = p[i - 1] ?? p[i];
    const p1 = p[i];
    const p2 = p[i + 1];
    const p3 = p[i + 2] ?? p2;
    d +=
      ` C${f(p1[0] + (p2[0] - p0[0]) / 6)} ${f(p1[1] + (p2[1] - p0[1]) / 6)}` +
      ` ${f(p2[0] - (p3[0] - p1[0]) / 6)} ${f(p2[1] - (p3[1] - p1[1]) / 6)}` +
      ` ${f(p2[0])} ${f(p2[1])}`;
  }
  return d;
}

/** A closed band: smooth along the top edge, across, and back along the bottom. */
function bandPath(hi: Point[], lo: Point[], w: number, h: number, proj: Proj = "bio"): string {
  return (
    path(hi, w, h, proj) + path(lo.slice().reverse(), w, h, proj).replace(/^M/, " L") + " Z"
  );
}

function xy(q: Point, w: number, h: number, proj: Proj = "bio"): [string, string] {
  const x = ((q[0] - A0) / (A1 - A0)) * w;
  const t =
    proj === "gap"
      ? (q[1] - q[0] - G0) / (G1 - G0)
      : (q[1] - Y0) / (Y1 - Y0);
  return [x.toFixed(1), ((1 - Math.max(0, Math.min(1, t))) * h).toFixed(1)];
}

/** Plot-space y for a biological age, in a chart of height `h`. */
export const bioY = (bio: number, h: number): number =>
  (1 - Math.max(0, Math.min(1, (bio - Y0) / (Y1 - Y0)))) * h;

/** Plot-space y on the gap axis, for a biological age at the horizon. */
export const gapY = (bio: number, h: number): number =>
  (1 - Math.max(0, Math.min(1, (bio - A1 - G0) / (G1 - G0)))) * h;

/** Biological age at the horizon: the last sample of a trajectory. */
function final(pts: Point[]): number {
  return pts[pts.length - 1][1];
}

function qtl(arr: number[], pr: number): number {
  const s = arr.slice().sort((x, y) => x - y);
  return s[Math.max(0, Math.min(s.length - 1, Math.floor(pr * s.length)))];
}

/**
 * P10 / median / P90 envelopes across a bundle of trajectories. Every
 * trajectory walks the same age grid, so the quantiles are taken by position.
 */
function envelope(sample: Point[][], n: number) {
  const hi: Point[] = [];
  const lo: Point[] = [];
  const mid: Point[] = [];
  for (let i = 0; i <= n; i++) {
    const a = A0 + (i / n) * (A1 - A0);
    const vs = sample.map((x) => x[i][1]);
    hi.push([a, qtl(vs, 0.9)]);
    lo.push([a, qtl(vs, 0.1)]);
    mid.push([a, qtl(vs, 0.5)]);
  }
  return { hi, lo, mid };
}

function pathLength(pts: Point[], w: number, h: number, proj: Proj = "bio"): number {
  let len = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = xy(pts[i - 1], w, h, proj);
    const b = xy(pts[i], w, h, proj);
    len += Math.hypot(+b[0] - +a[0], +b[1] - +a[1]);
  }
  // The spline bows slightly outside its control polygon, so pad the dash
  // length rather than leaving a sliver of stroke showing at progress 0.
  return len * 1.1;
}

export interface MiniCurves {
  lines: { d: string; delay: string }[];
  band: string;
  med: string;
  wide: string;
  narrow: string;
  wideMed: string;
  bandWide: string;
  medWide: string;
}

/**
 * Curves for the small in-phone charts and the onboarding fan. The wobble is
 * scaled up here: these boxes are a fifth of the height of the wide charts, so
 * the same amplitude in years would land under a pixel.
 */
function buildMini(): MiniCurves {
  const W = 196;
  const H = 78;
  const WOB = 1.8;
  const lines = Array.from({ length: 14 }, (_, i) => ({
    d: path(traj(rng(9000 + i * 131), 0.3, N_MINI, WOB), W, H),
    delay: (i * 0.07).toFixed(2),
  }));

  const sample = Array.from({ length: 140 }, (_, i) =>
    traj(rng(4100 + i * 17), 0.3, N_MINI, WOB),
  );
  const { hi, lo, mid } = envelope(sample, N_MINI);

  // The same envelope pulled 34% toward the median: the "fan closing" state.
  const nb: Point[] = [];
  const nl: Point[] = [];
  for (let i = 0; i <= N_MINI; i++) {
    const m = mid[i][1];
    nb.push([mid[i][0], m + (hi[i][1] - m) * 0.34]);
    nl.push([mid[i][0], m + (lo[i][1] - m) * 0.34]);
  }

  return {
    lines,
    band: bandPath(hi, lo, W, H),
    med: path(mid, W, H),
    wide: bandPath(hi, lo, 108, 80),
    narrow: bandPath(nb, nl, 108, 80),
    wideMed: path(mid, 108, 80),
    bandWide: bandPath(hi, lo, 260, 92),
    medWide: path(mid, 260, 92),
  };
}

export interface DrawnLine {
  d: string;
  /** Total path length, for the stroke-dash draw-on effect. */
  len: number;
  /** Coordinates of the last point, where the head dot lands. */
  end: [number, number];
}

/** One lever's paired counterfactual: same seeds, one variable changed. */
export interface PairedRun {
  band: string;
  med: string;
  medLen: number;
  /** Median biological age at the horizon. */
  p50: number;
  p10: number;
  p90: number;
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
  /** Histogram tick positions for P10 / median / P90 at the horizon. */
  x10: string;
  x50: string;
  x90: string;
  /** Biological age at the horizon, rounded for display. */
  p10: number;
  p50: number;
  p90: number;
  /** How many years wide the P10-P90 band is at the horizon. */
  spread: number;
  /** Baseline vs. lever, run from the same seeds. */
  base: PairedRun;
  lever: PairedRun;
  /** Years of biological ageing the lever avoids, with its range. */
  delta: number;
  deltaLo: number;
  deltaHi: number;
  /** Share of paired futures where the lever helped. */
  pctMejoran: number;
  /** A few individually paired lives, to show the pairing is real. */
  pairs: { base: DrawnLine; lever: DrawnLine }[];
}

const SOFT = 0.65;
/** Biological-age range the histogram bins cover. */
export const HIST_LO = 46;
export const HIST_HI = 62;

/** Curves for the full-width engine visualisation. */
function buildBig(): BigCurves {
  const W = 1016;
  const H = 360;

  const lines: DrawnLine[] = Array.from({ length: 52 }, (_, i) => {
    const t = traj(rng(1201 + i * 977), 0);
    return { d: path(t, W, H), len: pathLength(t, W, H), end: numXY(t[t.length - 1], W, H) };
  });

  // Same seeds for both arms: every lever life is the pair of a baseline life.
  // Enough draws that the histogram reads as a distribution rather than as
  // noise. Only paid once, at module init, and then cached.
  const seeds = Array.from({ length: 900 }, (_, i) => 3301 + i * 131);
  const baseSample = seeds.map((s) => traj(rng(s), 0));
  const leverSample = seeds.map((s) => traj(rng(s), SOFT));

  const baseEnv = envelope(baseSample, N_BIG);
  const leverEnv = envelope(leverSample, N_BIG);

  const finals = baseSample.map(final);
  const leverFinals = leverSample.map(final);

  const p10 = qtl(finals, 0.1);
  const p50 = qtl(finals, 0.5);
  const p90 = qtl(finals, 0.9);

  // Paired differences, which is what "años que te ahorras" actually is.
  const diffs = finals.map((v, i) => v - leverFinals[i]);
  const mejoran = diffs.filter((d) => d > 0).length;

  const B = 22;
  const step = (HIST_HI - HIST_LO) / B;
  const bins = new Array(B).fill(0);
  finals.forEach((v) => {
    const k = Math.floor((Math.max(HIST_LO, Math.min(HIST_HI, v)) - HIST_LO) / step);
    bins[Math.max(0, Math.min(B - 1, k))]++;
  });
  const mx = Math.max(...bins);
  const bw = W / B;
  const bars = bins.map((c, i) => ({
    x: (i * bw + 3).toFixed(1),
    w: (bw - 6).toFixed(1),
    h: (c / mx) * 300,
  }));

  const onScale = (bio: number) =>
    Math.max(14, Math.min(W - 14, ((bio - HIST_LO) / (HIST_HI - HIST_LO)) * W)).toFixed(1);

  const run = (env: ReturnType<typeof envelope>, fin: number[]): PairedRun => ({
    band: bandPath(env.hi, env.lo, W, H, "gap"),
    med: path(env.mid, W, H, "gap"),
    medLen: pathLength(env.mid, W, H, "gap"),
    p50: r1(qtl(fin, 0.5)),
    p10: r1(qtl(fin, 0.1)),
    p90: r1(qtl(fin, 0.9)),
  });

  const pairs = [0, 7, 19, 31, 44].map((i) => {
    const b = traj(rng(seeds[i]), 0);
    const l = traj(rng(seeds[i]), SOFT);
    return {
      base: {
        d: path(b, W, H, "gap"),
        len: pathLength(b, W, H, "gap"),
        end: numXY(b[b.length - 1], W, H, "gap"),
      },
      lever: {
        d: path(l, W, H, "gap"),
        len: pathLength(l, W, H, "gap"),
        end: numXY(l[l.length - 1], W, H, "gap"),
      },
    };
  });

  return {
    w: W,
    h: H,
    lines,
    band: bandPath(baseEnv.hi, baseEnv.lo, W, H),
    med: path(baseEnv.mid, W, H),
    medLen: pathLength(baseEnv.mid, W, H),
    markX: W.toFixed(1),
    markY: xy([A1, qtl(finals, 0.5)], W, H)[1],
    bars,
    x10: onScale(p10),
    x50: onScale(p50),
    x90: onScale(p90),
    p10: r1(p10),
    p50: r1(p50),
    p90: r1(p90),
    spread: r1(p90 - p10),
    base: run(baseEnv, finals),
    lever: run(leverEnv, leverFinals),
    delta: r1(qtl(diffs, 0.5)),
    deltaLo: r1(qtl(diffs, 0.1)),
    deltaHi: r1(qtl(diffs, 0.9)),
    pctMejoran: Math.round((mejoran / diffs.length) * 100),
    pairs,
  };
}

const r1 = (v: number) => Math.round(v * 10) / 10;

function numXY(q: Point, w: number, h: number, proj: Proj = "bio"): [number, number] {
  const [x, y] = xy(q, w, h, proj);
  return [+x, +y];
}

let miniCache: MiniCurves | undefined;
let bigCache: BigCurves | undefined;

export const miniCurves = (): MiniCurves => (miniCache ??= buildMini());
export const bigCurves = (): BigCurves => (bigCache ??= buildBig());
