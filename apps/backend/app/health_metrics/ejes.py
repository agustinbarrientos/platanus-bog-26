"""Ejes sistémicos del reporte (docs/MOIRAI_REPORTE_SPEC.md §2 y §5): agrupar
los biomarcadores en cinco ejes (inflamación, metabólico, renal/hepático,
hematológico, cardio-metabólico), darle a cada uno un nivel cualitativo a
partir de los rangos de referencia (`reference_ranges.clasificar`) y, de ahí,
sugerir con QUÉ TIPO de profesional conviene hablar.

Todo esto es una TABLA DE REGLAS SIMPLES, declarada y revisable — no lógica
clínica. El nivel de un eje se decide solo con los biomarcadores MEDIDOS
(uno imputado no cuenta: es la mediana poblacional, no un dato de la
persona):

- `atencion`  : algún biomarcador medido del eje está `fuera` de su rango.
- `a_vigilar` : ninguno fuera, pero alguno en `borde`.
- `optimo`    : todos los medidos del eje están en rango.
- `sin_datos` : ningún biomarcador del eje está medido.

Nada aquí nombra una enfermedad. El triage dice "valdría la pena una consulta
con X para que lo evalúe", nunca una conclusión. La spec §0 es la prueba de
fuego: cada frase de este módulo tiene que sonar a orientación responsable.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Literal, NamedTuple

from app.health_metrics.reference_ranges import ETIQUETAS, clasificar

Nivel = Literal["optimo", "a_vigilar", "atencion", "sin_datos"]

NIVEL_TEXTO: dict[str, str] = {
    "optimo": "en rango",
    "a_vigilar": "a vigilar",
    "atencion": "atención",
    "sin_datos": "sin datos",
}


class Eje(NamedTuple):
    id: str
    nombre: str
    #: Biomarcadores (vocabulario de `BIOMARKER_SPECS`) que lo componen.
    biomarcadores: tuple[str, ...]
    #: Qué mide, en lenguaje humano (para el lector, no para el médico).
    que_mide: str
    #: Qué profesional, en lenguaje de orientación, si el eje está a vigilar/atención.
    profesional: str
    #: Frase de triage (se imprime tal cual bajo el eje). Orientativa.
    sugerencia: str


EJES: tuple[Eje, ...] = (
    Eje(
        "inflamacion",
        "Inflamación",
        ("hs_CRP", "leucocitos"),
        "Señales de inflamación de bajo grado en la sangre: la proteína C reactiva y el recuento de glóbulos blancos.",
        "medicina general o medicina interna",
        "Conviene que un médico general o internista lo evalúe e investigue la causa; repetir la medición en unas semanas ayuda a saber si es algo pasajero o sostenido.",
    ),
    Eje(
        "metabolico",
        "Metabólico",
        ("glucosa", "imc"),
        "Cómo maneja tu cuerpo la energía: la glucosa en ayunas y la relación entre peso y estatura.",
        "medicina interna o endocrinología",
        "Valdría la pena una consulta con medicina interna o endocrinología para que lo evalúe con más detalle (por ejemplo, con una hemoglobina glicosilada).",
    ),
    Eje(
        "renal_hepatico",
        "Renal y hepático",
        ("creatinina", "albumina", "fosfatasa_alcalina"),
        "Cómo están trabajando riñones e hígado: la creatinina, la albúmina y la fosfatasa alcalina.",
        "medicina general o medicina interna",
        "Vale la pena que medicina general o interna lo revise y evalúe; según lo que encuentre, puede sugerir nefrología o hepatología.",
    ),
    Eje(
        "hematologico",
        "Hematológico",
        ("vcm", "rdw", "linfocitos_pct"),
        "La forma y la variedad de tus glóbulos rojos y la proporción de linfocitos.",
        "medicina general; hematología si persiste",
        "Un hemograma completo para que medicina general lo evalúe; si se mantiene, una valoración por hematología.",
    ),
    Eje(
        "cardio_metabolico",
        "Cardio-metabólico",
        ("presion_sistolica", "colesterol_total", "imc"),
        "Los factores que más pesan en la salud del corazón y las arterias: presión arterial, colesterol y peso.",
        "medicina general o cardiología preventiva",
        "Considera una evaluación cardiovascular preventiva para que medicina general o cardiología lo valore; suele incluir un perfil de lípidos completo y varias tomas de presión.",
    ),
)

#: Qué se sugiere cuando ningún eje pide atención.
SUGERENCIA_TODO_EN_RANGO = (
    "Con lo medido no veo ningún eje que pida una consulta especial. Un control "
    "preventivo de rutina con medicina general o familiar, una vez al año, es lo "
    "que conviene para mantenerlo así."
)

#: Disclaimer que acompaña SIEMPRE a la sección de triage (spec §5).
DISCLAIMER_TRIAGE = (
    "Esto es orientación para que un profesional lo evalúe, no una conclusión. "
    "Lleva este reporte a tu consulta: resume lo que Moirai observó."
)


class EstadoBiomarcador(NamedTuple):
    nombre: str
    etiqueta: str
    valor: float | None
    medido: bool
    estado: str  # en_rango | borde | fuera | inferido | sin_rango
    lado: str | None


class EjeEvaluado(NamedTuple):
    id: str
    nombre: str
    nivel: Nivel
    que_mide: str
    biomarcadores: list[EstadoBiomarcador]
    #: Los medidos en borde/fuera, para explicar el nivel.
    senales: list[str]
    #: Suma de `contribuciones` (años de PhenoAge hoy) de sus biomarcadores medidos; 0 si ninguno es de PhenoAge.
    aporte_anios: float
    explicacion: str
    profesional: str
    sugerencia: str


def _explicar(eje: Eje, nivel: Nivel, senales: list[str], aporte: float) -> str:
    if nivel == "sin_datos":
        return f"No tengo ningún dato medido de este eje. {eje.que_mide}"
    if nivel == "optimo":
        base = f"{eje.que_mide} Lo que mediste está dentro de los rangos de referencia."
    elif nivel == "a_vigilar":
        base = f"{eje.que_mide} {', '.join(senales)} está en el borde del rango de referencia: no es una alarma, es algo que vale la pena mirar en la próxima medición."
    else:
        base = f"{eje.que_mide} {', '.join(senales)} está fuera del rango de referencia; por eso marco este eje para que un profesional lo evalúe."
    if abs(aporte) >= 0.3:
        direccion = "suma" if aporte > 0 else "resta"
        base += f" En la edad biológica de hoy, este eje {direccion} {_fmt(abs(aporte))} años frente a la referencia de tu edad y sexo."
    return base


def _fmt(x: float) -> str:
    return f"{x:.1f}".replace(".", ",")


def evaluar_ejes(
    medidos: Mapping[str, float],
    sexo: str | None,
    contribuciones: Mapping[str, float] | None = None,
) -> list[EjeEvaluado]:
    """`medidos` = solo biomarcadores realmente medidos (nombre → valor, en
    unidades de almacenamiento). `contribuciones` = las de `/phenoage` (años
    por biomarcador medido; los imputados valen 0)."""
    contribuciones = contribuciones or {}
    out: list[EjeEvaluado] = []
    for eje in EJES:
        estados: list[EstadoBiomarcador] = []
        senales: list[str] = []
        peor = "sin_datos"
        aporte = 0.0
        for nombre in eje.biomarcadores:
            etiqueta = ETIQUETAS.get(nombre, nombre)
            if nombre not in medidos:
                estados.append(EstadoBiomarcador(nombre, etiqueta, None, False, "inferido", None))
                continue
            valor = float(medidos[nombre])
            c = clasificar(nombre, valor, sexo)
            if c is None:
                estados.append(EstadoBiomarcador(nombre, etiqueta, valor, True, "sin_rango", None))
                continue
            estados.append(EstadoBiomarcador(nombre, etiqueta, valor, True, c.estado, c.lado))
            aporte += float(contribuciones.get(nombre, 0.0))
            if c.estado == "fuera":
                peor = "atencion"
                senales.append(etiqueta)
            elif c.estado == "borde":
                if peor != "atencion":
                    peor = "a_vigilar"
                senales.append(etiqueta)
            elif peor == "sin_datos":
                peor = "optimo"
        nivel: Nivel = peor  # type: ignore[assignment]
        out.append(
            EjeEvaluado(
                id=eje.id,
                nombre=eje.nombre,
                nivel=nivel,
                que_mide=eje.que_mide,
                biomarcadores=estados,
                senales=senales,
                aporte_anios=aporte,
                explicacion=_explicar(eje, nivel, senales, aporte),
                profesional=eje.profesional,
                sugerencia=eje.sugerencia,
            )
        )
    return out


class SugerenciaConsulta(NamedTuple):
    eje: str
    nombre: str
    nivel: Nivel
    profesional: str
    texto: str


def triage(ejes: list[EjeEvaluado]) -> list[SugerenciaConsulta]:
    """Reglas eje → tipo de profesional, solo para los ejes a vigilar / en
    atención (atención primero). Si ninguno, la sugerencia de rutina."""
    orden = {"atencion": 0, "a_vigilar": 1}
    activos = sorted((e for e in ejes if e.nivel in orden), key=lambda e: orden[e.nivel])
    if not activos:
        return [SugerenciaConsulta("ninguno", "Control de rutina", "optimo", "medicina general o familiar", SUGERENCIA_TODO_EN_RANGO)]
    return [SugerenciaConsulta(e.id, e.nombre, e.nivel, e.profesional, e.sugerencia) for e in activos]


__all__ = [
    "DISCLAIMER_TRIAGE",
    "EJES",
    "Eje",
    "EjeEvaluado",
    "EstadoBiomarcador",
    "NIVEL_TEXTO",
    "Nivel",
    "SUGERENCIA_TODO_EN_RANGO",
    "SugerenciaConsulta",
    "evaluar_ejes",
    "triage",
]
