import { writeFileSync, readFileSync } from 'node:fs';
import { T, W, H, TOP, BOT, DISPLAY, tino, icon, screen, topbar, card, btn, navbar, calibChip, page } from './kit.mjs';
const C = JSON.parse(readFileSync(new URL('./curves.json', import.meta.url)));
const out = (n, s) => writeFileSync(new URL(`./${n}.dc.html`, import.meta.url), s);

// The hero fan: 90% band + individual simulated lives + median.
const fanSvg = (w = 330, h = 168) => `
<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" fill="none" style="display: block;">
  <defs><clipPath id="fc"><rect x="0" y="0" width="${w}" height="${h}"/></clipPath></defs>
  <g clip-path="url(#fc)">
    <path d="${C.mainBand.area}" fill="${T.blue}" opacity=".13"/>
    ${C.mainFan.map((d) => `<path d="${d}" stroke="${T.blue}" stroke-width="1" fill="none" opacity=".22"/>`).join('')}
    <path d="${C.mainBand.median}" stroke="${T.blueInk}" stroke-width="2.6" fill="none"
      stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <line x1="159" y1="0" x2="159" y2="${h}" stroke="${T.greenInk}" stroke-width="1.6"
    stroke-dasharray="4 4" opacity=".65"/>
  <circle cx="159" cy="62" r="5.5" fill="${T.greenInk}"/>
  <circle cx="159" cy="62" r="10" fill="${T.greenInk}" opacity=".18"/>
</svg>`;

const leverCard = (name, delta, band, prob, effort, tone = 'green') => {
  const c = tone === 'green' ? [T.greenSoft, T.greenInk] : [T.blueSoft, T.blueInk];
  return `<div style="display: flex; align-items: center; gap: 13px; min-height: 74px; padding: 14px 16px;
    background: ${T.surface}; border: 1px solid ${T.line}; border-radius: 22px;">
    <div style="display: flex; flex-direction: column; gap: 3px; flex-grow: 1; min-width: 0;">
      <div style="font-size: 15.5px; font-weight: 700;">${name}</div>
      <div style="font-size: 12.5px; color: ${T.ink3};">${band} &middot; ayuda en ${prob} de tus futuros</div>
    </div>
    <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 3px; flex-shrink: 0;">
      <div style="font-family: ${DISPLAY}; font-size: 21px; font-weight: 600; color: ${c[1]};">${delta}</div>
      <div style="font-size: 11px; font-weight: 700; color: ${T.ink3};">${effort}</div>
    </div></div>`;
};

// ── Main: el gemelo ───────────────────────────────────────────────────
out('Main', page({ name: 'Main', body: screen(`
  ${topbar({ title: 'Tu gemelo', chip: calibChip() })}

  <div style="padding: 10px 20px 0; display: flex; flex-direction: column; gap: 6px;">
    <div style="font-size: 12px; font-weight: 700; color: ${T.ink3}; letter-spacing: .04em;">
      AÑOS SIN ENFERMEDAD CRÓNICA</div>
    <div style="display: flex; align-items: baseline; gap: 10px;">
      <span style="font-family: ${DISPLAY}; font-size: 60px; font-weight: 600; line-height: 1;
        color: ${T.greenInk};">68</span>
      <span style="font-family: ${DISPLAY}; font-size: 24px; font-weight: 500; color: ${T.ink2};">años</span>
    </div>
    <div style="display: flex; align-items: center; gap: 7px;">
      <div style="width: 30px; height: 4px; border-radius: 2px; background: ${T.blue}; opacity: .45;"></div>
      <span style="font-size: 14.5px; color: ${T.ink2}; font-weight: 600;">entre 61 y 75</span></div>
    <div style="font-size: 13px; color: ${T.ink3}; line-height: 1.45; padding-top: 2px; text-wrap: pretty;">
      Ese rango no es un detalle: es lo que todavía no sé de ti.</div>
  </div>

  <div style="margin: 14px 20px 0; padding: 14px 10px 10px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 26px;">
    ${fanSvg()}
    <div style="display: flex; justify-content: space-between; padding: 6px 4px 0;
      font-size: 11px; color: ${T.ink3}; font-weight: 600;">
      <span>42</span><span>55</span><span>68</span><span>82</span><span>96 años</span></div>
  </div>

  <div style="padding: 18px 20px 0; display: flex; flex-direction: column; gap: 8px;">
    <div style="font-family: ${DISPLAY}; font-size: 17px; font-weight: 500;">Lo que puedes mover</div>
    ${leverCard('Caminar 30 min al día', '+3,1', 'entre +0,9 y +6,4', '84%', 'esfuerzo bajo')}
    ${leverCard('Dormir 7 horas seguidas', '+1,8', 'entre +0,3 y +4,0', '71%', 'esfuerzo medio', 'blue')}
  </div>

  <div style="padding: 16px 20px 16px; display: flex; align-items: center; justify-content: center; gap: 6px;">
    <span style="font-size: 13.5px; color: ${T.ink3}; font-weight: 600;">Ver la curva de supervivencia</span>
    ${icon('chevron', T.ink3, 15)}</div>
  ${navbar('twin')}
`) }));

