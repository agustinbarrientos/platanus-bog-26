import { writeFileSync, readFileSync } from 'node:fs';
import { T, W, H, TOP, BOT, DISPLAY, tino, icon, screen, topbar, btn, navbar, calibChip, page } from './kit.mjs';
const C = JSON.parse(readFileSync(new URL('./curves.json', import.meta.url)));
const out = (n, s) => writeFileSync(new URL(`./${n}.dc.html`, import.meta.url), s);

// ── Palancas ordenadas (LIVE: tap to select) ──────────────────────────
out('Palancas', page({
  name: 'Palancas',
  css: `.lv { transition: background .18s ease, border-color .18s ease; cursor: pointer; }`,
  logic: `class Component extends DCLogic {
  constructor(props) { super(props); this.state = { sel: 0 }; }
  renderVals() {
    const data = [
      { n: 'Dejar de fumar',            d: '+4,2', b: 'entre +1,1 y +8,6', p: '87%', e: 'Esfuerzo alto' },
      { n: 'Caminar 30 min al día',     d: '+3,1', b: 'entre +0,9 y +6,4', p: '84%', e: 'Esfuerzo bajo' },
      { n: 'Bajar 6 kg y sostenerlo',   d: '+2,4', b: 'entre +0,4 y +5,5', p: '76%', e: 'Esfuerzo alto' },
      { n: 'Dormir 7 horas seguidas',   d: '+1,8', b: 'entre +0,3 y +4,0', p: '71%', e: 'Esfuerzo medio' },
      { n: 'Bajar la sal a la mitad',   d: '+0,9', b: 'entre −0,2 y +2,6', p: '58%', e: 'Esfuerzo bajo' },
    ];
    return { items: data.map((x, i) => {
      const on = i === this.state.sel;
      return { ...x, on,
        pick: () => this.setState({ sel: i }),
        bg: on ? '${T.greenSoft}' : '${T.surface}',
        bd: on ? '${T.green}' : '${T.line}',
        dc: on ? '${T.greenInk}' : '${T.ink}' };
    }) };
  }
}`,
  body: screen(`
  ${topbar({ title: 'Lo que puedes mover', chip: calibChip() })}
  <div style="padding: 4px 20px 0; font-size: 14px; color: ${T.ink2}; line-height: 1.5; text-wrap: pretty;">
    Las ordené por cuánto mueven tu distribución, no por cuánto cuestan.
    Toca una para ver los futuros pareados.</div>

  <div style="display: flex; flex-direction: column; gap: 9px; padding: 16px 20px 0;">
    <sc-for list="{{items}}" as="it" hint-placeholder-count="5">
      <div class="lv" onClick="{{it.pick}}" style="display: flex; align-items: center; gap: 13px;
        min-height: 78px; padding: 14px 16px; border-radius: 22px;
        background: {{it.bg}}; border: 1.5px solid {{it.bd}};">
        <div style="display: flex; flex-direction: column; gap: 4px; flex-grow: 1; min-width: 0;">
          <div style="font-size: 15.5px; font-weight: 700;">{{it.n}}</div>
          <div style="font-size: 12.5px; color: ${T.ink3};">{{it.b}} &middot; te ayuda en {{it.p}}</div>
          <div style="font-size: 11.5px; font-weight: 700; color: ${T.ink3};">{{it.e}}</div>
        </div>
        <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 2px; flex-shrink: 0;">
          <div style="font-family: ${DISPLAY}; font-size: 26px; font-weight: 600; color: {{it.dc}};">{{it.d}}</div>
          <div style="font-size: 10.5px; font-weight: 700; color: ${T.ink3};">años sanos</div>
        </div>
      </div>
    </sc-for>
  </div>

  <div style="margin: 16px 20px 0; padding: 14px 16px; border-radius: 20px; background: ${T.blueSoft};
    display: flex; gap: 11px; align-items: flex-start;">
    ${icon('info', T.blueInk, 18)}
    <div style="font-size: 13px; color: ${T.blueInk}; line-height: 1.5; text-wrap: pretty;">
      Los rangos son anchos a propósito. Confío mucho más en el orden de esta lista
      que en cualquiera de los números por separado.</div>
  </div>
  ${navbar('sim')}
`) }));

