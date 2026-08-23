"""Dibuja el reporte (dict con la forma de `schema.ReporteOut`) como PDF con
reportlab: portada + 6 secciones, o el resumen de 1 página (spec §2).

Diseño: la paleta y la tipografía de la app (Fredoka para números grandes,
Nunito para el cuerpo; azul clínico, verde = en rango, ámbar = atención;
NUNCA rojo, sin emoji). Las fuentes TTF viven en `app/report/fonts/` (OFL);
si faltan, cae a Helvetica y limpia los pocos glifos que WinAnsi no tiene.
Disclaimer en portada, en el pie de TODAS las páginas y en la sección de
triage (spec §5 punto 3). No genera texto: todo viene del dict.
"""

from __future__ import annotations

import io
from collections.abc import Mapping, Sequence
from datetime import datetime
from pathlib import Path
from typing import Any

from reportlab.graphics.shapes import Drawing, Line, Polygon, PolyLine, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.platypus import (
    BaseDocTemplate,
    CondPageBreak,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from app.report.builder import fmt, fmt_delta

# ---- Paleta (apps/mobile/lib/app/theme/tokens.dart) ------------------------------
BG = colors.HexColor("#F3FBFC")
SURFACE2 = colors.HexColor("#EBF6F8")
INK = colors.HexColor("#222F3B")
INK2 = colors.HexColor("#626D78")
INK3 = colors.HexColor("#8C97A0")
LINE = colors.HexColor("#DBE5E8")
BLUE = colors.HexColor("#6BAED1")
BLUE_SOFT = colors.HexColor("#D5EEFC")
BLUE_INK = colors.HexColor("#2C5D7E")
GREEN = colors.HexColor("#76B590")
GREEN_SOFT = colors.HexColor("#D9F0E1")
GREEN_INK = colors.HexColor("#2B5E45")
AMBER = colors.HexColor("#CFAB72")
AMBER_SOFT = colors.HexColor("#FAECD7")
AMBER_INK = colors.HexColor("#77562F")
ACTION = colors.HexColor("#2C8BCF")

_FONT_DIR = Path(__file__).with_name("fonts")
_FONTS = {
    "Body": "Nunito-Regular.ttf",
    "Body-Semi": "Nunito-SemiBold.ttf",
    "Body-Bold": "Nunito-Bold.ttf",
    "Display": "Fredoka-SemiBold.ttf",
    "Display-Medium": "Fredoka-Medium.ttf",
}
_registered: dict[str, str] | None = None


def _fonts() -> dict[str, str]:
    """Registra las TTF una vez; devuelve el nombre de fuente por rol. Si
    alguna falta, todos los roles caen a Helvetica (nunca mezcla)."""
    global _registered
    if _registered is not None:
        return _registered
    out: dict[str, str] = {}
    try:
        for rol, archivo in _FONTS.items():
            path = _FONT_DIR / archivo
            if not path.exists():
                raise FileNotFoundError(path)
            name = f"Moirai-{rol}"
            if name not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont(name, str(path)))
            out[rol] = name
        out["unicode"] = "1"
    except Exception:  # pragma: no cover — solo si el deploy perdió las fuentes
        out = {"Body": "Helvetica", "Body-Semi": "Helvetica-Bold", "Body-Bold": "Helvetica-Bold",
               "Display": "Helvetica-Bold", "Display-Medium": "Helvetica-Bold", "unicode": ""}
    _registered = out
    return out


def _m(markup: str) -> str:
    """Marcado ya armado (con `<b>`/`<font>` sobre piezas pasadas por `_t`):
    solo aplica la limpieza de glifos del fallback."""
    if not _fonts().get("unicode"):
        markup = markup.replace("−", "-").replace("≥", ">=").replace("≤", "<=").replace("→", "->").replace("≈", "~")
    return markup


def _t(s: Any) -> str:
    """Texto seguro para Paragraph (escapa `&<>`; si no hay TTF, reemplaza los
    glifos que Helvetica/WinAnsi no tiene)."""
    s = "" if s is None else str(s)
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if not _fonts().get("unicode"):
        s = s.replace("−", "-").replace("≥", ">=").replace("≤", "<=").replace("→", "->").replace("≈", "~")
    return s


# ---- Estilos ------------------------------------------------------------------------


