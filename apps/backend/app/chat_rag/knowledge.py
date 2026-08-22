"""The static knowledge base: what the engine is and how to read it.

Everything a user might ask that is *not* about their own numbers — what
PhenoAge is, why the band is wide, what each biomarker means, what each
intervention moves. Built at import time from the same tables the engine runs
on (`BIOMARKER_SPECS`, `SCENARIOS`, `DYNAMICS`, the PhenoAge coefficient
signs), so the explanation can never drift from the computation.

Voice: plain facts, Spanish. The system prompt turns them into Moirai's
first-person voice; these chunks only have to be correct and honest about what
is approximate.
"""

from __future__ import annotations

from app.chat_rag.chunks import Chunk, fmt_lista, fmt_num
from app.health_metrics.biomarkers import BIOMARKER_SPECS, PHENOAGE_BIOMARKERS
from app.health_metrics.interventions import DYNAMICS, SCENARIOS
from app.health_metrics.phenoage import _COEF

#: Human names for the biomarker vocabulary (same wording as the app's
#: `BiomarcadorDef`), reused by `documents.py`.
NOMBRE_BIOMARCADOR: dict[str, str] = {
    "hs_CRP": "proteína C reactiva ultrasensible (hs-CRP)",
    "glucosa": "glucosa en ayunas",
    "albumina": "albúmina",
    "creatinina": "creatinina",
    "fosfatasa_alcalina": "fosfatasa alcalina",
    "linfocitos_pct": "porcentaje de linfocitos",
    "vcm": "volumen corpuscular medio (VCM)",
    "rdw": "RDW (ancho de distribución eritrocitaria)",
    "leucocitos": "leucocitos (glóbulos blancos)",
    "colesterol_total": "colesterol total",
    "presion_sistolica": "presión arterial sistólica",
    "imc": "índice de masa corporal (IMC)",
}

#: Extra retrieval vocabulary per biomarker: what people actually call it.
ALIAS_BIOMARCADOR: dict[str, tuple[str, ...]] = {
    "hs_CRP": ("pcr", "crp", "inflamacion", "proteina c reactiva"),
    "glucosa": ("azucar", "glicemia", "diabetes", "insulina"),
    "albumina": ("proteina", "higado", "nutricion"),
    "creatinina": ("rinon", "renal", "filtrado"),
    "fosfatasa_alcalina": ("alp", "higado", "hueso", "enzima"),
    "linfocitos_pct": ("linfocitos", "inmune", "defensas", "hemograma"),
    "vcm": ("globulos rojos", "hemograma", "mcv", "anemia"),
    "rdw": ("globulos rojos", "hemograma", "ade"),
    "leucocitos": ("globulos blancos", "wbc", "hemograma", "defensas", "infeccion"),
    "colesterol_total": ("colesterol", "grasa", "corazon", "cardiovascular"),
    "presion_sistolica": ("presion", "tension", "hipertension", "corazon"),
    "imc": ("peso", "obesidad", "masa corporal", "bmi", "estatura"),
}

