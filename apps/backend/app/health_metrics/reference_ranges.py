"""Rangos de referencia clínicos de los 12 biomarcadores que acepta la API, para
el reporte descargable (docs/MOIRAI_REPORTE_SPEC.md §1: "valor, rango de
referencia y una marca de cuáles están en borde/fuera").

Esto NO es parte del motor (PhenoAge no usa rangos: usa el valor continuo) y
NO es un diagnóstico: es la tabla de referencia que trae cualquier informe de
laboratorio, con la fuente de cada rango. Un valor "fuera del rango de
referencia" se reporta exactamente así — nunca con el nombre de una
enfermedad. La regla de clasificación es deliberadamente simple y declarada:

- `en_rango`: dentro de [lo, hi].
- `borde`: fuera de [lo, hi] pero dentro de la banda límite explícita del
  biomarcador (p. ej. glucosa en ayunas 100–125 mg/dL, colesterol total
  200–239 mg/dL), o —si el biomarcador no tiene banda explícita— a menos del
  10 % del ancho del rango por fuera del límite.
- `fuera`: más allá de eso.

Los rangos son los de adultos de los documentos citados en cada entrada;
varían por laboratorio, edad y método, y el reporte lo dice. Los rangos de
laboratorio "habituales" (albúmina, creatinina, fosfatasa, hemograma) son los
que publican los grandes laboratorios de referencia y MedlinePlus; los de
PCR, glucosa, colesterol, presión e IMC salen de guías de sociedades.
"""

from __future__ import annotations

from typing import Literal, NamedTuple

Estado = Literal["en_rango", "borde", "fuera"]


class RangoReferencia(NamedTuple):
    #: Límite inferior del rango de referencia (None = no hay límite bajo relevante).
    lo: float | None
    #: Límite superior (None = sin límite alto relevante).
    hi: float | None
    #: Banda límite explícita por encima de `hi` (inclusive): `borde` hasta aquí.
    borde_alto: float | None
    #: Banda límite explícita por debajo de `lo` (inclusive).
    borde_bajo: float | None
    #: Texto del rango tal como se imprime ("70–99 mg/dL").
    texto: str
    #: De dónde sale el rango.
    fuente: str
    #: Matiz para el lector (opcional), solo si el valor está fuera/borde.
    nota: str | None = None
    #: Si se fija, la nota solo aplica cuando el valor supera este umbral
    #: (p. ej. la de PCR habla de > 10 mg/L).
    nota_si_mayor_a: float | None = None


