"""Turn a chat reply into something worth listening to.

The app writes for the eye: Markdown emphasis, es-CO number formatting
(`8.240`, `6,4`), engine shorthand (`hs-CRP`, `P10–P90`, `SHAP`). Fed
verbatim to a text-to-speech model that reads Spanish, several of those come
out wrong — `8.240` as "ocho punto doscientos cuarenta", `hs-CRP` spelled
letter by letter, `+2,4` as a stray plus sign.

`para_voz()` rewrites the text so the *sound* is right, without touching what
the app shows on screen. Two rules the product owns:

- The decimal comma stays. `6,4` is read "seis coma cuatro" in Spanish, which
  is correct; only the thousands dot is a problem.
- Deltas keep their sign as a word ("más 2,4 años"), because the voice has to
  keep framing gains as gains — same rule as the UI.

Names that are wrong at the phoneme level (Moirai, PhenoAge, Turritopsis)
belong in an ElevenLabs pronunciation dictionary, not here: this module can
only reach spelling, not phonetics.
"""

from __future__ import annotations

import re

#: Engine shorthand → how a person would say it out loud. Order matters:
#: longer keys first so `hs-CRP` wins over a hypothetical `CRP`.
_TERMINOS: list[tuple[str, str]] = [
    (r"hs[-_ ]?CRP", "proteína C reactiva ultrasensible"),
    (r"\bPhenoAge\b", "PhenoAge"),
    (r"\bNHANES\b", "NHANES"),
    (r"\bSHAP\b", "SHAP"),
    (r"\bIMC\b", "índice de masa corporal"),
    (r"\bRDW\b", "amplitud de distribución eritrocitaria"),
    (r"\bMCV\b", "volumen corpuscular medio"),
    (r"\bWBC\b", "recuento de leucocitos"),
    (r"\bALP\b", "fosfatasa alcalina"),
    (r"\bHbA1c\b", "hemoglobina glicosilada"),
    (r"\bP(\d{1,2})\b", r"percentil \1"),
    (r"mg/dL", "miligramos por decilitro"),
    (r"mg/L", "miligramos por litro"),
    (r"g/dL", "gramos por decilitro"),
    (r"µmol/L|umol/L", "micromoles por litro"),
    (r"U/L", "unidades por litro"),
    (r"kg/m2|kg/m²", "kilogramos por metro cuadrado"),
    (r"\bkcal\b", "kilocalorías"),
]

#: Markdown the agent may emit. Stripped, never spoken.
_MARKDOWN = [
    (re.compile(r"```.*?```", re.S), " "),          # bloques de código
    (re.compile(r"`([^`]*)`"), r"\1"),              # código inline
    (re.compile(r"!?\[([^\]]*)\]\([^)]*\)"), r"\1"),  # enlaces e imágenes
    (re.compile(r"(\*\*|__|\*|_)"), ""),            # énfasis
    (re.compile(r"^\s{0,3}#{1,6}\s*", re.M), ""),   # encabezados
    (re.compile(r"^\s*[-–—•·]\s+", re.M), ""),      # viñetas
    (re.compile(r"^\s*>\s?", re.M), ""),            # citas
]

_MILES = re.compile(r"(?<=\d)\.(?=\d{3}(?!\d))")
_NUMERAL = re.compile(r"#\s*(?=\d)")
_RANGO = re.compile(r"\b([A-Za-z]?\d+(?:[.,]\d+)?)\s*[–—]\s*([A-Za-z]?\d+(?:[.,]\d+)?)\b")
_SIGNO = re.compile(r"(?<![\w,.])([+\-−])(?=\d)")
_PORCENTAJE = re.compile(r"\s*%")
_ESPACIOS = re.compile(r"[ \t]{2,}")


def para_voz(texto: str, *, max_chars: int | None = None) -> str:
    """The reply, rewritten to be spoken. Idempotent and safe on empty input.

    `max_chars` truncates at the last sentence boundary that fits, so the
    audio ends on a full stop instead of mid-word — a cut-off sentence sounds
    like a bug, a shorter answer just sounds shorter.
    """
    t = texto or ""
    for patron, reemplazo in _MARKDOWN:
        t = patron.sub(reemplazo, t)

    # 8.240 → 8240, y 1.234.567 → 1234567 (el punto de miles se aplica en
    # cadena, por eso el bucle). La coma decimal de es-CO se queda: "6,4" ya
    # se lee "seis coma cuatro".
    while _MILES.search(t):
        t = _MILES.sub("", t)

    # "1,1–3,7" y "P10–P90" son rangos, no restas.
    t = _RANGO.sub(r"\1 a \2", t)
    # "#1" se leería "almohadilla uno".
    t = _NUMERAL.sub("número ", t)
    # "+2,4" / "−2,4": el signo se dice, y la ganancia se enmarca como ganancia.
    t = _SIGNO.sub(lambda m: "menos " if m.group(1) in "-−" else "más ", t)
    t = _PORCENTAJE.sub(" por ciento", t)
    t = t.replace("≈", "aproximadamente ").replace("±", " más o menos ")

    for patron, reemplazo in _TERMINOS:
        t = re.sub(patron, reemplazo, t)

    t = _ESPACIOS.sub(" ", t).strip()
    if max_chars is not None and len(t) > max_chars:
        t = _recortar(t, max_chars)
    return t


def _recortar(texto: str, max_chars: int) -> str:
    """Cut at the last `.`, `?` or `!` that fits; fall back to the last space
    so we never split a word."""
    recorte = texto[:max_chars]
    corte = max(recorte.rfind("."), recorte.rfind("?"), recorte.rfind("!"))
    if corte >= max_chars // 2:
        return recorte[: corte + 1]
    corte = recorte.rfind(" ")
    return (recorte[:corte] if corte > 0 else recorte).rstrip() + "…"
