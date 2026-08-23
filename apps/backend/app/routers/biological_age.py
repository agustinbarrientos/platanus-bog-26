"""Compute endpoints on top of the data `/me` + `/me/health-context` store:
PhenoAge right now (with the "por qué" and the population percentile), a
Monte Carlo projection of where PhenoAge lands in `anios` years under each
intervention scenario (habit-aware, paired, with per-year curves, value of
information and sample trajectories), and the engine's static catalog (what
every number is made of). The compute endpoints are pure functions of what's
already saved — neither takes a body describing the person, only (for the
simulation) which scenarios to run and how big to make it.
"""

from __future__ import annotations

from itertools import combinations
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUserDep
from app.db import get_db
from app.health_metrics import montecarlo, phenoage
from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import (
    BRECHA_DESCONOCIDA,
    DESCUENTO_COMBINACION,
    DYNAMICS,
    HABITOS,
    HETEROGENEIDAD_RESPUESTA,
    MAX_INTERVENCIONES,
    PALANCAS,
    SCENARIOS,
    aplica,
    brecha_efectiva,
    brechas_desde_habitos,
    descripcion_de,
    es_escenario_valido,
)
from app.health_metrics.nhanes_reference import DISPERSION
from app.models import HealthContext
from app.routers.profile import biological_inputs

router = APIRouter(prefix="/me/health-context", tags=["biological-age"])
#: Static constants of the engine — no auth, nothing personal (like /health).
catalogo_router = APIRouter(prefix="/engine", tags=["engine"])

SessionDep = Annotated[AsyncSession, Depends(get_db)]

ENGINE_VERSION = "0.3.0"


def _r(x: float, nd: int = 2) -> float:
    return round(float(x), nd)


def _rl(xs, nd: int = 2) -> list[float]:
    return [round(float(x), nd) for x in xs]


async def _read_inputs(
    session: AsyncSession, user_id
) -> tuple[float, str | None, dict[str, float], dict]:
    """Chronological age (from the profile), sex, whichever PhenoAge
    biomarkers are on file, and the stored habits — everything both compute
    endpoints need."""
    edad, sexo = await biological_inputs(session, user_id)
    if edad is None or sexo is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="falta date_of_birth y/o sex_at_birth — PATCH /me antes de calcular",
        )

    row = await session.get(HealthContext, user_id)
    biomarcadores_guardados = (row.biomarcadores if row else None) or []
    biomarcadores = {
        b["nombre"]: b["valor"]
        for b in biomarcadores_guardados
        if b["nombre"] in PHENOAGE_BIOMARKERS
    }
    habitos = dict((row.habitos if row else None) or {})
    return edad, sexo, biomarcadores, habitos


# ---- /phenoage -----------------------------------------------------------------


class PhenoAgeOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "edad_cronologica": 52,
                "edad_biologica": 58.3,
                "aceleracion": 6.3,
                "aceleracion_referencia": 0.4,
                "percentil_poblacional": 88.2,
                "campos_inferidos": ["creatinina", "fosfatasa_alcalina", "linfocitos_pct", "vcm", "rdw", "leucocitos"],
                "valores_usados": {
                    "hs_CRP": 2.1, "glucosa": 92, "albumina": 4.4, "creatinina": 0.945,
                    "fosfatasa_alcalina": 82, "linfocitos_pct": 29.2, "vcm": 91.2, "rdw": 13.7,
                    "leucocitos": 7.1,
                },
                "contribuciones": {"hs_CRP": -0.2, "glucosa": -0.7, "albumina": -1.1, "creatinina": 0.0},
            }
        }
    )

    edad_cronologica: float
    edad_biologica: float
    #: edad_biologica - edad_cronologica. Positive means the clock reads
    #: older than the calendar; negative means younger.
    aceleracion: float
    #: Aceleración de la persona de referencia (los 9 biomarcadores en la
    #: mediana de su edad y sexo): el cero del percentil. ≈0 (±2).
    aceleracion_referencia: float
    #: 1–99 frente a personas de la misma edad y sexo; 50 = como la referencia.
    percentil_poblacional: float
    campos_inferidos: list[str]
    valores_usados: dict[str, float]
    #: Años que cada biomarcador MEDIDO suma (+) o resta (−) frente a la
    #: referencia; los imputados valen 0. Suma = aceleracion − aceleracion_referencia.
    contribuciones: dict[str, float]