// ── Detalle de palanca: trayectorias pareadas ─────────────────────────
const pairSvg = () => `<svg width="322" height="150" viewBox="0 0 322 150" fill="none" style="display: block;">
  ${C.pairBase.map((d) => `<path d="${d}" stroke="${T.ink3}" stroke-width="1" fill="none" opacity=".30"/>`).join('')}
  ${C.pairBetter.map((d) => `<path d="${d}" stroke="${T.green}" stroke-width="1.15" fill="none" opacity=".55"/>`).join('')}
</svg>`;

out('DetallePalanca', page({ name: 'DetallePalanca', body: screen(`
  ${topbar({ title: 'Dejar de fumar', back: true, chip: calibChip() })}
  <div style="padding: 4px 20px 0; font-size: 14px; color: ${T.ink2}; line-height: 1.5; text-wrap: pretty;">
    Corrí <strong style="color: ${T.ink};">los mismos</strong> diez mil futuros otra vez,
    cambiando solo esto. Cada línea verde es la pareja exacta de una gris.</div>

  <div style="margin: 16px 20px 0; padding: 16px 14px 12px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 26px;">
    ${pairSvg()}
    <div style="display: flex; justify-content: space-between; padding: 8px 0 12px;
      font-size: 11px; color: ${T.ink3}; font-weight: 600;">
      <span>42</span><span>55</span><span>68</span><span>82</span><span>96 años</span></div>
    <div style="display: flex; gap: 18px; padding-top: 2px; border-top: 1px solid ${T.line};
      margin-top: 2px; padding-top: 12px;">
      <div style="display: flex; align-items: center; gap: 7px;">
        <div style="width: 18px; height: 2.5px; border-radius: 2px; background: ${T.ink3};"></div>
        <span style="font-size: 12.5px; color: ${T.ink2}; font-weight: 600;">Si sigues igual</span></div>
      <div style="display: flex; align-items: center; gap: 7px;">
        <div style="width: 18px; height: 2.5px; border-radius: 2px; background: ${T.green};"></div>
        <span style="font-size: 12.5px; color: ${T.ink2}; font-weight: 600;">Si lo dejas</span></div>
    </div>
  </div>

  <div style="display: flex; gap: 9px; padding: 16px 20px 0;">
    <div style="flex-grow: 1; padding: 14px; background: ${T.greenSoft}; border-radius: 20px;
      display: flex; flex-direction: column; gap: 3px;">
      <div style="font-family: ${DISPLAY}; font-size: 30px; font-weight: 600; color: ${T.greenInk};">+4,2</div>
      <div style="font-size: 11.5px; font-weight: 700; color: ${T.greenInk};">AÑOS SANOS</div>
      <div style="font-size: 12px; color: ${T.ink2}; padding-top: 2px;">entre +1,1 y +8,6</div>
    </div>
    <div style="flex-grow: 1; padding: 14px; background: ${T.blueSoft}; border-radius: 20px;
      display: flex; flex-direction: column; gap: 3px;">
      <div style="font-family: ${DISPLAY}; font-size: 30px; font-weight: 600; color: ${T.blueInk};">87%</div>
      <div style="font-size: 11.5px; font-weight: 700; color: ${T.blueInk};">DE TUS FUTUROS</div>
      <div style="font-size: 12px; color: ${T.ink2}; padding-top: 2px;">mejoran con esto</div>
    </div>
  </div>

  <div style="margin: 14px 20px 0; padding: 14px 16px; border-radius: 20px; background: ${T.surface};
    border: 1px solid ${T.line}; display: flex; gap: 12px; align-items: center;">
    ${tino(44, 'idle')}
    <div style="font-size: 13.5px; color: ${T.ink2}; line-height: 1.5; flex-grow: 1;">
      En el 13% restante no te hace daño: simplemente algo más pasa primero.</div>
  </div>

  <div style="padding: 16px 24px ${BOT + 10}px; margin-top: auto;">
    ${btn('¿Y si no lo sostengo?', 'primary')}</div>
`) }));

