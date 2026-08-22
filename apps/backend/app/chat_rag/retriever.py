"""Lexical retrieval over the chat chunks: BM25 on accent-stripped Spanish
stems, plus a synonym map so "azúcar" finds `glucosa` and "fumar" finds
`cesacion_tabaco`. Deterministic and dependency-free.

Why not embeddings: the corpus is ~60 short chunks per user, the vocabulary is
closed (12 biomarkers, 4 interventions, a dozen concepts) and Anthropic does
not serve embeddings — a synonym table covers the semantic gap a vector index
would, without a second API or a vector column. `retrieve()` is the seam to
replace if that ever changes.
"""

from __future__ import annotations

import math
import re
import unicodedata
from collections import Counter
from collections.abc import Iterable, Sequence

from app.chat_rag.chunks import Chunk

#: Function words and chat filler that carry no topic. Accent-free because
#: `normalize()` runs first. "que" is here, so "por qué" must be rewritten to
#: "porque" *before* tokenizing — see `_FRASES`.
STOPWORDS: frozenset[str] = frozenset(
    """
    a al algo alguna algunas alguno algunos ante antes aqui asi aun aunque cada casi
    como con contra cual cuales cualquier cuando cuanta cuantas cuanto cuantos de del
    demasiado desde donde dos e el ella ellas ellos en entre era eran eres es esa esas
    ese eso esos esta estaba estaban estamos estan estar estas este esto estos estoy fue
    fueron fui ha habia hace hacen hacer haces hago han has hasta hay he la las le les
    lo los me mi mia mias mio mios mis mucha muchas mucho muchos muy nada ni no nos
    nosotras nosotros nuestra nuestras nuestro nuestros o os otra otras otro otros para
    pero poco pocos por porfa puede pueden puedo puedes que quien quienes se sea sean
    segun ser si sido siempre sin sobre sois somos son soy su sus suya suyas suyo suyos
    tal tambien tan tanta tantas tanto tantos te tener tengo ti tiene tienen tienes toda
    todas todo todos tu tus tuya tuyas tuyo tuyos un una unas uno unos usted ustedes va
    vamos van vaya ve veo ver vez vosotras vosotros vuestra vuestras vuestro vuestros y
    ya yo
    hola buenas gracias favor dime dame cuentame explicame ayudame quiero quisiera
    gustaria saber significa significan entonces pues bueno ok oye mira vale listo
    podrias podria deberia deberias seria serian cuento sale
    """.split()
)

#: Multi-word rewrites applied before tokenizing, so intents made of stopwords
#: survive ("por qué" → "porque").
_FRASES: tuple[tuple[str, str], ...] = (
    ("por que", "porque"),
    ("de donde", "fuentes"),
    ("que tan", "cuanto"),
    ("que pasa si", "escenario palanca"),
    ("y si", "escenario palanca"),
    ("que puedes hacer", "app ayuda"),
    ("que sabes", "app ayuda"),
    ("que haces", "app ayuda"),
    ("globulos rojos", "globulosrojos"),
    ("globulos blancos", "globulosblancos"),
    ("proteina c reactiva", "pcr"),
    ("actividad fisica", "ejercicio"),
    ("aceite de oliva", "dieta"),
    ("todo junto", "combinada"),
    ("las tres", "combinada"),
    ("masa corporal", "imc"),
    ("datos faltantes", "faltante"),
    ("como funciona", "simulacion"),
    ("personas como yo", "poblacion"),
    ("gente como yo", "poblacion"),
    ("ano tras ano", "curva"),
    ("ano a ano", "curva"),
)