@router.post("/phenoage", summary="PhenoAge (Levine et al. 2018) from the stored health context")
async def compute_phenoage(user: CurrentUserDep, session: SessionDep) -> PhenoAgeOut:
    edad, sexo, biomarcadores, _ = await _read_inputs(session, user.id)
    result = phenoage.compute(biomarcadores, edad, sexo)
    return PhenoAgeOut(
        edad_cronologica=result.edad_cronologica,
        edad_biologica=_r(result.edad_biologica),
        aceleracion=_r(result.aceleracion),
        aceleracion_referencia=_r(result.aceleracion_referencia),
        percentil_poblacional=_r(result.percentil_poblacional, 1),
        campos_inferidos=result.campos_inferidos,
        valores_usados=result.valores_usados,
        contribuciones={k: _r(v) for k, v in result.contribuciones.items()},
    )


# ---- /montecarlo ---------------------------------------------------------------


class MontecarloIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    #: Claves de escenario: una palanca (`"ejercicio_aerobico"`), varias a la
    #: vez unidas con `+` (`"ejercicio_aerobico+sueno_8h"`, máximo 3), la
    #: compuesta `combinada` o `ninguna`. Omitido → `ninguna` + las palancas
    #: que APLICAN a esta persona según sus hábitos + sus combinaciones de 2 y 3.
    escenarios: list[str] | None = None
    n_trayectorias: int = Field(
        default=montecarlo.DEFAULT_TRAYECTORIAS, ge=100, le=montecarlo.MAX_TRAYECTORIAS
    )
    anios: int = Field(default=montecarlo.DEFAULT_ANIOS, ge=1, le=montecarlo.MAX_ANIOS)
    #: Semilla del generador; omitida → fija (`DEFAULT_SEED`), así el mismo
    #: input da el mismo abanico y todos los escenarios quedan pareados.
    semilla: int | None = None
    #: Solo cuando `escenarios` se omite: incluir las combinaciones de 2 y 3
    #: palancas aplicables (spec §6). `false` = solo palancas sueltas.
    combinaciones: bool = True


class CurvaOut(BaseModel):
    anios: list[int]
    p10: list[float]
    mediana: list[float]
    p90: list[float]


class EscenarioOut(BaseModel):
    escenario: str
    nombre: str
    intervenciones: list[str]
    descripcion: str
    esfuerzo: int
    #: False si ninguna de sus palancas tiene brecha abierta para esta persona
    #: (ya tiene el hábito): colapsa sobre la línea base, años ganados ≈ 0.
    aplica: bool
    # Al horizonte (misma forma que antes).
    edad_biologica_p10: float
    edad_biologica_mediana: float
    edad_biologica_p90: float
    #: Año a año (del 0 al horizonte): P10 / mediana / P90 de las trayectorias.
    curva: CurvaOut
    #: Diferencia PAREADA frente a la línea base (misma vida con y sin la
    #: palanca): mediana, P10 y P90 de la distribución de esa diferencia.
    anios_ganados: float
    anios_ganados_p10: float
    anios_ganados_p90: float
    #: % de trayectorias en que la palanca termina con menor edad biológica.
    pct_futuros_que_mejoran: float
    #: anios_ganados / esfuerzo — la app ordena las palancas por esto.
    ratio_impacto_esfuerzo: float


class PalancaOut(BaseModel):
    id: str
    nombre: str
    descripcion: str
    esfuerzo: int
    #: Hábito registrado que cierra (`actividad`, `alimentacion`, `tabaco`,
    #: `sueno`, `estres`, `alcohol`).
    habito: str
    #: Brecha de ESTA persona (0 = ya tiene el hábito, 1 = del todo abierta),
    #: null si el hábito no está registrado.
    brecha: float | None
    #: Brecha con la que se aplicó el efecto (la registrada, o la asumida si
    #: no se conoce — ver `BRECHA_DESCONOCIDA`).
    brecha_efectiva: float
    aplica: bool
    efectos_anuales: dict[str, float]


class ValorDeInformacionOut(BaseModel):
    nombre: str
    #: Años que se angosta la banda P10–P90 de la línea base al horizonte si
    #: este biomarcador imputado estuviera medido.
    reduccion_banda_anios: float
    #: Parte de la reducción total (suma 1 entre los imputados).
    fraccion: float


