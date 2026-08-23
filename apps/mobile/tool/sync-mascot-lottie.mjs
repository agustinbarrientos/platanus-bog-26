#!/usr/bin/env node
/**
 * Copia el Lottie de la medusa desde la web a los assets de la app.
 *
 *   node apps/mobile/tool/sync-mascot-lottie.mjs
 *
 * Es la MISMA animación que se ve en `apps/web` (`moirai-plain.json`, la
 * versión que se queda quieta en su sitio); la única transformación es hornear
 * las expresiones de After Effects.
 *
 * Por qué hornear: cinco capas ("tail 2L 2", "tail 2R 2", "tail 2", "tail 3L 2",
 * "tail 3R 2") son el resplandor desenfocado de los tentáculos y toman su
 * trazado de la capa original con una expresión
 * (`thisComp.layer('tail 2L').content('Vector 8').content('Path 1').path`).
 * lottie-web evalúa expresiones; el paquete `lottie` de Dart no, así que ahí se
 * quedarían congeladas en el trazado exportado mientras los tentáculos se
 * mueven. Copiar los keyframes de la capa fuente da exactamente lo que la
 * expresión calcula, sin depender de un intérprete.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const origen = join(aqui, '../../web/public/moirai/moirai-plain.json');
const destino = join(aqui, '../assets/moirai/moirai-mascot.json');

const anim = JSON.parse(readFileSync(origen, 'utf8'));
const porNombre = new Map(anim.layers.map((l) => [l.nm, l]));

/** `thisComp.layer('X').content('A').content('B').path` → ['X', 'A', 'B']. */
const LINK = /thisComp\.layer\('([^']+)'\)\.content\('([^']+)'\)\.content\('([^']+)'\)\.path/;

const contenido = (items, nombre) => items?.find((i) => i.nm === nombre);

let horneadas = 0;
const hornear = (nodo) => {
  if (Array.isArray(nodo)) return nodo.forEach(hornear);
  if (!nodo || typeof nodo !== 'object') return;

  if (typeof nodo.x === 'string' && LINK.test(nodo.x)) {
    const [, capa, grupo, trazado] = nodo.x.match(LINK);
    const fuente = porNombre.get(capa);
    const origenTrazado = contenido(contenido(fuente?.shapes, grupo)?.it, trazado);
    if (!origenTrazado) throw new Error(`No encontré ${capa} > ${grupo} > ${trazado}`);
    const { ix } = nodo;
    for (const k of Object.keys(nodo)) delete nodo[k];
    Object.assign(nodo, structuredClone(origenTrazado.ks), ix === undefined ? {} : { ix });
    horneadas++;
    return;
  }

  for (const v of Object.values(nodo)) hornear(v);
};

hornear(anim.layers);
if (!horneadas) throw new Error('No horneé ninguna expresión: ¿cambió el Lottie de la web?');

writeFileSync(destino, JSON.stringify(anim));
console.log(`${horneadas} expresiones horneadas → ${destino}`);
