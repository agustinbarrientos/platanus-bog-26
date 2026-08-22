// Generates plausible microsimulation trajectory data for the design artboards.
// Deterministic: seeded PRNG so the canvas is reproducible.
import { writeFileSync } from 'node:fs';

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// One simulated life: health index (0-100) by age, with event drops, ending at death.
function life(rnd, opts = {}) {
  const { declineScale = 1, eventScale = 1, startAge = 42 } = opts;
  let h = 88 + (rnd() - 0.5) * 10;
  const frailty = 0.6 + rnd() * 0.9;          // individual heterogeneity
  const pts = [];
  let age = startAge;
  while (age <= 96 && h > 8) {
    pts.push([age, h]);
    const yrs = 2;
    const base = 0.42 * frailty * declineScale * Math.pow(1.032, age - 42);
    h -= base * yrs + (rnd() - 0.5) * 1.6;
    // discrete events get more likely with age and lower health
    const pEvent = 0.012 * eventScale * Math.pow(1.055, age - 42) * (h < 55 ? 1.7 : 1);
    if (rnd() < pEvent * yrs) h -= 7 + rnd() * 13;
    age += yrs;
  }
  return pts;
}

// map to svg coords
const X0 = 42, X1 = 96;
function path(pts, w, hgt, pad = 0) {
  return 'M' + pts.map(([a, v]) => {
    const x = pad + ((a - X0) / (X1 - X0)) * (w - pad * 2);
    const y = (1 - v / 100) * (hgt - pad) + pad;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join('L');
}

function fan(seed, n, w, hgt, opts) {
  const rnd = mulberry32(seed);
  return Array.from({ length: n }, () => path(life(rnd, opts), w, hgt));
}

// Quantile band across many lives (median + 90% interval) on a common age grid.
function band(seed, n, w, hgt, opts) {
  const rnd = mulberry32(seed);
  const grid = [];
  for (let a = X0; a <= X1; a += 2) grid.push(a);
  const runs = Array.from({ length: n }, () => {
    const m = new Map(life(rnd, opts));
    let last = null;
    return grid.map((a) => { if (m.has(a)) last = m.get(a); return m.has(a) ? m.get(a) : (last !== null ? 0 : null); });
  });
  const q = (arr, p) => { const s = arr.slice().sort((x, y) => x - y); return s[Math.floor(p * (s.length - 1))]; };
  const cols = grid.map((_, i) => runs.map((r) => r[i] ?? 0));
  const lo = grid.map((a, i) => [a, q(cols[i], 0.05)]);
  const mid = grid.map((a, i) => [a, q(cols[i], 0.5)]);
  const hi = grid.map((a, i) => [a, q(cols[i], 0.95)]);
  const toXY = ([a, v]) => {
    const x = ((a - X0) / (X1 - X0)) * w;
    const y = (1 - v / 100) * hgt;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  };
  return {
    median: 'M' + mid.map(toXY).join('L'),
    area: 'M' + hi.map(toXY).join('L') + 'L' + lo.slice().reverse().map(toXY).join('L') + 'Z',
  };
}

const out = {
  // main twin screen
  mainFan: fan(7, 46, 330, 168),
  mainBand: band(7, 400, 330, 168),
  // onboarding corner preview: wide (few answers) then narrow (more answers)
  miniWide: fan(21, 16, 108, 54, { declineScale: 1, eventScale: 1.5 }),
  miniNarrow: fan(21, 16, 108, 54, { declineScale: 1, eventScale: 0.55 }),
  // simulating-in-progress: partial draw
  simFan: fan(33, 34, 318, 190),
  // lever detail: paired seeds, base vs improved
  pairBase: fan(101, 22, 322, 150),
  pairBetter: fan(101, 22, 322, 150, { declineScale: 0.78, eventScale: 0.5 }),
  // case-study screen: a DIFFERENT person than the main twin
  caseBand: band(404, 300, 330, 168, { declineScale: 1.22, eventScale: 1.5 }),
  // survival curve (progressive disclosure screen)
  survival: (() => {
    const rnd = mulberry32(55); const n = 600;
    const ages = Array.from({ length: n }, () => { const p = life(rnd); return p[p.length - 1][0]; });
    const grid = []; for (let a = 42; a <= 96; a += 2) grid.push(a);
    const pts = grid.map((a) => [a, ages.filter((x) => x >= a).length / n]);
    const w = 322, hgt = 128;
    return 'M' + pts.map(([a, s]) => `${(((a - 42) / 54) * w).toFixed(1)},${((1 - s) * hgt).toFixed(1)}`).join('L');
  })(),
  // calibration: predicted vs observed, near diagonal with honest scatter
  calibration: (() => {
    const rnd = mulberry32(9);
    return Array.from({ length: 10 }, (_, i) => {
      const p = (i + 0.5) / 10;
      const o = Math.min(0.98, Math.max(0.02, p + (rnd() - 0.5) * 0.09));
      return { p: +p.toFixed(3), o: +o.toFixed(3) };
    });
  })(),
};

writeFileSync(new URL('./curves.json', import.meta.url), JSON.stringify(out));
const n = JSON.stringify(out).length;
console.log('curves.json written,', (n / 1024).toFixed(1), 'KB');
console.log('mainFan paths:', out.mainFan.length, '| sample len:', out.mainFan[0].length);
