# MOIRAI — Especificación del Motor
## Input · Output · Simulación Monte Carlo — listo para Claude Code

> **Cómo usar:** ábrelo con Claude Code y di:
> *"Lee MOIRAI_ENGINE_SPEC.md. Construye el motor de simulación en Python/FastAPI siguiendo las tres capas y los esquemas JSON. Empieza por la Capa 1, valida con el caso de prueba de la sección 9, y no avances de capa hasta que la anterior pase su test. Prioriza que corra sobre que sea completo."*

---

## 0. OBJETIVO EN UNA FRASE
Tomar los biomarcadores y hábitos de una persona, medir su edad biológica hoy, y **simular miles de trayectorias de su salud futura a 10 años** bajo distintas decisiones — devolviendo UNA recomendación protagonista: *qué decisión gana más años de salud por unidad de esfuerzo, y por qué.*

---

## 1. DECISIÓN DE ALCANCE (leer antes de codear)

**Output protagonista (lo que el demo genera en vivo):**
> La trayectoria de edad biológica a 10 años + la mejor decisión, con su explicación.

**Outputs "Fase 2" (se narran en el pitch, NO se construyen):**
- Foto envejecida del rostro real → reemplazado por avatar abstracto que envejece.
- Alimentación personalizada detallada.
- Suplementos específicos.
- Propensión a alergias.
- Integración de prueba genética / ancestría.

> Del boceto original había ~4 outputs. En 36h eso son 4 cosas a medias. Podamos a UNO impecable. Los demás son roadmap — valiosos como visión, fatales como build.

**Biomarcadores del demo:** los 9 de PhenoAge si el tiempo alcanza; el núcleo mínimo si no: **albúmina, creatinina, glucosa, hs-CRP, RDW, recuento de leucocitos** + edad. Los faltantes se imputan de medianas NHANES (marcados como inferidos).

---

## 2. ARQUITECTURA DE TRES CAPAS (el modelo mental)

```
INPUT (biomarcadores + hábitos)
        │
        ▼
┌─────────────────────────────────────────────┐
│ CAPA 1 — MEDIDOR (PhenoAge)                  │
│ estado actual → edad biológica HOY           │
│ Fórmula con pesos publicados. Determinista.  │
│ NO predice — mide el presente.               │
└─────────────────┬───────────────────────────┘
                  ▼
┌─────────────────────────────────────────────┐
│ CAPA 2 — MOTOR DE EVOLUCIÓN (dinámica)       │
│ estado(t) + hábitos → estado(t+1)            │
│ Regla de deriva anual por biomarcador.       │
│ ESTO es lo que proyecta al futuro.           │
└─────────────────┬───────────────────────────┘
                  ▼
┌─────────────────────────────────────────────┐
│ CAPA 3 — MONTE CARLO (incertidumbre)         │
│ corre la Capa 2 N=10000 veces con ruido      │
│ → abanico de futuros: mediana, P10, P90      │
│ ESTO da honestidad + el wow visual.          │
└─────────────────┬───────────────────────────┘
                  ▼
        SHAP → explica qué variable domina
                  ▼
OUTPUT protagonista (trayectoria + decisión + porqué)
```

**La confusión que esto resuelve:** una fórmula de pesos (PhenoAge) NO predice el futuro — mide el presente. La predicción vive en la Capa 2 (dinámica temporal). Monte Carlo (Capa 3) solo le añade incertidumbre. Son tres piezas apiladas, no una.

---

## 3. ESQUEMA DE INPUT (del boceto, formalizado)