#: What each biomarker is and what tends to move it. Short, non-clinical,
#: no reference ranges (the product never says "normal"/"abnormal").
QUE_ES_BIOMARCADOR: dict[str, str] = {
    "hs_CRP": (
        "Marcador de inflamación de bajo grado. Tiende a subir con tabaco, exceso de grasa "
        "abdominal, mal sueño, estrés sostenido e infecciones; tiende a bajar con ejercicio "
        "regular, buen sueño y una alimentación tipo mediterránea."
    ),
    "glucosa": (
        "Azúcar en sangre tras unas 8 horas sin comer: refleja cómo maneja el cuerpo los "
        "carbohidratos. La mueven el ejercicio, el peso, la alimentación y el sueño."
    ),
    "albumina": (
        "Proteína que fabrica el hígado; refleja estado nutricional y hepático. Valores más "
        "altos se asocian a mejor salud general."
    ),
    "creatinina": (
        "Producto del músculo que filtran los riñones: marca la función renal, aunque "
        "también depende de la masa muscular y la hidratación."
    ),
    "fosfatasa_alcalina": "Enzima presente sobre todo en hígado y hueso.",
    "linfocitos_pct": (
        "Parte del sistema inmune, como porcentaje de los glóbulos blancos. Tiende a bajar "
        "con la edad; más linfocitos (en %) se asocia a menor edad biológica."
    ),
    "vcm": (
        "Tamaño promedio de los glóbulos rojos. Sube con alcohol, tabaco y déficit de "
        "vitamina B12 o folato."
    ),
    "rdw": (
        "Qué tan variados en tamaño son los glóbulos rojos. Es el biomarcador con más peso "
        "individual en la fórmula PhenoAge."
    ),
    "leucocitos": (
        "Recuento total de glóbulos blancos: actividad inmune e inflamación. Sube con "
        "tabaco e infecciones."
    ),
    "colesterol_total": (
        "No entra en PhenoAge; se guarda para otros modelos de riesgo (cardiovascular)."
    ),
    "presion_sistolica": (
        "El número de arriba del tensiómetro. No entra en PhenoAge; se guarda para otros "
        "modelos de riesgo."
    ),
    "imc": (
        "Peso sobre estatura al cuadrado; la app lo calcula con los datos del perfil. No "
        "entra en PhenoAge; se guarda para otros modelos de riesgo."
    ),
}

#: Effort per intervention as the app ranks them (1–10, lower is easier) and
#: the description the app shows — `SimulationRepository.escenariosBackend`.
#: The backend has no effort model of its own; kept here so the chat explains
#: the ranking the user actually saw.
ESFUERZO_APP: dict[str, int] = {
    "ejercicio_aerobico": 3,
    "dieta_mediterranea": 3,
    "cesacion_tabaco": 4,
    "combinada": 10,
}
DESCRIPCION_APP: dict[str, str] = {
    "ejercicio_aerobico": (
        "150 minutos a la semana de algo que suba el pulso: caminar rápido, bici, nadar."
    ),
    "dieta_mediterranea": (
        "Más verduras, legumbres, pescado y aceite de oliva; menos ultraprocesados. Un "
        "patrón, no una dieta."
    ),
    "cesacion_tabaco": (
        "Cero cigarrillos. Es la palanca que más mueve la inflamación y los leucocitos; solo "
        "aplica si la persona fuma."
    ),
    "combinada": "Las tres a la vez: ejercicio + dieta mediterránea + dejar el tabaco.",
}
ALIAS_INTERVENCION: dict[str, tuple[str, ...]] = {
    "ejercicio_aerobico": (
        "ejercicio", "deporte", "correr", "caminar", "bici", "nadar", "gimnasio", "gym",
        "actividad fisica", "cardio", "moverme", "entrenar",
    ),
    "dieta_mediterranea": (
        "dieta", "comer", "comida", "alimentacion", "verduras", "pescado", "aceite de oliva",
        "ultraprocesados", "nutricion",
    ),
    "cesacion_tabaco": ("tabaco", "fumar", "cigarrillo", "cigarro", "vapear", "nicotina"),
    "combinada": ("combinada", "todo junto", "las tres", "combinacion", "combo"),
}

#: Which PhenoAge input each formula coefficient belongs to, to explain the
#: direction of each biomarker in the clock without hand-writing it.
_COEF_POR_BIOMARCADOR: dict[str, str] = {
    "albumina": "albumin_gL",
    "creatinina": "creatinine_umol",
    "glucosa": "glucose_mmol",
    "hs_CRP": "ln_crp_mgdL",
    "linfocitos_pct": "lymphocyte_pct",
    "vcm": "mcv_fL",
    "rdw": "rdw_pct",
    "fosfatasa_alcalina": "alp_UL",
    "leucocitos": "wbc_1000uL",
}


def direccion_en_phenoage(nombre: str) -> str | None:
    """'sube'/'baja': what a higher value does to biological age in the
    published fit. None for biomarkers PhenoAge does not use."""
    key = _COEF_POR_BIOMARCADOR.get(nombre)
    if key is None:
        return None
    return "sube" if _COEF[key] > 0 else "baja"


