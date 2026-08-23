"""Arma el reporte (docs/MOIRAI_REPORTE_SPEC.md §1) a partir del MOTOR REAL:
`phenoage.compute` (foto de hoy + contribuciones + percentil) y
`montecarlo.simular` (curvas, escenarios pareados, valor de información), más
las tablas de reglas de `reference_ranges` (rangos), `ejes` (ejes + triage) y
`evidencia` (literatura por palanca).

Principios (spec §0, §4):
- Ningún número viene de datos de ejemplo ni del mock: todo se recalcula aquí
  con la misma semilla por defecto que usa la app, así el reporte coincide con
  lo que la persona vio en pantalla.
- Ninguna frase nombra una enfermedad ni prescribe nada. Los textos son
  plantillas fijas; `tests/test_report.py` pasa una lista de palabras
  prohibidas sobre todo el texto generado.
- Lo que el motor NO produce no se inventa: si falta, se dice ("sin datos").

El único escenario que el motor no corre por defecto y el reporte sí pide
(spec §3, "si te descuidas") se calcula con el mismo motor y la misma
semilla: la línea base con TODAS las brechas de hábito abiertas
(`brechas = 1` en los seis hábitos), pareada con la base de la persona. Es la
misma maquinaria con la que el motor explica `contribuciones_habitos`; no es
una predicción de enfermedad ni una amenaza — es "dónde quedaría el reloj si
los hábitos se deterioraran del todo".
"""

from __future__ import annotations

import secrets
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from itertools import combinations
from typing import Any

from app.health_metrics import montecarlo, phenoage
from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.ejes import DISCLAIMER_TRIAGE, NIVEL_TEXTO, evaluar_ejes, triage
from app.health_metrics.evidencia import FUENTES_GENERALES, evidencia_de
from app.health_metrics.interventions import (
    HABITOS,
    MAX_INTERVENCIONES,
    PALANCAS,
    SCENARIOS,
    aplica,
    brecha_efectiva,
    brechas_desde_habitos,
)
from app.health_metrics.reference_ranges import ETIQUETAS, clasificar

VERSION_REPORTE = "1.0.0"

DISCLAIMER = (
    "Documento orientativo, no diagnóstico. Moirai estima y orienta; no reemplaza "
    "a tu médico. Compártelo con un profesional de salud."
)
PRIVACIDAD = "Datos procesados de forma privada; este documento no constituye historia clínica."

NOTA_POBLACIONAL = (
    "Los rangos de referencia y la población de comparación vienen mayormente de "
    "poblaciones europeas y estadounidenses (NHANES); para ascendencia mixta o "
    "latinoamericana pueden no ajustar igual de bien."
)

NOTA_INCERTIDUMBRE = (
    "Estimación, no certeza: el rango refleja lo que no sé de ti (lo que no está "
    "medido y la variabilidad biológica año a año). Los años ganados son la "
    "diferencia, trayectoria por trayectoria, entre la misma vida con y sin la "
    "palanca (futuros pareados, misma semilla)."
)

#: Cómo se ve cada unidad en el reporte.
_UNIDAD_BONITA = {"10^3/uL": "×10³/µL", "kg/m2": "kg/m²"}

#: Cómo explicar el efecto de una palanca sobre cada biomarcador en lenguaje humano.
_EFECTO_HUMANO = {
    "hs_CRP": "baja la inflamación (proteína C reactiva)",
    "glucosa": "baja la glucosa en ayunas",
    "leucocitos": "baja el recuento de leucocitos",
    "vcm": "normaliza el tamaño de los glóbulos rojos (VCM)",
    "albumina": "sostiene la albúmina",
    "creatinina": "cuida la creatinina",
    "fosfatasa_alcalina": "cuida la fosfatasa alcalina",
    "linfocitos_pct": "sostiene los linfocitos",
    "rdw": "cuida el RDW",
}

