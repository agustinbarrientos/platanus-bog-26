"""Respaldo de literatura de cada palanca, para citarlo en el reporte
(docs/MOIRAI_REPORTE_SPEC.md §3–§4: "ranking de intervenciones CON su fuente
de literatura citada", "cada una con el respaldo: asociado en la literatura
con reducción de inflamación (referencia)").

Es la misma procedencia que está anotada, coeficiente por coeficiente, en
`interventions.py` — aquí solo queda en frases citables para un lector
humano (la persona y su médico). Dos reglas:

- Se describe lo que dicen los estudios en términos de BIOMARCADORES (PCR,
  glucosa, leucocitos, VCM), que es lo que el motor mueve. Nunca "previene X"
  ni "cura Y".
- Solo se nombra un estudio con autor/año cuando la cita es segura; si no, se
  describe el tipo de evidencia (metaanálisis de ensayos, cohortes) sin
  inventar autores. Las cifras (tamaños de efecto) son las mismas que las
  notas de `interventions.py`, que es donde se calibran.

`FUENTES_GENERALES` son las que van al pie de cada página del reporte.
"""

from __future__ import annotations

from typing import NamedTuple


class Evidencia(NamedTuple):
    #: Qué encontró la literatura, en una frase (lenguaje humano).
    hallazgo: str
    #: La referencia, tal cual se imprime.
    fuente: str


EVIDENCIA_PALANCAS: dict[str, tuple[Evidencia, ...]] = {
    "ejercicio_aerobico": (
        Evidencia(
            "El entrenamiento físico sostenido se asocia con menor proteína C reactiva "
            "(en adultos sanos, efecto pequeño; en adultos sedentarios, moderado) y con "
            "menor glucosa en ayunas (del orden de 5 a 10 mg/dL en los ensayos).",
            "Fedewa MV, Hathaway ED, Ward-Ritacco CL. Br J Sports Med 2017;51:670–676 "
            "(revisión sistemática y metaanálisis de ensayos controlados sobre PCR); "
            "metaanálisis de ensayos de entrenamiento combinado en adultos sedentarios.",
        ),
        Evidencia(
            "150 minutos semanales de actividad moderada es la recomendación mínima de la OMS para adultos.",
            "OMS, Directrices sobre actividad física y hábitos sedentarios, 2020.",
        ),
    ),
    "dieta_mediterranea": (
        Evidencia(
            "Un patrón mediterráneo (verduras, legumbres, pescado, aceite de oliva) redujo la "
            "proteína C reactiva alrededor de 0,5–0,7 mg/L y la glucosa en ayunas unos 4–7 mg/dL "
            "en ensayos controlados, el mayor efecto entre los patrones dietarios evaluados.",
            "Estruch R, et al. Ann Intern Med 2006;145:1–11 (ensayo PREDIMED, factores de riesgo); "
            "revisiones paraguas de metaanálisis de ensayos sobre patrones dietarios e inflamación.",
        ),
    ),
    "cesacion_tabaco": (
        Evidencia(
            "Dejar de fumar baja el recuento de leucocitos y la proteína C reactiva de forma "
            "dosis-dependiente, y el volumen corpuscular medio (que el tabaco eleva) vuelve a "
            "valores de no fumador en unos años.",
            "Cohortes y ensayos de cesación con abstinencia confirmada bioquímicamente "
            "(leucocitos, neutrófilos, PCR); estudios poblacionales de VCM en fumadores.",
        ),
    ),
    "sueno_8h": (
        Evidencia(
            "Dormir poco se asocia con más proteína C reactiva e interleucina-6; los ensayos de "
            "extensión de sueño mejoran la sensibilidad a la insulina, aunque el efecto sobre la "
            "PCR es más modesto. Por eso esta palanca se modela de forma conservadora.",
            "Irwin MR, Olmstead R, Carroll JE. Biol Psychiatry 2016;80:40–52 (revisión sistemática "
            "y metaanálisis de sueño e inflamación); ensayos de extensión de sueño en durmientes cortos.",
        ),
    ),
    "reducir_estres": (
        Evidencia(
            "Las intervenciones basadas en atención plena (mindfulness) reducen marcadores de "
            "inflamación crónica en metaanálisis de ensayos; el efecto es pequeño y más claro en "
            "personas de mediana edad en adelante.",
            "Black DS, Slavich GM. Ann N Y Acad Sci 2016;1373:13–24 (revisión sistemática de ensayos "
            "sobre mindfulness y sistema inmune); metaanálisis de ensayos sobre PCR e IL-6.",
        ),
    ),
    "reducir_alcohol": (
        Evidencia(
            "El consumo alto de alcohol eleva el volumen corpuscular medio (se normaliza en 2–4 meses "
            "de moderación) y se asocia con más proteína C reactiva que el consumo bajo.",
            "Imhof A, et al. Lancet 2001;357:763–767 (alcohol y marcadores de inflamación); "
            "estudios de laboratorio sobre macrocitosis asociada al alcohol.",
        ),
    ),
}

#: Fuentes generales del motor (pie de página del reporte).
FUENTES_GENERALES: tuple[str, ...] = (
    "Levine ME, et al. An epigenetic biomarker of aging for lifespan and healthspan. Aging 2018;10:573–591 (PhenoAge).",
    "NHANES (CDC): medianas y dispersión poblacional de referencia por edad y sexo (tabla aproximada del motor).",
    "Tamaños de efecto de las palancas: metaanálisis y ensayos citados en cada recomendación.",
)


def evidencia_de(palanca: str) -> tuple[Evidencia, ...]:
    return EVIDENCIA_PALANCAS.get(palanca, ())


__all__ = ["EVIDENCIA_PALANCAS", "Evidencia", "FUENTES_GENERALES", "evidencia_de"]