#: Query expansion: a normalized token (or its stem) → canonical tags that
#: chunks carry. This is the "semantic" layer of the retriever. Values are
#: tags as they appear on chunks (`retriever.stem()` is applied to both sides
#: at match time, so write them as plain words).
SINONIMOS: dict[str, tuple[str, ...]] = {
    # biomarkers
    "azucar": ("glucosa",), "glicemia": ("glucosa",), "diabetes": ("glucosa",),
    "insulina": ("glucosa",), "pcr": ("hs_crp", "inflamacion"), "crp": ("hs_crp",),
    "inflamacion": ("hs_crp",), "inflamado": ("hs_crp",), "rinon": ("creatinina",),
    "rinones": ("creatinina",), "renal": ("creatinina",), "higado": ("albumina", "fosfatasa_alcalina"),
    "hepatico": ("albumina", "fosfatasa_alcalina"), "hueso": ("fosfatasa_alcalina",),
    "huesos": ("fosfatasa_alcalina",), "defensas": ("leucocitos", "linfocitos_pct"),
    "inmune": ("leucocitos", "linfocitos_pct"), "globulosblancos": ("leucocitos",),
    "globulosrojos": ("rdw", "vcm"), "hemograma": ("rdw", "vcm", "leucocitos", "linfocitos_pct"),
    "anemia": ("vcm", "rdw"), "colesterol": ("colesterol_total",), "presion": ("presion_sistolica",),
    "tension": ("presion_sistolica",), "hipertension": ("presion_sistolica",),
    "peso": ("imc", "perfil"), "obesidad": ("imc",), "gordo": ("imc",), "estatura": ("perfil", "imc"),
    "altura": ("perfil", "imc"), "bmi": ("imc",),
    # interventions / habits
    "deporte": ("ejercicio",), "correr": ("ejercicio",), "caminar": ("ejercicio",),
    "trotar": ("ejercicio",), "bici": ("ejercicio",), "bicicleta": ("ejercicio",),
    "nadar": ("ejercicio",), "gimnasio": ("ejercicio",), "gym": ("ejercicio",),
    "entrenar": ("ejercicio",), "moverme": ("ejercicio",), "cardio": ("ejercicio",),
    "pasos": ("ejercicio",), "sedentario": ("ejercicio", "habitos"),
    "dieta": ("dieta", "alimentacion"), "comer": ("dieta", "alimentacion"),
    "comida": ("dieta", "alimentacion"), "comidas": ("dieta", "alimentacion"),
    "alimentacion": ("dieta",), "alimentos": ("dieta",), "verduras": ("dieta",),
    "pescado": ("dieta",), "ultraprocesados": ("dieta",), "mediterranea": ("dieta",),
    "nutricion": ("dieta", "albumina"),
    "fumar": ("tabaco",), "fumo": ("tabaco",), "cigarrillo": ("tabaco",), "cigarrillos": ("tabaco",),
    "cigarro": ("tabaco",), "vapear": ("tabaco",), "vapeo": ("tabaco",), "nicotina": ("tabaco",),
    "dormir": ("sueno", "habitos"), "duermo": ("sueno", "habitos"), "sueno": ("habitos",),
    "insomnio": ("sueno", "habitos"), "descanso": ("sueno", "habitos"),
    "estres": ("habitos",), "estresado": ("estres", "habitos"), "ansiedad": ("estres", "habitos"),
    "alcohol": ("habitos",), "trago": ("alcohol", "habitos"), "cerveza": ("alcohol", "habitos"),
    "vino": ("alcohol", "habitos"), "beber": ("alcohol", "habitos"), "tomar": ("alcohol", "habitos"),
    # result concepts
    "palanca": ("palancas", "escenario"), "palancas": ("escenario",), "habito": ("palancas", "habitos"),
    "habitos": ("palancas",), "cambio": ("palancas", "escenario"), "cambios": ("palancas", "escenario"),
    "cambiar": ("palancas", "escenario"), "mejorar": ("palancas", "mejor"), "recomiendas": ("palancas", "mejor"),
    "recomendacion": ("palancas", "mejor"), "recomendar": ("palancas", "mejor"), "consejo": ("palancas", "mejor"),
    "empezar": ("mejor", "palancas"), "primero": ("mejor", "primera"), "gemelo": ("veredicto", "mejor"),
    "intervencion": ("palancas", "escenario"), "intervenciones": ("palancas", "escenario"),
    "escenarios": ("escenario",), "combinacion": ("combinada",), "combo": ("combinada",),
    "ganar": ("anos ganados",), "ganados": ("anos ganados",), "gano": ("anos ganados",),
    "rango": ("incertidumbre", "banda"), "rangos": ("incertidumbre", "banda"), "banda": ("incertidumbre",),
    "intervalo": ("incertidumbre", "banda"), "seguro": ("incertidumbre", "calibracion"),
    "segura": ("incertidumbre", "calibracion"), "confiable": ("calibracion", "incertidumbre"),
    "confianza": ("incertidumbre", "calibracion"), "exacto": ("incertidumbre",), "preciso": ("incertidumbre",),
    "error": ("incertidumbre",), "ancho": ("incertidumbre", "banda"), "ancha": ("incertidumbre", "banda"),
    "abanico": ("banda", "proyeccion"), "p10": ("banda",), "p90": ("banda",), "mediana": ("banda",),
    "porque": ("porque", "shap"), "pesa": ("porque", "shap"), "pesan": ("porque", "shap"),
    "influye": ("porque", "shap"), "influyen": ("porque", "shap"), "causa": ("porque", "shap"),
    "causas": ("porque", "shap"), "razon": ("porque",), "razones": ("porque",), "explica": ("porque",),
    "culpa": ("porque", "shap"), "afecta": ("porque", "shap"), "afectan": ("porque", "shap"),
    "envejece": ("porque", "shap", "phenoage"), "rejuvenece": ("porque", "shap", "phenoage"),
    "biologica": ("phenoage",), "reloj": ("phenoage",), "phenoage": ("phenoage",), "fenoage": ("phenoage",),
    "aceleracion": ("phenoage",), "edad": ("phenoage", "perfil"), "joven": ("phenoage", "poblacion"),
    "viejo": ("phenoage", "poblacion"), "vieja": ("phenoage", "poblacion"), "mayor": ("phenoage",),
    "futuro": ("proyeccion", "resumen"), "futuros": ("proyeccion", "simulacion"),
    "proyeccion": ("proyeccion", "baseline"), "trayectoria": ("baseline", "curva"),
    "trayectorias": ("simulacion", "curva"), "curva": ("baseline",), "simulacion": ("simulacion", "resumen"),
    "simular": ("simulacion",), "simulaste": ("simulacion", "resumen"), "resultado": ("resumen",),
    "resultados": ("resumen",), "montecarlo": ("simulacion",), "monte": ("simulacion",), "carlo": ("simulacion",),
    "anos": ("proyeccion",), "decada": ("proyeccion",), "horizonte": ("proyeccion",),
    "percentil": ("poblacion",), "promedio": ("poblacion",), "gente": ("poblacion",),
    "personas": ("poblacion",), "poblacion": ("poblacion",), "nhanes": ("poblacion", "imputacion"),
    "comparo": ("poblacion",), "comparar": ("poblacion",), "comparacion": ("poblacion",),
    "medir": ("medir", "faltante"), "medirme": ("medir", "faltante"), "mida": ("medir", "faltante"),
    "examen": ("medir", "examen"), "examenes": ("medir", "examen"), "laboratorio": ("medir", "examen"),
    "prueba": ("medir", "examen"), "pruebas": ("medir", "examen"), "analisis": ("medir", "examen"),
    "sangre": ("medir", "examen"), "falta": ("faltante", "imputacion"), "faltan": ("faltante", "imputacion"),
    "faltante": ("imputacion",), "faltantes": ("faltante", "imputacion"), "imputado": ("imputacion", "faltante"),
    "imputados": ("imputacion", "faltante"), "inferido": ("imputacion", "faltante"),
    "inferidos": ("imputacion", "faltante"), "estimado": ("imputacion",), "estimados": ("imputacion",),
    "inventado": ("imputacion", "calibracion"), "inventas": ("imputacion", "calibracion"),
    "sostener": ("adherencia",), "sostengo": ("adherencia",), "constante": ("adherencia",),
    "constancia": ("adherencia",), "meses": ("adherencia",), "siempre": ("adherencia",),
    "dejo": ("adherencia",), "abandono": ("adherencia",), "plan": ("adherencia", "app"),
    "esfuerzo": ("esfuerzo", "ratio"), "dificil": ("esfuerzo",), "facil": ("esfuerzo",),
    "costo": ("esfuerzo",), "cuesta": ("esfuerzo",), "ratio": ("esfuerzo",), "orden": ("esfuerzo", "ranking"),
    "ordenaste": ("esfuerzo", "ranking"), "ranking": ("esfuerzo",), "mejor": ("mejor", "palancas"),
    "diagnostico": ("limites",), "diagnosticar": ("limites",), "medico": ("limites",), "doctor": ("limites",),
    "doctora": ("limites",), "enfermedad": ("limites",), "enfermo": ("limites",), "tratamiento": ("limites",),
    "medicamento": ("limites",), "medicamentos": ("limites",), "pastilla": ("limites",),
    "suplemento": ("limites",), "suplementos": ("limites",), "genetica": ("limites",), "adn": ("limites",),
    "morir": ("limites", "proyeccion"), "muerte": ("limites", "proyeccion"), "mortalidad": ("limites", "proyeccion"),
    "calibracion": ("calibracion",), "respaldo": ("calibracion",), "fuentes": ("calibracion",),
    "evidencia": ("calibracion",), "estudio": ("calibracion",), "estudios": ("calibracion",),
    "paper": ("calibracion",), "literatura": ("calibracion",), "validado": ("calibracion",),
    "familia": ("historia familiar",), "familiar": ("historia familiar",), "familiares": ("historia familiar",),
    "mama": ("historia familiar",), "papa": ("historia familiar",), "madre": ("historia familiar",),
    "padre": ("historia familiar",), "abuelo": ("historia familiar",), "abuela": ("historia familiar",),
    "hereditario": ("historia familiar",), "genes": ("historia familiar", "limites"),
    "objetivo": ("objetivos",), "objetivos": ("objetivos",), "meta": ("objetivos",), "metas": ("objetivos",),
    "perfil": ("perfil",), "datos": ("perfil", "resumen"), "informacion": ("perfil", "resumen"),
    "guardado": ("perfil", "app"), "guardaste": ("perfil", "app"), "sabes": ("resumen", "app"),
    "app": ("app",), "aplicacion": ("app",), "pantalla": ("app",), "subir": ("app", "examen"),
    "subo": ("app", "examen"), "cargar": ("app", "examen"), "borrar": ("app",), "cuenta": ("app",),
    "privacidad": ("app",), "ayuda": ("app",),
}