def palancas_que_mueven(nombre: str) -> list[str]:
    """Intervention keys whose per-year effect touches this biomarker."""
    return [key for key, sc in SCENARIOS.items() if nombre in sc.efectos_anuales]


def _nombre_escenario(key: str) -> str:
    return SCENARIOS[key].nombre


def _chunk_biomarcador(nombre: str) -> Chunk:
    spec = BIOMARKER_SPECS[nombre]
    en_phenoage = nombre in PHENOAGE_BIOMARKERS
    partes = [
        f"{NOMBRE_BIOMARCADOR[nombre].capitalize()}, en {spec.unidad}.",
        QUE_ES_BIOMARCADOR[nombre],
        f"Rango plausible que el sistema acepta: {fmt_num(spec.valor_min, 2)}–"
        f"{fmt_num(spec.valor_max)} {spec.unidad}.",
    ]
    if en_phenoage:
        dire = direccion_en_phenoage(nombre)
        partes.append(
            f"Entra en PhenoAge: sí — en la fórmula, un valor más alto {dire} la edad biológica."
        )
        dyn = DYNAMICS[nombre]
        partes.append(
            f"En la simulación deriva {fmt_num(dyn.deriva_anual, 3)} {spec.unidad} por año por "
            f"envejecimiento natural, con ruido anual de ±{fmt_num(dyn.ruido_anual_sd, 2)}."
        )
        palancas = palancas_que_mueven(nombre)
        if palancas:
            efectos = fmt_lista(
                f"{_nombre_escenario(k).lower()} ({fmt_num(SCENARIOS[k].efectos_anuales[nombre], 2)}/año)"
                for k in palancas
            )
            partes.append(f"Palancas del motor que lo mueven: {efectos}.")
        else:
            partes.append(
                "Ninguna de las palancas que simulo lo mueve directamente: solo sigue su deriva natural."
            )
        if nombre not in ("colesterol_total", "presion_sistolica", "imc"):
            partes.append(
                "Si no está medido, lo imputo con la mediana de referencia por edad y sexo y "
                "la banda de la proyección sale más ancha."
            )
    else:
        partes.append("Entra en PhenoAge: no.")
    return Chunk(
        id=f"kb:biomarcador:{nombre}",
        titulo=f"Qué es {NOMBRE_BIOMARCADOR[nombre]}",
        texto=" ".join(partes),
        grupo="conocimiento",
        tags=(nombre.lower(), "biomarcador", "examen", *ALIAS_BIOMARCADOR.get(nombre, ())),
        prioridad=0.9,
    )


def _chunk_intervencion(key: str) -> Chunk:
    sc = SCENARIOS[key]
    efectos = fmt_lista(
        f"{NOMBRE_BIOMARCADOR[b]} {fmt_num(v, 2)} {BIOMARKER_SPECS[b].unidad}/año"
        for b, v in sc.efectos_anuales.items()
    )
    esfuerzo = ESFUERZO_APP.get(key)
    partes = [
        f"{sc.nombre}. {DESCRIPCION_APP.get(key, '')}".strip(),
        f"Efecto anual que sumo a la deriva natural de cada biomarcador: {efectos}."
        if efectos
        else "Sin efecto sobre los biomarcadores (línea base).",
    ]
    if esfuerzo is not None:
        partes.append(
            f"Esfuerzo según la app: {esfuerzo} de 10 (las palancas se ordenan por años ganados "
            "dividido entre este esfuerzo)."
        )
    partes.append(
        "Los tamaños de efecto son direccionales, sintetizados de la literatura de ejercicio, "
        "dieta y cesación de tabaco; no están ajustados a un ensayo concreto."
    )
    return Chunk(
        id=f"kb:intervencion:{key}",
        titulo=f"Palanca: {sc.nombre}",
        texto=" ".join(partes),
        grupo="conocimiento",
        tags=(key, "palanca", "intervencion", "escenario", *ALIAS_INTERVENCION.get(key, ())),
        prioridad=0.9,
    )