```json
{
  "demografia": {
    "edad": 34,
    "sexo_biologico": "F",
    "peso_kg": 62,
    "nacionalidad": "CO",
    "ancestria_reportada": "mixta_latam"
  },
  "objetivos": ["energia", "prevencion", "longevidad"],
  "historial_familiar": ["diabetes_t2", "cardiovascular"],
  "biomarcadores": [
    { "nombre": "albumina",   "valor": 4.4, "unidad": "g/dL",  "fecha": "2026-07", "fuente": "documento" },
    { "nombre": "creatinina", "valor": 0.8, "unidad": "mg/dL", "fecha": "2026-07", "fuente": "documento" },
    { "nombre": "glucosa",    "valor": 92,  "unidad": "mg/dL", "fecha": "2026-07", "fuente": "documento" },
    { "nombre": "hs_CRP",     "valor": 2.1, "unidad": "mg/L",  "fecha": "2026-07", "fuente": "documento" },
    { "nombre": "rdw",        "valor": 13.1,"unidad": "%",     "fecha": "2026-07", "fuente": "documento" },
    { "nombre": "leucocitos", "valor": 6.2, "unidad": "10^3/uL","fecha": "2026-07","fuente": "documento" }
  ],
  "habitos_moduladores": {
    "sueno_h": 6,
    "sueno_calidad": "media",
    "ejercicio": "bajo",
    "alcohol": "moderado",
    "alimentacion": "media",
    "tabaco": false,
    "estres": "alto"
  },
  "opcionales": {
    "suplementos": [],
    "prueba_genetica": null,
    "foto": null
  },
  "datos_faltantes": ["fosfatasa_alcalina", "linfocitos_pct", "vcm"],
  "notas_incertidumbre": "3 biomarcadores imputados de medianas NHANES por edad/sexo"
}
```

---

## 4. CAPA 1 — MEDIDOR (PhenoAge)

### Qué hace
Colapsa el estado de biomarcadores en un número: edad fenotípica (biológica).

### Fórmula (PhenoAge, Levine et al. 2018)
Los 9 predictores + edad cronológica, con sus coeficientes publicados:
albúmina, creatinina, glucosa, log(hs-CRP), recuento de linfocitos %, volumen corpuscular medio, RDW, fosfatasa alcalina, recuento de leucocitos, edad.

```python
import numpy as np

# Coeficientes PhenoAge (Levine 2018). Unidades canónicas del paper.
# NOTA: verificar unidades exactas al implementar — el paper usa
# albúmina g/L, creatinina umol/L, glucosa mmol/L, CRP en ln(mg/dL).
# Normaliza TODAS las unidades de entrada antes de aplicar.

def phenoage(bm: dict, edad: float) -> float:
    """
    bm: biomarcadores ya normalizados a unidades del paper.
    Devuelve edad fenotípica en años.
    """
    xb = (
        -19.907
        - 0.0336 * bm["albumina"]
        + 0.0095 * bm["creatinina"]
        + 0.1953 * bm["glucosa"]
        + 0.0954 * np.log(bm["hs_CRP"])
        - 0.0120 * bm["linfocitos_pct"]
        + 0.0268 * bm["vcm"]
        + 0.3306 * bm["rdw"]
        + 0.00188 * bm["fosfatasa_alcalina"]
        + 0.0554 * bm["leucocitos"]
        + 0.0804 * edad
    )
    # Transformación a edad fenotípica (mortality score -> age)
    g = 0.0076927
    mortality = 1 - np.exp(-np.exp(xb) * (np.exp(120 * g) - 1) / g)
    phenoage_years = 141.50225 + np.log(-0.00553 * np.log(1 - mortality)) / 0.090165
    return phenoage_years
```

> **CRÍTICO:** los coeficientes y la normalización de unidades deben verificarse contra el paper original al implementar. No confíes en los números de arriba sin cross-check — es tu ancla de credibilidad ante el jurado. Documenta la fuente en el código.

### Manejo de faltantes
Si falta un biomarcador → imputar con mediana NHANES por edad/sexo, marcar `fuente:"inferido"`, y **ensanchar la incertidumbre** en Capa 3 (menos datos reales → banda P10–P90 más ancha).

### Test Capa 1
Dado un perfil de NHANES con edad cronológica conocida, la edad fenotípica debe caer en rango plausible (±10–15 años de la cronológica para población sana). Si sale 200 o -30, hay error de unidades.

---

## 5. CAPA 2 — MOTOR DE EVOLUCIÓN (la dinámica que predice)