_TOKEN_RE = re.compile(r"[a-z0-9_]+")


def normalize(text: str) -> str:
    """Lowercase, accents stripped (NFKD), ñ → n."""
    nfkd = unicodedata.normalize("NFKD", text.lower())
    return "".join(ch for ch in nfkd if not unicodedata.combining(ch))


def stem(token: str) -> str:
    """Crude Spanish stemming: drop a plural suffix, then truncate to 6 chars,
    so "palancas"/"palanca", "simulación"/"simular", "intervenciones"/
    "intervención" collapse together. Biomarker ids (`hs_crp`) survive intact
    because they are short and contain no plural ending."""
    t = token
    if len(t) > 5 and t.endswith("es") and not t.endswith(("les", "nes", "res")):
        t = t[:-2]
    elif len(t) > 3 and t.endswith("s"):
        t = t[:-1]
    return t[:6]


def tokenize(text: str) -> list[str]:
    """Normalized, phrase-rewritten, stopword-free tokens (not yet stemmed)."""
    norm = normalize(text)
    for frase, reemplazo in _FRASES:
        norm = norm.replace(frase, reemplazo)
    return [t for t in _TOKEN_RE.findall(norm) if t not in STOPWORDS and len(t) > 1]


def terminos(text: str, peso: float = 1.0) -> Counter:
    """Weighted query stems, with synonym expansion to canonical tags."""
    out: Counter = Counter()
    for tok in tokenize(text):
        out[stem(tok)] += peso
        for tag in SINONIMOS.get(tok, ()):
            for part in tag.split():
                out[stem(part)] += peso
    return out


