"""La pantalla "Respaldo" de la app Flutter muestra los coeficientes del motor
para que el jurado pueda auditarlos, y los tiene **copiados** en Dart
(`apps/mobile/lib/features/backing/backing_screen.dart`) en vez de pedirlos por
red — a propósito: esa pantalla tiene que abrir sin backend y con
`USE_MOCK_ENGINE`, y un explicador que depende de la red es justo lo que no
quieres en un pitch.

El costo de esa copia es que se desincroniza, y ya pasó: cuando `glucosa` bajó
de 0,5 a 0,29 y los leucocitos de la cesación de tabaco de -0,15 a -0,11, la
app siguió mostrando los viejos durante varios commits. Este test lee el
archivo Dart y falla si algún número deja de coincidir con `interventions.py`.

No valida Dart ni lo compila: solo extrae los literales de las dos tablas.
Si alguien reformatea el archivo y el parseo deja de encontrarlas, el test
falla ruidosamente en vez de pasar en falso.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.health_metrics.interventions import DYNAMICS, SCENARIOS

_BACKING_DART = (
    Path(__file__).resolve().parents[3]
    / "apps"
    / "mobile"
    / "lib"
    / "features"
    / "backing"
    / "backing_screen.dart"
)

#: Escenarios que la pantalla no lista. `ninguna` no es una palanca: su deriva
#: se muestra en la tabla de línea base, no como intervención.
_NO_LISTADOS = {"ninguna"}


def _fuente() -> str:
    if not _BACKING_DART.exists():  # pragma: no cover - solo si mueven el archivo
        pytest.skip(f"no encontré {_BACKING_DART}")
    return _BACKING_DART.read_text(encoding="utf-8")


def _bloque(fuente: str, nombre: str) -> str:
    """El cuerpo `{...}` de un `const <nombre> = <...>{ ... };` de Dart."""
    inicio = fuente.find(f"const {nombre}")
    assert inicio != -1, (
        f"no encontré `const {nombre}` en {_BACKING_DART.name}. Si lo renombraron, "
        f"actualiza este test — no lo borres: es lo único que evita que la "
        f"pantalla Respaldo muestre coeficientes que el motor ya no usa."
    )
    # El literal empieza en el `{` que sigue al `>` del genérico, no en el
    # primero que aparezca: el tipo `({double deriva, double ruido})` trae sus
    # propias llaves y engañaría a una búsqueda ingenua.
    apertura = re.search(r">\s*\{", fuente[inicio:])
    assert apertura is not None, f"no encontré el literal de `const {nombre}`"
    abre = inicio + apertura.end() - 1
    profundidad, i = 0, abre
    while i < len(fuente):
        if fuente[i] == "{":
            profundidad += 1
        elif fuente[i] == "}":
            profundidad -= 1
            if profundidad == 0:
                return fuente[abre : i + 1]
        i += 1
    raise AssertionError(f"llave sin cerrar en `const {nombre}`")  # pragma: no cover


def test_deriva_y_ruido_coinciden_con_dynamics():
    bloque = _bloque(_fuente(), "_dinamicaBackend")
    encontrados = dict(
        (nombre, (float(deriva), float(ruido)))
        for nombre, deriva, ruido in re.findall(
            r"'([a-zA-Z_]+)':\s*\(deriva:\s*(-?[\d.]+),\s*ruido:\s*(-?[\d.]+)\)", bloque
        )
    )

    assert set(encontrados) == set(DYNAMICS), (
        "la tabla de la app y DYNAMICS no cubren los mismos biomarcadores: "
        f"sobran {set(encontrados) - set(DYNAMICS)}, faltan {set(DYNAMICS) - set(encontrados)}"
    )
    for nombre, (deriva, ruido) in encontrados.items():
        esperado = DYNAMICS[nombre]
        assert deriva == pytest.approx(esperado.deriva_anual), (
            f"deriva de {nombre}: la app muestra {deriva}, el motor usa "
            f"{esperado.deriva_anual}. Actualiza `_dinamicaBackend` en "
            f"{_BACKING_DART.name}."
        )
        assert ruido == pytest.approx(esperado.ruido_anual_sd), (
            f"ruido de {nombre}: la app muestra {ruido}, el motor usa "
            f"{esperado.ruido_anual_sd}."
        )


def test_efectos_por_escenario_coinciden_con_scenarios():
    bloque = _bloque(_fuente(), "_efectosBackend")
    encontrados: dict[str, dict[str, float]] = {}
    for escenario, cuerpo in re.findall(r"'([a-zA-Z_0-9]+)':\s*\{([^}]*)\}", bloque):
        encontrados[escenario] = {
            bm: float(valor)
            for bm, valor in re.findall(r"'([a-zA-Z_]+)':\s*(-?[\d.]+)", cuerpo)
        }

    esperados = {k: v for k, v in SCENARIOS.items() if k not in _NO_LISTADOS}
    assert set(encontrados) == set(esperados), (
        "la app y el motor no ofrecen las mismas palancas: "
        f"sobran {set(encontrados) - set(esperados)}, faltan {set(esperados) - set(encontrados)}. "
        "Una palanca que el motor tiene y la app no lista sale en pantalla con "
        "'0 biomarcadores' y el desplegable vacío."
    )
    for escenario, efectos in encontrados.items():
        esperado = esperados[escenario].efectos_anuales
        assert efectos == pytest.approx(esperado), (
            f"efectos de {escenario}: la app muestra {efectos}, el motor usa "
            f"{esperado}. Actualiza `_efectosBackend` en {_BACKING_DART.name}."
        )


def test_la_app_no_inventa_biomarcadores():
    """Cada biomarcador nombrado en la pantalla tiene que ser uno de los 9 de
    PhenoAge — un typo en una llave del mapa Dart pasaría desapercibido si no."""
    fuente = _fuente()
    for nombre in ("_dinamicaBackend", "_efectosBackend"):
        for bm in re.findall(r"'([a-zA-Z_]+)':", _bloque(fuente, nombre)):
            if bm in SCENARIOS or bm in ("deriva", "ruido"):
                continue
            assert bm in DYNAMICS, f"{nombre} nombra `{bm}`, que no es un biomarcador del motor"