### Qué hace
Regla: dado el estado en el año `t` y los hábitos/intervenciones, produce el estado en `t+1`. Aplicada 10 veces = trayectoria de 10 años.

### El modelo de deriva
Cada biomarcador tiene una **deriva anual base** (cómo cambia con la edad si no cambia nada) + un **efecto de intervención** (cómo la modifica cada hábito).

```python
# Coeficientes de deriva anual. DERIVADOS DE LITERATURA epidemiológica,
# no inventados. Documentar la fuente de cada uno. Son aproximados y
# el pitch DEBE decir "aproximados, derivados de literatura".
#
# Ejemplo de estructura (valores ilustrativos — calibrar con papers):

DERIVA_BASE = {           # cambio anual natural con la edad
    "hs_CRP":     +0.02,  # inflamación tiende a subir lento
    "glucosa":    +0.3,
    "albumina":   -0.01,
    "creatinina": +0.005,
    "rdw":        +0.02,
    "leucocitos":  0.0,
}

# Efecto MODIFICADOR de cada intervención sobre la deriva anual.
# Positivo = empeora, negativo = mejora. Multiplicadores o sumandos
# derivados de tamaños de efecto publicados.
EFECTO_INTERVENCION = {
    "sueno_8h":         {"hs_CRP": -0.05, "glucosa": -0.2},
    "ejercicio_moderado":{"hs_CRP": -0.08, "glucosa": -0.5, "albumina": +0.005},
    "dejar_alcohol":    {"hs_CRP": -0.03, "creatinina": -0.002},
    "dieta_mejor":      {"glucosa": -0.4, "hs_CRP": -0.04},
    "reducir_estres":   {"hs_CRP": -0.04},
}

def evolucionar_un_paso(estado: dict, intervenciones: list) -> dict:
    nuevo = dict(estado)
    for bm in nuevo:
        cambio = DERIVA_BASE.get(bm, 0.0)
        for interv in intervenciones:
            cambio += EFECTO_INTERVENCION.get(interv, {}).get(bm, 0.0)
        nuevo[bm] = nuevo[bm] + cambio
    return nuevo

def trayectoria_deterministica(estado0: dict, intervenciones: list,
                                edad0: float, anios: int = 10) -> list:
    estados = [estado0]
    for a in range(anios):
        estados.append(evolucionar_un_paso(estados[-1], intervenciones))
    # edad biológica en cada año
    return [phenoage(e, edad0 + i) for i, e in enumerate(estados)]
```

> **De dónde salen estos pesos (tu pregunta filosa):** los de Capa 1 = paper PhenoAge. Los de Capa 2 = tamaños de efecto de literatura epidemiológica (ej. cuánto baja la PCR el ejercicio). Aproximados pero CITABLES. Nunca inventados-y-presentados-como-verdad. Si el tiempo alcanza, calibrar con asociaciones hábito↔biomarcador en NHANES.

### Test Capa 2
Una trayectoria "sin intervención" debe envejecer más rápido que una "con buenas intervenciones". Si dormir 8h no mejora nada, hay error de signo.

---

## 6. CAPA 3 — MONTE CARLO (incertidumbre + wow)

### Qué hace
El cuerpo no es determinista. Corre la Capa 2 N=10000 veces; en cada paso anual añade ruido biológico aleatorio. Las 10000 trayectorias forman el abanico.

```python
import numpy as np

def monte_carlo(estado0: dict, intervenciones: list, edad0: float,
                anios: int = 10, N: int = 10000, sigma: dict = None) -> dict:
    """
    sigma: desviación estándar del ruido anual por biomarcador.
    Mayor sigma para biomarcadores imputados (más incertidumbre).
    Devuelve percentiles de edad biológica por año.
    """
    if sigma is None:
        sigma = {bm: abs(DERIVA_BASE.get(bm, 0.1)) * 2 for bm in estado0}

    todas = np.zeros((N, anios + 1))
    for n in range(N):
        estado = dict(estado0)
        for a in range(anios + 1):
            todas[n, a] = phenoage(estado, edad0 + a)
            # evolucionar con ruido
            for bm in estado:
                cambio = DERIVA_BASE.get(bm, 0.0)
                for interv in intervenciones:
                    cambio += EFECTO_INTERVENCION.get(interv, {}).get(bm, 0.0)
                ruido = np.random.normal(0, sigma.get(bm, 0.1))
                estado[bm] += cambio + ruido

    return {
        "mediana": np.median(todas, axis=0).tolist(),
        "p10": np.percentile(todas, 10, axis=0).tolist(),
        "p90": np.percentile(todas, 90, axis=0).tolist(),
        "anios": list(range(anios + 1)),
    }
```

