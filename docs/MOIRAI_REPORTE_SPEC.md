# MOIRAI — Especificación del Reporte de Salud Descargable
## Output holístico, nivel clínico, responsable — para Claude Code

> **Cómo usar:** dáselo a Claude Code para construir la generación del reporte (PDF descargable).
> El reporte es el "entregable" que el usuario guarda y LLEVA A SU MÉDICO — no lo reemplaza.

---

## 0. PRINCIPIO RECTOR (la línea que no se cruza)
Moirai **orienta, no diagnostica.** El reporte:
- SÍ traduce biomarcadores en una imagen integrada y accionable.
- SÍ sugiere QUÉ TIPO de profesional consultar (triage orientativo).
- SÍ da rangos con incertidumbre explícita.
- NO nombra enfermedades como diagnóstico ("tienes X").
- NO prescribe medicamentos ni dosis.
- NO reemplaza al médico — está diseñado para LLEVARLO al médico.

> Prueba de fuego para cada frase del reporte: ¿un médico la firmaría como "orientación
> responsable", o sonaría a que la app está jugando a ser doctor? Si es lo segundo, reescribir.

---

## 1. QUÉ DEBE CONTENER EL REPORTE (estructura completa)

### Portada
- Nombre de la persona, fecha, ID de sesión.
- Disclaimer prominente arriba: "Documento orientativo, no diagnóstico. Compártelo con tu médico."
- Una línea de resumen humano: "Tu edad biológica estimada es X; esto es lo que más la mueve."

### Sección 1 — Tu foto de hoy
- Edad cronológica vs. edad biológica estimada, con el rango de incertidumbre (no un número seco).
- Los biomarcadores que subiste, con su valor, rango de referencia, y una marca de cuáles están en borde/fuera.
- Nota de fuente de cada dato: medido / reportado / inferido.
- Nota de contexto poblacional: "Rangos de referencia derivados mayormente de poblaciones
  europeas/estadounidenses; para ascendencia mixta pueden subestimar riesgo."

### Sección 2 — Los ejes de tu sistema
- Presenta los ejes sistémicos (inflamación, metabólico, renal/hepático, hematológico,
  cardio-metabólico) con un nivel cualitativo (óptimo / a vigilar / atención).
- Para cada eje elevado: qué biomarcadores lo componen y por qué, en lenguaje humano.
- NADA de nombrar enfermedades. "Tu eje metabólico está a vigilar" — NO "tienes prediabetes".

### Sección 3 — Tus futuros posibles
- La trayectoria de edad biológica a 10 años: mediana + banda P10-P90.
- Los tres escenarios: si sigues igual / si mejoras / si te descuidas.
- Ranking de intervenciones por años ganados, CON su fuente de literatura citada.
- Incertidumbre explícita: "estimación, no certeza; el rango refleja lo que no sabemos."

### Sección 4 — Qué puedes hacer (accionable, no prescriptivo)
- Las 2-3 palancas de mayor impacto PARA ESTA PERSONA (que el motor calcule, no genéricas).
- Formuladas como hábitos, no como tratamientos: "actividad física moderada", no "toma X".
- Cada una con el respaldo: "asociado en la literatura con reducción de inflamación (referencia)."

### Sección 5 — Con quién consultar (triage orientativo, NO diagnóstico)
- Según el eje dominante, sugiere el TIPO de profesional, en lenguaje de orientación:
  - eje metabólico elevado → "valdría la pena una consulta con medicina interna o endocrinología"
  - eje cardio-metabólico → "considera evaluación cardiovascular preventiva"
  - eje inflamatorio persistente → "conviene que un médico investigue la causa"
- SIEMPRE enmarcado como "para que un profesional lo evalúe", nunca como conclusión.
- Incluir: "lleva este reporte a tu consulta; resume lo que Moirai observó."

### Sección 6 — Qué datos ayudarían a afinar (el perfil que crece)
- Lista de biomarcadores que faltaron y que, si se agregan, estrecharían la estimación.
- Esto es honesto (muestra los límites) y útil (guía la próxima analítica).