#: Por sexo cuando aplica ("F"/"M"); "*" = cualquiera.
_RANGOS: dict[str, dict[str, RangoReferencia]] = {
    "hs_CRP": {
        "*": RangoReferencia(
            None, 3.0, None, None, "< 3 mg/L",
            "AHA/CDC 2003 (Pearson et al., Circulation): < 1 bajo, 1–3 promedio, > 3 alto",
            "Por encima de 10 mg/L suele reflejar un proceso agudo reciente (una infección, por ejemplo); vale la pena repetir la medición en unas semanas.",
            nota_si_mayor_a=10.0,
        )
    },
    "glucosa": {
        "*": RangoReferencia(
            70.0, 99.0, 125.0, None, "70–99 mg/dL (en ayunas)",
            "ADA, Standards of Care (glucosa en ayunas 100–125 mg/dL = banda límite)",
        )
    },
    "albumina": {
        "*": RangoReferencia(3.5, 5.0, None, None, "3,5–5,0 g/dL", "rango de laboratorio habitual (MedlinePlus)")
    },
    "creatinina": {
        "F": RangoReferencia(0.5, 1.1, None, None, "0,5–1,1 mg/dL", "rango de laboratorio habitual para mujeres; varía con la masa muscular"),
        "M": RangoReferencia(0.7, 1.3, None, None, "0,7–1,3 mg/dL", "rango de laboratorio habitual para hombres; varía con la masa muscular"),
        "*": RangoReferencia(0.5, 1.3, None, None, "0,5–1,3 mg/dL", "rango de laboratorio habitual; varía con el sexo y la masa muscular"),
    },
    "fosfatasa_alcalina": {
        "*": RangoReferencia(44.0, 147.0, None, None, "44–147 U/L", "rango de laboratorio habitual (MedlinePlus); varía por laboratorio y edad")
    },
    "linfocitos_pct": {
        "*": RangoReferencia(20.0, 40.0, None, None, "20–40 %", "rango de laboratorio habitual del hemograma")
    },
    "vcm": {
        "*": RangoReferencia(80.0, 100.0, None, None, "80–100 fL", "rango de laboratorio habitual del hemograma")
    },
    "rdw": {
        "*": RangoReferencia(11.5, 14.5, None, None, "11,5–14,5 %", "rango de laboratorio habitual del hemograma")
    },
    "leucocitos": {
        "*": RangoReferencia(4.0, 11.0, None, None, "4,0–11,0 ×10³/µL", "rango de laboratorio habitual del hemograma")
    },
    "colesterol_total": {
        "*": RangoReferencia(
            None, 199.0, 239.0, None, "< 200 mg/dL",
            "NCEP ATP III: < 200 deseable, 200–239 límite, 240 o más alto",
        )
    },
    "presion_sistolica": {
        "*": RangoReferencia(
            90.0, 119.0, 129.0, None, "90–119 mmHg",
            "ACC/AHA 2017: < 120 normal, 120–129 elevada, 130 o más por encima del rango",
            "Una sola toma dice poco: la presión se evalúa con varias mediciones en reposo.",
        )
    },
    "imc": {
        "*": RangoReferencia(
            18.5, 24.9, 29.9, None, "18,5–24,9 kg/m²",
            "OMS (adultos): 18,5–24,9 referencia, 25–29,9 límite, 30 o más por encima del rango",
            "El IMC no distingue músculo de grasa; en personas muy musculosas sobreestima.",
        )
    },
}

#: Nombres en lenguaje humano para el reporte (coinciden con los de la app).
ETIQUETAS: dict[str, str] = {
    "hs_CRP": "Proteína C reactiva (hs-CRP)",
    "glucosa": "Glucosa en ayunas",
    "albumina": "Albúmina",
    "creatinina": "Creatinina",
    "fosfatasa_alcalina": "Fosfatasa alcalina",
    "linfocitos_pct": "Linfocitos (%)",
    "vcm": "Volumen corpuscular medio (VCM)",
    "rdw": "Amplitud de distribución eritrocitaria (RDW)",
    "leucocitos": "Leucocitos",
    "colesterol_total": "Colesterol total",
    "presion_sistolica": "Presión arterial sistólica",
    "imc": "Índice de masa corporal (IMC)",
}


def rango_para(nombre: str, sexo: str | None) -> RangoReferencia | None:
    por_sexo = _RANGOS.get(nombre)
    if not por_sexo:
        return None
    s = (sexo or "").strip().upper()[:1]
    return por_sexo.get(s) or por_sexo["*"]


class Clasificacion(NamedTuple):
    estado: Estado
    #: "alto" / "bajo" / None — de qué lado del rango está.
    lado: str | None
    rango: RangoReferencia


def clasificar(nombre: str, valor: float, sexo: str | None) -> Clasificacion | None:
    """`en_rango` / `borde` / `fuera` según la regla del docstring del módulo;
    None si el biomarcador no tiene rango tabulado."""
    r = rango_para(nombre, sexo)
    if r is None:
        return None
    lo, hi = r.lo, r.hi
    ancho = (hi - lo) if (lo is not None and hi is not None) else (hi if hi is not None else lo) or 1.0
    margen = 0.10 * ancho
    if hi is not None and valor > hi:
        limite = r.borde_alto if r.borde_alto is not None else hi + margen
        return Clasificacion("borde" if valor <= limite else "fuera", "alto", r)
    if lo is not None and valor < lo:
        limite = r.borde_bajo if r.borde_bajo is not None else lo - margen
        return Clasificacion("borde" if valor >= limite else "fuera", "bajo", r)
    return Clasificacion("en_rango", None, r)


__all__ = ["Clasificacion", "ETIQUETAS", "Estado", "RangoReferencia", "clasificar", "rango_para"]