class ContribucionHabitoOut(BaseModel):
    habito: str
    palanca: str
    brecha: float
    #: Años de edad biológica al horizonte que este hábito suma (+, `empeora`)
    #: o ahorra (−, `mejora`) frente a tenerlo al revés. Determinista.
    contribucion: float
    direccion: str


class MontecarloOut(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "edad_cronologica": 52,
                "horizonte_anios": 10,
                "trayectorias_por_escenario": 10000,
                "semilla": 20260822,
                "campos_inferidos": ["linfocitos_pct", "vcm", "fosfatasa_alcalina"],
                "ancho_banda_hoy": 4.7,
                "habitos_usados": {"sueno_h": 6, "tabaco": False, "actividad": "baja"},
                "brechas": {"actividad": 1.0, "alimentacion": None, "tabaco": 0.0, "sueno": 1.0, "estres": None, "alcohol": None},
                "palancas": [
                    {"id": "ejercicio_aerobico", "nombre": "Ejercicio aeróbico regular", "descripcion": "150 minutos…",
                     "esfuerzo": 3, "habito": "actividad", "brecha": 1.0, "brecha_efectiva": 1.0, "aplica": True,
                     "efectos_anuales": {"hs_CRP": -0.08, "glucosa": -0.9, "leucocitos": -0.03}}
                ],
                "escenarios": [
                    {"escenario": "ninguna", "nombre": "Sin intervención (línea base)", "intervenciones": [],
                     "descripcion": "", "esfuerzo": 0, "aplica": True,
                     "edad_biologica_p10": 56.1, "edad_biologica_mediana": 62.3, "edad_biologica_p90": 68.4,
                     "curva": {"anios": [0, 1, 10], "p10": [50.0, 50.6, 56.1], "mediana": [52.4, 53.4, 62.3], "p90": [54.8, 56.3, 68.4]},
                     "anios_ganados": 0, "anios_ganados_p10": 0, "anios_ganados_p90": 0,
                     "pct_futuros_que_mejoran": 0, "ratio_impacto_esfuerzo": 0},
                    {"escenario": "ejercicio_aerobico+sueno_8h", "nombre": "Ejercicio aeróbico regular + dormir 8 horas",
                     "intervenciones": ["ejercicio_aerobico", "sueno_8h"], "descripcion": "150 minutos… · Acostarte…",
                     "esfuerzo": 5, "aplica": True,
                     "edad_biologica_p10": 54.2, "edad_biologica_mediana": 60.4, "edad_biologica_p90": 66.6,
                     "curva": {"anios": [0, 1, 10], "p10": [50.0, 50.4, 54.2], "mediana": [52.4, 53.2, 60.4], "p90": [54.8, 56.1, 66.6]},
                     "anios_ganados": 1.9, "anios_ganados_p10": 0.9, "anios_ganados_p90": 3.3,
                     "pct_futuros_que_mejoran": 99.8, "ratio_impacto_esfuerzo": 0.38},
                ],
                "muestra_trayectorias": [[52.4, 53.1, 54.0, 55.2, 55.9, 57.3, 58.0, 59.4, 60.1, 61.6, 62.0]],
                "valor_de_informacion": [{"nombre": "vcm", "reduccion_banda_anios": 0.7, "fraccion": 0.8}],
                "contribuciones_habitos": [{"habito": "actividad", "palanca": "ejercicio_aerobico", "brecha": 1.0, "contribucion": 1.1, "direccion": "empeora"}],
            }
        }
    )

    edad_cronologica: float
    horizonte_anios: int
    trayectorias_por_escenario: int
    semilla: int
    campos_inferidos: list[str]
    #: P90 − P10 de la edad biológica HOY: 0 con los 9 medidos; la
    #: incertidumbre de lo imputado si no (la banda del año 0 de las curvas).
    ancho_banda_hoy: float
    #: El objeto `habitos` guardado que leyó el motor (tal cual).
    habitos_usados: dict
    #: Brecha 0–1 por hábito (null = no registrado). Lo que hizo personal a la
    #: línea base y decidió qué palancas aplican.
    brechas: dict[str, float | None]
    #: El catálogo de palancas evaluado para esta persona.
    palancas: list[PalancaOut]
    #: `ninguna` siempre va primero: la línea base.
    escenarios: list[EscenarioOut]
    #: Hasta 40 trayectorias reales de la línea base (edad biológica año a
    #: año), para dibujarlas mientras corre la simulación / en el abanico.
    muestra_trayectorias: list[list[float]]
    #: Qué biomarcador imputado angostaría más la banda si se midiera, de
    #: mayor a menor. Vacío si los 9 están medidos.
    valor_de_informacion: list[ValorDeInformacionOut]
    #: El "por qué" de los hábitos registrados, a `horizonte_anios` años.
    contribuciones_habitos: list[ContribucionHabitoOut]