def _styles() -> dict[str, ParagraphStyle]:
    f = _fonts()
    base = ParagraphStyle("base", fontName=f["Body"], fontSize=9.6, leading=13.6, textColor=INK, alignment=TA_LEFT)
    return {
        "body": base,
        "small": ParagraphStyle("small", parent=base, fontSize=8.4, leading=11.6, textColor=INK2),
        "tiny": ParagraphStyle("tiny", parent=base, fontSize=7.4, leading=10, textColor=INK3),
        "h1": ParagraphStyle("h1", parent=base, fontName=f["Display"], fontSize=26, leading=30, textColor=INK, spaceAfter=4),
        "h2": ParagraphStyle("h2", parent=base, fontName=f["Display"], fontSize=16, leading=20, textColor=INK, spaceBefore=6, spaceAfter=4),
        "h3": ParagraphStyle("h3", parent=base, fontName=f["Body-Bold"], fontSize=10.6, leading=14, textColor=INK, spaceBefore=4, spaceAfter=2),
        "overline": ParagraphStyle("overline", parent=base, fontName=f["Body-Bold"], fontSize=7.6, leading=10, textColor=BLUE_INK),
        "lead": ParagraphStyle("lead", parent=base, fontSize=11, leading=15.5, textColor=INK2),
        "big": ParagraphStyle("big", parent=base, fontName=f["Display"], fontSize=30, leading=34, textColor=BLUE_INK),
        "mid": ParagraphStyle("mid", parent=base, fontName=f["Display"], fontSize=20, leading=34, textColor=BLUE_INK),
        "bigunit": ParagraphStyle("bigunit", parent=base, fontName=f["Body-Semi"], fontSize=9, leading=12, textColor=BLUE_INK),
        "cell": ParagraphStyle("cell", parent=base, fontSize=8.6, leading=11.4),
        "cellb": ParagraphStyle("cellb", parent=base, fontName=f["Body-Bold"], fontSize=8.6, leading=11.4),
        "cellsm": ParagraphStyle("cellsm", parent=base, fontSize=7.6, leading=10, textColor=INK2),
        "disc": ParagraphStyle("disc", parent=base, fontName=f["Body-Semi"], fontSize=9.4, leading=13, textColor=BLUE_INK),
        "foot": ParagraphStyle("foot", parent=base, fontSize=6.9, leading=9, textColor=INK3),
    }


def _pill(texto: str, tono: str) -> Table:
    """Chip de estado: en rango (verde) / borde, atención (ámbar) / neutro (gris)."""
    f = _fonts()
    bg, fg = {
        "good": (GREEN_SOFT, GREEN_INK),
        "watch": (AMBER_SOFT, AMBER_INK),
        "brand": (BLUE_SOFT, BLUE_INK),
    }.get(tono, (SURFACE2, INK2))
    p = Paragraph(_t(texto), ParagraphStyle("pill", fontName=f["Body-Bold"], fontSize=7.4, leading=9, textColor=fg))
    t = Table([[p]], colWidths=[None], rowHeights=[12])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ("ROUNDEDCORNERS", [6, 6, 6, 6]),
    ]))
    return t


def _tono_estado(estado: str) -> tuple[str, str]:
    return {
        "en_rango": ("en rango", "good"),
        "borde": ("en el borde", "watch"),
        "fuera": ("fuera del rango", "watch"),
        "inferido": ("inferido", "neutral"),
        "sin_rango": ("sin rango", "neutral"),
    }.get(estado, (estado, "neutral"))


def _tono_nivel(nivel: str) -> str:
    return {"optimo": "good", "a_vigilar": "watch", "atencion": "watch"}.get(nivel, "neutral")


def _card(flowables: list, bg=colors.white, border=LINE, pad: float = 9) -> Table:
    t = Table([[flowables]], colWidths=["100%"])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("BOX", (0, 0), (-1, -1), 0.6, border),
        ("LEFTPADDING", (0, 0), (-1, -1), pad), ("RIGHTPADDING", (0, 0), (-1, -1), pad),
        ("TOPPADDING", (0, 0), (-1, -1), pad), ("BOTTOMPADDING", (0, 0), (-1, -1), pad),
        ("ROUNDEDCORNERS", [8, 8, 8, 8]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    return t


def _stat(etiqueta: str, valor: str, unidad: str, st: Mapping[str, ParagraphStyle], *, mid: bool = False) -> list:
    return [Paragraph(_t(etiqueta), st["overline"]), Paragraph(_t(valor), st["mid" if mid else "big"]), Paragraph(_t(unidad), st["bigunit"])]


def _tabla(filas: Sequence[Sequence[Any]], anchos: Sequence[float], header: bool = True, zebra: bool = True) -> Table:
    t = Table(filas, colWidths=list(anchos), repeatRows=1 if header else 0)
    estilo = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
    ]
    if header:
        estilo += [("BACKGROUND", (0, 0), (-1, 0), SURFACE2), ("LINEBELOW", (0, 0), (-1, 0), 0.8, BLUE)]
    if zebra:
        for i in range(1 if header else 0, len(filas)):
            if i % 2 == 0:
                estilo.append(("BACKGROUND", (0, i), (-1, i), BG))
    t.setStyle(TableStyle(estilo))
    return t


# ---- Abanico ---------------------------------------------------------------------------