class _Index:
    """BM25 over the chunks' title + text + tags. Tags are repeated so a
    canonical topic word on a chunk outweighs the same word buried in prose."""

    K1 = 1.5
    B = 0.75
    TAG_PESO = 3

    def __init__(self, chunks: Sequence[Chunk]):
        self.chunks = list(chunks)
        self.tf: list[Counter] = []
        df: Counter = Counter()
        for c in self.chunks:
            cnt: Counter = Counter()
            for tok in tokenize(c.titulo) + tokenize(c.texto):
                cnt[stem(tok)] += 1
            for tag in c.tags:
                for part in tokenize(tag) or [normalize(tag)]:
                    cnt[stem(part)] += self.TAG_PESO
            self.tf.append(cnt)
            df.update(cnt.keys())
        self.n = len(self.chunks)
        self.avgdl = (sum(sum(c.values()) for c in self.tf) / self.n) if self.n else 1.0
        self.idf = {
            term: math.log(1 + (self.n - d + 0.5) / (d + 0.5)) for term, d in df.items()
        }

    def scores(self, query: Counter) -> list[float]:
        out: list[float] = []
        for cnt in self.tf:
            dl = sum(cnt.values()) or 1
            s = 0.0
            for term, peso in query.items():
                f = cnt.get(term)
                if not f:
                    continue
                idf = self.idf.get(term, 0.0)
                s += peso * idf * (f * (self.K1 + 1)) / (
                    f + self.K1 * (1 - self.B + self.B * dl / self.avgdl)
                )
            out.append(s)
        return out