### El barrido de escenarios (tu "muchos escenarios")
Corre Monte Carlo para cada combinación de intervenciones, rankea por años ganados / esfuerzo.

```python
ESFUERZO = {  # costo percibido de cada intervención (para el ratio impacto/esfuerzo)
    "sueno_8h": 2, "ejercicio_moderado": 3, "dejar_alcohol": 2,
    "dieta_mejor": 3, "reducir_estres": 2,
}

def barrido_escenarios(estado0, edad0, intervenciones_posibles):
    from itertools import combinations
    baseline = monte_carlo(estado0, [], edad0)
    base_final = baseline["mediana"][-1]
    resultados = []
    # todas las combinaciones de 1 a 3 intervenciones (evita explosión)
    for k in range(1, 4):
        for combo in combinations(intervenciones_posibles, k):
            sim = monte_carlo(estado0, list(combo), edad0)
            ganados = base_final - sim["mediana"][-1]
            esfuerzo = sum(ESFUERZO[i] for i in combo)
            resultados.append({
                "intervenciones": list(combo),
                "anios_ganados": round(ganados, 1),
                "esfuerzo": esfuerzo,
                "ratio": round(ganados / esfuerzo, 2) if esfuerzo else 0,
                "curva": sim,
            })
    resultados.sort(key=lambda r: r["ratio"], reverse=True)
    return {"baseline": baseline, "escenarios": resultados}
```

### Test Capa 3
El abanico P10–P90 debe ensancharse con los años (más incertidumbre a futuro). Un perfil con biomarcadores imputados debe tener banda más ancha que uno con datos completos.

---

## 7. SHAP — INTERPRETABILIDAD (el porqué)

Sobre el modelo de riesgo, calcula la contribución de cada biomarcador/hábito a la edad biológica proyectada. Alimenta al mensaje del output.

```python
import shap
# Envuelve phenoage() como función de predicción sobre un vector de features.
# explainer = shap.KernelExplainer(pred_fn, background_data_nhanes)
# shap_values = explainer.shap_values(perfil_usuario)
# -> top drivers positivos (empeoran) y negativos (mejoran)
```

> Para el demo, SHAP puede correr sobre el estado basal (no sobre las 10000 trayectorias). Basta para explicar "tu sueño es tu mayor palanca".

---

## 8. ESQUEMA DE OUTPUT (protagonista)

```json
{
  "edad_cronologica": 34,
  "edad_biologica_hoy": 37.8,
  "trayectoria_baseline": {
    "anios": [0,1,2,3,4,5,6,7,8,9,10],
    "mediana": [37.8, 38.9, "..."],
    "p10": ["..."],
    "p90": ["..."]
  },
  "mejor_decision": {
    "intervenciones": ["sueno_8h", "ejercicio_moderado"],
    "anios_ganados": 4.1,
    "rango": [3.2, 5.0],
    "esfuerzo": 5,
    "ratio_impacto_esfuerzo": 0.82
  },
  "veredicto_gemelo": "Tu gemelo dormiría 8 horas y añadiría ejercicio moderado antes que cambiar la dieta.",
  "porque": "El sueño es tu palanca de mayor impacto: reduce la inflamación (hs-CRP), que es tu eje dominante de riesgo.",
  "shap_top_drivers": [
    { "variable": "sueno_h", "contribucion": -1.8, "direccion": "mejora" },
    { "variable": "hs_CRP",  "contribucion": +1.2, "direccion": "empeora" }
  ],
  "comparacion_poblacional": {
    "fuente": "NHANES",
    "percentil_edad_biologica": 68,
    "mensaje": "Tu edad biológica está por encima del promedio de tu grupo de edad y sexo."
  },
  "incertidumbre": "3 de 9 biomarcadores fueron imputados; la banda de proyección es más ancha en consecuencia.",
  "descargo": "Estimación de riesgo poblacional, no diagnóstico. Consulta a un profesional para decisiones clínicas."
}
```

