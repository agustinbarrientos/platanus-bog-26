import { writeFileSync, readFileSync } from 'node:fs';
import { T, W, H, TOP, BOT, DISPLAY, BODY, tino, icon, screen, topbar, card, btn, page } from './kit.mjs';
const C = JSON.parse(readFileSync(new URL('./curves.json', import.meta.url)));
const out = (n, s) => writeFileSync(new URL(`./${n}.dc.html`, import.meta.url), s);

// ── Bienvenida ────────────────────────────────────────────────────────
out('Bienvenida', page({ name: 'Bienvenida', body: screen(`
  <div style="flex-grow: 1; display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 26px; padding: ${TOP}px 32px 0; text-align: center;">
    ${tino(132, 'idle')}
    <div style="display: flex; flex-direction: column; gap: 12px; align-items: center;">
      <div style="font-family: ${DISPLAY}; font-size: 30px; font-weight: 500; line-height: 1.15;">
        Hola, soy Tino.</div>
      <div style="font-size: 16.5px; line-height: 1.55; color: ${T.ink2}; max-width: 290px; text-wrap: pretty;">
        Necesito muy poco para empezar. Con ocho datos puedo simular
        <strong style="color: ${T.ink};">diez mil versiones</strong> de tu futuro
        y mostrarte cuáles dependen de ti.</div>
    </div>
  </div>
  <div style="display: flex; flex-direction: column; gap: 10px; padding: 0 24px ${BOT + 14}px;">
    ${btn('Empieza', 'primary')}
    <div style="text-align: center; font-size: 13px; color: ${T.ink3}; padding: 8px;">
      No te voy a pedir nada que no necesite.</div>
  </div>
`) }));

// ── Datos básicos ─────────────────────────────────────────────────────
const field = (label, val, state) => {
  const done = state === 'done', now = state === 'now';
  return `<div style="display: flex; align-items: center; gap: 12px; min-height: 56px;
    padding: 0 16px; border-radius: 18px; background: ${now ? T.surface : 'transparent'};
    border: 1.5px solid ${now ? T.green : 'transparent'};">
    <div style="width: 22px; height: 22px; border-radius: 11px; flex-shrink: 0;
      background: ${done ? T.greenSoft : T.surface2}; display: flex; align-items: center; justify-content: center;">
      ${done ? icon('check', T.greenInk, 14) : ''}</div>
    <div style="flex-grow: 1; font-size: 15.5px; font-weight: 600;
      color: ${done || now ? T.ink : T.ink3};">${label}</div>
    <div style="font-size: 15.5px; font-weight: 700; font-family: ${DISPLAY};
      color: ${done ? T.greenInk : T.ink3};">${val}</div>
  </div>`;
};
const miniFan = (paths, op) => `<svg width="108" height="54" viewBox="0 0 108 54" fill="none">
  ${paths.map((d) => `<path d="${d}" stroke="${T.blue}" stroke-width="1" opacity="${op}" fill="none"/>`).join('')}
</svg>`;

out('DatosBasicos', page({ name: 'DatosBasicos', body: screen(`
  ${topbar({ title: 'Cuéntame lo básico', back: true })}
  <div style="padding: 4px 20px 0; font-size: 14.5px; color: ${T.ink2}; line-height: 1.5;">
    Voy en el dato 4 de 8. Cada respuesta angosta el abanico.</div>

  <div style="margin: 18px 20px 0; display: flex; align-items: center; gap: 14px;
    background: ${T.surface}; border: 1px solid ${T.line}; border-radius: 22px; padding: 14px 16px;">
    <div style="display: flex; flex-direction: column; gap: 4px; flex-grow: 1;">
      <div style="font-size: 12px; font-weight: 700; color: ${T.ink3}; letter-spacing: .03em;">
        TUS FUTUROS POSIBLES</div>
      <div style="font-size: 13px; color: ${T.ink2}; line-height: 1.4;">
        Se van cerrando<br>con cada dato.</div>
    </div>
    <div style="position: relative; width: 108px; height: 54px;">
      <div style="position: absolute; inset: 0; opacity: .3;">${miniFan(C.miniWide, .55)}</div>
      <div style="position: absolute; inset: 0;">${miniFan(C.miniNarrow, .75)}</div>
    </div>
  </div>

  <div style="display: flex; flex-direction: column; gap: 2px; padding: 14px 12px 0;">
    ${field('Edad', '42', 'done')}
    ${field('Sexo asignado al nacer', 'Femenino', 'done')}
    ${field('Estatura', '1,64 m', 'done')}
    ${field('Peso aproximado', '¿Cuánto pesas?', 'now')}
    ${field('¿Fumas?', '', 'pending')}
    ${field('Actividad física por semana', '', 'pending')}
    ${field('Presión arterial', '', 'pending')}
    ${field('Diabetes en tu familia', '', 'pending')}
  </div>
  <div style="padding: 14px 24px ${BOT + 10}px; margin-top: auto;">${btn('Siguiente', 'primary')}</div>
`) }));

