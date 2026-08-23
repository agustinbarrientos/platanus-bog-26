"""Coeficientes de la Capa 2 (MOIRAI_ENGINE_SPEC.md §5): cuánto se mueve cada
uno de los 9 biomarcadores de PhenoAge por año, por edad sola y por cada
intervención; qué hábito registrado cierra cada palanca y cuánto cuesta. La
*regla* que los aplica vive en `evolution.py`; acá solo están los números y
de dónde salen.

ADVERTENCIA DE PROCEDENCIA — esto NO es el paper de PhenoAge.
Los coeficientes de la Capa 1 (`phenoage.py`) son los publicados por Levine et
al. 2018 y se verifican contra el paper. Los de este módulo son otra cosa:
tamaños de efecto **aproximados, derivados de literatura epidemiológica**, cada
uno anotado abajo con el estudio del que sale su orden de magnitud. Son
citables, no exactos. El pitch tiene que decirlo así (spec §13). Nada acá está
ajustado a los datos de un usuario ni a una cohorte propia.

REGLA DE CALIBRACIÓN de los efectos de intervención: los ensayos publican un
*desplazamiento total* del biomarcador al final del estudio (ej. la dieta
mediterránea baja la PCR 0,54–0,71 mg/L), no una pendiente por año. Acá se
necesita una pendiente. La convención de este módulo es fijar el modificador
anual de modo que **el acumulado a 10 años caiga dentro del rango observado en
los ensayos**: -0,06 mg/L/año × 10 años = -0,6 mg/L, que es justo la banda de
la literatura. `tests/test_evolution.py` verifica ese acumulado escenario por
escenario, así que la calibración no puede desviarse en silencio.

CÓMO ENTRAN LOS HÁBITOS (gemelo digital). Cada palanca cierra la *brecha* de
un hábito registrado (`habito`): la brecha es 1 si la persona tiene el hábito
"malo" del todo (fuma, sedentaria, duerme ≤6 h…), 0 si ya tiene el hábito
bueno, y 0,5 en el nivel intermedio. Con eso:
- El efecto de la palanca se escala por la brecha: a quien ya hace ejercicio
  no se le ofrece (brecha 0 → efecto 0, `aplica=False`).
- La línea base de la persona se ajusta por sus hábitos ACTUALES con una
  descomposición de mezcla: la deriva natural de `DYNAMICS` es la de la
  población (mezcla de hábitos buenos y malos); si el efecto bueno→malo de una
  palanca es E y la fracción poblacional con el hábito malo es ḡ
  (`brecha_promedio`), la persona con brecha g deriva `D + (g − ḡ)·|E|`: el
  fumador envejece más rápido que la población, el no fumador un poco menos.
  El ajuste "bueno" se acota a como mucho neutralizar la deriva por edad —
  tener buenos hábitos frena el reloj, no lo hace retroceder para siempre.
  Consecuencia: intervenir (cerrar la brecha) deja a la persona exactamente en
  la deriva de quien ya tenía el hábito bueno (`D − ḡ·|E|`), y los años
  ganados por la palanca NO dependen de ḡ — solo dónde queda la línea base.
- ḡ son prevalencias aproximadas (tabaquismo ~10 % en Colombia —ENCSPA 2019—,
  actividad insuficiente ~50 %, sueño corto ~35 %, estrés alto ~30 %, consumo
  alto de alcohol ~15 %): supuestos declarados, no resultados nuestros.

Todo en las unidades de almacenamiento de `BIOMARKER_SPECS` (mg/dL, g/dL, %,
fL, ...), aplicado una vez por año simulado.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import NamedTuple

from app.health_metrics.biomarkers import PHENOAGE_BIOMARKERS


class BiomarkerDynamics(NamedTuple):
    deriva_anual: float  # natural aging trend, per year
    ruido_anual_sd: float  # year-to-year biological variability (Gaussian SD)


#: Deriva natural por edad + ruido, independiente de cualquier intervención.
#:
#: FUENTE de `deriva_anual`: la literatura no publica pendientes anuales limpias
#: y comparables para los 9 biomarcadores a la vez, así que estas reproducen el
#: **gradiente por edad de la propia tabla de medianas del motor**
#: (`nhanes_reference._MEDIANS`, medianas por tramo de edad y sexo). Eso las
#: hace verificables en vez de ser números sueltos: `test_evolution.py`
#: comprueba que cada deriva tenga el mismo signo y el mismo orden de magnitud
#: que la pendiente implícita en esa tabla. Es un ancla interna y consistente,
#: no una estimación poblacional publicada — que es exactamente lo que se puede
#: defender ante el jurado.
#:
#: Recalibradas el 2026-08-22 junto con la tabla de medianas (ver la nota de
#: calibración en `nhanes_reference.py`): la tabla anterior tenía un gradiente
#: demasiado empinado y la persona de referencia "envejecía" 1,2 años PhenoAge
#: por año; con estas derivas la referencia envejece ≈1,0 por año, que es lo
#: que por construcción hace PhenoAge en su población de ajuste.
DYNAMICS: dict[str, BiomarkerDynamics] = {
    "hs_CRP": BiomarkerDynamics(0.012, 0.6),
    "glucosa": BiomarkerDynamics(0.20, 4.0),
    "albumina": BiomarkerDynamics(-0.005, 0.08),
    "creatinina": BiomarkerDynamics(0.002, 0.04),
    "fosfatasa_alcalina": BiomarkerDynamics(0.15, 4.0),
    "linfocitos_pct": BiomarkerDynamics(-0.05, 1.5),
    "vcm": BiomarkerDynamics(0.035, 1.0),
    "rdw": BiomarkerDynamics(0.012, 0.3),
    "leucocitos": BiomarkerDynamics(0.005, 0.4),
}

assert set(DYNAMICS) == set(PHENOAGE_BIOMARKERS)

#: Sublinealidad al combinar palancas: dos o tres palancas que actúan sobre el
#: MISMO biomarcador (p. ej. PCR con ejercicio + dieta + dejar el tabaco) no
#: suman sus beneficios en la realidad porque tocan vías inflamatorias y
#: metabólicas que se solapan. Por cada palanca adicional que toca un
#: biomarcador se descuenta un 8 % de la suma: 2 palancas → ×0,92; 3 → ×0,84.
#: Es una decisión de modelado (reproduce el descuento ~15–17 % que traía el
#: escenario `combinada` precocinado), no un resultado publicado.
DESCUENTO_COMBINACION = 0.08

#: Spec §12: nunca más de 3 intervenciones simultáneas.
MAX_INTERVENCIONES = 3

#: Biomarcadores cuyos efectos de palanca (y ajustes por hábito) son
#: PROPORCIONALES al valor actual, no una cantidad fija: el valor es la PCR a
#: la que están calibrados los coeficientes (la media de las poblaciones de
#: los ensayos citados, ~2–3 mg/L). Un efecto de -0,08 mg/L/año a 2,5 mg/L es
#: -3,2 %/año: quien tiene PCR 5,5 baja -0,18 mg/L/año y quien tiene 0,4 baja
#: -0,013. Por qué: los ensayos de PCR reportan reducciones relativas (y
#: absolutas mayores cuanto más inflamado), la PCR es log-normal y entra a
#: PhenoAge en logaritmo, y con efectos absolutos una persona con PCR baja
#: "ganaba" años imposibles empujando la PCR al piso del ensayo (diagnóstico
#: 2026-08-22: un combo de 3 palancas ganaba más que la suma de sus partes).
EFECTO_RELATIVO_A: dict[str, float] = {"hs_CRP": 2.5}

#: Heterogeneidad de respuesta: el efecto de una palanca en la Capa 3 se
#: multiplica, trayectoria a trayectoria, por m ~ N(1, 0,5) truncada en 0 —
#: la misma persona "sorteada" responde más o menos que el promedio del
#: ensayo, y ~2 % de los futuros no responde. Recoge dos cosas que el efecto
#: promedio esconde: la variabilidad individual de respuesta (bien documentada
#: en ejercicio y dieta: hay no respondedores) y la incertidumbre del propio
#: coeficiente (los IC de los metaanálisis citados son del orden de ±50 % del
#: punto). Es lo que da un RANGO honesto a los años ganados y un "% de
#: futuros que mejoran" < 100 % aun con futuros pareados. 0,5 es una
#: decisión de modelado declarada, no un valor publicado.
HETEROGENEIDAD_RESPUESTA = 0.5


class Scenario(NamedTuple):
    nombre: str
    #: Additional per-year delta on top of `DYNAMICS[...].deriva_anual`, for
    #: whichever biomarkers this intervention plausibly moves (at brecha = 1).
    #: Absent biomarkers get no adjustment beyond the natural drift.
    efectos_anuales: dict[str, float]
    #: Costo percibido 1–10 (spec §6 `ESFUERZO`): las palancas se ordenan por
    #: años ganados / esfuerzo.
    esfuerzo: int = 0
    #: Lo que la app muestra bajo la palanca.
    descripcion: str = ""
    #: Hábito registrado que esta palanca cierra (`HABITOS`), o None.
    habito: str | None = None
    #: ḡ: fracción poblacional con la brecha abierta (ver docstring del módulo).
    brecha_promedio: float = 0.0
    #: Escenario compuesto: las palancas simples que lo forman.
    partes: tuple[str, ...] = ()


#: Hábitos que el motor lee del contexto de salud (`habitos` de
#: `/me/health-context`), en el vocabulario con el que la app los manda.
HABITOS: tuple[str, ...] = ("actividad", "alimentacion", "tabaco", "sueno", "estres", "alcohol")

#: Brecha que se asume para el EFECTO de una palanca cuando el hábito no está
#: registrado: las "universales" (todo el mundo puede dormir más, moverse más,
#: comer mejor, estresarse menos) se ofrecen con efecto completo, como hacía el
#: motor antes de leer hábitos; las que solo tienen sentido si la persona hace
#: algo (fumar, beber mucho) no se asumen. La línea base NO se ajusta por un
#: hábito desconocido (ajuste 0): no se castiga ni se premia lo que no se sabe.
BRECHA_DESCONOCIDA: dict[str, float] = {
    "actividad": 1.0,
    "alimentacion": 1.0,
    "sueno": 1.0,
    "estres": 1.0,
    "tabaco": 0.0,
    "alcohol": 0.0,
}

_PALANCAS: dict[str, Scenario] = {
    # hs_CRP: metaanálisis de 38 RCT en 2.557 sujetos sanos, entrenamiento
    #   prolongado -> PCR SMD -0,18 (IC95% -0,31 a -0,06); en adultos
    #   sedentarios, 24 RCT de entrenamiento combinado -> PCR SMD -0,51.
    #   Acumulado a 10 años: -0,8 mg/L, dentro de la banda absoluta típica
    #   (-0,3 a -1,0 mg/L).
    # glucosa: los mismos 24 RCT -> glucosa en ayunas SMD -0,47; los ensayos
    #   reportan del orden de -5 a -10 mg/dL. Acumulado: -9 mg/dL.
    # leucocitos: efecto antiinflamatorio secundario, el más flojo de los tres.
    "ejercicio_aerobico": Scenario(
        "Ejercicio aeróbico regular",
        {"hs_CRP": -0.08, "glucosa": -0.9, "leucocitos": -0.03},
        esfuerzo=3,
        descripcion="150 minutos a la semana de algo que te suba el pulso: caminar rápido, bici, nadar.",
        habito="actividad",
        brecha_promedio=0.5,
    ),
    # hs_CRP: PREDIMED (dieta mediterránea + aceite de oliva vs baja en grasa)
    #   -> PCR -0,54 mg/L; revisión paraguas de metaanálisis de RCT -> -0,71
    #   mg/L, el mayor efecto de todos los patrones dietarios evaluados.
    #   Acumulado a 10 años: -0,6 mg/L, entre ambos.
    # glucosa: Estruch et al. 2006 (Ann Intern Med) -> -3,8 mg/dL a 2 años;
    #   PREDIMED -> -0,39 mmol/L (~-7 mg/dL). Acumulado: -6 mg/dL.
    # albumina: efecto nutricional pequeño y positivo (albúmina alta protege).
    "dieta_mediterranea": Scenario(
        "Dieta mediterránea",
        {"hs_CRP": -0.06, "glucosa": -0.6, "albumina": 0.01},
        esfuerzo=3,
        descripcion="Más verduras, legumbres, pescado y aceite de oliva; menos ultraprocesados. Un patrón, no una dieta.",
        habito="alimentacion",
        brecha_promedio=0.5,
    ),
    # leucocitos: dejar de fumar baja el recuento -0,03 a -1,12 x10^3/uL según
    #   dosis previa (<1 a >=2 cajetillas/día); la abstinencia confirmada
    #   bioquímicamente produce una caída rápida y sostenida de leucocitos y
    #   neutrófilos. Acumulado a 10 años: -1,1, el extremo alto del rango
    #   observado (fumador de >=2 cajetillas/día).
    # vcm: los fumadores tienen VCM significativamente mayor que los no
    #   fumadores, de forma dosis-dependiente. Acumulado: -1,5 fL.
    # hs_CRP: componente inflamatorio del tabaquismo. Ojo: la normalización
    #   hematológica completa tarda >=5 años tras dejar de fumar, así que
    #   modelar esto como pendiente constante subestima el primer año y
    #   sobreestima el último.
    "cesacion_tabaco": Scenario(
        "Cesación de tabaco",
        {"leucocitos": -0.11, "hs_CRP": -0.10, "vcm": -0.15},
        esfuerzo=4,
        descripcion="Cero cigarrillos. Es la palanca que más mueve la inflamación y los leucocitos.",
        habito="tabaco",
        brecha_promedio=0.10,
    ),
    # Palanca de la spec §5 (`sueno_8h`), deliberadamente CONSERVADORA porque
    # la evidencia es más débil que la de ejercicio o dieta:
    # - Asociación observacional consistente: dormir poco se asocia a PCR e
    #   IL-6 más altas en adultos de EE.UU.
    # - Pero los ensayos de extensión de sueño son mixtos: mejoran la
    #   resistencia a la insulina en ayunas, la respuesta temprana a la glucosa
    #   y la función de célula beta en durmientes cortos, mientras que PCR,
    #   presión arterial y glucosa en ayunas NO se movieron significativamente
    #   en adultos jóvenes sanos.
    # Por eso el efecto se fija por debajo del de ejercicio: acumulado a 10
    # años -0,5 mg/L de PCR y -2 mg/dL de glucosa. Coincide con los valores
    # ilustrativos de la spec §5. La brecha sale de las horas: ≤6 h → 1,
    # ≥7,5 h → 0, lineal en medio.
    "sueno_8h": Scenario(
        "Dormir 8 horas",
        {"hs_CRP": -0.05, "glucosa": -0.2},
        esfuerzo=2,
        descripcion="Acostarte a una hora fija y llegar a 7,5–8 horas casi todas las noches.",
        habito="sueno",
        brecha_promedio=0.35,
    ),
    # Palanca de la spec §5 (`reducir_estres`). Metaanálisis de 48 RCT con
    # 4.683 participantes: las intervenciones basadas en mindfulness reducen
    # significativamente marcadores de inflamación crónica (PCR, IL-6). Pero
    # los ensayos individuales grandes en adultos de la comunidad no encuentran
    # reducción de PCR salvo en subgrupos de riesgo (mediana edad en adelante,
    # IMC alto). Efecto pequeño y solo sobre PCR: acumulado -0,4 mg/L.
    "reducir_estres": Scenario(
        "Reducir el estrés",
        {"hs_CRP": -0.04},
        esfuerzo=2,
        descripcion="Un hábito diario que lo baje de verdad: pausas, respiración, terapia.",
        habito="estres",
        brecha_promedio=0.30,
    ),
    # Palanca de la spec §5 (`dejar_alcohol`), ACOTADA al consumo alto:
    # vcm: el VCM está elevado de forma dosis-dependiente en bebedores fuertes
    #   (macrocitosis por alcohol, +2–4 fL frente a abstemios) y se normaliza
    #   en 2–4 meses de abstinencia. Acumulado a 10 años: -2 fL (en realidad
    #   es un cambio de nivel rápido; la pendiente constante lo reparte).
    # hs_CRP: la relación alcohol–PCR es en J: el consumo alto (>2 tragos/día)
    #   se asocia a PCR mayor que el moderado (Imhof et al. 2001, Lancet).
    #   Acumulado: -0,3 mg/L, el valor ilustrativo de la spec §5.
    # No se modela creatinina (el de la spec era dudoso) ni glucosa.
    "reducir_alcohol": Scenario(
        "Bajar el alcohol",
        {"vcm": -0.20, "hs_CRP": -0.03},
        esfuerzo=2,
        descripcion="De casi diario a ocasional. Las copas del fin de semana también cuentan.",
        habito="alcohol",
        brecha_promedio=0.15,
    ),
}


def efectos_combinados(partes: Iterable[str], brechas_efecto: Mapping[str, float] | None = None) -> dict[str, float]:
    """Efecto anual conjunto de varias palancas simples sobre cada biomarcador:
    suma de efectos (escalados por la brecha de cada una) con el descuento de
    `DESCUENTO_COMBINACION` por cada palanca adicional que toque el mismo
    biomarcador."""
    por_biomarcador: dict[str, list[float]] = {}
    for key in partes:
        sc = _PALANCAS[key]
        g = 1.0 if brechas_efecto is None else brechas_efecto.get(key, 1.0)
        for nombre, efecto in sc.efectos_anuales.items():
            if efecto != 0.0 and g != 0.0:
                por_biomarcador.setdefault(nombre, []).append(g * efecto)
    return {
        nombre: sum(efectos) * (1.0 - DESCUENTO_COMBINACION * (len(efectos) - 1))
        for nombre, efectos in por_biomarcador.items()
    }


_PARTES_COMBINADA = ("ejercicio_aerobico", "dieta_mediterranea", "cesacion_tabaco")

SCENARIOS: dict[str, Scenario] = {
    "ninguna": Scenario("Sin intervención (línea base)", {}),
    **_PALANCAS,
    # Combinación precocinada de ejercicio + dieta + cesación. Se mantiene por
    # compatibilidad (la app la pedía por esa clave); hoy es el mismo escenario
    # compuesto "ejercicio_aerobico+dieta_mediterranea+cesacion_tabaco" que se
    # obtiene con la regla genérica de sublinealidad. Solo aplica si las tres
    # brechas están abiertas (en particular, si la persona fuma).
    "combinada": Scenario(
        "Ejercicio + dieta mediterránea + cesación de tabaco",
        efectos_combinados(_PARTES_COMBINADA),
        esfuerzo=sum(_PALANCAS[k].esfuerzo for k in _PARTES_COMBINADA),
        descripcion="Las tres a la vez.",
        partes=_PARTES_COMBINADA,
    ),
}

#: Las palancas simples (lo que el barrido combina), en orden de declaración.
PALANCAS: tuple[str, ...] = tuple(_PALANCAS)


def expandir(escenario: str) -> tuple[str, ...]:
    """Palancas simples de un escenario: `"ninguna"` → (); una palanca → (ella,);
    un compuesto declarado (`combinada`) → sus partes; `"a+b+c"` → las tres.
    ValueError si una parte no existe, se repite o son más de
    `MAX_INTERVENCIONES`."""
    if escenario == "ninguna":
        return ()
    if escenario in SCENARIOS:
        sc = SCENARIOS[escenario]
        return sc.partes if sc.partes else (escenario,)
    partes = tuple(p.strip() for p in escenario.split("+") if p.strip())
    if not partes:
        raise ValueError(f"escenario vacío: {escenario!r}")
    for p in partes:
        if p not in _PALANCAS:
            raise ValueError(f"palanca desconocida: {p!r}")
    if len(set(partes)) != len(partes):
        raise ValueError(f"palanca repetida en {escenario!r}")
    if len(partes) > MAX_INTERVENCIONES:
        raise ValueError(f"máximo {MAX_INTERVENCIONES} intervenciones por escenario (spec §12): {escenario!r}")
    return partes


def es_escenario_valido(escenario: str) -> bool:
    try:
        expandir(escenario)
    except ValueError:
        return False
    return True


def palancas_de(escenarios: Iterable[str]) -> list[str]:
    """Palancas simples activas en una lista de escenarios, sin repetir y en
    orden de aparición."""
    out: list[str] = []
    for esc in escenarios:
        for p in expandir(esc):
            if p not in out:
                out.append(p)
    return out


def etiqueta_de(escenario: str) -> str:
    if escenario in SCENARIOS:
        return SCENARIOS[escenario].nombre
    partes = expandir(escenario)
    nombres = [SCENARIOS[p].nombre for p in partes]
    return " + ".join([nombres[0], *[n[0].lower() + n[1:] for n in nombres[1:]]])


def esfuerzo_de(escenario: str) -> int:
    if escenario in SCENARIOS:
        return SCENARIOS[escenario].esfuerzo
    return sum(SCENARIOS[p].esfuerzo for p in expandir(escenario))


def descripcion_de(escenario: str) -> str:
    if escenario in SCENARIOS:
        return SCENARIOS[escenario].descripcion
    return " · ".join(SCENARIOS[p].descripcion for p in expandir(escenario))


# ---- Hábitos -> brechas ---------------------------------------------------------

_NIVEL_BRECHA_ADVERSO_ALTO = {"alto": 1.0, "alta": 1.0, "medio": 0.5, "media": 0.5, "bajo": 0.0, "baja": 0.0}
_NIVEL_BRECHA_ADVERSO_BAJO = {"baja": 1.0, "bajo": 1.0, "media": 0.5, "medio": 0.5, "alta": 0.0, "alto": 0.0}
_ALCOHOL_BRECHA = {"alto": 1.0, "moderado": 0.5, "ocasional": 0.0, "nunca": 0.0}


def brecha_sueno(horas: float) -> float:
    """≤6 h → 1 (brecha completa), ≥7,5 h → 0, lineal entre medias."""
    return min(1.0, max(0.0, (7.5 - float(horas)) / 1.5))


def brechas_desde_habitos(habitos: Mapping[str, object] | None) -> dict[str, float | None]:
    """Convierte el objeto `habitos` guardado (`sueno_h`, `tabaco`, `actividad`,
    `alimentacion`, `estres`, `alcohol`) en una brecha 0–1 por hábito de
    `HABITOS`; `None` = no registrado. Tolera las dos grafías de nivel que
    circulan (baja/bajo, media/medio, alta/alto) y valores desconocidos (→ None).
    """
    h = habitos or {}
    out: dict[str, float | None] = {k: None for k in HABITOS}

    act = h.get("actividad")
    if isinstance(act, str):
        out["actividad"] = _NIVEL_BRECHA_ADVERSO_BAJO.get(act.strip().lower())
    ali = h.get("alimentacion")
    if isinstance(ali, str):
        out["alimentacion"] = _NIVEL_BRECHA_ADVERSO_BAJO.get(ali.strip().lower())
    est = h.get("estres")
    if isinstance(est, str):
        out["estres"] = _NIVEL_BRECHA_ADVERSO_ALTO.get(est.strip().lower())
    tab = h.get("tabaco")
    if isinstance(tab, bool):
        out["tabaco"] = 1.0 if tab else 0.0
    sue = h.get("sueno_h")
    if isinstance(sue, (int, float)) and not isinstance(sue, bool):
        out["sueno"] = brecha_sueno(sue)
    alc = h.get("alcohol")
    if isinstance(alc, str):
        out["alcohol"] = _ALCOHOL_BRECHA.get(alc.strip().lower())
    return out


def brecha_efectiva(brechas: Mapping[str, float | None] | None, habito: str | None) -> float:
    """Brecha con la que se aplica el EFECTO de una palanca: la registrada si
    se conoce, `BRECHA_DESCONOCIDA` si no, 1 en modo legado (sin hábitos) o si
    la palanca no cierra ningún hábito."""
    if brechas is None or habito is None:
        return 1.0
    g = brechas.get(habito)
    if g is None:
        return BRECHA_DESCONOCIDA.get(habito, 1.0)
    return float(g)


def brechas_efecto_por_palanca(brechas: Mapping[str, float | None] | None) -> dict[str, float]:
    return {key: brecha_efectiva(brechas, sc.habito) for key, sc in _PALANCAS.items()}


def aplica(escenario: str, brechas: Mapping[str, float | None] | None) -> bool:
    """¿Tiene sentido ofrecer este escenario a esta persona? Sí si al menos una
    de sus palancas tiene brecha > 0 (la línea base siempre "aplica")."""
    partes = expandir(escenario)
    if not partes:
        return True
    return any(brecha_efectiva(brechas, SCENARIOS[p].habito) > 0.0 for p in partes)
