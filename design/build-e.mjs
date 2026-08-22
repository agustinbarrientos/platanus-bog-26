import { writeFileSync, readFileSync } from 'node:fs';
import { T, W, H, TOP, BOT, DISPLAY, tino, icon, screen, topbar, btn, navbar, page } from './kit.mjs';
const C = JSON.parse(readFileSync(new URL('./curves.json', import.meta.url)));
const out = (n, s) => writeFileSync(new URL(`./${n}.dc.html`, import.meta.url), s);

// ── Calibración e historial ───────────────────────────────────────────
const S = 250;
const calSvg = () => `<svg width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" fill="none" style="display: block;">
  <rect x="0" y="0" width="${S}" height="${S}" rx="14" fill="${T.surface2}" opacity=".55"/>
  ${[0.25, 0.5, 0.75].map((g) => `<line x1="${g * S}" y1="0" x2="${g * S}" y2="${S}" stroke="${T.line}" stroke-width="1"/>
    <line x1="0" y1="${g * S}" x2="${S}" y2="${g * S}" stroke="${T.line}" stroke-width="1"/>`).join('')}
  <line x1="0" y1="${S}" x2="${S}" y2="0" stroke="${T.ink3}" stroke-width="1.6" stroke-dasharray="5 5" opacity=".7"/>
  <path d="M${C.calibration.map((d) => `${(d.p * S).toFixed(1)},${((1 - d.o) * S).toFixed(1)}`).join('L')}"
    stroke="${T.blueInk}" stroke-width="2.2" fill="none" stroke-linejoin="round"/>
  ${C.calibration.map((d) => `<circle cx="${(d.p * S).toFixed(1)}" cy="${((1 - d.o) * S).toFixed(1)}"
    r="5" fill="${T.surface}" stroke="${T.blueInk}" stroke-width="2.2"/>`).join('')}
</svg>`;

const stat = (big, lab, tone) => {
  const c = tone === 'green' ? [T.greenSoft, T.greenInk] : [T.blueSoft, T.blueInk];
  return `<div style="flex-grow: 1; padding: 14px; background: ${c[0]}; border-radius: 20px;
    display: flex; flex-direction: column; gap: 3px;">
    <div style="font-family: ${DISPLAY}; font-size: 27px; font-weight: 600; color: ${c[1]}; line-height: 1.1;">${big}</div>
    <div style="font-size: 11.5px; font-weight: 700; color: ${c[1]}; line-height: 1.35;">${lab}</div></div>`;
};

out('Calibracion', page({ name: 'Calibracion', body: screen(`
  ${topbar({ title: 'Qué tan bien acierto' })}
  <div style="padding: 4px 20px 0; font-size: 14px; color: ${T.ink2}; line-height: 1.5; text-wrap: pretty;">
    Me probé contra 5.000 personas reales cuyo desenlace ya se conoce, y que nunca vi
    mientras aprendía. Esto es lo que salió.</div>

  <div style="display: flex; gap: 9px; padding: 16px 20px 0;">
    ${stat('88%', 'DE LAS VECES MI RANGO DEL 90% CONTUVO EL RESULTADO', 'green')}
    ${stat('5.000', 'PERSONAS QUE NUNCA VI AL APRENDER', 'blue')}
  </div>

  <div style="margin: 14px 20px 0; padding: 16px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 26px; display: flex; flex-direction: column; gap: 10px;">
    <div style="font-size: 12px; font-weight: 700; color: ${T.ink3}; letter-spacing: .04em;">
      LO QUE PREDIJE vs. LO QUE PASÓ</div>
    <div style="display: flex; gap: 12px; align-items: flex-end;">
      <div style="display: flex; flex-direction: column; align-items: center; gap: 8px;">
        ${calSvg()}
        <div style="font-size: 11px; color: ${T.ink3}; font-weight: 600;">lo que predije &rarr;</div>
      </div>
      <div style="writing-mode: vertical-rl; transform: rotate(180deg); font-size: 11px;
        color: ${T.ink3}; font-weight: 600; padding-bottom: 26px;">lo que pasó &rarr;</div>
    </div>
    <div style="font-size: 13px; color: ${T.ink2}; line-height: 1.5; text-wrap: pretty;">
      Mientras más pegada esté la línea azul a la punteada, mejor calibrado estoy.
      Estar calibrado no es lo mismo que adivinarte a ti: por eso comparo tus escenarios
      entre sí en vez de darte una cifra sola.</div>
  </div>

  <div style="margin: 14px 20px 0; padding: 15px 16px; border-radius: 20px; background: ${T.amberSoft};
    display: flex; gap: 11px; align-items: flex-start;">
    ${icon('info', T.amberInk, 18)}
    <div style="font-size: 12.5px; color: ${T.amberInk}; line-height: 1.5; text-wrap: pretty;">
      Aprendí de NHANES (CDC), con seguimiento de mortalidad hasta 2019. Algunos registros
      públicos vienen deliberadamente alterados para proteger identidades. Sirve para orientarte;
      no sirve como diagnóstico.</div>
  </div>
  ${navbar('proof')}
`) }));