// ── Subir exámenes ────────────────────────────────────────────────────
const upBtn = (ic, label, sub) => `<div style="display: flex; align-items: center; gap: 14px;
  min-height: 72px; padding: 14px 18px; background: ${T.surface}; border: 1px solid ${T.line};
  border-radius: 22px;">
  <div style="width: 44px; height: 44px; border-radius: 22px; background: ${T.blueSoft};
    display: flex; align-items: center; justify-content: center; flex-shrink: 0;">${icon(ic, T.blueInk, 22)}</div>
  <div style="display: flex; flex-direction: column; gap: 2px; flex-grow: 1;">
    <div style="font-size: 16px; font-weight: 700;">${label}</div>
    <div style="font-size: 13px; color: ${T.ink3};">${sub}</div>
  </div>
  ${icon('chevron', T.ink3, 18)}</div>`;

out('SubirExamenes', page({ name: 'SubirExamenes', body: screen(`
  ${topbar({ title: '¿Tienes exámenes recientes?', back: true })}
  <div style="padding: 4px 20px 0; font-size: 14.5px; color: ${T.ink2}; line-height: 1.55; text-wrap: pretty;">
    Con una foto me basta, aunque esté torcida. Si no tienes, no importa:
    puedo seguir sin ellos y decirte después qué te conviene medir.</div>
  <div style="display: flex; justify-content: center; padding: 26px 0 6px;">${tino(104, 'idle')}</div>
  <div style="display: flex; flex-direction: column; gap: 10px; padding: 12px 20px 0;">
    ${upBtn('camera', 'Tomar una foto', 'De tu último examen de sangre')}
    ${upBtn('file', 'Elegir un archivo', 'PDF o imagen desde tu teléfono')}
  </div>
  <div style="margin: 20px 20px 0; padding: 14px 16px; border-radius: 18px; background: ${T.blueSoft};
    display: flex; gap: 10px; align-items: flex-start;">
    ${icon('info', T.blueInk, 18)}
    <div style="font-size: 13.5px; color: ${T.blueInk}; line-height: 1.5;">
      Tus exámenes se quedan en tu teléfono. Solo leo los números que necesito.</div>
  </div>
  <div style="display: flex; flex-direction: column; gap: 6px; padding: 14px 24px ${BOT + 10}px; margin-top: auto;">
    ${btn('Seguir sin exámenes', 'ghost')}</div>
`) }));

// ── Confirmar lectura ─────────────────────────────────────────────────
const conf = (lvl) => {
  const m = { alta: [T.greenSoft, T.greenInk, 'Confianza alta'],
              media: [T.blueSoft, T.blueInk, 'Confianza media'],
              baja: [T.amberSoft, T.amberInk, 'Confianza baja'] }[lvl];
  return `<div style="display: inline-flex; align-items: center; height: 24px; padding: 0 10px;
    border-radius: 12px; background: ${m[0]}; color: ${m[1]}; font-size: 11.5px; font-weight: 700;">${m[2]}</div>`;
};
const row = (name, val, unit, lvl) => `<div style="display: flex; align-items: center; gap: 12px;
  min-height: 62px; padding: 12px 16px; border-radius: 20px; background: ${T.surface};
  border: 1px solid ${lvl === 'baja' ? T.amber : T.line};">
  <div style="display: flex; flex-direction: column; gap: 5px; flex-grow: 1;">
    <div style="font-size: 14.5px; font-weight: 600; color: ${T.ink2};">${name}</div>${conf(lvl)}</div>
  <div style="display: flex; align-items: baseline; gap: 4px;">
    <span style="font-family: ${DISPLAY}; font-size: 22px; font-weight: 500;">${val}</span>
    <span style="font-size: 12.5px; color: ${T.ink3}; font-weight: 600;">${unit}</span></div>
  <div style="width: 44px; height: 44px; margin-right: -10px; border-radius: 22px;
    display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
    ${icon('edit', T.ink3, 18)}</div></div>`;

out('ConfirmarLectura', page({ name: 'ConfirmarLectura', body: screen(`
  ${topbar({ title: 'Esto es lo que leí', back: true })}
  <div style="padding: 4px 20px 0; font-size: 14.5px; color: ${T.ink2}; line-height: 1.55; text-wrap: pretty;">
    Corrige lo que esté mal. Con los datos de confianza baja mi estimación se vuelve
    <strong style="color: ${T.ink};">más amplia</strong>, no más falsa.</div>
  <div style="display: flex; flex-direction: column; gap: 8px; padding: 18px 20px 0; overflow: hidden;">
    ${row('Colesterol total', '212', 'mg/dL', 'alta')}
    ${row('Colesterol HDL', '48', 'mg/dL', 'alta')}
    ${row('Glucosa en ayunas', '104', 'mg/dL', 'media')}
    ${row('Hemoglobina glicosilada', '5,7', '%', 'baja')}
    ${row('Triglicéridos', '158', 'mg/dL', 'alta')}
  </div>
  <div style="margin: 16px 20px 0; padding: 14px 16px; border-radius: 18px; background: ${T.amberSoft};
    display: flex; gap: 10px; align-items: flex-start;">
    ${icon('info', T.amberInk, 18)}
    <div style="font-size: 13.5px; color: ${T.amberInk}; line-height: 1.5;">
      La hemoglobina glicosilada la leí borrosa. Si la corriges, mi estimación se angosta bastante.</div>
  </div>
  <div style="padding: 16px 24px ${BOT + 10}px; margin-top: auto;">${btn('Construir mi gemelo', 'primary')}</div>
`) }));

console.log('flow A written: Bienvenida, DatosBasicos, SubirExamenes, ConfirmarLectura');