def _escenarios_por_defecto(brechas: dict[str, float | None], combinaciones: bool) -> list[str]:
    sueltas = [k for k in PALANCAS if aplica(k, brechas)]
    out = ["ninguna", *sueltas]
    if combinaciones:
        for k in range(2, MAX_INTERVENCIONES + 1):
            out.extend("+".join(c) for c in combinations(sueltas, k))
    return out


def _palancas_out(brechas: dict[str, float | None]) -> list[PalancaOut]:
    out = []
    for key in PALANCAS:
        sc = SCENARIOS[key]
        out.append(
            PalancaOut(
                id=key,
                nombre=sc.nombre,
                descripcion=sc.descripcion,
                esfuerzo=sc.esfuerzo,
                habito=sc.habito or "",
                brecha=brechas.get(sc.habito) if sc.habito else None,
                brecha_efectiva=brecha_efectiva(brechas, sc.habito),
                aplica=aplica(key, brechas),
                efectos_anuales=dict(sc.efectos_anuales),
            )
        )
    return out


@router.post(
    "/montecarlo",
    summary="Paired, habit-aware N-trajectory Monte Carlo projection of PhenoAge under each scenario",
    responses={422: {"description": "Unknown/invalid scenario key (or >3 levers), or date_of_birth/sex_at_birth is not on file"}},
)
async def run_montecarlo(
    body: MontecarloIn, user: CurrentUserDep, session: SessionDep
) -> MontecarloOut:
    edad, sexo, biomarcadores, habitos = await _read_inputs(session, user.id)
    brechas = brechas_desde_habitos(habitos)

    if body.escenarios is not None:
        escenarios = list(dict.fromkeys(body.escenarios))  # dedupe, keep order
        malos = [key for key in escenarios if not es_escenario_valido(key)]
        if malos:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"escenario(s) inválido(s): {malos}. válidos: 'ninguna', una de {list(PALANCAS)}, "
                    f"'combinada', o hasta {MAX_INTERVENCIONES} palancas unidas con '+'"
                ),
            )
        if "ninguna" in escenarios:
            escenarios.remove("ninguna")
        escenarios = ["ninguna", *escenarios]
    else:
        escenarios = _escenarios_por_defecto(brechas, body.combinaciones)

    # montecarlo.simular() is synchronous, CPU-bound numpy work — up to 20,000
    # trajectories x every scenario x 30 years. Run it off the event loop, or
    # this stalls every other request this process is handling, including
    # /health, for however long the simulation takes.
    r = await run_in_threadpool(
        montecarlo.simular,
        biomarcadores, edad, sexo, escenarios, body.n_trayectorias, body.anios,
        seed=body.semilla, brechas=brechas,
    )
    return MontecarloOut(
        edad_cronologica=edad,
        horizonte_anios=r.anios,
        trayectorias_por_escenario=r.n_trayectorias,
        semilla=r.semilla,
        campos_inferidos=r.campos_inferidos,
        ancho_banda_hoy=_r(r.ancho_banda_hoy),
        habitos_usados=habitos,
        brechas=brechas,
        palancas=_palancas_out(brechas),
        escenarios=[
            EscenarioOut(
                escenario=e.escenario,
                nombre=e.nombre,
                intervenciones=list(e.intervenciones),
                descripcion=descripcion_de(e.escenario),
                esfuerzo=e.esfuerzo,
                aplica=e.aplica,
                edad_biologica_p10=_r(e.edad_biologica_p10),
                edad_biologica_mediana=_r(e.edad_biologica_mediana),
                edad_biologica_p90=_r(e.edad_biologica_p90),
                curva=CurvaOut(
                    anios=list(e.curva_anios),
                    p10=_rl(e.curva_p10),
                    mediana=_rl(e.curva_mediana),
                    p90=_rl(e.curva_p90),
                ),
                anios_ganados=_r(e.anios_ganados),
                anios_ganados_p10=_r(e.anios_ganados_p10),
                anios_ganados_p90=_r(e.anios_ganados_p90),
                pct_futuros_que_mejoran=_r(e.pct_futuros_que_mejoran, 1),
                ratio_impacto_esfuerzo=_r(e.ratio_impacto_esfuerzo, 3),
            )
            for e in r.escenarios
        ],
        muestra_trayectorias=[_rl(t) for t in r.muestra_trayectorias],
        valor_de_informacion=[
            ValorDeInformacionOut(
                nombre=v.nombre,
                reduccion_banda_anios=_r(v.reduccion_banda_anios),
                fraccion=_r(v.fraccion, 3),
            )
            for v in r.valor_de_informacion
        ],
        contribuciones_habitos=[
            ContribucionHabitoOut(
                habito=str(c["habito"]),
                palanca=str(c["palanca"]),
                brecha=_r(c["brecha"]),  # type: ignore[arg-type]
                contribucion=_r(c["contribucion"]),  # type: ignore[arg-type]
                direccion=str(c["direccion"]),
            )
            for c in r.contribuciones_habitos
        ],
    )