// ── Caso individual: el reveal ────────────────────────────────────────
const miniFanE = () => `<svg width="290" height="86" viewBox="0 0 330 168" preserveAspectRatio="none"
  fill="none" style="display: block;">
  <path d="${C.caseBand.area}" fill="${T.blue}" opacity=".16"/>
  <path d="${C.caseBand.median}" stroke="${T.blueInk}" stroke-width="4" fill="none"/>
  <line x1="196" y1="0" x2="196" y2="168" stroke="${T.greenInk}" stroke-width="4" stroke-dasharray="9 7"/>
</svg>`;

out('CasoIndividual', page({ name: 'CasoIndividual', body: screen(`
  ${topbar({ title: 'Una prueba real', back: true })}

  <div style="margin: 6px 20px 0; padding: 15px 16px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 22px; display: flex; flex-direction: column; gap: 9px;">
    <div style="display: flex; align-items: baseline; gap: 8px;">
      <div style="font-family: ${DISPLAY}; font-size: 18px; font-weight: 500; flex-grow: 1;">
        Participante #40213</div>
      <div style="font-size: 12px; color: ${T.ink3}; font-weight: 700;">medido en 2003</div></div>
    <div style="display: flex; gap: 7px; flex-wrap: wrap;">
      ${[['52 años', ''], ['fumador', ''], ['presión 148/92', '']].map(([v]) =>
        `<div style="padding: 7px 12px; border-radius: 14px; background: ${T.surface2};
          font-size: 12.5px; font-weight: 700; color: ${T.ink2};">${v}</div>`).join('')}
    </div>
    <div style="font-size: 13px; color: ${T.ink3}; line-height: 1.45;">
      Solo le di estos tres datos. Nada más.</div>
  </div>

  <div style="margin: 14px 20px 0; padding: 16px; background: ${T.blueSoft}; border-radius: 24px;
    display: flex; flex-direction: column; gap: 11px;">
    <div style="font-size: 12px; font-weight: 700; color: ${T.blueInk}; letter-spacing: .04em;">
      LO QUE DIJE EN ESE MOMENTO</div>
    ${miniFanE()}
    <div style="display: flex; align-items: baseline; gap: 8px;">
      <span style="font-family: ${DISPLAY}; font-size: 32px; font-weight: 600; color: ${T.blueInk};">63</span>
      <span style="font-size: 14.5px; font-weight: 700; color: ${T.blueInk};">años sin enfermedad crónica</span></div>
    <div style="font-size: 13.5px; color: ${T.blueInk};">mi rango del 90%: entre 55 y 74</div>
  </div>

  <div style="margin: 14px 20px 0; padding: 16px; background: ${T.greenSoft}; border-radius: 24px;
    display: flex; flex-direction: column; gap: 10px;">
    <div style="font-size: 12px; font-weight: 700; color: ${T.greenInk}; letter-spacing: .04em;">
      LO QUE REALMENTE PASÓ</div>
    <div style="display: flex; align-items: baseline; gap: 8px;">
      <span style="font-family: ${DISPLAY}; font-size: 32px; font-weight: 600; color: ${T.greenInk};">66</span>
      <span style="font-size: 14.5px; font-weight: 700; color: ${T.greenInk};">años &mdash; primer evento cardíaco</span></div>
    <div style="display: flex; align-items: center; gap: 8px; padding: 9px 13px; border-radius: 16px;
      background: oklch(1 0 0 / .55); align-self: flex-start;">
      ${icon('check', T.greenInk, 16)}
      <span style="font-size: 13px; font-weight: 700; color: ${T.greenInk};">Cayó dentro de mi rango</span></div>
  </div>

  <div style="margin: 14px 20px 0; padding: 14px 16px; border-radius: 20px; background: ${T.surface};
    border: 1px solid ${T.line}; display: flex; gap: 12px; align-items: center;">
    ${tino(44, 'idle')}
    <div style="font-size: 13px; color: ${T.ink2}; line-height: 1.5; flex-grow: 1; text-wrap: pretty;">
      Acertarle a una persona no prueba nada. Por eso te dejo revisar las 5.000.</div>
  </div>

  <div style="display: flex; gap: 10px; padding: 16px 20px ${BOT + 10}px; margin-top: auto;">
    <div style="width: 54px; height: 54px; border-radius: 27px; border: 1px solid ${T.line};
      background: ${T.surface}; display: flex; align-items: center; justify-content: center;">
      ${icon('back', T.ink2, 20)}</div>
    <div style="flex-grow: 1;">${btn('Ver otro caso', 'secondary')}</div>
    <div style="width: 54px; height: 54px; border-radius: 27px; border: 1px solid ${T.line};
      background: ${T.surface}; display: flex; align-items: center; justify-content: center;">
      ${icon('chevron', T.ink2, 20)}</div>
  </div>
`) }));

console.log('flow E written: Calibracion, CasoIndividual');
