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
from app.health_metrics.interventions import (
    DESCUENTO_COMBINACION,
    DYNAMICS,
    EFECTO_RELATIVO_A,
    HETEROGENEIDAD_RESPUESTA,
    PALANCAS,
    SCENARIOS,
)
from app.health_metrics.nhanes_reference import DISPERSION
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

#: Effort (1–10, lower is easier) and description per lever now live in the
#: engine itself (`SCENARIOS[...].esfuerzo` / `.descripcion`), so the chat, the
#: app and the ranking can never disagree. Kept as names for the old callers.
ESFUERZO_APP: dict[str, int] = {key: sc.esfuerzo for key, sc in SCENARIOS.items() if key != "ninguna"}
DESCRIPCION_APP: dict[str, str] = {
    key: sc.descripcion for key, sc in SCENARIOS.items() if key != "ninguna"
}
#: Which stored habit each lever closes, in the user's words.
NOMBRE_HABITO: dict[str, str] = {
    "actividad": "la actividad física",
    "alimentacion": "la alimentación",
    "tabaco": "el tabaco",
    "sueno": "el sueño",
    "estres": "el estrés",
    "alcohol": "el alcohol",
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
    "sueno_8h": ("sueno", "dormir", "horas de sueno", "descanso", "insomnio", "acostarme"),
    "reducir_estres": ("estres", "ansiedad", "mindfulness", "meditar", "relajar", "tension"),
    "reducir_alcohol": ("alcohol", "tomar", "beber", "trago", "cerveza", "vino", "copas"),
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
        + (" (proporcional al valor actual)" if b in EFECTO_RELATIVO_A else "")
        for b, v in sc.efectos_anuales.items()
    )
    partes = [
        f"{sc.nombre}. {sc.descripcion}".strip(),
        f"Efecto anual que sumo a la deriva natural de cada biomarcador: {efectos}."
        if efectos
        else "Sin efecto sobre los biomarcadores (línea base).",
    ]
    if sc.habito:
        partes.append(
            f"Cierra la brecha de {NOMBRE_HABITO[sc.habito]}: solo aplica si la persona tiene "
            "ese hábito abierto (brecha 1 = del todo, 0,5 = a medias, 0 = ya lo tiene, y "
            "entonces no se ofrece); el efecto se escala por esa brecha."
        )
    if sc.partes:
        partes.append(
            "Es la combinación de " + fmt_lista(SCENARIOS[p].nombre.lower() for p in sc.partes)
            + "; solo aplica si al menos una de sus partes aplica."
        )
    if sc.esfuerzo:
        partes.append(
            f"Esfuerzo: {sc.esfuerzo} de 10 (las palancas se ordenan por años ganados dividido "
            "entre este esfuerzo; en una combinación los esfuerzos se suman)."
        )
    partes.append(
        "Los tamaños de efecto son direccionales, sintetizados de la literatura de ejercicio, "
        "dieta, cesación de tabaco, sueño, estrés y alcohol; no están ajustados a un ensayo "
        "concreto. Cada persona responde distinto: en la simulación el efecto se multiplica "
        "por una respuesta individual (promedio 1, ±50 %), que es lo que da el rango de los años "
        "ganados."
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
            "cada biomarcador cambia un poco cada año (deriva natural por edad), los hábitos "
            "actuales de la persona ajustan esa deriva (fumar, sedentarismo, dormir poco, estrés, "
            "alcohol la empeoran; tenerlos buenos la frena) y cada palanca suma un efecto anual "
            "escalado por la brecha que le queda a la persona. Capa 3, Monte Carlo: repito la capa 2 "
            "en 5.000 trayectorias por escenario, con ruido biológico nuevo cada año, durante 10 "
            "años, y calculo PhenoAge en cada año de cada una; los percentiles 10, 50 (mediana) y 90 "
            "son la banda P10–P90, año a año. Los futuros están PAREADOS: cada trayectoria usa los "
            "mismos arranques y los mismos ruidos con y sin la palanca, así que los 'años ganados' "
            "son la mediana de la diferencia 'misma vida con la palanca menos sin ella', con su "
            "rango P10–P90 y el porcentaje de futuros en que la palanca termina mejor. Las "
            "combinaciones de 2 o 3 palancas se simulan también (nunca más de 3), con un descuento "
            "por solaparse."
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
            "El rango no es un intervalo de confianza estadístico: es la dispersión real que producen "
            "en las 5.000 trayectorias (a) el ruido biológico año a año, (b) lo que no sé de la "
            "persona —cada biomarcador NO medido arranca muestreado de la dispersión de su grupo de "
            "edad y sexo, por eso la banda de HOY ya tiene ancho si falta algo— y (c) la respuesta "
            "individual a cada palanca (promedio 1, ±50 %, con ~2 % de no respondedores), que es lo "
            "que da rango a los años ganados. El 80 % de los futuros simulados cae dentro de la "
            "banda; la mediana es el futuro 'del medio'. El rango es ancho a propósito. Se angosta "
            "cuando hay más biomarcadores medidos y se ensancha con el horizonte (más años, más "
            "incertidumbre). Confío más en el orden de las palancas que en cualquiera de los "
            "números por separado."
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
            "y tendencia de NHANES, calibrados para que la persona mediana de cada edad marque ≈ su "
            "edad cronológica; no extraídos del microdato). Ese valor aparece marcado como "
            "'inferido' o 'imputado': fue estimado, no medido en esta persona. En la simulación un "
            "dato imputado no se fija: se sortea en cada trayectoria dentro de la dispersión "
            "poblacional de ese biomarcador, así que ensancha la banda desde el día de hoy; medirlo "
            "no cambia la salud de nadie, cambia lo que yo sé y por eso angosta el rango. El motor "
            "calcula cuánto angostaría la banda medir cada uno (valor de información)."
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
            "imputados. El motor lo calcula de verdad (valor de información): vuelve a correr la "
            "línea base con ese biomarcador fijo y mide cuánto se angosta la banda P10–P90 a 10 "
            "años; la pantalla 'Qué medir' de la app muestra ese ranking. Por peso en la fórmula y "
            "dispersión típica, el RDW es por mucho el que más pesa (varios años de banda), luego "
            "creatinina y VCM, después glucosa, albúmina, leucocitos, hs-CRP y linfocitos, y por "
            "último fosfatasa alcalina. Casi todos vienen en un hemograma completo más una química "
            "sanguínea básica (glucosa, creatinina, albúmina, fosfatasa alcalina) y una PCR "
            "ultrasensible."
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
            "Cada escenario tiene años ganados (mediana de la diferencia pareada a 10 años frente "
            "a seguir igual), su rango P10–P90, y un esfuerzo de 1 a 10 fijado en el motor "
            "(ejercicio 3, dieta 3, dejar el tabaco 4, dormir 8 horas 2, reducir el estrés 2, "
            "bajar el alcohol 2; en una combinación se suman). El ratio impacto/esfuerzo = años "
            "ganados ÷ esfuerzo, y las palancas se ordenan por ese ratio, de mayor a menor. Por eso "
            "una combinación puede ganar más años y aun así no ser la primera: cuesta más. Solo se "
            "ofrecen las palancas que aplican a la persona según sus hábitos registrados (a quien ya "
            "hace ejercicio no se le ofrece el ejercicio). El 'porcentaje de futuros que mejoran' es "
            "la proporción de trayectorias pareadas en las que la palanca termina con menor edad "
            "biológica; en el resto no hace daño, simplemente algo más pasa primero."
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
            "El servidor calcula PhenoAge hoy, la curva año a año (P10/mediana/P90) de cada "
            "escenario, los años ganados pareados con su rango, el porcentaje de futuros que "
            "mejoran, 40 trayectorias reales de muestra, el 'por qué' (contribución de cada "
            "biomarcador medido frente a la mediana de referencia de su edad y sexo, y de cada "
            "hábito registrado a 10 años — tipo SHAP sobre el estado basal, no sobre las 5.000 "
            "trayectorias), el percentil poblacional y el valor de información de cada dato sin "
            "medir. Lo único que sigue siendo una aproximación local de la app es la adherencia "
            "(factores 0,25 · 0,5 · 0,8 · 1). Si la app corre contra un servidor viejo, interpola "
            "la curva y aproxima el resto en el dispositivo, y lo dice."
        ),
        grupo="conocimiento",
        tags=("aproximacion", "interpolada", "ilustrativa", "local", "shap", "percentil", "curva"),
        prioridad=0.7,
    ),
    Chunk(
        id="kb:poblacion",
        titulo="Frente a personas como tú (percentil)",
        texto=(
            "El percentil compara la aceleración (edad biológica menos cronológica) con la de la "
            "persona de referencia de la misma edad y sexo (los 9 biomarcadores en su mediana, que "
            "marca ≈ su edad) y con la dispersión poblacional de PhenoAge (~5 años, propagada desde "
            "la dispersión de cada biomarcador): percentil 50 = como la referencia; más bajo = más "
            "joven que el promedio; más alto = mayor edad biológica que el promedio. Lo calcula el "
            "motor con una normal; es una aproximación, no un ranking exacto sobre microdato."
        ),
        grupo="conocimiento",
        tags=("percentil", "poblacion", "promedio", "personas como tu", "nhanes", "comparacion", "gente"),
        prioridad=0.8,
    ),
    Chunk(
        id="kb:habitos",
        titulo="Qué hago con los hábitos registrados",
        texto=(
            "Guardo sueño (horas), tabaco, actividad física, alimentación, estrés y alcohol. Cada "
            "uno entra al motor como una brecha de 0 a 1 (0 = ya tiene el hábito bueno, 1 = del "
            "todo abierta: fuma, actividad baja, alimentación baja, ≤6 h de sueño, estrés alto, "
            "alcohol casi diario; 0,5 el nivel intermedio). Dos usos: (1) la línea base es personal "
            "— los hábitos malos la empeoran y los buenos la frenan (el 'por qué' dice cuántos años "
            "a 10 años cuesta o ahorra cada hábito registrado); (2) solo se ofrecen las palancas "
            "cuya brecha está abierta, con el efecto escalado por la brecha: ejercicio aeróbico "
            "(actividad), dieta mediterránea (alimentación), dejar el tabaco, dormir 8 horas, "
            "reducir el estrés y bajar el alcohol. Un hábito no registrado no ajusta la línea base; "
            "las palancas universales se ofrecen igual y las de 'solo si lo haces' (tabaco, alcohol) "
            "no se asumen."
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
            "exacta; la tabla de medianas de referencia está calibrada para que la persona mediana "
            "de cada edad y sexo marque ≈ su edad y envejezca ≈ 1 año PhenoAge por año, y las "
            "prevalencias que sitúan la línea base de cada hábito son supuestos declarados. Capa 3 "
            "es Monte Carlo con ruido biológico, incertidumbre de lo imputado y respuesta individual. "
            "Todavía no publico una calibración formal (cobertura del rango en datos no vistos): lo "
            "que muestro en Respaldo es de dónde sale cada número, las fuentes (NHANES, Levine 2018) "
            "y la banda P10–P90 como incertidumbre explícita. No pido confianza ciega."
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
