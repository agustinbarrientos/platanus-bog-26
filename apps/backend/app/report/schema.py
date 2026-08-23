"""Forma del reporte (`POST /me/health-context/reporte`). Es lo mismo que
va al PDF, en JSON, para que la app lo muestre en pantalla ("Tu reporte") y
el usuario pueda leerlo antes de descargarlo. Cada número sale del motor real
(`health_metrics`); los textos son plantillas fijas rellenadas con esos
números — nada se genera con un modelo de lenguaje."""

from __future__ import annotations

from pydantic import BaseModel


class MetaOut(BaseModel):
    id: str
    generado_en: str
    version_motor: str
    semilla: int
    trayectorias_por_escenario: int
    horizonte_anios: int
    disclaimer: str
    privacidad: str
    fuentes: list[str]


class PersonaOut(BaseModel):
    nombre: str | None
    edad: int
    sexo: str | None
    ancestria: str | None


class RangoOut(BaseModel):
    p10: float
    mediana: float
    p90: float


class BiomarcadorReporteOut(BaseModel):
    nombre: str
    etiqueta: str
    valor: float
    unidad: str
    #: `en_rango` | `borde` | `fuera` | `inferido` | `sin_rango`
    estado: str
    #: `alto` | `bajo` | null
    lado: str | None
    rango_referencia: str | None
    fuente_rango: str | None
    #: `documento` | `reportado` | `calculado` | `inferido` (como lo guardó la app; imputado = `inferido`)
    fuente: str
    #: Años de edad biológica que suma (+) o resta (−) hoy frente a la referencia; 0 si imputado o no es de PhenoAge.
    contribucion_anios: float
    nota: str | None


class FotoHoyOut(BaseModel):
    edad_cronologica: int
    edad_biologica: float
    #: Banda de HOY por lo imputado (año 0 de la línea base). p10 == p90 si los 9 están medidos.
    rango_hoy: RangoOut
    aceleracion: float
    percentil_poblacional: float
    n_medidos: int
    n_inferidos: int
    biomarcadores: list[BiomarcadorReporteOut]
    nota_poblacional: str
    lectura: str


class BiomarcadorEjeOut(BaseModel):
    nombre: str
    etiqueta: str
    valor: float | None
    medido: bool
    estado: str


class EjeOut(BaseModel):
    id: str
    nombre: str
    #: `optimo` | `a_vigilar` | `atencion` | `sin_datos`
    nivel: str
    nivel_texto: str
    biomarcadores: list[BiomarcadorEjeOut]
    aporte_anios: float
    explicacion: str


class CurvaOut(BaseModel):
    anios: list[int]
    p10: list[float]
    mediana: list[float]
    p90: list[float]


class EscenarioClaveOut(BaseModel):
    titulo: str
    escenario: str | None
    nombre: str
    al_horizonte: RangoOut
    anios_ganados: float | None
    rango_ganados: list[float] | None
    texto: str


class RankingOut(BaseModel):
    escenario: str
    nombre: str
    intervenciones: list[str]
    anios_ganados: float
    anios_ganados_p10: float
    anios_ganados_p90: float
    pct_futuros_que_mejoran: float
    esfuerzo: int
    ratio_impacto_esfuerzo: float
    fuentes: list[str]


class FuturosOut(BaseModel):
    horizonte_anios: int
    curva_base: CurvaOut
    sigues_igual: EscenarioClaveOut
    si_mejoras: EscenarioClaveOut | None
    si_te_descuidas: EscenarioClaveOut | None
    ranking: list[RankingOut]
    nota_incertidumbre: str


class EvidenciaOut(BaseModel):
    hallazgo: str
    fuente: str


class RecomendacionOut(BaseModel):
    id: str
    nombre: str
    que_hacer: str
    por_que: str
    anios_ganados: float
    rango_ganados: list[float]
    pct_futuros_que_mejoran: float
    esfuerzo: int
    evidencia: list[EvidenciaOut]
    #: Hábito registrado que cierra y la brecha con la que se evaluó (0–1).
    habito: str
    brecha: float


class SugerenciaConsultaOut(BaseModel):
    eje: str
    nombre: str
    nivel: str
    profesional: str
    texto: str


class ConsultaOut(BaseModel):
    disclaimer: str
    sugerencias: list[SugerenciaConsultaOut]
    lleva_esto: str


class FaltanteOut(BaseModel):
    nombre: str
    etiqueta: str
    reduccion_banda_anios: float | None
    fraccion: float | None


class AfinarOut(BaseModel):
    ancho_banda_hoy: float
    faltantes: list[FaltanteOut]
    nota: str


class ReporteOut(BaseModel):
    meta: MetaOut
    persona: PersonaOut
    resumen: str
    foto_hoy: FotoHoyOut
    ejes: list[EjeOut]
    futuros: FuturosOut
    recomendaciones: list[RecomendacionOut]
    consulta: ConsultaOut
    afinar: AfinarOut
