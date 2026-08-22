// Shared visual system for the artboards. Light clinical calm.
// Accents share L≈0.72 / C≈0.085, hue varies. Rounded type. No red anywhere.

export const T = {
  bg: 'oklch(0.982 0.008 215)',
  surface: 'oklch(1 0.002 215)',
  surface2: 'oklch(0.966 0.012 212)',
  ink: 'oklch(0.30 0.028 245)',
  ink2: 'oklch(0.53 0.022 245)',
  ink3: 'oklch(0.67 0.018 245)',
  line: 'oklch(0.915 0.012 220)',
  blue: 'oklch(0.72 0.085 232)',
  blueSoft: 'oklch(0.935 0.032 232)',
  blueInk: 'oklch(0.46 0.075 240)',
  green: 'oklch(0.72 0.085 158)',
  greenSoft: 'oklch(0.935 0.032 158)',
  greenInk: 'oklch(0.44 0.070 160)',
  amber: 'oklch(0.76 0.085 78)',
  amberSoft: 'oklch(0.948 0.032 78)',
  amberInk: 'oklch(0.48 0.070 70)',
};

export const W = 390, H = 844, TOP = 52, BOT = 30;

export const FONTS =
  '<link rel="preconnect" href="https://fonts.googleapis.com">' +
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
  '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600&family=Nunito:wght@400;600;700&display=swap">';

export const DISPLAY = "'Fredoka', 'Trebuchet MS', system-ui, sans-serif";
export const BODY = "'Nunito', 'Avenir Next', 'Segoe UI', system-ui, sans-serif";

export const baseCss = `
  body { margin: 0; background: ${T.bg}; font-family: ${BODY}; color: ${T.ink};
         -webkit-font-smoothing: antialiased; }
  * { box-sizing: border-box; }
  a { color: ${T.blueInk}; text-decoration: none; }
  a:hover { color: ${T.ink}; }
  @keyframes breathe { 0%,100% { transform: translateY(0) scale(1); }
                       50% { transform: translateY(-3px) scale(1.025); } }
  @keyframes blink { 0%,92%,100% { transform: scaleY(1); } 96% { transform: scaleY(0.1); } }
  @keyframes orbit { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
  @keyframes draw { from { stroke-dashoffset: 620; } to { stroke-dashoffset: 0; } }
  @keyframes rise { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
  @keyframes pulse { 0%,100% { opacity: .35; } 50% { opacity: .9; } }
`;

// ---- mascot -----------------------------------------------------------
// "Tino": a soft rounded companion. Never sad — a sad mascot amplifies dread.
// mood: idle | working | gentle | happy
export function tino(size = 96, mood = 'idle') {
  const s = size;
  const eyeY = mood === 'gentle' ? 43 : 41;
  const eyes = mood === 'happy'
    ? `<path d="M32 ${eyeY} q5 -5 10 0" stroke="${T.greenInk}" stroke-width="3.4" fill="none" stroke-linecap="round"/>
       <path d="M58 ${eyeY} q5 -5 10 0" stroke="${T.greenInk}" stroke-width="3.4" fill="none" stroke-linecap="round"/>`
    : `<ellipse cx="37" cy="${eyeY}" rx="3.6" ry="4.2" fill="${T.greenInk}" style="animation: blink 6.5s infinite"/>
       <ellipse cx="63" cy="${eyeY}" rx="3.6" ry="4.2" fill="${T.greenInk}" style="animation: blink 6.5s infinite"/>`;
  const mouth = mood === 'gentle'
    ? `<path d="M43 55 q7 3 14 0" stroke="${T.greenInk}" stroke-width="3" fill="none" stroke-linecap="round" opacity=".75"/>`
    : `<path d="M42 54 q8 7 16 0" stroke="${T.greenInk}" stroke-width="3.2" fill="none" stroke-linecap="round"/>`;
  const halo = mood === 'working'
    ? `<g style="transform-origin: 50px 48px; animation: orbit 4.5s linear infinite">
         <circle cx="50" cy="8" r="3.4" fill="${T.blue}"/>
         <circle cx="88" cy="62" r="2.6" fill="${T.blue}" opacity=".7"/>
         <circle cx="14" cy="66" r="2.2" fill="${T.blue}" opacity=".5"/>
       </g>` : '';
  const arm = mood === 'gentle'
    ? `<path d="M79 52 q10 -3 11 -12" stroke="${T.green}" stroke-width="6" fill="none" stroke-linecap="round"/>` : '';
  return `<svg width="${s}" height="${s}" viewBox="0 0 100 100" fill="none" aria-hidden="true"
      style="animation: breathe 4.2s ease-in-out infinite; overflow: visible">
    ${halo}
    <path d="M50 12 C70 12 82 28 82 46 C82 66 68 80 50 80 C32 80 18 66 18 46 C18 28 30 12 50 12 Z"
          fill="${T.greenSoft}" stroke="${T.green}" stroke-width="2.5"/>
    <ellipse cx="28" cy="52" rx="5" ry="3.6" fill="${T.green}" opacity=".28"/>
    <ellipse cx="72" cy="52" rx="5" ry="3.6" fill="${T.green}" opacity=".28"/>
    ${arm}${eyes}${mouth}
  </svg>`;
}

