# Auditoría del motor y del flujo de datos - 2026-08-22

Auditoría de punta a punta de lo que la app calcula y muestra: motor (`apps/backend/app/health_metrics/`), endpoints (`/phenoage`, `/montecarlo`), cómo la app arma y pinta el resultado, y qué datos del onboarding entran de verdad al cálculo. Se corrieron 7 personas sintéticas (hábitos excelentes, hábitos malos + fumador, sin exámenes, caso sec. 9 de la spec, 72 años, atleta de 19, y "sin hábitos ni exámenes") contra el motor antes y después.

## 1. Qué estaba mal (y ya está arreglado)

| # | Hallazgo | Evidencia (antes) | Arreglo | Evidencia (después) |
|---|---|---|---|---|
| 1 | **La banda no se angostaba al medir.** El Monte Carlo solo tenía ruido de deriva; un biomarcador imputado se fijaba en la mediana. La app y la spec prometían lo contrario ("qué medir angosta el rango"). | Ancho P10-P90 a 10 años = 12,09 con 0, 3, 6 o 9 biomarcadores medidos. | Los imputados arrancan **muestreados** de su dispersión poblacional (`nhanes_reference.DISPERSION`); el motor calcula el **valor de información** de cada uno (`valor_de_informacion`). | 0 medidos: 17,4 - 6 medidos: 12,3 - 9 medidos: 11,7. Hoy mismo la banda mide 12,7 años sin exámenes y 0 con los 9. "Qué medir" muestra años reales (RDW ~ 2,8 años, luego creatinina y VCM). |
| 2 | **Los hábitos no entraban al motor.** A alguien con actividad alta y alimentación alta se le recomendaba "ejercicio +1,9 años"; sueño y estrés existían en el backend pero la app nunca los pedía; alcohol ni siquiera se mandaba. | Persona A (hábitos excelentes): 4 palancas con ganancia. | `habitos` -> **brecha 0-1 por hábito**; cada palanca cierra un hábito (efecto x brecha; brecha 0 => no aplica); la **línea base es personal** (descomposición de mezcla con prevalencias declaradas, bono acotado a frenar el reloj); palanca nueva **bajar el alcohol**; `habitos.alcohol` en la API y en la app. | Persona A: 0 palancas -> "Estás bien", y el "por qué" muestra lo que sus hábitos le ahorran (no fumar -1,5, ejercicio -1,1...). Persona B (6 hábitos malos): base envejece +13,9 en 10 años vs +9,9 de A; 6 palancas + combos. |
| 3 | **Persona mediana sesgada.** La tabla de medianas era más "sana" que la población de ajuste de PhenoAge: la mediana marcaba 5-8 años menos que su edad a los 20-45 y +4 a los 82 en hombres => todo usuario sin exámenes salía 7 años más joven, percentil de la mediana = 11-17, y todo el mundo "envejecía" +12 años en 10. | 40F todo imputado: PhenoAge 32,6 (-7,5), percentil 11. | Tabla recalibrada con criterio explícito y testeado (persona mediana ~ su edad +/-2, mujeres ~1 año bajo hombres, pendiente ~ 1,0/año), derivas re-derivadas de su gradiente, percentil centrado en la referencia y con SD propagada (~5 años). | 40F todo imputado: PhenoAge 38,6 (-1,4 = referencia), percentil 50; la referencia envejece +10 en 10 años. |
| 4 | **Piso de hs-CRP 0,01 mg/L**: las trayectorias que tocaban el piso entraban como ln(0,001 mg/dL) y sesgaban la mediana ~0,4 años. | MC mediana - determinista = -0,44. | Piso 0,1 mg/L (límite de detección real). | -0,17. |
| 5 | **Efectos absolutos sobre PCR**: una persona con PCR baja "ganaba" años imposibles (la PCR se iba al piso); un combo de 3 palancas ganaba MÁS que la suma de sus partes. | combo 5,8 > suma 4,9. | Efectos sobre hs-CRP **proporcionales al valor actual** (calibrados a 2,5 mg/L; los ensayos reportan reducciones relativas). | Quien tiene PCR 5,5 gana más por la misma palanca que quien tiene 0,4; combo < suma. |
| 6 | **"Futuros pareados" no lo eran**, y el "% que mejora", el rango de años ganados, la curva por año, el "por qué", el percentil y las trayectorias se aproximaban en la app. | UI: "misma semilla, una sola variable cambiada" era falso; curva interpolada √t; Φ(delta/sd) ad hoc. | Misma semilla, mismos arranques, misma **respuesta individual** (N(1, 0,5) truncada) para todos los escenarios; el backend devuelve `curva` por año, `anios_ganados` pareados con P10-P90, `pct_futuros_que_mejoran`, 40 trayectorias reales, `contribuciones` (biomarcadores hoy) + `contribuciones_habitos` (10 años), percentil, semilla fija reproducible. La app usa todo eso y cae a las aproximaciones solo si el backend es viejo (`fuente_curvas`). | ejercicio +1,6 [+0,6, +2,7], mejora 98 %. |
| 7 | **Combinaciones de 2-3 palancas** (spec sec. 6, filtro "1/2/3 cambios" de la pantalla Simular) solo existían en el mock; el backend corría palancas sueltas + una `combinada` precocinada. | - | Claves `a+b+c` (máx. 3) con descuento de sublinealidad genérico (8 % por palanca adicional sobre el mismo biomarcador); sin `escenarios` el backend corre lo que aplica + sus pares y tríos. 41 escenarios x 5.000 x 10 años en ~0,3 s (vectorizado). | Persona B: 42 escenarios; D (spec sec. 9): 15. |
| 8 | **Respaldo mostraba coeficientes viejos** (glucosa 0,5, tabaco -0,15, sin sueño/estrés). | Copias a mano desfasadas. | `GET /engine/catalogo` (sin auth) + la pantalla lo consume (copia local solo de respaldo, y lo dice). | - |
| 9 | Onboarding prometía "pongo primero las palancas que tocan tus objetivos" y nada lo hacía. | - | Copy honesto ("te marco las que tocan eso") + badge "toca ..." en las cards (no altera el orden, que es años/esfuerzo). | - |
| 10 | `edad_cronologica` del resultado salía del input local (el caso demo) y no del perfil que usó el backend. | - | Se toma de `/phenoage`. | - |