def _fan_chart(curva: Mapping[str, Sequence[float]], mejora: Mapping[str, Any] | None, edad0: int, width: float, height: float = 150) -> Drawing:
    """Banda P10–P90 + mediana de la línea base, y la mediana del mejor
    escenario si lo hay (línea verde). Mismo lenguaje visual que el FanChart
    de la app."""
    f = _fonts()
    anios = list(curva["anios"])
    p10, p50, p90 = list(curva["p10"]), list(curva["mediana"]), list(curva["p90"])
    lo = min(p10) - 1
    hi = max(p90) + 1
    if mejora and mejora.get("al_horizonte"):
        lo = min(lo, mejora["al_horizonte"]["p10"] - 1)
    ml, mr, mt, mb = 30, 8, 8, 18
    W = width - ml - mr
    H = height - mt - mb
    d = Drawing(width, height)
    d.add(Rect(0, 0, width, height, fillColor=colors.white, strokeColor=None))

    def X(t: float) -> float:
        return ml + W * (t - anios[0]) / max(1, anios[-1] - anios[0])

    def Y(v: float) -> float:
        return mb + H * (v - lo) / max(1e-6, hi - lo)

    # Rejilla suave y ejes
    ticks = 4
    for i in range(ticks + 1):
        v = lo + (hi - lo) * i / ticks
        d.add(Line(ml, Y(v), width - mr, Y(v), strokeColor=LINE, strokeWidth=0.4))
        d.add(String(ml - 4, Y(v) - 3, fmt(v, 0), fontName=f["Body"], fontSize=6.5, fillColor=INK3, textAnchor="end"))
    for t in anios:
        if t % 2 == 0:
            d.add(String(X(t), mb - 10, f"+{t}" if t else "hoy", fontName=f["Body"], fontSize=6.5, fillColor=INK3, textAnchor="middle"))
    # Banda
    pts = []
    for t, v in zip(anios, p90):
        pts += [X(t), Y(v)]
    for t, v in zip(reversed(anios), reversed(p10)):
        pts += [X(t), Y(v)]
    d.add(Polygon(pts, fillColor=BLUE_SOFT, strokeColor=None, fillOpacity=0.9))
    # Línea de edad cronológica (referencia: 1 año por año)
    d.add(PolyLine([X(anios[0]), Y(edad0), X(anios[-1]), Y(edad0 + anios[-1])], strokeColor=INK3, strokeWidth=0.6, strokeDashArray=[2, 2]))
    # Mediana base
    med = []
    for t, v in zip(anios, p50):
        med += [X(t), Y(v)]
    d.add(PolyLine(med, strokeColor=BLUE_INK, strokeWidth=1.8))
    # Mejor escenario: línea recta entre hoy y su mediana al horizonte (solo tenemos el punto final aquí).
    if mejora and mejora.get("al_horizonte"):
        d.add(PolyLine([X(anios[0]), Y(p50[0]), X(anios[-1]), Y(mejora["al_horizonte"]["mediana"])], strokeColor=GREEN, strokeWidth=1.6, strokeDashArray=[4, 2]))
        d.add(String(width - mr, Y(mejora["al_horizonte"]["mediana"]) + 3, "si mejoras", fontName=f["Body"], fontSize=6.5, fillColor=GREEN_INK, textAnchor="end"))
    d.add(String(width - mr, Y(p50[-1]) - 8, "si sigues igual", fontName=f["Body"], fontSize=6.5, fillColor=BLUE_INK, textAnchor="end"))
    d.add(String(ml + 3, mt + H - 8, "edad biológica (años) · banda P10–P90", fontName=f["Body"], fontSize=6.5, fillColor=INK3))
    return d


# ---- Plantilla de página ------------------------------------------------------------------