_HABITO_HUMANO = {
    "actividad": "actividad física",
    "alimentacion": "alimentación",
    "tabaco": "tabaco",
    "sueno": "sueño",
    "estres": "estrés",
    "alcohol": "alcohol",
}


def fmt(x: float | None, nd: int = 1) -> str:
    """Número en formato es-CO: 6,4 · 8.240 · un decimal máximo."""
    if x is None:
        return "—"
    s = f"{x:,.{nd}f}"  # 8,240.5
    ent, _, dec = s.partition(".")
    ent = ent.replace(",", ".")
    return ent + ("," + dec if dec else "")


def fmt_delta(x: float, nd: int = 1) -> str:
    if abs(x) < 0.05:
        return "0"
    return ("+" if x > 0 else "−") + fmt(abs(x), nd)


def _r(x: float, nd: int = 2) -> float:
    return round(float(x), nd)


def _unidad(nombre: str) -> str:
    u = BIOMARKER_SPECS[nombre].unidad
    return _UNIDAD_BONITA.get(u, u)


def _escenarios_por_defecto(brechas: Mapping[str, float | None]) -> list[str]:
    sueltas = [k for k in PALANCAS if aplica(k, brechas)]
    out = ["ninguna", *sueltas]
    for k in range(2, MAX_INTERVENCIONES + 1):
        out.extend("+".join(c) for c in combinations(sueltas, k))
    return out


def _nombre_palanca(key: str) -> str:
    return SCENARIOS[key].nombre


def _nombre_humano(intervenciones: Sequence[str]) -> str:
    nombres = [_nombre_palanca(k) for k in intervenciones]
    if not nombres:
        return "Sin intervención"
    if len(nombres) == 1:
        return nombres[0]
    resto = [n[0].lower() + n[1:] for n in nombres[1:]]
    return " + ".join([nombres[0], *resto])