### Pie de cada página
- Disclaimer persistente + fuentes (PhenoAge/Levine 2018, NHANES, papers de intervención).
- "Datos procesados de forma privada; no constituyen historia clínica."

---

## 2. FORMATO Y ENTREGABLES
- **PDF descargable** como formato principal (portable, imprimible, se lleva al médico).
- Opcional: una versión **resumen de 1 página** (lo esencial para la consulta médica).
- El Excel/hoja NO es ideal para un reporte clínico narrativo — úsalo solo si quieres
  además una tabla de "biomarcador / valor / rango / fuente" que el usuario pueda trackear
  en el tiempo. Si lo haces, que sea complemento del PDF, no el entregable principal.

---

## 3. TONO Y LENGUAJE (nivel clínico responsable)
- Humano y claro, no jerga. "Tu cuerpo muestra señales de inflamación leve" > "hs-CRP elevada".
- Nunca alarmista. Nunca miedo como palanca. Marco de agencia: "esto está en tus manos".
- Cálido pero preciso. Como un buen médico que explica bien y no asusta.
- Cada afirmación fuerte, anclada a evidencia o marcada como estimación.

---

## 4. LO QUE EL REPORTE NUNCA HACE (barreras de seguridad)
- ❌ Nombrar una enfermedad como diagnóstico.
- ❌ Prescribir medicamentos, suplementos específicos o dosis.
- ❌ Prometer resultados ("vas a vivir X años").
- ❌ Predecir enfermedades específicas ("tendrás diabetes").
- ❌ Sustituir consulta médica o dar falsa tranquilidad ("estás bien, no vayas al médico").
- ❌ Afirmar cobertura estadística (ej. "88% de acierto") sin un estudio de validación real detrás.

---

## 5. INSTRUCCIÓN PARA CLAUDE CODE
> Construye la generación de un reporte PDF descargable siguiendo esta spec. Requisitos:
> 1. Todos los números (edad biológica, trayectorias, años ganados, palancas) vienen del
>    MOTOR REAL (health_metrics), NO de valores hardcodeados ni del MockEngine. Si algún
>    dato (ej. SHAP/drivers) todavía es mock, NO lo incluyas en el reporte hasta que sea real,
>    o márcalo explícitamente como ilustrativo.
> 2. El triage de especialidades (Sección 5) es una tabla de reglas simples eje→tipo de
>    profesional, en lenguaje orientativo. No inventes lógica clínica compleja.
> 3. Disclaimer en portada, pie de cada página, y en la sección de triage.
> 4. El reporte debe generarse desde el resultado real de una simulación (el JSON de output
>    del motor), no desde datos de ejemplo.
> 5. Verifica que ninguna frase nombre una enfermedad como diagnóstico ni prescriba nada.
>    Dime si alguna sección te obliga a inventar datos que el motor no produce — esos son
>    gaps a resolver, no a rellenar.
> Dime qué secciones pudiste construir con datos reales del motor y cuáles requieren datos
> que aún no existen.

---

## 6. SOBRE "QUIERO USARLO PARA MÍ Y MI FAMILIA, Y QUE SEA SEGURO"
Esto es lo más importante y lo digo como cofundadora, no como spec:
- Que TÚ quieras usarlo es la mejor señal de producto que existe. Consérvala.
- PERO: si lo vas a usar de verdad para ti y tu familia, trátalo como lo que es —
  una herramienta orientativa, no un médico. Lleva SIEMPRE los resultados a un profesional.
- "Que sea seguro" en salud significa dos cosas: (a) que no dé consejos que dañen —
  por eso todas las barreras de arriba; (b) que proteja los datos — por eso el "se lee una
  vez, no se guarda" que ya tienen es correcto y hay que mantenerlo.
- Un producto de salud en el que confías para tu familia es uno que sabe decir "esto no lo
  sé, ve al médico". Esa humildad ES la seguridad.