// ── Adherencia (LIVE slider) ──────────────────────────────────────────
out('Adherencia', page({
  name: 'Adherencia',
  css: `.stop { cursor: pointer; transition: transform .16s ease; }
        .stop:hover { transform: scale(1.08); }
        .thumb { transition: left .22s cubic-bezier(.34,1.3,.5,1); }`,
  logic: `class Component extends DCLogic {
  constructor(props) { super(props); this.state = { i: 1 }; }
  renderVals() {
    const opts = [
      { lab: '3 meses',  d: '+0,6', pct: '38%', note: 'Poco, pero no es cero. Nunca es cero.' },
      { lab: '8 meses',  d: '+1,3', pct: '61%', note: 'Aunque aflojes después, esto se te queda.' },
      { lab: '2 años',   d: '+2,9', pct: '79%', note: 'Aquí el cuerpo ya cambió lo que tenía que cambiar.' },
      { lab: 'Siempre',  d: '+4,2', pct: '87%', note: 'El escenario ideal. Casi nadie vive aquí, y está bien.' },
    ];
    const i = this.state.i;
    return {
      cur: opts[i],
      thumbLeft: 'calc(' + (i * 33.333) + '% - ' + (i * 22 - 0) + 'px)',
      stops: opts.map((o, k) => ({ lab: o.lab,
        pick: () => this.setState({ i: k }),
        dot: k <= i ? '${T.green}' : '${T.line}',
        col: k === i ? '${T.greenInk}' : '${T.ink3}',
        wt: k === i ? 700 : 600 })),
    };
  }
}`,
  body: screen(`
  ${topbar({ title: 'Dejar de fumar', back: true, chip: calibChip() })}
  <div style="padding: 14px 24px 0; display: flex; flex-direction: column; align-items: center;
    gap: 14px; text-align: center;">
    ${tino(88, 'gentle')}
    <div style="font-family: ${DISPLAY}; font-size: 25px; font-weight: 500; line-height: 1.2;">
      ¿Cuánto tiempo<br>lo sostienes?</div>
    <div style="font-size: 14.5px; color: ${T.ink2}; line-height: 1.55; max-width: 300px; text-wrap: pretty;">
      Nadie lo sostiene todo. Prefiero simular lo que de verdad va a pasar
      y no lo que se supone que debo decirte.</div>
  </div>

  <div style="margin: 26px 24px 0;">
    <div style="position: relative; height: 44px;">
      <div style="position: absolute; top: 19px; left: 11px; right: 11px; height: 6px;
        border-radius: 3px; background: ${T.surface2};"></div>
      <div style="display: flex; justify-content: space-between; position: relative;">
        <sc-for list="{{stops}}" as="s" hint-placeholder-count="4">
          <div class="stop" onClick="{{s.pick}}" style="display: flex; flex-direction: column;
            align-items: center; gap: 8px; width: 72px; padding-top: 13px;">
            <div style="width: 18px; height: 18px; border-radius: 9px; background: {{s.dot}};
              border: 3px solid ${T.surface}; box-shadow: 0 0 0 1px {{s.dot}};"></div>
            <span style="font-size: 12.5px; font-weight: {{s.wt}}; color: {{s.col}};">{{s.lab}}</span>
          </div>
        </sc-for>
      </div>
    </div>
  </div>

  <div style="margin: 24px 20px 0; padding: 20px 18px; background: ${T.greenSoft};
    border-radius: 26px; display: flex; flex-direction: column; gap: 10px; align-items: center;">
    <div style="display: flex; align-items: baseline; gap: 9px;">
      <span style="font-family: ${DISPLAY}; font-size: 52px; font-weight: 600; line-height: 1;
        color: ${T.greenInk};">{{cur.d}}</span>
      <span style="font-family: ${DISPLAY}; font-size: 19px; font-weight: 500; color: ${T.greenInk};">
        años sanos</span></div>
    <div style="font-size: 14px; font-weight: 700; color: ${T.greenInk};">
      te ayuda en {{cur.pct}} de tus futuros</div>
    <div style="font-size: 14px; color: ${T.ink2}; line-height: 1.5; text-align: center;
      padding-top: 4px; text-wrap: pretty;">{{cur.note}}</div>
  </div>

  <div style="padding: 18px 24px ${BOT + 10}px; margin-top: auto;">
    ${btn('Guardar como mi plan', 'primary')}</div>
`) }));

console.log('flow D written: Palancas (live), DetallePalanca, Adherencia (live)');