// ── Estado "estás bien" ───────────────────────────────────────────────
out('EstasBien', page({ name: 'EstasBien', body: screen(`
  ${topbar({ title: 'Tu gemelo', chip: calibChip() })}
  <div style="padding: 18px 24px 0; display: flex; flex-direction: column; align-items: center;
    gap: 18px; text-align: center;">
    ${tino(116, 'happy')}
    <div style="display: flex; flex-direction: column; gap: 10px; align-items: center;">
      <div style="font-family: ${DISPLAY}; font-size: 26px; font-weight: 500; line-height: 1.2;">
        No encontré nada<br>que requiera acción</div>
      <div style="font-size: 15.5px; color: ${T.ink2}; line-height: 1.55; max-width: 300px; text-wrap: pretty;">
        En serio. Revisé tus diez mil futuros y ninguno cambia mucho
        con lo que podrías hacer distinto hoy.</div>
    </div>
  </div>
  <div style="margin: 22px 20px 0;">
    <div style="padding: 16px; background: ${T.greenSoft}; border-radius: 22px;
      display: flex; flex-direction: column; gap: 6px;">
      <div style="font-size: 13.5px; font-weight: 700; color: ${T.greenInk};">Lo único que te sugiero</div>
      <div style="font-size: 15px; color: ${T.ink}; line-height: 1.5;">
        Seguir como vas. Lo que ya haces es la razón por la que este resultado se ve así.</div>
    </div>
  </div>
  <div style="margin: 12px 20px 0; padding: 15px 16px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 22px; display: flex; align-items: center; gap: 12px;">
    ${icon('clock', T.ink3, 20)}
    <div style="flex-grow: 1; font-size: 14.5px; color: ${T.ink2}; line-height: 1.45;">
      Vuelve en seis meses, o cuando tengas exámenes nuevos.</div>
  </div>
  <div style="padding: 16px 20px 0; text-align: center; font-size: 13px; color: ${T.ink3};
    line-height: 1.5;">No te voy a inventar un problema para que vuelvas.</div>
  ${navbar('twin')}
`) }));

// ── Qué conviene medir (bottom sheet) ─────────────────────────────────
const voiRow = (name, pct, w, note) => `<div style="display: flex; flex-direction: column; gap: 8px;
  padding: 15px 16px; background: ${T.surface}; border: 1px solid ${T.line}; border-radius: 20px;">
  <div style="display: flex; align-items: baseline; gap: 10px;">
    <div style="flex-grow: 1; font-size: 15.5px; font-weight: 700;">${name}</div>
    <div style="font-family: ${DISPLAY}; font-size: 20px; font-weight: 600; color: ${T.blueInk};">${pct}</div>
  </div>
  <div style="height: 7px; border-radius: 4px; background: ${T.surface2}; overflow: hidden;">
    <div style="height: 7px; width: ${w}; border-radius: 4px; background: ${T.blue};"></div></div>
  <div style="font-size: 12.5px; color: ${T.ink3};">${note}</div></div>`;