def construir_reporte(
    *,
    nombre: str | None,
    edad: float,
    sexo: str | None,
    biomarcadores_guardados: Sequence[Mapping[str, Any]],
    habitos: Mapping[str, Any] | None,
    ancestria: str | None = None,
    n_trayectorias: int = montecarlo.DEFAULT_TRAYECTORIAS,
    anios: int = montecarlo.DEFAULT_ANIOS,
    semilla: int | None = None,
    version_motor: str = "",
    ahora: datetime | None = None,
    id_reporte: str | None = None,
) -> dict[str, Any]:
    """Devuelve el reporte como dict con la forma de `schema.ReporteOut`.
    `biomarcadores_guardados` es la lista tal como está en
    `health_context.biomarcadores` (`nombre`, `valor`, `unidad`, `fuente`)."""
    ahora = ahora or datetime.now(UTC)
    id_reporte = id_reporte or f"rep_{secrets.token_hex(4)}"
    edad_i = int(edad)

    guardados = {b["nombre"]: b for b in biomarcadores_guardados if b.get("nombre") in BIOMARKER_SPECS}
    medidos_ph = {n: float(b["valor"]) for n, b in guardados.items() if n in PHENOAGE_BIOMARKERS}
    medidos_todos = {n: float(b["valor"]) for n, b in guardados.items()}
    habitos = dict(habitos or {})
    brechas = brechas_desde_habitos(habitos)

    # ---- Motor -----------------------------------------------------------------
    ph = phenoage.compute(medidos_ph, edad, sexo)
    escenarios = _escenarios_por_defecto(brechas)
    mc = montecarlo.simular(medidos_ph, edad, sexo, escenarios, n_trayectorias, anios, seed=semilla, brechas=brechas)
    peor_brechas = {h: 1.0 for h in HABITOS}
    ya_en_peor = all((brechas.get(h) or 0.0) >= 1.0 for h in HABITOS)
    descuido = montecarlo.simular(
        medidos_ph, edad, sexo, ["ninguna"], n_trayectorias, anios, seed=semilla,
        brechas=peor_brechas, valor_de_informacion=False,
    ).escenarios[0]

    base = mc.escenarios[0]
    resto = [e for e in mc.escenarios[1:] if e.aplica]
    por_ratio = sorted(resto, key=lambda e: e.ratio_impacto_esfuerzo, reverse=True)
    mejor = por_ratio[0] if por_ratio else None
    sueltas = sorted((e for e in resto if len(e.intervenciones) == 1), key=lambda e: e.ratio_impacto_esfuerzo, reverse=True)

    # ---- Sección 1: foto de hoy -------------------------------------------------
    filas = []
    for n in (*PHENOAGE_BIOMARKERS, *(k for k in BIOMARKER_SPECS if k not in PHENOAGE_BIOMARKERS)):
        medido = n in medidos_todos
        if not medido and n not in PHENOAGE_BIOMARKERS:
            continue  # los que no son de PhenoAge solo aparecen si se midieron
        valor = medidos_todos[n] if medido else float(ph.valores_usados[n])
        c = clasificar(n, valor, sexo) if medido else None
        filas.append(
            {
                "nombre": n,
                "etiqueta": ETIQUETAS.get(n, n),
                "valor": _r(valor, 3),
                "unidad": _unidad(n),
                "estado": ("inferido" if not medido else (c.estado if c else "sin_rango")),
                "lado": c.lado if c else None,
                "rango_referencia": c.rango.texto if c else (clasificar(n, valor, sexo).rango.texto if clasificar(n, valor, sexo) else None),
                "fuente_rango": c.rango.fuente if c else None,
                "fuente": (str(guardados[n].get("fuente") or "reportado") if medido else "inferido"),
                "contribucion_anios": _r(ph.contribuciones.get(n, 0.0)) if medido else 0.0,
                "nota": (
                    c.rango.nota
                    if (c and c.estado != "en_rango" and c.rango.nota and (c.rango.nota_si_mayor_a is None or valor > c.rango.nota_si_mayor_a))
                    else None
                ),
            }
        )
    n_med = len(medidos_ph)
    n_inf = len(ph.campos_inferidos)
    hoy_p10, hoy_p90 = base.curva_p10[0], base.curva_p90[0]
    acel = ph.aceleracion
    if abs(acel) < 0.5:
        lectura = f"Tu edad biológica estimada ({fmt(ph.edad_biologica)}) va prácticamente pareja con tu edad ({edad_i})."
    elif acel < 0:
        lectura = f"Tu edad biológica estimada ({fmt(ph.edad_biologica)}) está {fmt(abs(acel))} años por debajo de tu edad ({edad_i}): tu reloj va más despacio que el calendario."
    else:
        lectura = f"Tu edad biológica estimada ({fmt(ph.edad_biologica)}) está {fmt(acel)} años por encima de tu edad ({edad_i}). No es un veredicto: es una foto de hoy, y las palancas de la sección 4 son lo que más la mueve."
    if n_inf:
        lectura += f" Ojo: {n_inf} de los 9 biomarcadores no están medidos y se imputaron con la mediana de tu edad y sexo; por eso hoy mismo el rango va {fmt(hoy_p10)}–{fmt(hoy_p90)}."

    foto_hoy = {
        "edad_cronologica": edad_i,
        "edad_biologica": _r(ph.edad_biologica, 1),
        "rango_hoy": {"p10": _r(hoy_p10, 1), "mediana": _r(base.curva_mediana[0], 1), "p90": _r(hoy_p90, 1)},
        "aceleracion": _r(acel, 1),
        "percentil_poblacional": _r(ph.percentil_poblacional, 1),
        "n_medidos": n_med,
        "n_inferidos": n_inf,
        "biomarcadores": filas,
        "nota_poblacional": NOTA_POBLACIONAL,
        "lectura": lectura,
    }

    # ---- Sección 2: ejes ----------------------------------------------------------
    ejes_ev = evaluar_ejes(medidos_todos, sexo, ph.contribuciones)
    ejes = [
        {
            "id": e.id,
            "nombre": e.nombre,
            "nivel": e.nivel,
            "nivel_texto": NIVEL_TEXTO[e.nivel],
            "biomarcadores": [
                {"nombre": b.nombre, "etiqueta": b.etiqueta, "valor": (_r(b.valor, 3) if b.valor is not None else None), "medido": b.medido, "estado": b.estado}
                for b in e.biomarcadores
            ],
            "aporte_anios": _r(e.aporte_anios, 1),
            "explicacion": e.explicacion,
        }
        for e in ejes_ev
    ]

    # ---- Sección 3: futuros --------------------------------------------------------
    def al_horizonte(e) -> dict[str, float]:
        return {"p10": _r(e.edad_biologica_p10, 1), "mediana": _r(e.edad_biologica_mediana, 1), "p90": _r(e.edad_biologica_p90, 1)}

    sigues_igual = {
        "titulo": "Si sigues igual",
        "escenario": "ninguna",
        "nombre": "Línea base con tus hábitos de hoy",
        "al_horizonte": al_horizonte(base),
        "anios_ganados": None,
        "rango_ganados": None,
        "texto": (
            f"En {anios} años tu edad biológica estaría alrededor de {fmt(base.edad_biologica_mediana)} "
            f"(entre {fmt(base.edad_biologica_p10)} y {fmt(base.edad_biologica_p90)} en el 80 % de los futuros que simulé)."
        ),
    }
    si_mejoras = None
    if mejor is not None:
        si_mejoras = {
            "titulo": "Si mejoras",
            "escenario": mejor.escenario,
            "nombre": _nombre_humano(mejor.intervenciones),
            "al_horizonte": al_horizonte(mejor),
            "anios_ganados": _r(mejor.anios_ganados, 1),
            "rango_ganados": [_r(mejor.anios_ganados_p10, 1), _r(mejor.anios_ganados_p90, 1)],
            "texto": (
                f"Con {_nombre_humano(mejor.intervenciones).lower()} —la mejor relación entre años ganados y esfuerzo para ti— "
                f"la mediana baja a {fmt(mejor.edad_biologica_mediana)}: {fmt_delta(mejor.anios_ganados)} años "
                f"(entre {fmt_delta(mejor.anios_ganados_p10)} y {fmt_delta(mejor.anios_ganados_p90)}), "
                f"y mejora en el {fmt(mejor.pct_futuros_que_mejoran, 0)} % de los futuros pareados."
            ),
        }
    if ya_en_peor:
        texto_desc = "Tus hábitos registrados ya están todos en el extremo adverso: este escenario coincide con tu línea base. Eso también significa que todo lo que muevas suma."
    else:
        dif = descuido.edad_biologica_mediana - base.edad_biologica_mediana
        texto_desc = (
            f"Si los seis hábitos que leo (actividad, alimentación, tabaco, sueño, estrés, alcohol) se fueran al extremo adverso, "
            f"la mediana a {anios} años quedaría en {fmt(descuido.edad_biologica_mediana)} "
            f"(entre {fmt(descuido.edad_biologica_p10)} y {fmt(descuido.edad_biologica_p90)}): {fmt(dif)} años más que siguiendo igual. "
            "No es una predicción: es la misma simulación con otros hábitos, para ver cuánto de esto está en tus manos."
        )
    si_te_descuidas = {
        "titulo": "Si te descuidas",
        "escenario": None,
        "nombre": "Línea base con todos los hábitos en el extremo adverso",
        "al_horizonte": al_horizonte(descuido),
        "anios_ganados": None if ya_en_peor else _r(base.edad_biologica_mediana - descuido.edad_biologica_mediana, 1),
        "rango_ganados": None,
        "texto": texto_desc,
    }
    ranking = [
        {
            "escenario": e.escenario,
            "nombre": _nombre_humano(e.intervenciones),
            "intervenciones": list(e.intervenciones),
            "anios_ganados": _r(e.anios_ganados, 1),
            "anios_ganados_p10": _r(e.anios_ganados_p10, 1),
            "anios_ganados_p90": _r(e.anios_ganados_p90, 1),
            "pct_futuros_que_mejoran": _r(e.pct_futuros_que_mejoran, 0),
            "esfuerzo": e.esfuerzo,
            "ratio_impacto_esfuerzo": _r(e.ratio_impacto_esfuerzo, 2),
            "fuentes": [ev.fuente for k in e.intervenciones for ev in evidencia_de(k)[:1]],
        }
        for e in sorted(resto, key=lambda e: e.anios_ganados, reverse=True)
    ]
    futuros = {
        "horizonte_anios": anios,
        "curva_base": {
            "anios": list(base.curva_anios),
            "p10": [_r(x, 1) for x in base.curva_p10],
            "mediana": [_r(x, 1) for x in base.curva_mediana],
            "p90": [_r(x, 1) for x in base.curva_p90],
        },
        "sigues_igual": sigues_igual,
        "si_mejoras": si_mejoras,
        "si_te_descuidas": si_te_descuidas,
        "ranking": ranking,
        "nota_incertidumbre": NOTA_INCERTIDUMBRE,
    }

    # ---- Sección 4: recomendaciones (2–3 palancas sueltas de mayor impacto/esfuerzo) ----
    recomendaciones = []
    for e in sueltas[:3]:
        key = e.intervenciones[0]
        sc = SCENARIOS[key]
        efectos = [(_EFECTO_HUMANO.get(n, n), v) for n, v in sc.efectos_anuales.items() if v != 0.0]
        partes = [h for h, _ in efectos]
        por_que = (
            f"En tu simulación, {sc.nombre.lower()} " + (", ".join(partes[:-1]) + " y " + partes[-1] if len(partes) > 1 else partes[0])
            + f"; acumulado a {anios} años, eso se traduce en {fmt_delta(e.anios_ganados)} años de edad biológica "
            f"(entre {fmt_delta(e.anios_ganados_p10)} y {fmt_delta(e.anios_ganados_p90)}) en {fmt(e.pct_futuros_que_mejoran, 0)} % de tus futuros."
        )
        recomendaciones.append(
            {
                "id": key,
                "nombre": sc.nombre,
                "que_hacer": sc.descripcion,
                "por_que": por_que,
                "anios_ganados": _r(e.anios_ganados, 1),
                "rango_ganados": [_r(e.anios_ganados_p10, 1), _r(e.anios_ganados_p90, 1)],
                "pct_futuros_que_mejoran": _r(e.pct_futuros_que_mejoran, 0),
                "esfuerzo": e.esfuerzo,
                "evidencia": [{"hallazgo": ev.hallazgo, "fuente": ev.fuente} for ev in evidencia_de(key)],
                "habito": _HABITO_HUMANO.get(sc.habito or "", sc.habito or ""),
                "brecha": _r(brecha_efectiva(brechas, sc.habito), 2),
            }
        )

    # ---- Sección 5: con quién consultar ------------------------------------------------
    sugerencias = triage(ejes_ev)
    consulta = {
        "disclaimer": DISCLAIMER_TRIAGE,
        "sugerencias": [
            {"eje": s.eje, "nombre": s.nombre, "nivel": s.nivel, "profesional": s.profesional, "texto": s.texto}
            for s in sugerencias
        ],
        "lleva_esto": (
            "Lleva este reporte a tu consulta. Resume lo que Moirai observó: la foto de hoy (sección 1), "
            "los ejes marcados (sección 2) y lo que tú puedes mover (sección 4). El profesional decide qué sigue."
        ),
    }

    # ---- Sección 6: qué afinaría ----------------------------------------------------------
    voi = {v.nombre: v for v in mc.valor_de_informacion}
    faltantes = [
        {
            "nombre": n,
            "etiqueta": ETIQUETAS.get(n, n),
            "reduccion_banda_anios": _r(voi[n].reduccion_banda_anios, 1) if n in voi else None,
            "fraccion": _r(voi[n].fraccion, 3) if n in voi else None,
        }
        for n in sorted(ph.campos_inferidos, key=lambda n: -(voi[n].reduccion_banda_anios if n in voi else 0.0))
    ]
    otros_no_medidos = [n for n in BIOMARKER_SPECS if n not in PHENOAGE_BIOMARKERS and n not in medidos_todos]
    if faltantes:
        nota_afinar = (
            f"Hoy {n_inf} de los 9 biomarcadores del reloj están imputados; la banda P10–P90 de hoy mide {fmt(mc.ancho_banda_hoy)} años solo por eso. "
            "El ranking dice cuánto se angosta la banda a 10 años si mides cada uno (volví a correr tus futuros con ese valor fijo, misma semilla)."
        )
    else:
        nota_afinar = "Tengo tus 9 biomarcadores del reloj: la banda es la más angosta que puedo darte con lo que existe hoy."
    if otros_no_medidos:
        nota_afinar += " También ayudarían, para los ejes cardio-metabólico y metabólico: " + ", ".join(ETIQUETAS[n].lower() for n in otros_no_medidos) + "."

    afinar = {"ancho_banda_hoy": _r(mc.ancho_banda_hoy, 1), "faltantes": faltantes, "nota": nota_afinar}

    # ---- Portada ---------------------------------------------------------------------------------
    if mejor is not None:
        resumen = (
            f"Tu edad biológica estimada es {fmt(ph.edad_biologica)} años (tienes {edad_i}); "
            f"lo que más la mueve a {anios} años es {_nombre_humano(mejor.intervenciones).lower()}: "
            f"{fmt_delta(mejor.anios_ganados)} años, entre {fmt_delta(mejor.anios_ganados_p10)} y {fmt_delta(mejor.anios_ganados_p90)}."
        )
    else:
        resumen = (
            f"Tu edad biológica estimada es {fmt(ph.edad_biologica)} años (tienes {edad_i}); "
            "con tus hábitos de hoy no encuentro una palanca que la mueva de forma apreciable — seguir como vas es la recomendación."
        )

    return {
        "meta": {
            "id": id_reporte,
            "generado_en": ahora.isoformat(timespec="seconds"),
            "version_motor": version_motor,
            "semilla": mc.semilla,
            "trayectorias_por_escenario": mc.n_trayectorias,
            "horizonte_anios": mc.anios,
            "disclaimer": DISCLAIMER,
            "privacidad": PRIVACIDAD,
            "fuentes": list(FUENTES_GENERALES),
        },
        "persona": {"nombre": nombre, "edad": edad_i, "sexo": sexo, "ancestria": ancestria},
        "resumen": resumen,
        "foto_hoy": foto_hoy,
        "ejes": ejes,
        "futuros": futuros,
        "recomendaciones": recomendaciones,
        "consulta": consulta,
        "afinar": afinar,
    }


def textos_del_reporte(rep: Mapping[str, Any]) -> list[str]:
    """Todas las cadenas del reporte (recursivo) — lo que el test de
    palabras prohibidas revisa, y lo mismo que acaba en el PDF."""
    out: list[str] = []

    def walk(x: Any) -> None:
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, Mapping):
            for v in x.values():
                walk(v)
        elif isinstance(x, (list, tuple)):
            for v in x:
                walk(v)

    walk(rep)
    return out


__all__ = ["DISCLAIMER", "PRIVACIDAD", "VERSION_REPORTE", "construir_reporte", "fmt", "fmt_delta", "textos_del_reporte"]
