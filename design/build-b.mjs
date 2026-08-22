import { writeFileSync, readFileSync } from 'node:fs';
import { T, W, H, TOP, BOT, DISPLAY, tino, icon, screen, topbar, btn, page } from './kit.mjs';
const C = JSON.parse(readFileSync(new URL('./curves.json', import.meta.url)));
const out = (n, s) => writeFileSync(new URL(`./${n}.dc.html`, import.meta.url), s);

// ── Simulando en vivo (LIVE: counter climbs, lines appear) ────────────
out('SimulandoEnVivo', page({
  name: 'SimulandoEnVivo',
  css: `.simline { transition: opacity .35s ease; }`,
  props: '{"ritmo":{"editor":"range","default":140,"min":40,"max":400,"step":20,"unit":"/tick","section":"Simulación"}}',
  logic: `class Component extends DCLogic {
  constructor(props) { super(props); this.state = { n: 0 }; }
  componentDidMount() {
    const step = () => this.setState((s) => ({ n: s.n >= 10000 ? 0 : Math.min(10000, s.n + (this.props.ritmo ?? 140)) }));
    this.timer = setInterval(step, 55);
  }
  componentWillUnmount() { clearInterval(this.timer); }
  renderVals() {
    const paths = ${JSON.stringify(C.simFan)};
    const n = this.state.n;
    const frac = n / 10000;
    const revealed = Math.floor(frac * paths.length);
    return {
      n: n.toLocaleString('es-CO'),
      barW: (frac * 100).toFixed(1) + '%',
      lines: paths.map((d, i) => ({ d, op: i < revealed ? 0.30 : 0, w: i === revealed - 1 ? 1.8 : 1.05 })),
    };
  }
}`,
  body: screen(`
  <div style="padding: ${TOP + 12}px 28px 0; display: flex; flex-direction: column;
    align-items: center; gap: 14px; text-align: center;">
    ${tino(96, 'working')}
    <div style="font-family: ${DISPLAY}; font-size: 25px; font-weight: 500; line-height: 1.2;">
      Estoy recorriendo tus futuros</div>
    <div style="font-size: 15px; color: ${T.ink2}; line-height: 1.5; max-width: 300px; text-wrap: pretty;">
      Cada línea es una versión posible de tu vida. Ninguna es una predicción por sí sola.</div>
  </div>

  <div style="margin: 22px 20px 0; padding: 18px 16px 14px; background: ${T.surface};
    border: 1px solid ${T.line}; border-radius: 26px;">
    <svg width="318" height="190" viewBox="0 0 318 190" fill="none" style="display: block;">
      <line x1="0" y1="189" x2="318" y2="189" stroke="${T.line}" stroke-width="1"/>
      <sc-for list="{{lines}}" as="ln" hint-placeholder-count="34">
        <path class="simline" d="{{ln.d}}" stroke="${T.blue}" fill="none"
          stroke-width="{{ln.w}}" opacity="{{ln.op}}" stroke-linecap="round"/>
      </sc-for>
    </svg>
    <div style="display: flex; justify-content: space-between; padding-top: 6px;
      font-size: 11px; color: ${T.ink3}; font-weight: 600;">
      <span>42</span><span>55</span><span>68</span><span>82</span><span>96 años</span></div>
  </div>

  <div style="padding: 26px 28px 0; display: flex; flex-direction: column; gap: 12px; align-items: center;">
    <div style="display: flex; align-items: baseline; gap: 8px;">
      <span style="font-family: ${DISPLAY}; font-size: 44px; font-weight: 600;
        color: ${T.greenInk}; font-variant-numeric: tabular-nums;">{{n}}</span>
      <span style="font-size: 16px; color: ${T.ink2}; font-weight: 600;">de 10.000</span></div>
    <div style="width: 100%; height: 8px; border-radius: 4px; background: ${T.surface2}; overflow: hidden;">
      <div style="height: 8px; border-radius: 4px; background: ${T.green}; width: {{barW}};"></div></div>
    <div style="font-size: 13.5px; color: ${T.ink3};">vidas simuladas</div>
  </div>

  <div style="padding: 18px 24px ${BOT + 10}px; margin-top: auto;">
    ${btn('Avísame y déjame salir', 'secondary')}</div>
`) }));