Tests: backend 73 -> 120 (`test_montecarlo.py`, `test_biological_age_router.py` nuevos; calibración de la tabla, pareado, imputación, VOI, hábitos, combinaciones, PCR relativa); app `flutter analyze` limpio y `test/remote_result_test.dart` (forma nueva y forma vieja del backend).

## 2. Qué se pide y cómo entra hoy al cálculo

| Dato del onboarding | Antes | Ahora |
|---|---|---|
| Edad, sexo | PhenoAge, imputación | igual + referencia/percentil por edad y sexo |
| Estatura, peso (IMC) | se guarda como biomarcador `imc`, no entra | igual (ver propuestas) |
| Tipo de sangre | no entra | no entra (no hay evidencia para un reloj de edad biológica) |
| Nacionalidad / país / ancestría | no entra (solo chat) | igual (ver propuestas) |
| Objetivos | prometía ordenar; no hacía nada | badge en las palancas + contexto del chat |
| Historia familiar | solo chat | igual (ver propuestas) |
| Sueño (horas) | no entraba | palanca **dormir 8 horas** (brecha lineal 6 h->7,5 h) + línea base |
| Calidad de sueño | no entra | no entra (ver propuestas) |
| Ejercicio (4 niveles) | solo decidía la palanca en el mock | brecha 1/0,5/0 -> aplica, efecto escalado, línea base |
| Alcohol (frecuencia) | solo local | `habitos.alcohol` -> palanca **bajar el alcohol** + línea base |
| Alimentación (3 niveles) | no entraba | brecha -> dieta mediterránea, línea base |
| Patrones de alimentación (chips) | no entra | no entra (ver propuestas) |
| Tabaco | decidía pedir `cesacion_tabaco` | brecha 0/1 -> aplica + línea base (fumar envejece la base) |
| Estrés | no entraba | palanca **reducir el estrés** + línea base |
| Suplementos | no entra | no entra (spec sec. 12: fuera de alcance) |
| Wearables (sueño, pasos, ejercicio, FC reposo) | recalcula `sueno_h`/`actividad` | igual, y ahora esos dos sí mueven el motor; FC reposo no se usa (ver propuestas) |
| Foto, prueba genética | solo se guardan | igual (spec sec. 12: fase 2) |
| Colesterol total, presión sistólica | se guardan "para otros modelos" | igual (ver propuestas) |

## 3. Propuestas para usar lo que falta (gemelo más preciso)

Ordenadas por valor/esfuerzo. Ninguna inventa coeficientes: cada una dice de dónde saldrían.

