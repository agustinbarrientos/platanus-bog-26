"""Turn a lab-report document into validated `Biomarcador` readings.

No FastAPI, no database — a pure function of (document bytes, media type) to
a list of readings, each either usable or a reason it wasn't. `Claude reads
the document; this module owns unit conversion and the final go/no-go
decision, deterministically, so nothing here trusts model arithmetic for the
one step that must be exactly right.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Literal

from pydantic import BaseModel, ValidationError

from app.health_metrics.biomarkers import BIOMARKER_SPECS, BiomarkerName

if TYPE_CHECKING:
    from app.routers.health_context import Biomarcador

#: What the extraction prompt tells Claude about each biomarker: canonical
#: name, expected unit, and the synonyms a real lab report uses instead of
#: our internal vocabulary.
_SYNONYMS: dict[BiomarkerName, str] = {
    "hs_CRP": "PCR ultrasensible, Proteína C Reactiva, hs-CRP, PCR-us",
    "glucosa": "Glucosa, Glicemia, Glucosa en ayunas",
    "albumina": "Albúmina, Albúmina sérica",
    "creatinina": "Creatinina, Creatinina sérica",
    "fosfatasa_alcalina": "Fosfatasa alcalina, FA, ALP",
    "linfocitos_pct": "Linfocitos %, Linfocitos relativos, % Linfocitos",
    "vcm": "VCM, Volumen Corpuscular Medio, MCV",
    "rdw": "RDW, Ancho de Distribución Eritrocitaria, ADE",
    "leucocitos": "Leucocitos, Glóbulos blancos, WBC, Recuento leucocitario",
    "colesterol_total": "Colesterol total, Colesterol",
    "presion_sistolica": "Presión sistólica, PA sistólica, PAS",
    "imc": "IMC, Índice de masa corporal, BMI",
}


class ExtractedReading(BaseModel):
    """One row Claude found on the document. Value and unit are copied
    exactly as printed — conversion happens afterward, in Python."""

    nombre: BiomarkerName
    valor_reportado: float
    unidad_reportada: str
    #: Short verbatim snippet from the document, for traceability if a
    #: reading looks wrong later.
    fuente_texto: str


class ExtractionResult(BaseModel):
    lecturas: list[ExtractedReading]
    #: Clinically relevant things the document says that aren't one of the
    #: 12 known biomarkers — a diagnosis, a doctor's recommendation, an
    #: abnormal finding, a mentioned family history or allergy. Short,
    #: factual, one item per entry; folded into `health_context
    #: .notas_incertidumbre` alongside the biomarker extraction, since that
    #: field already exists for exactly this kind of context.
    hallazgos: list[str] = []
    notas: str | None = None


class ExtractionWarning(BaseModel):
    nombre: BiomarkerName
    valor_reportado: float
    unidad_reportada: str
    razon: str


def build_prompt() -> str:
    tabla = "\n".join(f"- {nombre}: {sinonimos}" for nombre, sinonimos in _SYNONYMS.items())
    return f"""Extrae del documento adjunto (un examen de laboratorio) cualquier lectura \
que corresponda claramente a uno de estos biomarcadores. Usa exactamente uno \
de estos nombres — no inventes otros:

{tabla}

Para cada lectura reconocida, reporta el valor y la unidad **exactamente como \
aparecen impresos en el documento** — no conviertas unidades, no redondees. \
Incluye un fragmento breve y textual de dónde lo leíste.

Si un valor no corresponde con confianza a ninguno de estos biomarcadores, o \
el documento no lo indica, simplemente omítelo — no adivines.

Además, si el documento menciona algo clínicamente relevante que no sea uno \
de estos biomarcadores — un diagnóstico, una recomendación del médico, un \
hallazgo anormal, un antecedente familiar o una alergia mencionada — repórtalo \
en "hallazgos": una frase breve y factual por cada uno, citando lo que dice \
el documento, sin diagnosticar ni interpretar tú. Si no hay nada así, deja \
"hallazgos" vacío.

Si alguna parte del documento es ilegible o no se pudo procesar, dilo \
brevemente en "notas"."""


#: (biomarcador, unidad_reportada) -> factor de conversión hacia
#: BIOMARKER_SPECS[biomarcador].unidad. Solo las unidades alternativas que
#: realmente aparecen en exámenes reales — no una tabla general de unidades.
UNIT_CONVERSIONS: dict[tuple[BiomarkerName, str], Callable[[float], float]] = {
    ("glucosa", "mmol/L"): lambda v: v * 18.0182,
    ("colesterol_total", "mmol/L"): lambda v: v * 38.67,
    ("creatinina", "umol/L"): lambda v: v / 88.4,
    ("creatinina", "µmol/L"): lambda v: v / 88.4,
    ("hs_CRP", "mg/dL"): lambda v: v * 10,
    ("leucocitos", "/uL"): lambda v: v / 1000,
    ("leucocitos", "céls/uL"): lambda v: v / 1000,
}


def convert_and_validate(reading: ExtractedReading) -> tuple[Biomarcador | None, ExtractionWarning | None]:
    """Convert to storage units if needed, then run the *same* validator
    `Biomarcador` already applies on a normal PATCH — imported lazily to
    avoid a circular import (`health_context` doesn't import this module).
    Returns (biomarcador, None) on success, (None, warning) otherwise.
    """
    from app.routers.health_context import Biomarcador  # noqa: PLC0415

    spec = BIOMARKER_SPECS[reading.nombre]
    valor = reading.valor_reportado
    if reading.unidad_reportada != spec.unidad:
        convertidor = UNIT_CONVERSIONS.get((reading.nombre, reading.unidad_reportada))
        if convertidor is None:
            return None, ExtractionWarning(
                nombre=reading.nombre,
                valor_reportado=reading.valor_reportado,
                unidad_reportada=reading.unidad_reportada,
                razon=f"unidad {reading.unidad_reportada!r} no reconocida para {reading.nombre}, "
                f"se esperaba {spec.unidad!r}",
            )
        valor = convertidor(valor)

    try:
        biomarcador = Biomarcador(nombre=reading.nombre, valor=valor, unidad=spec.unidad, fuente="documento")
    except ValidationError as exc:
        return None, ExtractionWarning(
            nombre=reading.nombre,
            valor_reportado=reading.valor_reportado,
            unidad_reportada=reading.unidad_reportada,
            razon=str(exc.errors()[0]["msg"]) if exc.errors() else str(exc),
        )
    return biomarcador, None


#: Accepted upload content types -> the Messages API content-block "type"
#: each becomes. Single source of truth for both the router's upload
#: validation and the block it builds.
ACCEPTED_CONTENT_TYPES: dict[str, Literal["document", "image"]] = {
    "application/pdf": "document",
    "image/png": "image",
    "image/jpeg": "image",
    "image/webp": "image",
}


def build_content_block(media_type: str, data_b64: str) -> dict:
    block_type = ACCEPTED_CONTENT_TYPES[media_type]
    return {
        "type": block_type,
        "source": {"type": "base64", "media_type": media_type, "data": data_b64},
    }