---

## 9. CASO DE PRUEBA END-TO-END (valida todo el motor)

```python
perfil_test = {
    "edad": 34, "sexo": "F",
    "biomarcadores": {
        "albumina": 4.4, "creatinina": 0.8, "glucosa": 92,
        "hs_CRP": 2.1, "rdw": 13.1, "leucocitos": 6.2,
        # imputados:
        "linfocitos_pct": 30, "vcm": 90, "fosfatasa_alcalina": 70,
    },
    "habitos": {"sueno_h": 6, "ejercicio": "bajo", "estres": "alto"},
}

# 1. Capa 1: edad biológica hoy debe ser plausible (30-45 aprox)
# 2. Capa 2: trayectoria sin intervención sube; con intervención sube menos
# 3. Capa 3: abanico se ensancha con los años
# 4. Barrido: la mejor decisión tiene el mayor ratio ganados/esfuerzo
# 5. Output: JSON completo y bien formado
```

---

## 10. STACK Y DESPLIEGUE
- **Backend:** Python 3.11 + FastAPI + NumPy + shap. Deploy en Render.
- **Endpoint principal:** `POST /simular` recibe el JSON de input (sección 3), devuelve el JSON de output (sección 8).
- **Datos:** NHANES (CSV públicos) para medianas de imputación y comparación poblacional. Descargar y cachear al inicio.
- **Persistencia:** Supabase (perfil + resultado por usuario).
- **Frontend:** consume `/simular`, renderiza el abanico (Recharts/D3) y el veredicto.

---

## 11. ORDEN DE CONSTRUCCIÓN (no te saltes pasos)
1. Capa 1 sola, con caso de prueba. Que dé edad biológica plausible. ← empieza aquí
2. Cargar NHANES, medianas de imputación funcionando.
3. Capa 2: trayectoria determinista. Test de signos.
4. Capa 3: Monte Carlo, un escenario. Ver el abanico en números.
5. Barrido de escenarios + ranking.
6. SHAP sobre el basal.
7. Ensamblar output JSON completo (sección 8).
8. Endpoint FastAPI. Conectar frontend.
9. Caso demo pre-cargado (red de seguridad — NUNCA depender de upload en vivo).

---

## 12. LO QUE NO SE HACE (protección anti-dispersión)
- ❌ Foto envejecida del rostro real (avatar abstracto en su lugar).
- ❌ Alimentación/suplementos/alergias como output del demo (roadmap).
- ❌ Modelo biofísico "real" de envejecimiento (es modelo de trayectorias plausibles).
- ❌ Coeficientes inventados presentados como verdad (siempre "aproximados, de literatura").
- ❌ Más de 3 intervenciones simultáneas en el barrido (evita explosión combinatoria).
- ❌ Correr SHAP sobre las 10000 trayectorias (basal basta para el demo).

---

## 13. FRASES DEFENSIVAS PARA EL JURADO
- "¿Los pesos son inventados?" → "Capa 1 es PhenoAge publicado (Levine 2018). Capa 2 son efectos de literatura epidemiológica, aproximados y citables. Nada presentado como verdad exacta."
- "¿Esto predice enfermedad?" → "No. Estratifica riesgo y proyecta trayectorias probables de edad biológica, con incertidumbre explícita — el abanico muestra lo que no sabemos."
- "¿Por qué confiar en la proyección?" → "No pedimos confianza ciega: mostramos la banda P10–P90. La incertidumbre es parte del output, no algo que escondemos."