// ---- icons (stroke, 24 grid) -----------------------------------------
export function icon(name, c = T.ink2, sz = 22) {
  const p = {
    back: '<path d="M15 5l-7 7 7 7"/>',
    camera: '<path d="M3 8.5A2 2 0 015 6.5h2l1.2-2h7.6L17 6.5h2a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><circle cx="12" cy="13" r="3.4"/>',
    file: '<path d="M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8z"/><path d="M14 3v5h5"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
    twin: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"/>',
    lever: '<path d="M4 18h16M4 12h16M4 6h16"/><circle cx="9" cy="6" r="2.4" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="2.4" fill="currentColor" stroke="none"/><circle cx="7" cy="18" r="2.4" fill="currentColor" stroke="none"/>',
    proof: '<path d="M12 3l7 3v6c0 4.2-2.9 7.6-7 9-4.1-1.4-7-4.8-7-9V6z"/><path d="M9 12l2.2 2.2L15.5 10"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 7.6v.1"/>',
    bell: '<path d="M18 15V10a6 6 0 10-12 0v5l-1.6 2.5h15.2z"/><path d="M10 20.5a2.2 2.2 0 004 0"/>',
    chevron: '<path d="M9 5l7 7-7 7"/>',
    drop: '<path d="M12 3.5S5.5 11 5.5 15a6.5 6.5 0 0013 0C18.5 11 12 3.5 12 3.5z"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.4l3.4 2"/>',
  }[name] || '';
  return `<svg width="${sz}" height="${sz}" viewBox="0 0 24 24" fill="none" stroke="${c}"
    stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
}

// ---- building blocks --------------------------------------------------
export function screen(inner, bg = T.bg) {
  return `<div style="width: ${W}px; height: ${H}px; background: ${bg}; position: relative;
    overflow: hidden; display: flex; flex-direction: column;">${inner}</div>`;
}

export function topbar({ title = '', back = false, chip = '' } = {}) {
  return `<div style="display: flex; align-items: center; gap: 12px; padding: ${TOP}px 20px 8px;">
    ${back ? `<div style="width: 44px; height: 44px; margin-left: -11px; border-radius: 22px;
        display: flex; align-items: center; justify-content: center;">${icon('back', T.ink2, 22)}</div>` : ''}
    <div style="flex-grow: 1; font-family: ${DISPLAY}; font-size: 17px; font-weight: 500;">${title}</div>
    ${chip}
  </div>`;
}

// the persistent calibration chip — clickable from anywhere
export function calibChip() {
  return `<div style="display: flex; align-items: center; gap: 7px; height: 44px; padding: 0 14px;
    border-radius: 22px; background: ${T.blueSoft}; color: ${T.blueInk};
    font-size: 12.5px; font-weight: 700; white-space: nowrap;">
    ${icon('proof', T.blueInk, 14)}<span>calibración 88%</span></div>`;
}

export function card(inner, extra = '') {
  return `<div style="background: ${T.surface}; border: 1px solid ${T.line}; border-radius: 24px;
    padding: 18px; ${extra}">${inner}</div>`;
}

export function btn(label, kind = 'primary', extra = '') {
  const st = kind === 'primary'
    ? `background: ${T.green}; color: oklch(1 0 0); border: none;`
    : kind === 'ghost'
      ? `background: transparent; color: ${T.ink2}; border: none;`
      : `background: ${T.surface}; color: ${T.ink}; border: 1px solid ${T.line};`;
  return `<div style="height: 54px; border-radius: 27px; display: flex; align-items: center;
    justify-content: center; font-family: ${DISPLAY}; font-size: 16.5px; font-weight: 500;
    ${st} ${extra}">${label}</div>`;
}

export function navbar(active = 'twin') {
  const item = (key, label, ic) => {
    const on = key === active;
    const c = on ? T.greenInk : T.ink3;
    return `<div style="flex-grow: 1; display: flex; flex-direction: column; align-items: center;
      gap: 4px; height: 52px; justify-content: center;">
      ${icon(ic, c, 22)}
      <span style="font-size: 11px; font-weight: ${on ? 700 : 600}; color: ${c};">${label}</span></div>`;
  };
  return `<div style="margin-top: auto; display: flex; align-items: stretch; gap: 4px;
    padding: 6px 12px ${BOT}px; background: ${T.surface}; border-top: 1px solid ${T.line};">
    ${item('twin', 'Gemelo', 'twin')}${item('sim', 'Simular', 'lever')}${item('proof', 'Respaldo', 'proof')}
  </div>`;
}

// axis labels for the fan charts
export function ageAxis(w) {
  return `<div style="display: flex; justify-content: space-between; width: ${w}px;
    font-size: 11px; color: ${T.ink3}; font-weight: 600;">
    <span>42</span><span>55</span><span>68</span><span>82</span><span>96 años</span></div>`;
}

export function page({ name, body, css = '', props = null, logic = null }) {
  const dp = props ? ` data-props='${props}'` : '';
  const cls = logic || 'class Component extends DCLogic {\n  renderVals() { return {}; }\n}';
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  ${FONTS}
  <style>${baseCss}${css}</style>
</helmet>
${body}
</x-dc>
<script data-dc-script${dp}>
${cls}
</script>
</body>
</html>
`;
}