# ---- /engine/catalogo ------------------------------------------------------------


class BiomarcadorCatalogoOut(BaseModel):
    nombre: str
    unidad: str
    valor_min: float
    valor_max: float
    descripcion: str
    phenoage: bool
    #: Solo para los 9 de PhenoAge: deriva natural por año, ruido anual (SD) y
    #: dispersión poblacional con la que se muestrea si no está medido.
    deriva_anual: float | None = None
    ruido_anual_sd: float | None = None
    dispersion: dict | None = None


class PalancaCatalogoOut(BaseModel):
    id: str
    nombre: str
    descripcion: str
    esfuerzo: int
    habito: str
    brecha_promedio: float
    brecha_si_desconocido: float
    efectos_anuales: dict[str, float]


class CatalogoOut(BaseModel):
    version: str
    biomarcadores: list[BiomarcadorCatalogoOut]
    palancas: list[PalancaCatalogoOut]
    habitos: list[str]
    #: Reglas de combinación (spec §6/§12) y heterogeneidad de respuesta.
    combinacion: dict
    defaults: dict


@catalogo_router.get(
    "/catalogo",
    summary="Static engine constants: biomarkers, drift/noise, levers, effects, rules",
)
async def catalogo() -> CatalogoOut:
    return CatalogoOut(
        version=ENGINE_VERSION,
        biomarcadores=[
            BiomarcadorCatalogoOut(
                nombre=nombre,
                unidad=spec.unidad,
                valor_min=spec.valor_min,
                valor_max=spec.valor_max,
                descripcion=spec.descripcion,
                phenoage=nombre in PHENOAGE_BIOMARKERS,
                deriva_anual=DYNAMICS[nombre].deriva_anual if nombre in DYNAMICS else None,
                ruido_anual_sd=DYNAMICS[nombre].ruido_anual_sd if nombre in DYNAMICS else None,
                dispersion=(
                    {"tipo": DISPERSION[nombre][0], "sigma": DISPERSION[nombre][1]}
                    if nombre in DISPERSION else None
                ),
            )
            for nombre, spec in BIOMARKER_SPECS.items()
        ],
        palancas=[
            PalancaCatalogoOut(
                id=key,
                nombre=SCENARIOS[key].nombre,
                descripcion=SCENARIOS[key].descripcion,
                esfuerzo=SCENARIOS[key].esfuerzo,
                habito=SCENARIOS[key].habito or "",
                brecha_promedio=SCENARIOS[key].brecha_promedio,
                brecha_si_desconocido=BRECHA_DESCONOCIDA.get(SCENARIOS[key].habito or "", 1.0),
                efectos_anuales=dict(SCENARIOS[key].efectos_anuales),
            )
            for key in PALANCAS
        ],
        habitos=list(HABITOS),
        combinacion={
            "descuento_por_palanca_adicional": DESCUENTO_COMBINACION,
            "max_intervenciones": MAX_INTERVENCIONES,
            "heterogeneidad_respuesta_sd": HETEROGENEIDAD_RESPUESTA,
        },
        defaults={
            "n_trayectorias": montecarlo.DEFAULT_TRAYECTORIAS,
            "anios": montecarlo.DEFAULT_ANIOS,
            "semilla": montecarlo.DEFAULT_SEED,
            "muestra_trayectorias": montecarlo.MUESTRA_TRAYECTORIAS,
        },
    )