out('QueMedir', page({ name: 'QueMedir', body: screen(`
  <div style="opacity: .38; filter: blur(1.5px); pointer-events: none;">
    ${topbar({ title: 'Tu gemelo', chip: calibChip() })}
    <div style="padding: 10px 20px 0;">
      <div style="font-size: 12px; font-weight: 700; color: ${T.ink3};">AÑOS SIN ENFERMEDAD CRÓNICA</div>
      <div style="font-family: ${DISPLAY}; font-size: 60px; font-weight: 600; color: ${T.greenInk};">68</div>
    </div>
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; top: 148px; background: ${T.surface};
    border-radius: 30px 30px 0 0; box-shadow: 0 -10px 40px oklch(0.45 0.05 240 / .10);
    display: flex; flex-direction: column;">
    <div style="display: flex; justify-content: center; padding: 12px 0 4px;">
      <div style="width: 44px; height: 5px; border-radius: 3px; background: ${T.line};"></div></div>
    <div style="padding: 10px 20px 0; display: flex; gap: 14px; align-items: flex-start;">
      ${tino(56, 'idle')}
      <div style="display: flex; flex-direction: column; gap: 6px; flex-grow: 1;">
        <div style="font-family: ${DISPLAY}; font-size: 22px; font-weight: 500; line-height: 1.2;">
          ¿Qué te conviene medir?</div>
        <div style="font-size: 14px; color: ${T.ink2}; line-height: 1.5; text-wrap: pretty;">
          Medir esto no cambia tu salud. Cambia lo que yo sé de ti &mdash; y por eso angosta el rango.</div>
      </div>
    </div>
    <div style="display: flex; flex-direction: column; gap: 9px; padding: 18px 20px 0;">
      ${voiRow('Hemoglobina glicosilada', '−40%', '86%', 'La que más me falta ahora mismo')}
      ${voiRow('Presión arterial', '−18%', '40%', 'Fácil de conseguir en cualquier farmacia')}
      ${voiRow('Colesterol HDL', '−6%', '14%', 'Ya tengo una lectura reciente')}
    </div>
    <div style="padding: 16px 24px ${BOT + 12}px; margin-top: auto;">
      ${btn('Agendar lo primero', 'primary')}</div>
  </div>
`) }));

// ── Curva de supervivencia (detrás de divulgación progresiva) ─────────
out('CurvaSupervivencia', page({ name: 'CurvaSupervivencia', body: screen(`
  ${topbar({ title: 'Supervivencia', back: true })}
  <div style="margin: 8px 20px 0; padding: 16px; border-radius: 22px; background: ${T.amberSoft};
    display: flex; gap: 13px; align-items: flex-start;">
    ${tino(52, 'gentle')}
    <div style="display: flex; flex-direction: column; gap: 5px; flex-grow: 1;">
      <div style="font-size: 15px; font-weight: 700; color: ${T.amberInk};">
        Esta pantalla habla de mortalidad</div>
      <div style="font-size: 13.5px; color: ${T.amberInk}; line-height: 1.5; text-wrap: pretty;">
        La dejo aquí porque tienes derecho a verla, no porque te convenga mirarla seguido.
        Lo accionable está en la pantalla anterior.</div>
    </div>
  </div>

  <div style="margin: 16px 20px 0; padding: 16px 14px 12px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 26px;">
    <div style="font-size: 12px; font-weight: 700; color: ${T.ink3}; letter-spacing: .04em; padding-bottom: 10px;">
      PROBABILIDAD DE SEGUIR CON VIDA</div>
    <svg width="322" height="128" viewBox="0 0 322 128" fill="none" style="display: block;">
      ${[0, 32, 64, 96, 128].map((y) => `<line x1="0" y1="${y}" x2="322" y2="${y}"
        stroke="${T.line}" stroke-width="1"/>`).join('')}
      <path d="${C.survival}" stroke="${T.blueInk}" stroke-width="2.6" fill="none"
        stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    <div style="display: flex; justify-content: space-between; padding-top: 6px;
      font-size: 11px; color: ${T.ink3}; font-weight: 600;">
      <span>42</span><span>55</span><span>68</span><span>82</span><span>96 años</span></div>
  </div>

  <div style="margin: 18px 20px 0; padding: 16px; background: ${T.blueSoft}; border-radius: 22px;">
    <div style="font-size: 14px; color: ${T.blueInk}; line-height: 1.55; text-wrap: pretty;">
      Recuerda lo que esta curva es: describe a diez mil personas compatibles con lo poco
      que sé de ti. <strong>No te describe a ti.</strong> Por eso comparo tus escenarios
      entre sí, en vez de darte fechas.</div>
  </div>

  <div style="padding: 18px 24px ${BOT + 12}px; margin-top: auto;">
    ${btn('Volver a lo que puedo cambiar', 'secondary')}</div>
`) }));

console.log('flow C written: Main, EstasBien, QueMedir, CurvaSupervivencia');