def _query(consulta: str, contexto_previo: Sequence[str], enfoque: str | None) -> Counter:
    q = terminos(consulta, 1.0)
    # The previous user turns disambiguate follow-ups ("¿y por qué?"), at a
    # lower weight so they cannot hijack a question that changed topic.
    for i, prev in enumerate(reversed(list(contexto_previo)[-2:])):
        q.update(terminos(prev, 0.4 if i == 0 else 0.2))
    if enfoque:
        q.update(terminos(enfoque.replace(":", " ").replace("_", " "), 1.5))
    return q


def _subgrupo(chunk: Chunk) -> str:
    """`bio:glucosa` → `bio`, `sim:escenario:2` → `sim:escenario`, `kb:x` → `kb`.
    Used to keep one family of chunks from crowding out the others."""
    parts = chunk.id.split(":")
    return ":".join(parts[:2]) if parts[0] == "sim" and len(parts) > 2 else parts[0]


def _seleccionar(
    candidatos: list[tuple[float, Chunk]], presupuesto_tokens: int, k_max: int
) -> list[Chunk]:
    """Greedy pick by score with a mild diversity penalty per family, under a
    token budget. Skips a chunk that does not fit and keeps looking for smaller
    ones, so one long chunk never blocks three short relevant ones."""
    elegidos: list[Chunk] = []
    usados = 0
    por_familia: Counter = Counter()
    restantes = list(candidatos)
    while restantes and len(elegidos) < k_max:
        restantes.sort(
            key=lambda sc: sc[0] * (0.75 ** por_familia[_subgrupo(sc[1])]), reverse=True
        )
        _, chunk = restantes.pop(0)
        if usados + chunk.tokens > presupuesto_tokens:
            continue
        elegidos.append(chunk)
        usados += chunk.tokens
        por_familia[_subgrupo(chunk)] += 1
    return elegidos


def retrieve(
    chunks: Sequence[Chunk],
    consulta: str,
    *,
    contexto_previo: Sequence[str] = (),
    enfoque: str | None = None,
    presupuesto_tokens: int = 1600,
    k_max: int = 8,
    excluir: Iterable[str] = (),
) -> list[Chunk]:
    """The chunks to put in the system prompt for this turn.

    `contexto_previo` — the last user messages (oldest first), for follow-ups.
    `enfoque` — where in the app the chat was opened from ("escenario:0",
    "porque", "biomarcador:glucosa"...): its words join the query and any
    chunk whose id contains it gets a flat bonus, so "¿por qué esta?" asked
    from a lever's detail screen lands on that lever.
    With no usable keywords at all ("hola"), falls back to the overview chunks
    (`Chunk.respaldo`) so the model still knows who it is talking to.
    """
    excluidos = set(excluir)
    idx = _Index(chunks)
    q = _query(consulta, contexto_previo, enfoque)
    base = idx.scores(q)
    enf = normalize(enfoque).strip() if enfoque else ""
    bonus = max(5.0, max(base) if base else 0.0)
    puntuados: list[tuple[float, Chunk]] = []
    for c, s in zip(chunks, base, strict=True):
        if c.id in excluidos:
            continue
        score = s * c.prioridad
        if enf and enf in normalize(c.id):
            score += bonus
        if score > 0:
            puntuados.append((score, c))
    if not puntuados:
        puntuados = [
            (float(c.prioridad), c) for c in chunks if c.respaldo and c.id not in excluidos
        ]
    return _seleccionar(puntuados, presupuesto_tokens, k_max)


def buscar(
    chunks: Sequence[Chunk],
    consulta: str,
    *,
    excluir: Iterable[str] = (),
    presupuesto_tokens: int = 700,
    k_max: int = 3,
) -> list[Chunk]:
    """The `buscar_mis_datos` tool: same retriever, smaller budget, no
    fallback — an empty list tells the model there is nothing on that topic."""
    excluidos = set(excluir)
    idx = _Index(chunks)
    base = idx.scores(terminos(consulta))
    puntuados = [
        (s * c.prioridad, c)
        for c, s in zip(chunks, base, strict=True)
        if s > 0 and c.id not in excluidos
    ]
    return _seleccionar(puntuados, presupuesto_tokens, k_max)