_ESTATICOS: list[Chunk] = [
    Chunk(
        id="kb:phenoage",
        titulo="Qué es la edad biológica (PhenoAge)",
        texto=(
            "PhenoAge (Levine et al., 2018, Aging 10(4)) es un reloj de edad biológica: combina 9 "
            "biomarcadores de sangre (albúmina, creatinina, glucosa, hs-CRP, porcentaje de "
            "linfocitos, VCM, RDW, fosfatasa alcalina y leucocitos) con la edad cronológica, "
            "usando los pesos publicados ajustados sobre NHANES III. Mide el presente; no predice "
            "el futuro. La 'aceleración' es edad biológica menos edad cronológica: negativa = el "
            "cuerpo marca más joven que el calendario; positiva = más viejo. Es una estimación "
            "poblacional, no un diagnóstico, y cambia cuando cambian los biomarcadores."
        ),
        grupo="conocimiento",
        tags=("phenoage", "edad biologica", "reloj", "aceleracion", "levine", "edad"),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:simulacion",
        titulo="Cómo funciona la simulación (tres capas)",
        texto=(
            "Capa 1, medidor: PhenoAge con los biomarcadores de hoy. Capa 2, motor de evolución: "
            "cada biomarcador cambia un poco cada año (deriva natural) y cada palanca suma un efecto "
            "anual a esa deriva. Capa 3, Monte Carlo: repito la capa 2 en 5.000 trayectorias "
            "independientes por escenario, con ruido biológico nuevo cada año, durante 10 años, y "
            "calculo PhenoAge al final de cada una; los percentiles 10, 50 (mediana) y 90 de esas "
            "5.000 edades biológicas son la banda P10–P90. Todos los escenarios arrancan del mismo "
            "punto, así que son comparables; se comparan por la mediana. Los 'años ganados' de una "
            "palanca son la mediana sin hacer nada menos la mediana haciéndola."
        ),
        grupo="conocimiento",
        tags=(
            "simulacion", "monte carlo", "trayectorias", "futuros", "proyeccion", "10 anos",
            "como funciona", "motor", "capas", "5000",
        ),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:banda",
        titulo="Cómo leer el rango (banda P10–P90)",
        texto=(
            "El rango no es un intervalo de confianza estadístico: es la dispersión real que produce "
            "el ruido biológico año a año en las 5.000 trayectorias. El 80 % de los futuros "
            "simulados cae dentro de la banda; la mediana es el futuro 'del medio'. El rango es "
            "ancho a propósito: dice lo que todavía no sé de la persona. Se angosta cuando hay más "
            "biomarcadores medidos (cada uno imputado ensancha la banda) y se ensancha con el "
            "horizonte (más años, más incertidumbre). Confío más en el orden de las palancas que "
            "en cualquiera de los números por separado."
        ),
        grupo="conocimiento",
        tags=(
            "rango", "banda", "p10", "p90", "incertidumbre", "seguro", "confianza", "ancho",
            "dispersion", "percentiles",
        ),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:imputacion",
        titulo="Qué pasa con los datos que faltan (imputación)",
        texto=(
            "Cuando falta uno de los 9 biomarcadores de PhenoAge, lo relleno con la mediana de "
            "referencia para el grupo de edad y sexo de la persona (valores plausibles en la forma "
            "y tendencia de NHANES, no extraídos del microdato). Ese valor aparece marcado como "
            "'inferido' o 'imputado': fue estimado, no medido en esta persona. Cada dato imputado "
            "ensancha la banda de la proyección; medirlo no cambia la salud de nadie, cambia lo que "
            "yo sé y por eso angosta el rango."
        ),
        grupo="conocimiento",
        tags=("imputado", "inferido", "faltante", "mediana", "nhanes", "estimado", "datos faltantes"),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:que_medir",
        titulo="Qué conviene medir primero",
        texto=(
            "Lo que más angosta el rango es medir los biomarcadores de PhenoAge que hoy están "
            "imputados. Orientativamente, por peso en la fórmula y variabilidad típica: RDW y "
            "glucosa pesan más, luego creatinina y VCM, después albúmina, hs-CRP, linfocitos y "
            "leucocitos, y por último fosfatasa alcalina. La pantalla 'Qué medir' de la app ordena "
            "los que faltan con una heurística propia (pesos fijos normalizados); el motor todavía "
            "no calcula valor de información. Casi todos vienen en un hemograma completo más una "
            "química sanguínea básica (glucosa, creatinina, albúmina, fosfatasa alcalina) y una "
            "PCR ultrasensible."
        ),
        grupo="conocimiento",
        tags=(
            "medir", "examen", "laboratorio", "prueba", "hemograma", "que medir", "primero",
            "angostar", "siguiente examen",
        ),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:esfuerzo_ratio",
        titulo="Cómo ordeno las palancas (años ganados por esfuerzo)",
        texto=(
            "Cada escenario tiene años ganados (diferencia de medianas a 10 años frente a seguir "
            "igual), su rango, y un esfuerzo de 1 a 10 que pone la app (ejercicio 3, dieta 3, "
            "dejar el tabaco 4, las tres juntas 10). El ratio impacto/esfuerzo = años ganados ÷ "
            "esfuerzo, y las palancas se ordenan por ese ratio, de mayor a menor. Por eso la "
            "combinación de todo puede ganar más años y aun así no ser la primera: cuesta mucho más. "
            "El 'porcentaje de futuros que mejoran' es la proporción de trayectorias pareadas en "
            "las que la palanca termina con menor edad biológica; en el resto no hace daño, "
            "simplemente algo más pasa primero."
        ),
        grupo="conocimiento",
        tags=(
            "esfuerzo", "ratio", "orden", "ranking", "palancas", "primera", "mejor", "prioridad",
            "por que esta primero", "futuros que mejoran",
        ),
        prioridad=0.9,
    ),
    Chunk(
        id="kb:adherencia",
        titulo="¿Y si no lo sostengo? (adherencia)",
        texto=(
            "La app deja elegir cuánto se sostiene una palanca: 3 meses, 8 meses, 2 años o siempre. "
            "Hoy es una aproximación local de la app (factores 0,25 · 0,5 · 0,8 · 1 sobre los años "
            "ganados); el motor todavía no simula la adherencia. La idea que sí es robusta: poco no "
            "es cero, y parte de lo ganado se queda aunque se afloje después."
        ),
        grupo="conocimiento",
        tags=("adherencia", "sostener", "constancia", "meses", "siempre", "dejar de hacerlo", "plan"),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:aproximaciones",
        titulo="Qué parte del resultado se aproxima en el dispositivo",
        texto=(
            "El servidor calcula PhenoAge hoy y los percentiles P10/mediana/P90 al año 10 por "
            "escenario. La app completa el resto: la curva año a año se interpola entre hoy y el "
            "año 10 (banda creciendo con la raíz del tiempo); las líneas finas del abanico son "
            "ilustrativas; el 'por qué' (contribución de cada biomarcador) es una aproximación "
            "tipo SHAP sobre el estado de hoy, no sobre las 5.000 trayectorias; el percentil "
            "poblacional es aproximado; la adherencia es un factor local. Nada de eso cambia el "
            "orden de las palancas ni las medianas."
        ),
        grupo="conocimiento",
        tags=("aproximacion", "interpolada", "ilustrativa", "local", "shap", "percentil", "curva"),
        prioridad=0.7,
    ),
    Chunk(
        id="kb:poblacion",
        titulo="Frente a personas como tú (percentil)",
        texto=(
            "El percentil compara la aceleración (edad biológica menos cronológica) con la "
            "dispersión típica de la población de la misma edad y sexo, tomando NHANES como "
            "referencia: percentil 50 = en el promedio; más bajo = más joven que el promedio; más "
            "alto = mayor edad biológica que el promedio. Es una aproximación de la app, no un "
            "ranking exacto."
        ),
        grupo="conocimiento",
        tags=("percentil", "poblacion", "promedio", "personas como tu", "nhanes", "comparacion", "gente"),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:habitos",
        titulo="Qué hago con los hábitos registrados",
        texto=(
            "Guardo sueño (horas), tabaco, actividad física, alimentación y estrés. De esos, el motor "
            "de hoy solo simula como palancas el ejercicio aeróbico, la dieta mediterránea y dejar "
            "el tabaco (esta última solo aparece si la persona fuma). Sueño, alcohol y estrés se "
            "registran y se mencionan en el 'por qué' de forma aproximada, pero todavía no tienen "
            "efecto anual propio en la simulación; es trabajo pendiente del motor."
        ),
        grupo="conocimiento",
        tags=(
            "habitos", "sueno", "dormir", "estres", "alcohol", "alimentacion", "actividad",
            "tabaco", "fumar",
        ),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:calibracion",
        titulo="De dónde sale esto y qué tan confiable es",
        texto=(
            "Capa 1 son los pesos publicados de PhenoAge (Levine 2018). Capa 2 son efectos de "
            "literatura epidemiológica, aproximados y direccionales; nada se presenta como verdad "
            "exacta. Capa 3 es Monte Carlo con ruido biológico. Todavía no publico una calibración "
            "formal (cobertura del rango en datos no vistos): lo que muestro en la pestaña "
            "Respaldo es de dónde sale cada número, las fuentes (NHANES, Levine 2018) y la banda "
            "P10–P90 como incertidumbre explícita. No pido confianza ciega."
        ),
        grupo="conocimiento",
        tags=("calibracion", "respaldo", "confiable", "fuentes", "validado", "evidencia", "literatura"),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:limites",
        titulo="Lo que no hago",
        texto=(
            "No diagnostico ni indico tratamientos, dosis ni medicamentos; para decisiones clínicas, "
            "hablar con un profesional de la salud. No predigo una enfermedad concreta: estratifico "
            "y proyecto trayectorias probables de edad biológica con incertidumbre explícita. No "
            "simulo más de 3 cambios a la vez, ni dietas o suplementos específicos, ni genética, ni "
            "fotos envejecidas. Si un dato no está registrado, lo digo en vez de adivinarlo."
        ),
        grupo="conocimiento",
        tags=(
            "diagnostico", "medico", "doctor", "tratamiento", "enfermedad", "medicamento",
            "suplemento", "genetica", "limites", "no puedes",
        ),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:app",
        titulo="Dónde está cada cosa en la app",
        texto=(
            "Futuro: el resultado principal (edad biológica hoy, proyección a 10 años con su banda, "
            "tus palancas, el porqué, el percentil y qué medir). Simular: todas las palancas "
            "ordenadas, el detalle pareado de cada una (mismos futuros, una sola cosa cambiada), la "
            "adherencia y 'guardar como mi plan'. Respaldo: de dónde sale cada número y las fuentes. "
            "Perfil: datos básicos, hábitos, objetivos, exámenes (subir PDF o foto; leo hasta 12 "
            "biomarcadores), wearables, cerrar sesión y borrar mis datos. Para actualizar exámenes: "
            "Perfil → Exámenes, o 'Actualizar mis exámenes' en Qué medir. Después de subir exámenes "
            "o cambiar hábitos conviene volver a simular."
        ),
        grupo="conocimiento",
        tags=(
            "app", "donde", "pantalla", "subir", "examenes", "perfil", "plan", "borrar", "cuenta",
            "ayuda", "que puedes hacer", "como uso",
        ),
        prioridad=0.7,
        respaldo=True,
    ),
]

#: Every static chunk: explanations + one per biomarker + one per intervention.
KNOWLEDGE: tuple[Chunk, ...] = (
    *_ESTATICOS,
    *(_chunk_biomarcador(n) for n in BIOMARKER_SPECS),
    *(_chunk_intervencion(k) for k in SCENARIOS if k != "ninguna"),
)