1. **IMC como modulador y palanca "peso" (alto valor, esfuerzo medio).** El IMC ya viaja al backend. Literatura sólida: cada unidad de IMC se asocia a +0,1-0,2 mg/L de PCR y a mayor glucosa en ayunas; en el DPP una pérdida del 5-7 % del peso bajó glucosa en ayunas ~3-5 mg/dL y PCR ~30 %. Implementación: brecha `peso` = clamp((IMC - 25)/10, 0, 1), palanca `perder_5pct_peso` (hs_CRP -0,05/año proporcional, glucosa -0,5/año, esfuerzo 4), y ajuste de línea base por la brecha como los demás hábitos. Cuidado con la spec sec. 12 (no dieta personalizada): es una palanca de peso, no un plan.
2. **Presión sistólica y colesterol en un segundo reloj (alto valor, esfuerzo alto).** PhenoAge no los usa; la tabla los guarda "para otros modelos". El camino honesto es un segundo output - riesgo cardiovascular a 10 años con una ecuación publicada (p. ej. tipo Framingham/PCE con edad, sexo, PAS, colesterol total, tabaco, diabetes) - y palancas que lo muevan (tabaco ya está; PAS con ejercicio/sal). Mostrarlo como segunda métrica, no mezclarlo con PhenoAge. Hasta entonces: pedirlos solo si se van a usar, o decir en la UI que se guardan para la siguiente versión.
3. **Historia familiar (valor medio, esfuerzo bajo).** No hay coeficiente de deriva publicado; lo defendible es (a) priorizar en "Qué medir" (diabetes T2 familiar => glucosa/HbA1c primero; cardiovascular => presión y colesterol) y (b) ensanchar la dispersión de arranque del biomarcador asociado cuando está imputado (más heterogeneidad, no más edad). Ambas son una línea en `montecarlo.simular` + un campo en la respuesta.
4. **Frecuencia cardiaca en reposo del wearable (valor medio, esfuerzo bajo).** Ya se lee y se descarta. FC reposo alta se asocia a mortalidad y a menor capacidad aeróbica; úsese para afinar la brecha de `actividad` (FC reposo
   <60 => brecha 0 aunque el autorreporte diga "poco"; >80 => no bajar de 0,5) y
   como dato en el "por qué". No como biomarcador de PhenoAge.
5. **Calidad de sueño y patrones de alimentación (valor bajo-medio, esfuerzo bajo).** Hoy solo se guardan. Úsense para afinar la brecha: calidad "baja" con >=7,5 h => brecha de sueño 0,5 (no 0); "ultraprocesados frecuentes" o "mucha azúcar" => brecha de alimentación al menos 0,5 aunque el autorreporte diga "bastante bien". Es el mismo mecanismo de brechas, sin coeficientes nuevos.
6. **Ancestría / país (valor bajo hoy).** PhenoAge se ajustó en NHANES III (EE. UU.); no hay tablas de referencia por ancestría defendibles a mano. Lo honesto: decir que la referencia es NHANES y dejar el dato para cuando haya una tabla regional. No inventar medianas por país.
7. **Adherencia en el motor (valor alto para el producto, esfuerzo medio).** La app aplica 0,25 - 0,5 - 0,8 - 1 en local. En el motor: años activos + decaimiento (los biomarcadores vuelven hacia la deriva base cuando se deja el hábito; detraining en semanas-meses para PCR/glucosa, VCM en ~4 meses). Daría la curva "si lo sostienes 8 meses" de verdad.
8. **Sensibilidad del ranking (esfuerzo bajo).** Los pesos de esfuerzo (2/3/4) deciden el orden; exponer en "Respaldo" y permitir al usuario ajustar su esfuerzo percibido por palanca (la UI de adherencia ya tiene el patrón).

## 4. Límites que quedan y hay que decir

- **PhenoAge extrapola mal por debajo de ~22 años con exámenes excelentes** (un atleta de 19 con laboratorios perfectos marca 2,1 años). Es la fórmula, no un bug de unidades; la app exige >=18. Propuesta de presentación: para aceleraciones por debajo de -15 mostrar "muy por debajo de tu edad" y el percentil (1), no el número crudo.
- La tabla de medianas sigue siendo **a mano, tipo NHANES, calibrada**, no microdato. Las prevalencias que sitúan la línea base por hábito son supuestos declarados (no mueven los años ganados, solo la base).
- El ruido anual es un paseo aleatorio sin reversión a la media (diseño de la spec sec. 6): las bandas a 10 años son anchas (~12 años con los 9 medidos).
- **Hay que desplegar el backend** (Render) para que la app reciba la forma nueva; mientras tanto la app detecta la forma vieja y usa las aproximaciones anteriores, marcándolo (`fuente_curvas = "interpolada"`).