class _NumberedCanvas(rl_canvas.Canvas):
    """"Página X de Y" en el pie: se guardan las páginas y se escribe el total al final."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved: list[dict] = []

    def showPage(self):
        self._saved.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._saved)
        for state in self._saved:
            self.__dict__.update(state)
            self._draw_page_number(total)
            super().showPage()
        super().save()

    def _draw_page_number(self, total: int) -> None:
        f = _fonts()
        self.setFont(f["Body"], 7)
        self.setFillColor(INK3)
        self.drawRightString(A4[0] - 16 * mm, 9 * mm, f"Página {self._pageNumber} de {total}")


def _on_page_factory(rep: Mapping[str, Any]):
    f = _fonts()
    meta = rep["meta"]
    persona = rep["persona"]
    fecha = _fecha_humana(meta["generado_en"])
    fuentes = " · ".join(s.split(" (")[0].split(". ")[0] for s in meta["fuentes"][:2])

    def on_page(c: rl_canvas.Canvas, doc) -> None:
        w, h = A4
        # Encabezado
        c.setFillColor(BLUE_INK)
        c.setFont(f["Display"], 9)
        c.drawString(16 * mm, h - 11 * mm, "Moirai · Reporte de salud orientativo")
        c.setFillColor(INK3)
        c.setFont(f["Body"], 7.5)
        quien = persona.get("nombre") or "—"
        c.drawRightString(w - 16 * mm, h - 11 * mm, f"{quien} · {fecha} · {meta['id']}")
        c.setStrokeColor(LINE)
        c.setLineWidth(0.5)
        c.line(16 * mm, h - 13 * mm, w - 16 * mm, h - 13 * mm)
        # Pie
        c.line(16 * mm, 17 * mm, w - 16 * mm, 17 * mm)
        c.setFillColor(INK3)
        c.setFont(f["Body-Semi"], 6.9)
        c.drawString(16 * mm, 13.2 * mm, "Documento orientativo, no diagnóstico. Compártelo con tu médico. No reemplaza una consulta.")
        c.setFont(f["Body"], 6.6)
        c.drawString(16 * mm, 9 * mm, f"{meta['privacidad']}  Fuentes: {fuentes}.")

    return on_page


def _fecha_humana(iso: str) -> str:
    meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    try:
        d = datetime.fromisoformat(iso)
        return f"{d.day} de {meses[d.month - 1]} de {d.year}"
    except Exception:
        return iso[:10]


# ---- Secciones -----------------------------------------------------------------------------


def _portada(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    meta, persona = rep["meta"], rep["persona"]
    quien = persona.get("nombre") or "Reporte sin nombre"
    out: list = [
        Spacer(1, 4),
        Paragraph(_t("REPORTE DE SALUD ORIENTATIVO"), st["overline"]),
        Paragraph(_t(quien), st["h1"]),
        Paragraph(_t(f"{_fecha_humana(meta['generado_en'])} · ID {meta['id']} · motor {meta['version_motor'] or '—'} · semilla {meta['semilla']} · {fmt(meta['trayectorias_por_escenario'], 0)} futuros por escenario"), st["small"]),
        Spacer(1, 10),
        _card([Paragraph(_t(meta["disclaimer"]), st["disc"])], bg=BLUE_SOFT, border=BLUE_SOFT, pad=11),
        Spacer(1, 12),
        Paragraph(_t(rep["resumen"]), st["lead"]),
        Spacer(1, 10),
        Paragraph(_t("Qué hay adentro"), st["h3"]),
        *[Paragraph(_t(x), st["body"]) for x in (
            "1 · Tu foto de hoy — edad biológica estimada con su rango, y cada biomarcador con su rango de referencia.",
            "2 · Los ejes de tu sistema — inflamación, metabólico, renal/hepático, hematológico, cardio-metabólico.",
            "3 · Tus futuros posibles — la banda P10–P90 a 10 años y los escenarios, pareados.",
            "4 · Qué puedes hacer — las palancas que más mueven tu futuro por unidad de esfuerzo, con su respaldo.",
            "5 · Con quién consultar — qué tipo de profesional, para que lo evalúe.",
            "6 · Qué datos ayudarían a afinar — lo que no está medido y cuánto angostaría el rango.",
        )],
        Spacer(1, 10),
        Paragraph(_t("Cómo leerlo: ningún número va sin su rango. Los rangos son anchos a propósito: reflejan lo que no sé de ti. Estimación, no diagnóstico."), st["small"]),
    ]
    return out


def _seccion_1(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    foto = rep["foto_hoy"]
    r = foto["rango_hoy"]
    rango_hoy = f"{fmt(r['p10'])}–{fmt(r['p90'])}" if abs(r["p90"] - r["p10"]) > 0.05 else "sin banda"
    stats = Table(
        [[
            _stat("Edad biológica estimada", fmt(foto["edad_biologica"]), "años · PhenoAge (Levine 2018)", st),
            _stat("Tu edad", str(foto["edad_cronologica"]), "años", st),
            _stat("Rango de hoy", rango_hoy, "P10–P90 por lo no medido", st, mid=True),
            _stat("Percentil", fmt(foto["percentil_poblacional"], 0), "frente a tu edad y sexo (50 = promedio)", st),
        ]],
        colWidths=[ancho * 0.3, ancho * 0.17, ancho * 0.25, ancho * 0.28],
    )
    stats.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 2)]))
    filas: list[list[Any]] = [[
        Paragraph(_t("Biomarcador"), st["cellb"]), Paragraph(_t("Valor"), st["cellb"]), Paragraph(_t("Rango de referencia"), st["cellb"]),
        Paragraph(_t("Estado"), st["cellb"]), Paragraph(_t("Dato"), st["cellb"]), Paragraph(_t("Aporte hoy"), st["cellb"]),
    ]]
    notas: list[str] = []
    for b in foto["biomarcadores"]:
        texto, tono = _tono_estado(b["estado"])
        if b["estado"] in ("borde", "fuera") and b.get("lado"):
            texto += f" ({b['lado']})"
        aporte = fmt_delta(b["contribucion_anios"]) + " años" if b["estado"] != "inferido" and abs(b["contribucion_anios"]) >= 0.05 else "—"
        filas.append([
            Paragraph(_t(b["etiqueta"]), st["cell"]),
            Paragraph(_t(f"{fmt(b['valor'], 2 if b['valor'] < 10 else 1)} {b['unidad']}"), st["cell"]),
            Paragraph(_t(b["rango_referencia"] or "—"), st["cellsm"]),
            _pill(texto, tono),
            Paragraph(_t(b["fuente"]), st["cellsm"]),
            Paragraph(_t(aporte), st["cell"]),
        ])
        if b.get("nota"):
            notas.append(f"{b['etiqueta']}: {b['nota']}")
    tabla = _tabla(filas, [ancho * 0.30, ancho * 0.14, ancho * 0.20, ancho * 0.13, ancho * 0.11, ancho * 0.12])
    out: list = [
        Paragraph(_t("1 · Tu foto de hoy"), st["h2"]),
        Paragraph(_t(foto["lectura"]), st["body"]),
        Spacer(1, 8),
        stats,
        Spacer(1, 8),
        tabla,
        Spacer(1, 5),
        Paragraph(_t(f"Dato: documento = leído de un examen · reportado = lo escribiste · calculado = derivado (p. ej. IMC) · inferido = no medido, imputado con la mediana de tu edad y sexo ({foto['n_inferidos']} de 9). Aporte hoy: años que ese valor medido suma (+) o resta (−) a tu edad biológica frente a la referencia."), st["tiny"]),
    ]
    for n in notas:
        out.append(Paragraph(_t(n), st["small"]))
    out += [Spacer(1, 4), Paragraph(_t(foto["nota_poblacional"]), st["small"])]
    return out


def _seccion_2(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    out: list = [
        Paragraph(_t("2 · Los ejes de tu sistema"), st["h2"]),
        Paragraph(_t("Agrupo tus biomarcadores en cinco ejes y a cada uno le doy un nivel con una regla simple: atención si algún valor medido está fuera de su rango de referencia, a vigilar si alguno está en el borde, en rango si todos los medidos lo están. Los inferidos no cuentan: no son datos tuyos. Un eje marcado no es un diagnóstico — es dónde mirar."), st["body"]),
        Spacer(1, 6),
    ]
    ancho_in = ancho - 2 * 8 - 2
    for e in rep["ejes"]:
        partes = ", ".join(f"{b['etiqueta']}" + ("" if b["medido"] else " (inferido)") for b in e["biomarcadores"])
        fila = Table(
            [[Paragraph(_t(e["nombre"]), st["h3"]), _pill(e["nivel_texto"], _tono_nivel(e["nivel"]))],
             [Paragraph(_t(e["explicacion"]), st["body"]), ""],
             [Paragraph(_t(f"Biomarcadores: {partes}."), st["tiny"]), ""]],
            colWidths=[ancho_in * 0.80, ancho_in * 0.20],
        )
        fila.setStyle(TableStyle([
            ("SPAN", (0, 1), (1, 1)), ("SPAN", (0, 2), (1, 2)),
            ("VALIGN", (0, 0), (-1, -1), "TOP"), ("ALIGN", (1, 0), (1, 0), "RIGHT"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ("TOPPADDING", (0, 0), (-1, -1), 1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ]))
        out += [KeepTogether([_card([fila], pad=8)]), Spacer(1, 5)]
    return out


def _seccion_3(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    fu = rep["futuros"]
    H = fu["horizonte_anios"]
    out: list = [
        Paragraph(_t(f"3 · Tus futuros posibles (a {H} años)"), st["h2"]),
        Paragraph(_t(f"Simulé {fmt(rep['meta']['trayectorias_por_escenario'], 0)} versiones de tu próxima década por escenario, con la variabilidad biológica año a año y, si algo no está medido, con la dispersión poblacional de ese dato. La banda es el 80 % central de esos futuros (P10–P90)."), st["body"]),
        Spacer(1, 6),
        _fan_chart(fu["curva_base"], fu.get("si_mejoras"), rep["foto_hoy"]["edad_cronologica"], ancho),
        Paragraph(_t("Línea punteada gris: un año por año (edad cronológica). Banda azul: línea base con tus hábitos de hoy. Línea verde: el mejor escenario para ti."), st["tiny"]),
        Spacer(1, 8),
    ]
    tarjetas = []
    for clave, tono in (("sigues_igual", "brand"), ("si_mejoras", "good"), ("si_te_descuidas", "neutral")):
        e = fu.get(clave)
        if not e:
            continue
        ah = e["al_horizonte"]
        bg = {"brand": BLUE_SOFT, "good": GREEN_SOFT}.get(tono, SURFACE2)
        tarjetas.append(_card([
            Paragraph(_t(e["titulo"].upper()), st["overline"]),
            Paragraph(_t(f"{fmt(ah['mediana'])}"), st["big"]),
            Paragraph(_t(f"entre {fmt(ah['p10'])} y {fmt(ah['p90'])}"), st["bigunit"]),
            Spacer(1, 4),
            Paragraph(_t(e["texto"]), st["small"]),
        ], bg=bg, border=bg, pad=8))
    if tarjetas:
        t = Table([tarjetas], colWidths=[ancho / len(tarjetas)] * len(tarjetas))
        t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 2), ("RIGHTPADDING", (0, 0), (-1, -1), 2)]))
        out += [t, Spacer(1, 8)]
    if fu["ranking"]:
        filas: list[list[Any]] = [[Paragraph(_t("Escenario (1 a 3 palancas)"), st["cellb"]), Paragraph(_t("Años ganados"), st["cellb"]), Paragraph(_t("Rango"), st["cellb"]), Paragraph(_t("Futuros que mejoran"), st["cellb"]), Paragraph(_t("Esfuerzo"), st["cellb"])]]
        for r in fu["ranking"][:10]:
            filas.append([
                Paragraph(_t(r["nombre"]), st["cell"]),
                Paragraph(_t(fmt_delta(r["anios_ganados"])), st["cellb"]),
                Paragraph(_t(f"{fmt_delta(r['anios_ganados_p10'])} a {fmt_delta(r['anios_ganados_p90'])}"), st["cell"]),
                Paragraph(_t(f"{fmt(r['pct_futuros_que_mejoran'], 0)} %"), st["cell"]),
                Paragraph(_t(f"{r['esfuerzo']} / 10"), st["cell"]),
            ])
        out += [
            Paragraph(_t("Ranking por años ganados"), st["h3"]),
            _tabla(filas, [ancho * 0.46, ancho * 0.13, ancho * 0.17, ancho * 0.14, ancho * 0.10]),
            Spacer(1, 4),
            Paragraph(_t("Cada fila es la misma vida con y sin esas palancas (futuros pareados). Esfuerzo: costo percibido 1–10 sumado por palanca. La fuente de literatura de cada palanca está en la sección 4."), st["tiny"]),
        ]
    out += [Spacer(1, 4), Paragraph(_t(fu["nota_incertidumbre"]), st["small"])]
    return out


def _seccion_4(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    out: list = [
        Paragraph(_t("4 · Qué puedes hacer"), st["h2"]),
        Paragraph(_t("Las palancas que más mueven tu distribución por unidad de esfuerzo, calculadas para ti (solo las que aplican a tus hábitos registrados). Son hábitos, no tratamientos; el profesional que te acompaña decide cómo encajan en tu caso."), st["body"]),
        Spacer(1, 6),
    ]
    if not rep["recomendaciones"]:
        out.append(_card([Paragraph(_t("Con tus hábitos de hoy no encuentro ninguna palanca con brecha abierta: seguir como vas es la recomendación. Si algo cambia, vuelve a simular."), st["body"])], bg=GREEN_SOFT, border=GREEN_SOFT))
        return out
    ancho_in = ancho - 2 * 9 - 2
    for i, rec in enumerate(rep["recomendaciones"], start=1):
        ev = [Paragraph(_m(f"• {_t(e['hallazgo'])} <font color='#8C97A0'>— {_t(e['fuente'])}</font>"), st["small"]) for e in rec["evidencia"]]
        cab = Table(
            [[Paragraph(_t(f"{i}. {rec['nombre']}"), st["h3"]),
              Paragraph(_t(f"{fmt_delta(rec['anios_ganados'])} años"), ParagraphStyle("g", parent=st["h3"], textColor=GREEN_INK, alignment=2))],
             [Paragraph(_t(rec["que_hacer"]), st["body"]),
              Paragraph(_t(f"entre {fmt_delta(rec['rango_ganados'][0])} y {fmt_delta(rec['rango_ganados'][1])} · {fmt(rec['pct_futuros_que_mejoran'], 0)} % de futuros · esfuerzo {rec['esfuerzo']}/10"), ParagraphStyle("g2", parent=st["tiny"], alignment=2))]],
            colWidths=[ancho_in * 0.62, ancho_in * 0.38],
        )
        cab.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 1)]))
        cuerpo = [
            cab,
            Spacer(1, 4),
            Paragraph(_t(rec["por_que"]), st["small"]),
            Spacer(1, 3),
            Paragraph(_t("Respaldo en la literatura"), st["overline"]),
            *ev,
        ]
        if rec.get("brecha") is not None and rec["brecha"] < 1.0:
            cuerpo.append(Paragraph(_t(f"Tu hábito de {rec['habito']} ya está a medio camino (brecha {fmt(rec['brecha'], 1)} de 1): el efecto que calculé es proporcional a lo que te falta."), st["tiny"]))
        out += [KeepTogether([_card(cuerpo, pad=9)]), Spacer(1, 6)]
    return out


def _seccion_5(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    c = rep["consulta"]
    out: list = [
        Paragraph(_t("5 · Con quién consultar"), st["h2"]),
        _card([Paragraph(_t(c["disclaimer"]), st["disc"])], bg=BLUE_SOFT, border=BLUE_SOFT, pad=9),
        Spacer(1, 6),
    ]
    ancho_in = ancho - 2 * 8 - 2
    for s in c["sugerencias"]:
        tono = _tono_nivel(s["nivel"])
        fila = Table(
            [[Paragraph(_t(s["nombre"]), st["h3"]), _pill({"optimo": "en rango", "a_vigilar": "a vigilar", "atencion": "atención"}.get(s["nivel"], s["nivel"]), tono)],
             [Paragraph(_m(f"Tipo de profesional: <b>{_t(s['profesional'])}</b>"), st["small"]), ""],
             [Paragraph(_t(s["texto"]), st["body"]), ""]],
            colWidths=[ancho_in * 0.80, ancho_in * 0.20],
        )
        fila.setStyle(TableStyle([
            ("SPAN", (0, 1), (1, 1)), ("SPAN", (0, 2), (1, 2)), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("ALIGN", (1, 0), (1, 0), "RIGHT"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ]))
        out += [KeepTogether([_card([fila], pad=8)]), Spacer(1, 5)]
    out.append(Paragraph(_t(c["lleva_esto"]), st["body"]))
    return out


def _seccion_6(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    a = rep["afinar"]
    out: list = [
        Paragraph(_t("6 · Qué datos ayudarían a afinar"), st["h2"]),
        Paragraph(_t(a["nota"]), st["body"]),
        Spacer(1, 6),
    ]
    if a["faltantes"]:
        filas: list[list[Any]] = [[Paragraph(_t("Biomarcador no medido"), st["cellb"]), Paragraph(_t("Cuánto angosta la banda a 10 años"), st["cellb"]), Paragraph(_t("Parte de lo que falta"), st["cellb"])]]
        for f_ in a["faltantes"]:
            filas.append([
                Paragraph(_t(f_["etiqueta"]), st["cell"]),
                Paragraph(_t(f"−{fmt(f_['reduccion_banda_anios'])} años" if f_.get("reduccion_banda_anios") is not None else "—"), st["cellb"]),
                Paragraph(_t(f"{fmt((f_.get('fraccion') or 0) * 100, 0)} %" if f_.get("fraccion") is not None else "—"), st["cell"]),
            ])
        out += [_tabla(filas, [ancho * 0.5, ancho * 0.3, ancho * 0.2]), Spacer(1, 4)]
    out.append(Paragraph(_t("Medir esto no cambia tu salud: cambia lo que sé de ti, y por eso angosta el rango. Pídelo en tu próximo examen de sangre de rutina."), st["small"]))
    return out


# ---- Resumen de 1 página ---------------------------------------------------------------------------


def _resumen(rep: Mapping[str, Any], st: Mapping[str, ParagraphStyle], ancho: float) -> list:
    meta, persona, foto = rep["meta"], rep["persona"], rep["foto_hoy"]
    r = foto["rango_hoy"]
    rango_hoy = f"{fmt(r['p10'])}–{fmt(r['p90'])}" if abs(r["p90"] - r["p10"]) > 0.05 else "sin banda"
    out: list = [
        Paragraph(_t("RESUMEN PARA LA CONSULTA · 1 PÁGINA"), st["overline"]),
        Paragraph(_t(persona.get("nombre") or "Reporte sin nombre"), st["h1"]),
        Paragraph(_t(f"{_fecha_humana(meta['generado_en'])} · ID {meta['id']} · {fmt(meta['trayectorias_por_escenario'], 0)} futuros por escenario · semilla {meta['semilla']}"), st["small"]),
        Spacer(1, 6),
        _card([Paragraph(_t(meta["disclaimer"]), st["disc"])], bg=BLUE_SOFT, border=BLUE_SOFT, pad=8),
        Spacer(1, 8),
        Paragraph(_t(rep["resumen"]), st["lead"]),
        Spacer(1, 8),
    ]
    stats = Table(
        [[
            _stat("Edad biológica estimada", fmt(foto["edad_biologica"]), "años · PhenoAge", st),
            _stat("Tu edad", str(foto["edad_cronologica"]), "años", st),
            _stat("Rango de hoy", rango_hoy, "P10–P90 por lo no medido", st, mid=True),
            _stat("Percentil", fmt(foto["percentil_poblacional"], 0), "de tu edad y sexo", st),
        ]],
        colWidths=[ancho * 0.3, ancho * 0.17, ancho * 0.25, ancho * 0.28],
    )
    stats.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 2)]))
    out += [stats, Spacer(1, 8)]

    # Lo que está fuera/borde + ejes marcados
    marcados = [b for b in foto["biomarcadores"] if b["estado"] in ("borde", "fuera")]
    ejes_marcados = [e for e in rep["ejes"] if e["nivel"] in ("a_vigilar", "atencion")]
    out.append(Paragraph(_t("Lo que observé"), st["h3"]))
    if marcados:
        filas: list[list[Any]] = [[Paragraph(_t("Biomarcador"), st["cellb"]), Paragraph(_t("Valor"), st["cellb"]), Paragraph(_t("Rango de referencia"), st["cellb"]), Paragraph(_t("Estado"), st["cellb"])]]
        for b in marcados:
            texto, tono = _tono_estado(b["estado"])
            filas.append([Paragraph(_t(b["etiqueta"]), st["cell"]), Paragraph(_t(f"{fmt(b['valor'], 2 if b['valor'] < 10 else 1)} {b['unidad']}"), st["cell"]), Paragraph(_t(b["rango_referencia"] or "—"), st["cellsm"]), _pill(f"{texto} ({b['lado']})" if b.get("lado") else texto, tono)])
        out += [_tabla(filas, [ancho * 0.38, ancho * 0.2, ancho * 0.24, ancho * 0.18]), Spacer(1, 4)]
    else:
        out.append(Paragraph(_t(f"Los {foto['n_medidos']} biomarcadores medidos están dentro de sus rangos de referencia." if foto["n_medidos"] else "No hay biomarcadores medidos: todo está imputado con medianas poblacionales."), st["body"]))
    if ejes_marcados:
        out.append(Paragraph(_t("Ejes: " + " · ".join(f"{e['nombre']} ({e['nivel_texto']})" for e in ejes_marcados)), st["small"]))
    out.append(Spacer(1, 6))

    # Recomendaciones
    out.append(Paragraph(_t("Lo que más mueve tu futuro (a 10 años, por esfuerzo)"), st["h3"]))
    if rep["recomendaciones"]:
        for i, rec in enumerate(rep["recomendaciones"], start=1):
            out.append(Paragraph(_m(f"{i}. <b>{_t(rec['nombre'])}</b> — {fmt_delta(rec['anios_ganados'])} años (entre {fmt_delta(rec['rango_ganados'][0])} y {fmt_delta(rec['rango_ganados'][1])}), mejora en {fmt(rec['pct_futuros_que_mejoran'], 0)} % de los futuros. {_t(rec['que_hacer'])}"), st["body"]))
    else:
        out.append(Paragraph(_t("Con tus hábitos de hoy no encuentro una palanca con brecha abierta: seguir como vas."), st["body"]))
    out.append(Spacer(1, 6))

    # Triage
    c = rep["consulta"]
    out.append(Paragraph(_t("Con quién consultar"), st["h3"]))
    for s in c["sugerencias"]:
        out.append(Paragraph(_m(f"<b>{_t(s['nombre'])}</b> · {_t(s['profesional'])}: {_t(s['texto'])}"), st["small"]))
    out += [Spacer(1, 4), Paragraph(_t(c["disclaimer"]), st["tiny"])]

    # Afinar
    a = rep["afinar"]
    if a["faltantes"]:
        out += [Spacer(1, 6), Paragraph(_t("Qué medir la próxima vez"), st["h3"]), Paragraph(_t(", ".join(f_["etiqueta"] for f_ in a["faltantes"]) + "."), st["small"])]
    return out


# ---- Render ------------------------------------------------------------------------------------------


def render_pdf(rep: Mapping[str, Any], *, resumen: bool = False) -> bytes:
    """Bytes del PDF. `resumen=True` → una sola página para la consulta."""
    st = _styles()
    buf = io.BytesIO()
    margen = 16 * mm
    doc = BaseDocTemplate(
        buf, pagesize=A4, leftMargin=margen, rightMargin=margen, topMargin=18 * mm, bottomMargin=21 * mm,
        title=f"Moirai · Reporte de salud orientativo · {rep['persona'].get('nombre') or ''}".strip(),
        author="Moirai", subject="Documento orientativo, no diagnóstico", creator="Moirai (apps/backend)",
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=_on_page_factory(rep))])
    ancho = doc.width
    if resumen:
        story = _resumen(rep, st, ancho)
    else:
        story = [
            *_portada(rep, st, ancho),
            PageBreak(),
            *_seccion_1(rep, st, ancho),
            PageBreak(),
            *_seccion_2(rep, st, ancho),
            Spacer(1, 10),
            CondPageBreak(120 * mm),
            *_seccion_3(rep, st, ancho),
            Spacer(1, 10),
            CondPageBreak(90 * mm),
            *_seccion_4(rep, st, ancho),
            Spacer(1, 10),
            CondPageBreak(70 * mm),
            *_seccion_5(rep, st, ancho),
            Spacer(1, 12),
            CondPageBreak(60 * mm),
            *_seccion_6(rep, st, ancho),
        ]
    doc.build(story, canvasmaker=_NumberedCanvas)
    return buf.getvalue()


__all__ = ["render_pdf"]