// ── Simulando en segundo plano ────────────────────────────────────────
out('SimulandoFondo', page({ name: 'SimulandoFondo', body: screen(`
  ${topbar({ title: '' })}
  <div style="flex-grow: 1; display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 24px; padding: 0 32px; text-align: center;">
    ${tino(120, 'working')}
    <div style="display: flex; flex-direction: column; gap: 12px; align-items: center;">
      <div style="font-family: ${DISPLAY}; font-size: 27px; font-weight: 500; line-height: 1.2;">
        Sigo trabajando en esto</div>
      <div style="font-size: 16px; color: ${T.ink2}; line-height: 1.55; max-width: 290px; text-wrap: pretty;">
        Me toma un par de minutos hacerlo bien. Te aviso apenas termine
        &mdash; puedes cerrar la app tranquila.</div>
    </div>
    <div style="display: flex; align-items: center; gap: 8px; padding: 10px 16px; border-radius: 20px;
      background: ${T.blueSoft};">
      ${icon('clock', T.blueInk, 16)}
      <span style="font-size: 13.5px; font-weight: 700; color: ${T.blueInk};">
        Van 3.100 de 10.000</span></div>
  </div>
  <div style="display: flex; flex-direction: column; gap: 10px; padding: 0 24px ${BOT + 14}px;">
    ${btn('Avísame cuando esté listo', 'primary')}
    ${btn('Prefiero esperar aquí', 'ghost')}
  </div>
`) }));

// ── Notificación push (lock screen: clock is content, no status bar) ──
out('Notificacion', page({ name: 'Notificacion', body: screen(`
  <div style="position: absolute; inset: 0; background:
    radial-gradient(120% 80% at 50% 0%, ${T.blueSoft} 0%, ${T.bg} 55%, ${T.greenSoft} 130%);"></div>
  <div style="position: relative; padding: ${TOP + 40}px 0 0; display: flex; flex-direction: column;
    align-items: center; gap: 2px;">
    <div style="font-family: ${DISPLAY}; font-size: 76px; font-weight: 400; letter-spacing: -.02em;
      color: ${T.ink}; line-height: 1;">7:12</div>
    <div style="font-size: 15px; color: ${T.ink2}; font-weight: 600;">martes, 3 de junio</div>
  </div>
  <div style="position: relative; margin: 46px 14px 0; padding: 16px; border-radius: 26px;
    background: oklch(1 0.002 215 / .82); border: 1px solid oklch(1 0 0 / .7);
    box-shadow: 0 8px 28px oklch(0.45 0.05 240 / .12); display: flex; gap: 13px; align-items: flex-start;">
    <div style="width: 42px; height: 42px; border-radius: 13px; background: ${T.greenSoft};
      display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
      ${tino(30, 'happy')}</div>
    <div style="display: flex; flex-direction: column; gap: 3px; flex-grow: 1;">
      <div style="display: flex; align-items: baseline; gap: 8px;">
        <span style="font-size: 14px; font-weight: 700; font-family: ${DISPLAY};">Tino</span>
        <span style="font-size: 12px; color: ${T.ink3};">ahora</span></div>
      <div style="font-size: 15px; font-weight: 700; line-height: 1.3;">Ya terminé de simular</div>
      <div style="font-size: 14px; color: ${T.ink2}; line-height: 1.45; text-wrap: pretty;">
        Recorrí 10.000 versiones de tu vida. Encontré tres cosas que sí dependen de ti.</div>
    </div>
  </div>
  <div style="position: relative; margin-top: auto; padding: 0 24px ${BOT + 18}px;
    display: flex; flex-direction: column; align-items: center; gap: 6px;">
    <div style="font-size: 13px; color: ${T.ink3};">Desliza para abrir</div>
    <div style="width: 128px; height: 5px; border-radius: 3px; background: ${T.ink3}; opacity: .35;"></div>
  </div>
`) }));

console.log('flow B written: SimulandoEnVivo (live), SimulandoFondo, Notificacion');
