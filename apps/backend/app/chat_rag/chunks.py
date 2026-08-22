"""The record every document builder emits, plus the two helpers they all
share: es-CO number formatting (so the model copies numbers in the exact
format the app renders — `8.240`, `6,4`, `+2,4`) and the rough token estimate
the retrieval budget is measured in."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

#: Typographic minus, same glyph the app's `Fmt.delta` uses.
MINUS = "−"


@dataclass(frozen=True)
class Chunk:
    """One retrievable fragment: a stable id the UI can show as a source, a
    short title, the text the model reads, and the tags the retriever matches
    on top of the text (canonical topic words — see `retriever.SINONIMOS`)."""

    id: str
    titulo: str
    texto: str
    #: "usuario" (stored data) | "resultado" (the simulation the app sent) |
    #: "conocimiento" (static engine knowledge) | "core" (always included).
    grupo: str
    tags: tuple[str, ...] = ()
    #: Multiplier on the retrieval score. >1 for chunks that should win ties
    #: (the user's own numbers beat the generic explanation of the same topic).
    prioridad: float = 1.0
    #: Chunks worth showing when the question has no usable keywords ("hola",
    #: "¿qué puedes hacer?") — the overview of what I know about this person.
    respaldo: bool = False

    def render(self) -> str:
        return f"[{self.id}] {self.titulo}\n{self.texto}"

    @property
    def tokens(self) -> int:
        return estimate_tokens(self.render())


def estimate_tokens(text: str) -> int:
    """Deliberately conservative (Spanish runs ~3.5–4 chars per token on
    Claude's tokenizer): over-estimating keeps the prompt under budget, which
    is the only direction that matters here."""
    return max(1, len(text) // 3)


def fmt_num(valor: float | int | None, decimales: int = 1) -> str:
    """es-CO: thousands with '.', decimals with ','; at most `decimales`
    decimals and none at all when the value is (nearly) whole — the same rule
    as `Fmt.corto` in the app. `None` renders as an em dash."""
    if valor is None:
        return "—"
    v = float(valor)
    if abs(v - round(v)) < 0.05:
        return f"{int(round(v)):,}".replace(",", ".")
    s = f"{v:,.{decimales}f}"
    return s.replace(",", "\x00").replace(".", ",").replace("\x00", ".")


def fmt_delta(valor: float | None, decimales: int = 1) -> str:
    """Signed, with a typographic minus: '+2,4' · '−0,3' · '0'."""
    if valor is None:
        return "—"
    if abs(valor) < 0.05:
        return "0"
    s = fmt_num(abs(valor), decimales)
    return f"+{s}" if valor > 0 else f"{MINUS}{s}"


def fmt_rango(a: float | None, b: float | None) -> str:
    return f"entre {fmt_num(a)} y {fmt_num(b)}"


def fmt_rango_delta(a: float | None, b: float | None) -> str:
    return f"entre {fmt_delta(a)} y {fmt_delta(b)}"


def fmt_lista(items: Iterable[str]) -> str:
    """'a', 'a y b', 'a, b y c'."""
    lista = [i for i in items if i]
    if not lista:
        return ""
    if len(lista) == 1:
        return lista[0]
    return ", ".join(lista[:-1]) + " y " + lista[-1]
