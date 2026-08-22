"""Coeficientes de la Capa 2 (MOIRAI_ENGINE_SPEC.md §5): cuánto se mueve cada
uno de los 9 biomarcadores de PhenoAge por año, por edad sola y por cada
intervención. La *regla* que los aplica vive en `evolution.py`; acá solo están
los números y de dónde salen.

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

Todo en las unidades de almacenamiento de `BIOMARKER_SPECS` (mg/dL, g/dL, %,
fL, ...), aplicado una vez por año simulado.
"""

from __future__ import annotations

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
#: El caso más flojo es `glucosa`: 0.5 mg/dL/año está ~1,7x por encima de la
#: pendiente que implica la tabla (0,29) y muy por encima del ~1 mg/dL por
#: década que suele citarse para glucosa en ayunas en envejecimiento normal.
#: Se deja como está para no mover los números del demo sin decidirlo; queda
#: anotado como el primer coeficiente a recalibrar.
DYNAMICS: dict[str, BiomarkerDynamics] = {
    "hs_CRP": BiomarkerDynamics(0.03, 0.6),
    "glucosa": BiomarkerDynamics(0.5, 4.0),
    "albumina": BiomarkerDynamics(-0.01, 0.08),
    "creatinina": BiomarkerDynamics(0.005, 0.04),
    "fosfatasa_alcalina": BiomarkerDynamics(0.3, 4.0),
    "linfocitos_pct": BiomarkerDynamics(-0.15, 1.5),
    "vcm": BiomarkerDynamics(0.1, 1.0),
    "rdw": BiomarkerDynamics(0.03, 0.3),
    "leucocitos": BiomarkerDynamics(0.01, 0.4),
}

assert set(DYNAMICS) == set(PHENOAGE_BIOMARKERS)


class Scenario(NamedTuple):
    nombre: str
    #: Additional per-year delta on top of `DYNAMICS[...].deriva_anual`, for
    #: whichever biomarkers this intervention plausibly moves. Absent
    #: biomarkers get no adjustment beyond the natural drift.
    efectos_anuales: dict[str, float]


SCENARIOS: dict[str, Scenario] = {
    "ninguna": Scenario("Sin intervención (línea base)", {}),
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
    ),
    # leucocitos: dejar de fumar baja el recuento -0,03 a -1,12 x10^3/uL según
    #   dosis previa (<1 a >=2 cajetillas/día); la abstinencia confirmada
    #   bioquímicamente produce una caída rápida y sostenida de leucocitos y
    #   neutrófilos. Acumulado a 10 años: -1,1, el extremo alto del rango
    #   observado (fumador de >=2 cajetillas/día).
    #   Estaba en -0,15/año (-1,5 acumulado), por encima del máximo publicado;
    #   lo detectó `test_acumulado_a_10_anios_dentro_del_rango_publicado`.
    # vcm: los fumadores tienen VCM significativamente mayor que los no
    #   fumadores, de forma dosis-dependiente. Acumulado: -1,5 fL.
    # hs_CRP: componente inflamatorio del tabaquismo. Ojo: la normalización
    #   hematológica completa tarda >=5 años tras dejar de fumar, así que
    #   modelar esto como pendiente constante subestima el primer año y
    #   sobreestima el último.
    "cesacion_tabaco": Scenario(
        "Cesación de tabaco",
        {"leucocitos": -0.11, "hs_CRP": -0.10, "vcm": -0.15},
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
    # ilustrativos de la spec §5.
    "sueno_8h": Scenario(
        "Dormir 8 horas",
        {"hs_CRP": -0.05, "glucosa": -0.2},
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
    ),
    # Combinación precocinada de ejercicio + dieta + cesación. NO es la suma de
    # las tres (esa daría hs_CRP -0,24 / glucosa -1,5 / leucocitos -0,14): se
    # aplica sublinealidad a mano porque los tres actúan sobre vías
    # inflamatorias y metabólicas que se solapan, y sumarlas linealmente
    # sobreestimaría el beneficio conjunto. El descuento (~-17% en PCR, -14% en
    # leucocitos) es una decisión de modelado, no un resultado publicado.
    # `test_combinada_es_sublineal_frente_a_sumar_sus_partes` la mantiene.
    "combinada": Scenario(
        "Ejercicio + dieta mediterránea + cesación de tabaco",
        {
            "hs_CRP": -0.20, "glucosa": -1.4, "leucocitos": -0.12,
            "albumina": 0.01, "vcm": -0.10,
        },
    ),
}
