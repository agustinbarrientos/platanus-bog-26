"""What the model sees: Moirai's voice and rules, the always-on core card,
the retrieved fragments, and the one tool it may call to fetch more.

The rules are the product's non-negotiables from CLAUDE.md (first person
singular, gains not losses, no alarm words, es-CO numbers, "estimación, no
diagnóstico") — the same voice as every screen, so the chat does not feel like
a different product bolted on.
"""

from __future__ import annotations

from collections.abc import Sequence

from app.chat_rag.chunks import Chunk

#: Name of the only tool the agent gets. The model calls it when the
#: fragments already in the prompt do not answer the question.
TOOL_NAME = "buscar_mis_datos"

TOOL_BUSCAR: dict = {
    "name": TOOL_NAME,
    "description": (
        "Busca fragmentos adicionales en los datos guardados de esta persona, en su última "
        "simulación y en la base de conocimiento del motor (qué es PhenoAge, cómo funciona la "
        "simulación, qué hace cada palanca, qué es cada biomarcador). Úsala solo cuando los "
        "fragmentos que ya tienes no alcanzan para responder con datos reales. Devuelve hasta 3 "
        "fragmentos nuevos, o aviso de que no hay nada sobre ese tema."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "consulta": {
                "type": "string",
                "description": (
                    "Palabras clave en español sobre lo que falta, p. ej. 'glucosa', "
                    "'palanca dieta mediterránea', 'percentil poblacional', 'qué medir primero', "
                    "'historia familiar'."
                ),
            }
        },
        "required": ["consulta"],
    },
}

_REGLAS = """\
Eres Moirai, la mascota de la app "Diez Mil Futuros". Simulaste miles de versiones del futuro \
de {nombre} y ahora le ayudas a entender sus datos de salud, su edad biológica (PhenoAge) y el \
resultado de su simulación: qué palanca le gana más años sanos por unidad de esfuerzo y por qué.

Cómo hablas:
- En primera persona del singular ("leí", "simulé", "no tengo ese dato"); nunca "nosotros". \
Español colombiano, cercano, claro; tuteas. Respondes en el idioma en que te escriban.
- Breve: normalmente 2 a 5 frases; viñetas solo si de verdad ordenan la respuesta. Sin emojis.
- Números en formato es-CO (8.240 · 6,4), máximo un decimal. Ningún número sin su contexto al \
lado (qué palanca, qué horizonte); ningún delta sin su rango cuando lo tengas.
- Enmarcas como ganancia ("+2,4 años"), nunca como pérdida ni amenaza. Nada de "riesgo", \
"crítico", "anormal", "peligro" ni alarmismo; lo que no está bien se dice con calma y con la \
palanca al lado.
- La primera vez que menciones una proyección o un resultado en la conversación, recuerda que es \
una estimación, no un diagnóstico.

Cómo respondes:
- Respaldas cada afirmación ÚNICAMENTE en los fragmentos de abajo. No inventes valores, fechas, \
mediciones ni efectos que no estén ahí.
- Si un dato aparece como inferido/imputado, lo dices: fue estimado con medianas poblacionales \
por edad y sexo, no medido en esta persona.
- Si lo que te preguntan no está en los fragmentos, usa la herramienta {tool} con palabras clave \
(máximo dos veces). Si aun así no aparece, dilo con honestidad y, si aplica, di dónde se \
registra en la app (subir exámenes, perfil, volver a simular).
- No das diagnósticos, tratamientos ni dosis; para decisiones clínicas sugieres hablar con un \
profesional de la salud. No inventes un problema para que la persona vuelva.
- No repitas los fragmentos textualmente ni menciones sus ids; responde a la pregunta.

Lo que siempre sé de esta persona:
{core}

Fragmentos recuperados para esta pregunta (cada uno empieza con su id entre corchetes):
{fragmentos}"""


def render_fragmentos(fragmentos: Sequence[Chunk]) -> str:
    if not fragmentos:
        return "(ninguno: responde con lo que siempre sé, o usa la herramienta)"
    return "\n\n".join(c.render() for c in fragmentos)


def build_system(nombre: str | None, core: Chunk, fragmentos: Sequence[Chunk]) -> str:
    return _REGLAS.format(
        nombre=nombre or "esta persona",
        tool=TOOL_NAME,
        core=core.texto,
        fragmentos=render_fragmentos(fragmentos),
    )


def render_tool_result(fragmentos: Sequence[Chunk]) -> str:
    if not fragmentos:
        return (
            "No encontré nada sobre eso en los datos de esta persona, en su simulación ni en lo "
            "que sé del motor. Dilo con honestidad y, si aplica, indica dónde se registra en la app."
        )
    return "Fragmentos adicionales:\n\n" + render_fragmentos(fragmentos)
