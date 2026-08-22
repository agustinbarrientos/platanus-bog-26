"""Per-user chunks: the stored health context, a fresh PhenoAge, and the
simulation result the app sends with each chat turn — split by topic so the
retriever can hand the model only the two or three that matter.

The result comes from the app (`SimulacionResultado.toChatJson()`, spec §8
shape) rather than being recomputed here: the app is the one that assembled
what the user is looking at (the backend returns horizon percentiles; the
per-year curve, SHAP-style "por qué", effort and percentile are built on the
device — see API_CONTRACT.md), so sending it back is the only way the chat can
talk about *exactly* the numbers on screen. It is a few KB without the sample
trajectories, which `toChatJson()` drops.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from app.chat_rag.chunks import (
    Chunk,
    fmt_delta,
    fmt_lista,
    fmt_num,
    fmt_rango,
    fmt_rango_delta,
)
from app.chat_rag.knowledge import (
    ALIAS_BIOMARCADOR,
    ALIAS_INTERVENCION,
    KNOWLEDGE,
    NOMBRE_BIOMARCADOR,
    direccion_en_phenoage,
)
from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import SCENARIOS
from app.health_metrics.nhanes_reference import median_for
from app.health_metrics.phenoage import PhenoAgeResult

# ---- catalog labels (mirror the app's `Catalogos`, API_CONTRACT.md) ----

_OBJETIVOS = {
    "energia": "más energía", "prevencion": "prevención", "longevidad": "longevidad",
    "fertilidad": "fertilidad", "rendimiento": "rendimiento físico", "sueno": "dormir mejor",
    "peso": "peso saludable", "salud_mental": "salud mental",
}
_CONDICIONES = {
    "diabetes_t2": "diabetes tipo 2", "cardiovascular": "infarto o enfermedad del corazón",
    "hipertension": "presión alta", "cancer": "cáncer", "alzheimer": "Alzheimer o demencia",
    "obesidad": "obesidad", "tiroides": "tiroides", "alzheimer_materno": "Alzheimer (materno)",
}
_PARENTESCOS = {
    "madre": "madre", "padre": "padre", "hermano": "hermano/a", "abuelo": "abuelo/a", "otro": "otro familiar",
}
_ANCESTRIA = {
    "mixta_latam": "mixta latinoamericana", "europea": "europea", "africana": "africana",
    "indigena": "indígena", "asiatica": "asiática", "otra": "otra",
    "prefiero_no_decir": "prefiere no decirlo",
}
_SEXO = {"F": "femenino", "M": "masculino"}
_NIVEL = {"baja": "baja", "media": "media", "alta": "alta", "bajo": "bajo", "medio": "medio", "alto": "alto"}

#: SHAP variable → how the app names it ("la inflamación (hs-CRP)").
_NOMBRE_VARIABLE = {
    "hs_CRP": "la inflamación (hs-CRP)", "glucosa": "la glucosa", "albumina": "la albúmina",
    "creatinina": "la creatinina", "rdw": "el RDW", "leucocitos": "los leucocitos",
    "linfocitos_pct": "los linfocitos", "vcm": "el VCM", "fosfatasa_alcalina": "la fosfatasa alcalina",
    "sueno_h": "el sueño", "estres": "el estrés", "ejercicio": "el ejercicio", "tabaco": "el tabaco",
}

_ORDINAL = ("primera", "segunda", "tercera", "cuarta", "quinta", "sexta", "séptima", "octava")


def _etiqueta(clave: str, tabla: Mapping[str, str]) -> str:
    return tabla.get(clave, clave.replace("_", " "))


def _num(v: Any) -> float | None:
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


# ---- stored data ----

def user_chunks(
    perfil: Mapping[str, Any], context: Mapping[str, Any], pheno: PhenoAgeResult | None
) -> list[Chunk]:
    """One chunk per topic of `/me` + `/me/health-context`, plus one per
    biomarker (measured or not) and the fresh PhenoAge."""
    out: list[Chunk] = []
    edad = _num(perfil.get("edad"))
    sexo = perfil.get("sexo_biologico")

    # perfil
    partes = []
    if edad is not None:
        partes.append(f"{fmt_num(edad)} años")
    if sexo:
        partes.append(f"sexo {_SEXO.get(sexo, sexo)}")
    if perfil.get("estatura_cm"):
        partes.append(f"estatura {fmt_num(perfil['estatura_cm'])} cm")
    if perfil.get("peso_kg"):
        partes.append(f"peso {fmt_num(perfil['peso_kg'])} kg")
    if perfil.get("imc"):
        partes.append(f"IMC {fmt_num(perfil['imc'])}")
    demografia = context.get("demografia") or {}
    if demografia.get("ancestria_reportada"):
        partes.append(f"ancestría reportada {_etiqueta(demografia['ancestria_reportada'], _ANCESTRIA)}")
    if demografia.get("escolaridad_anios") is not None:
        partes.append(f"{fmt_num(demografia['escolaridad_anios'])} años de escolaridad")
    faltan = []
    if edad is None:
        faltan.append("fecha de nacimiento")
    if not sexo:
        faltan.append("sexo al nacer")
    texto = ("Perfil: " + ", ".join(partes) + "." if partes else "Perfil: todavía sin datos básicos.")
    if faltan:
        texto += (
            f" Falta {fmt_lista(faltan)} en el perfil: sin eso no puedo calcular PhenoAge ni simular "
            "(se completa en Perfil → Datos básicos)."
        )
    out.append(Chunk(
        id="perfil", titulo="Tu perfil", texto=texto, grupo="usuario",
        tags=("perfil", "edad", "sexo", "peso", "estatura", "imc", "ancestria", "datos basicos"),
        prioridad=1.2, respaldo=True,
    ))

    # hábitos
    h = context.get("habitos") or {}
    hab = []
    if h.get("sueno_h") is not None:
        hab.append(f"duerme {fmt_num(h['sueno_h'])} h por noche")
    if h.get("tabaco") is not None:
        hab.append("fuma" if h["tabaco"] else "no fuma")
    if h.get("actividad"):
        hab.append(f"actividad física {_NIVEL.get(h['actividad'], h['actividad'])}")
    if h.get("alimentacion"):
        hab.append(f"alimentación {_NIVEL.get(h['alimentacion'], h['alimentacion'])}")
    if h.get("estres"):
        hab.append(f"estrés {_NIVEL.get(h['estres'], h['estres'])}")
    palancas = ["ejercicio aeróbico", "dieta mediterránea"]
    if h.get("tabaco"):
        palancas += ["dejar el tabaco", "las tres combinadas"]
    texto = (
        ("Hábitos registrados: " + ", ".join(hab) + ".") if hab else "Hábitos: todavía no hay registrados."
    ) + (
        f" Palancas que el motor puede simular para esta persona: {fmt_lista(palancas)}"
        + ("" if h.get("tabaco") else " (dejar el tabaco no aplica porque no fuma)")
        + ". Sueño, alcohol y estrés se registran pero todavía no son palancas del motor."
    )
    out.append(Chunk(
        id="habitos", titulo="Tus hábitos", texto=texto, grupo="usuario",
        tags=("habitos", "sueno", "dormir", "tabaco", "fumar", "actividad", "ejercicio",
              "alimentacion", "dieta", "estres", "palancas"),
        prioridad=1.2, respaldo=True,
    ))

    # historia familiar
    hist = context.get("historia_familiar") or []
    if hist:
        items = []
        for entrada in hist:
            cond, _, par = str(entrada).partition(":")
            label = _etiqueta(cond, _CONDICIONES)
            if par:
                label += f" ({_etiqueta(par, _PARENTESCOS)})"
            items.append(label)
        texto = (
            f"Historia familiar reportada: {fmt_lista(items)}. El motor actual no la usa en la "
            "proyección (ni en PhenoAge); la guardo como contexto y para modelos futuros."
        )
    else:
        texto = "Historia familiar: no hay condiciones reportadas (o no se ha respondido)."
    out.append(Chunk(
        id="historia_familiar", titulo="Tu historia familiar", texto=texto, grupo="usuario",
        tags=("historia familiar", "familia", "hereditario", "padres"), prioridad=1.2,
    ))

    # objetivos
    obj = context.get("objetivos_usuario") or []
    texto = (
        f"Objetivos que me contó: {fmt_lista(_etiqueta(o, _OBJETIVOS) for o in obj)}."
        if obj else "Objetivos: no ha elegido ninguno todavía."
    )
    out.append(Chunk(
        id="objetivos", titulo="Tus objetivos", texto=texto, grupo="usuario",
        tags=("objetivos", "metas", "para que"), prioridad=1.1,
    ))

    # biomarcadores: uno por nombre del vocabulario, medido o no
    guardados = {b["nombre"]: b for b in (context.get("biomarcadores") or []) if "nombre" in b}
    medidos_phenoage = [n for n in PHENOAGE_BIOMARCADORES_ORDEN if n in guardados]
    for nombre, spec in BIOMARKER_SPECS.items():
        en_pheno = nombre in PHENOAGE_BIOMARKERS
        b = guardados.get(nombre)
        nombre_h = NOMBRE_BIOMARCADOR[nombre]
        if b is not None:
            fuente = str(b.get("fuente") or "registrado")
            texto = (
                f"{nombre_h.capitalize()}: {fmt_num(b.get('valor'), 2)} {spec.unidad} "
                f"(medido; fuente: {fuente})."
            )
            if edad is not None and en_pheno:
                med = median_for(nombre, edad, sexo)
                texto += f" Mediana de referencia para su edad y sexo: {fmt_num(med, 2)} {spec.unidad}."
            if en_pheno:
                texto += (
                    f" Entra en PhenoAge (un valor más alto {direccion_en_phenoage(nombre)} la edad biológica)."
                )
            else:
                texto += " No entra en PhenoAge; lo guardo para otros modelos de riesgo."
            titulo = f"Tu {nombre_h}"
        elif en_pheno:
            if edad is not None:
                med = median_for(nombre, edad, sexo)
                texto = (
                    f"{nombre_h.capitalize()}: NO está medido. Para calcular PhenoAge lo imputo con la "
                    f"mediana de su grupo de edad y sexo, {fmt_num(med, 2)} {spec.unidad} (estimado, "
                    "no medido), y eso ensancha la banda. Medirlo angosta el rango."
                )
            else:
                texto = (
                    f"{nombre_h.capitalize()}: NO está medido. Cuando tenga su edad y sexo lo imputaré "
                    "con una mediana poblacional; medirlo angosta el rango."
                )
            titulo = f"Tu {nombre_h} (no medido)"
        else:
            texto = f"{nombre_h.capitalize()}: no está registrado. No entra en PhenoAge."
            titulo = f"Tu {nombre_h} (no registrado)"
        out.append(Chunk(
            id=f"bio:{nombre}", titulo=titulo, texto=texto, grupo="usuario",
            tags=(nombre.lower(), "biomarcador", "examen", "mis examenes",
                  *ALIAS_BIOMARCADOR.get(nombre, ()),
                  *(("faltante", "imputado", "inferido") if (b is None and en_pheno) else ())),
            prioridad=1.3 if b is not None else 1.15,
        ))

    # PhenoAge fresco
    if pheno is not None:
        inferidos = [NOMBRE_BIOMARCADOR[n] for n in pheno.campos_inferidos]
        medidos = [NOMBRE_BIOMARCADOR[n] for n in PHENOAGE_BIOMARKERS if n not in pheno.campos_inferidos]
        valores = ", ".join(
            f"{n} {fmt_num(pheno.valores_usados[n], 2)} {BIOMARKER_SPECS[n].unidad}"
            + (" (imputado)" if n in pheno.campos_inferidos else "")
            for n in PHENOAGE_BIOMARKERS
        )
        texto = (
            f"PhenoAge calculado ahora mismo con los datos guardados: edad cronológica "
            f"{fmt_num(pheno.edad_cronologica)}, edad biológica {fmt_num(pheno.edad_biologica)} años, "
            f"aceleración {fmt_delta(pheno.aceleracion)} años "
            f"({'por encima' if pheno.aceleracion > 0 else 'por debajo'} de la cronológica). "
            f"Biomarcadores medidos ({len(medidos)} de 9): {fmt_lista(medidos) or 'ninguno'}. "
            f"Imputados ({len(inferidos)}): {fmt_lista(inferidos) or 'ninguno'}. "
            f"Valores usados: {valores}."
        )
    else:
        texto = (
            "PhenoAge: todavía no puedo calcularlo porque falta fecha de nacimiento y/o sexo al nacer "
            "en el perfil."
        )
    out.append(Chunk(
        id="phenoage", titulo="Tu edad biológica hoy (PhenoAge)", texto=texto, grupo="usuario",
        tags=("phenoage", "edad biologica", "aceleracion", "hoy", "reloj", "imputado", "valores usados"),
        prioridad=1.3, respaldo=True,
    ))

    # faltantes / notas
    faltantes = context.get("datos_faltantes") or []
    notas = context.get("notas_incertidumbre")
    no_medidos = [NOMBRE_BIOMARCADOR[n] for n in PHENOAGE_BIOMARKERS if n not in guardados]
    partes = []
    if no_medidos:
        partes.append(
            f"Biomarcadores de PhenoAge sin medir ({len(no_medidos)} de 9): {fmt_lista(no_medidos)}; "
            "cada uno se imputa y ensancha la banda."
        )
    else:
        partes.append("Los 9 biomarcadores de PhenoAge están medidos: la banda es la más angosta que puedo dar.")
    if faltantes:
        partes.append(
            f"Datos faltantes declarados: {fmt_lista(NOMBRE_BIOMARCADOR.get(str(f), str(f)) for f in faltantes)}."
        )
    if notas:
        partes.append(f"Notas de incertidumbre: {notas}")
    out.append(Chunk(
        id="faltantes", titulo="Lo que me falta de ti", texto=" ".join(partes), grupo="usuario",
        tags=("faltante", "imputado", "inferido", "medir", "examen", "incertidumbre", "que medir"),
        prioridad=1.2,
    ))
    return out


#: Stable order for "measured" lists: the six-core first (spec §1), then the rest.
PHENOAGE_BIOMARCADORES_ORDEN = (
    "albumina", "creatinina", "glucosa", "hs_CRP", "rdw", "leucocitos",
    "linfocitos_pct", "vcm", "fosfatasa_alcalina",
)


# ---- simulation result (spec §8 as the app holds it) ----

def _nombre_intervencion(key: str, catalogo: Mapping[str, Mapping[str, Any]]) -> str:
    if key in catalogo and catalogo[key].get("etiqueta"):
        return str(catalogo[key]["etiqueta"])
    if key in SCENARIOS:
        return SCENARIOS[key].nombre
    return key.replace("_", " ")


def _curva_final(curva: Mapping[str, Any] | None) -> tuple[float | None, float | None, float | None]:
    if not curva:
        return None, None, None
    med, p10, p90 = curva.get("mediana") or [], curva.get("p10") or [], curva.get("p90") or []
    return (
        _num(med[-1]) if med else None,
        _num(p10[-1]) if p10 else None,
        _num(p90[-1]) if p90 else None,
    )


def _escenario_texto(
    i: int, e: Mapping[str, Any], horizonte: int, base_final: float | None,
    catalogo: Mapping[str, Mapping[str, Any]],
) -> str:
    ids = [str(x) for x in (e.get("intervenciones") or [])]
    rango = e.get("rango") or []
    lo, hi = (_num(rango[0]), _num(rango[1])) if len(rango) >= 2 else (None, None)
    med, p10, p90 = _curva_final(e.get("curva"))
    partes = [
        f"Palanca #{i + 1} ({_ORDINAL[i] if i < len(_ORDINAL) else str(i + 1)} por años ganados por "
        f"unidad de esfuerzo): {e.get('etiqueta') or fmt_lista(_nombre_intervencion(k, catalogo) for k in ids)}.",
        f"Intervenciones: {fmt_lista(_nombre_intervencion(k, catalogo) for k in ids) or 'ninguna'}.",
        f"Años ganados a {horizonte} años: {fmt_delta(_num(e.get('anios_ganados')))}"
        + (f" (rango {fmt_rango_delta(lo, hi)})" if lo is not None else "") + ".",
    ]
    if e.get("esfuerzo") is not None:
        partes.append(f"Esfuerzo: {fmt_num(e['esfuerzo'])} de 10.")
    ratio = _num(e.get("ratio_impacto_esfuerzo", e.get("ratio")))
    if ratio is not None:
        partes.append(f"Ratio impacto/esfuerzo: {fmt_num(ratio, 2)}.")
    if e.get("pct_futuros_que_mejoran") is not None:
        partes.append(
            f"{fmt_num(e['pct_futuros_que_mejoran'])} % de sus futuros mejoran con esto; en el resto no "
            "hace daño, algo más pasa primero."
        )
    if med is not None:
        partes.append(
            f"Edad biológica en {horizonte} años si lo hace: mediana {fmt_num(med)}"
            + (f" (P10–P90 {fmt_num(p10)}–{fmt_num(p90)})" if p10 is not None else "")
            + (f", frente a {fmt_num(base_final)} si sigue igual" if base_final is not None else "")
            + "."
        )
    for k in ids:
        desc = catalogo.get(k, {}).get("descripcion")
        if desc:
            partes.append(f"{_nombre_intervencion(k, catalogo)}: {desc}")
    return " ".join(partes)


def result_chunks(resultado: Mapping[str, Any] | None) -> list[Chunk]:
    """Chunks for the simulation the user is looking at. Empty when the app
    has not sent one (no simulation yet, or an older client)."""
    if not resultado:
        return []
    out: list[Chunk] = []
    catalogo = {
        str(c.get("id")): c for c in (resultado.get("intervenciones_catalogo") or []) if c.get("id")
    }
    baseline = resultado.get("trayectoria_baseline") or {}
    anios = baseline.get("anios") or []
    horizonte = int(anios[-1]) if anios else 10
    base_med, base_p10, base_p90 = _curva_final(baseline)
    escenarios = list(resultado.get("escenarios") or [])
    hoy = _num(resultado.get("edad_biologica_hoy"))
    cron = _num(resultado.get("edad_cronologica"))
    fecha = str(resultado.get("creado_en") or "")[:10]

    mejor = escenarios[0] if escenarios else None
    mejor_texto = ""
    if mejor:
        r = mejor.get("rango") or []
        mejor_texto = (
            f" Mejor palanca: {mejor.get('etiqueta') or 'ver palancas'} "
            f"({fmt_delta(_num(mejor.get('anios_ganados')))} años"
            + (f", rango {fmt_rango_delta(_num(r[0]), _num(r[1]))}" if len(r) >= 2 else "") + ")."
        )
    elif resultado.get("mejor_decision"):
        md = resultado["mejor_decision"]
        mejor_texto = (
            f" Mejor decisión: {fmt_lista(_nombre_intervencion(str(k), catalogo) for k in (md.get('intervenciones') or []))} "
            f"({fmt_delta(_num(md.get('anios_ganados')))} años)."
        )
    out.append(Chunk(
        id="sim:resumen", titulo="Tu última simulación, en resumen",
        texto=(
            f"Última simulación{f' ({fecha})' if fecha else ''}: 5.000 futuros por escenario, horizonte "
            f"{horizonte} años. Edad biológica hoy {fmt_num(hoy)}"
            + (f" (edad cronológica {fmt_num(cron)})" if cron is not None else "") + ". "
            + (
                f"Si sigue igual, en {horizonte} años la mediana es {fmt_num(base_med)} "
                f"(banda P10–P90 {fmt_num(base_p10)}–{fmt_num(base_p90)}). "
                if base_med is not None else ""
            )
            + f"Escenarios comparados: {len(escenarios)}."
            + mejor_texto
            + (f" Veredicto: {resultado['veredicto_gemelo']}" if resultado.get("veredicto_gemelo") else "")
            + (f" {resultado['descargo']}" if resultado.get("descargo") else "")
        ),
        grupo="resultado",
        tags=("resumen", "simulacion", "resultado", "futuro", "proyeccion", "veredicto", "gemelo",
              "phenoage", "10 anos"),
        prioridad=1.3, respaldo=True,
    ))

    if mejor:
        out.append(Chunk(
            id="sim:mejor_decision", titulo="Tu mejor palanca",
            texto=_escenario_texto(0, mejor, horizonte, base_med, catalogo)
            + (f" Por qué: {resultado['porque']}" if resultado.get("porque") else "")
            + (f" Veredicto: {resultado['veredicto_gemelo']}" if resultado.get("veredicto_gemelo") else ""),
            grupo="resultado",
            tags=("mejor", "primera", "palancas", "escenario", "mejor decision", "recomendacion",
                  "gemelo", "veredicto", "anos ganados", "esfuerzo",
                  *(str(k) for k in (mejor.get("intervenciones") or [])),
                  *(a for k in (mejor.get("intervenciones") or []) for a in ALIAS_INTERVENCION.get(str(k), ()))),
            prioridad=1.4, respaldo=True,
        ))

    for i, e in enumerate(escenarios):
        ids = [str(k) for k in (e.get("intervenciones") or [])]
        out.append(Chunk(
            id=f"sim:escenario:{i}", titulo=f"Palanca #{i + 1}: {e.get('etiqueta') or fmt_lista(ids)}",
            texto=_escenario_texto(i, e, horizonte, base_med, catalogo),
            grupo="resultado",
            tags=("palancas", "escenario", "anos ganados", "esfuerzo", "futuros que mejoran",
                  _ORDINAL[i] if i < len(_ORDINAL) else f"#{i + 1}", *ids,
                  *(a for k in ids for a in ALIAS_INTERVENCION.get(k, ())),
                  *(("combinada", "combinacion", "todo junto") if len(ids) > 1 else ())),
            prioridad=1.3 if i > 0 else 1.1,  # #1 already has its own richer chunk
        ))

    if anios and baseline.get("mediana"):
        med, p10, p90 = baseline.get("mediana") or [], baseline.get("p10") or [], baseline.get("p90") or []
        puntos = []
        for j, a in enumerate(anios):
            if j < len(med):
                banda = f" ({fmt_num(p10[j])}–{fmt_num(p90[j])})" if j < len(p10) and j < len(p90) else ""
                puntos.append(f"año {fmt_num(a)}: {fmt_num(med[j])}{banda}")
        out.append(Chunk(
            id="sim:baseline", titulo="Tu trayectoria si sigues igual (año a año)",
            texto=(
                "Edad biológica proyectada sin cambiar nada, mediana (banda P10–P90) por año: "
                + "; ".join(puntos) + ". La curva entre hoy y el año final se interpola en la app (la "
                "banda crece con la raíz del tiempo); los percentiles del año final vienen del servidor."
            ),
            grupo="resultado",
            tags=("baseline", "curva", "trayectoria", "proyeccion", "ano", "sigues igual", "linea base",
                  "banda", "p10", "p90", "abanico"),
            prioridad=1.2,
        ))

    shap = resultado.get("shap_top_drivers") or []
    if shap or resultado.get("porque"):
        filas = []
        for d in shap:
            var = str(d.get("variable", ""))
            c = _num(d.get("contribucion"))
            dire = d.get("direccion") or ("mejora" if (c or 0) < 0 else "empeora")
            filas.append(
                f"{_NOMBRE_VARIABLE.get(var, var)} {fmt_delta(c)} años "
                f"({'le rejuvenece' if dire == 'mejora' else 'le envejece'})"
            )
        out.append(Chunk(
            id="sim:porque", titulo="Por qué: qué pesa en tu edad biológica de hoy",
            texto=(
                ("Contribuciones aproximadas (tipo SHAP sobre el estado de hoy, de mayor a menor): "
                 + "; ".join(filas) + ". " if filas else "")
                + (f"Explicación: {resultado['porque']} " if resultado.get("porque") else "")
                + "Son aproximaciones calculadas en el dispositivo reemplazando cada variable por su "
                "mediana; sirven para decir qué mueve más, no como cifras exactas."
            ),
            grupo="resultado",
            tags=("porque", "shap", "pesa", "influye", "contribucion", "eje dominante", "causa",
                  *(str(d.get("variable", "")).lower() for d in shap)),
            prioridad=1.3,
        ))

    cp = resultado.get("comparacion_poblacional") or {}
    if cp.get("percentil_edad_biologica") is not None:
        out.append(Chunk(
            id="sim:poblacion", titulo="Frente a personas como tú",
            texto=(
                f"Percentil {fmt_num(cp['percentil_edad_biologica'])} de edad biológica frente a personas de "
                f"su edad y sexo (referencia {cp.get('fuente') or 'NHANES'}). "
                + (f"{cp['mensaje']} " if cp.get("mensaje") else "")
                + "Es una aproximación de la app sobre la aceleración (edad biológica menos cronológica)."
            ),
            grupo="resultado",
            tags=("poblacion", "percentil", "promedio", "personas como tu", "nhanes", "comparacion"),
            prioridad=1.3,
        ))

    usados = resultado.get("biomarcadores_usados") or []
    inferidos = [NOMBRE_BIOMARCADOR.get(str(b.get("nombre")), str(b.get("nombre")))
                 for b in usados if b.get("fuente") == "inferido"]
    medidos = [NOMBRE_BIOMARCADOR.get(str(b.get("nombre")), str(b.get("nombre")))
               for b in usados if b.get("fuente") != "inferido"]
    if resultado.get("incertidumbre") or usados:
        out.append(Chunk(
            id="sim:incertidumbre", titulo="Qué tan seguro estoy de este resultado",
            texto=(
                (f"{resultado['incertidumbre']} " if resultado.get("incertidumbre") else "")
                + (f"Biomarcadores medidos en esta simulación: {fmt_lista(medidos) or 'ninguno'}. " if usados else "")
                + (f"Imputados: {fmt_lista(inferidos)}. " if inferidos else "")
                + "Medir los imputados angosta la banda; el orden de las palancas es lo más robusto del resultado."
            ),
            grupo="resultado",
            tags=("incertidumbre", "banda", "rango", "seguro", "imputado", "inferido", "faltante", "medir"),
            prioridad=1.3,
        ))

    if catalogo:
        out.append(Chunk(
            id="sim:catalogo", titulo="Las palancas que consideré",
            texto="Catálogo de intervenciones de esta simulación: " + "; ".join(
                f"{c.get('etiqueta') or k} (esfuerzo {fmt_num(c.get('esfuerzo'))} de 10"
                + (f": {c['descripcion']}" if c.get("descripcion") else "") + ")"
                for k, c in catalogo.items()
            ) + ".",
            grupo="resultado",
            tags=("catalogo", "palancas", "intervencion", "esfuerzo", *catalogo.keys()),
            prioridad=1.0,
        ))
    return out


# ---- the always-on card ----

def core_chunk(
    perfil: Mapping[str, Any], pheno: PhenoAgeResult | None, resultado: Mapping[str, Any] | None
) -> Chunk:
    """≈120 tokens the model always gets, so even a question the retriever
    missed is answered about the right person with the right headline numbers."""
    nombre = perfil.get("nombre") or "sin nombre registrado"
    edad = _num(perfil.get("edad"))
    sexo = perfil.get("sexo_biologico")
    partes = [
        f"Persona: {nombre}"
        + (f", {fmt_num(edad)} años" if edad is not None else ", edad sin registrar")
        + (f", sexo {_SEXO.get(sexo, sexo)}" if sexo else ", sexo sin registrar") + "."
    ]
    if pheno is not None:
        medidos = 9 - len(pheno.campos_inferidos)
        partes.append(
            f"Edad biológica hoy (PhenoAge con los datos guardados): {fmt_num(pheno.edad_biologica)} años, "
            f"{fmt_delta(pheno.aceleracion)} frente a la cronológica; {medidos} de 9 biomarcadores medidos, "
            f"{len(pheno.campos_inferidos)} imputados."
        )
    else:
        partes.append("PhenoAge: aún no calculable (falta fecha de nacimiento o sexo en el perfil).")
    if resultado:
        hoy_sim = _num(resultado.get("edad_biologica_hoy"))
        baseline = resultado.get("trayectoria_baseline") or {}
        anios = baseline.get("anios") or []
        horizonte = int(anios[-1]) if anios else 10
        med, p10, p90 = _curva_final(baseline)
        escenarios = resultado.get("escenarios") or []
        fecha = str(resultado.get("creado_en") or "")[:10]
        s = f"Última simulación{f' ({fecha})' if fecha else ''}:"
        if hoy_sim is not None and (pheno is None or abs(hoy_sim - pheno.edad_biologica) > 0.2):
            s += f" marcaba edad biológica hoy {fmt_num(hoy_sim)} (los datos cambiaron desde entonces);"
        if med is not None:
            s += f" si sigue igual, en {horizonte} años mediana {fmt_num(med)} ({fmt_num(p10)}–{fmt_num(p90)});"
        if escenarios:
            m = escenarios[0]
            r = m.get("rango") or []
            s += (
                f" mejor palanca: {m.get('etiqueta') or 'ver palancas'} "
                f"({fmt_delta(_num(m.get('anios_ganados')))} años"
                + (f", {fmt_rango_delta(_num(r[0]), _num(r[1]))}" if len(r) >= 2 else "")
                + f", esfuerzo {fmt_num(m.get('esfuerzo'))} de 10); {len(escenarios)} escenarios en total."
            )
        else:
            s += " sin escenarios con efecto apreciable (\"estás bien\")."
        partes.append(s)
    else:
        partes.append(
            "Todavía no hay una simulación en la app (o no me la enviaron): puedo hablar de sus datos y "
            "de cómo funciona el motor, y sugerir correr la simulación desde Futuro."
        )
    return Chunk(id="core", titulo="Lo que siempre sé", texto=" ".join(partes), grupo="core")


def build_documents(
    perfil: Mapping[str, Any],
    context: Mapping[str, Any],
    pheno: PhenoAgeResult | None,
    resultado: Mapping[str, Any] | None,
) -> tuple[Chunk, list[Chunk]]:
    """(always-on core card, every retrievable chunk for this user)."""
    chunks: list[Chunk] = [*user_chunks(perfil, context, pheno), *result_chunks(resultado), *KNOWLEDGE]
    return core_chunk(perfil, pheno, resultado), chunks


__all__: Sequence[str] = ("build_documents", "core_chunk", "result_chunks", "user_chunks")
