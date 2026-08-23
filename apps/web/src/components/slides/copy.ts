/** Every word the deck shows. es-CO, tildes in place, no period at the end of a title. */
export const COPY = {
  intro: { line: "Cuánto puedes frenar el reloj de tu cuerpo" },
  problema: {
    bigN: 8,
    bigRest: "de cada 10",
    rest: "infartos, derrames y diabetes prematuros se pueden prevenir",
    source: "OMS",
  },
  examen: {
    line1: "Tu examen de sangre ya tiene las señales",
    line2: "Nadie te las traduce",
    header: "Laboratorio clínico · Resultados",
    /** A real report's order; `signal` marks the PhenoAge inputs. The six
        measured values are the app's demo case (demo_data.dart). */
    rows: [
      { label: "Hemoglobina", value: "13,8", unit: "g/dL", signal: false },
      { label: "Leucocitos", value: "6,2", unit: "×10³/µL", signal: true },
      { label: "Plaquetas", value: "245", unit: "×10³/µL", signal: false },
      { label: "RDW", value: "13,1", unit: "%", signal: true },
      { label: "Glucosa", value: "92", unit: "mg/dL", signal: true },
      { label: "Creatinina", value: "0,8", unit: "mg/dL", signal: true },
      { label: "Albúmina", value: "4,4", unit: "g/dL", signal: true },
      { label: "PCR-us", value: "2,1", unit: "mg/L", signal: true },
      { label: "Colesterol total", value: "178", unit: "mg/dL", signal: false },
      { label: "TSH", value: "1,9", unit: "µUI/mL", signal: false },
    ],
  },
  solucion: {
    title: "Lee tu examen y simula diez mil futuros tuyos",
    chips: ["tu edad biológica en 10 años", "la decisión que más años te ahorra"],
    counterLabel: "de 10.000 futuros",
  },
  impacto: {
    /** `delta` arrives signed and formatted: `+1,9`. */
    title: (delta: string) => `${delta} años que le ahorras a tu cuerpo`,
    chips: (lo: string, hi: string, pct: number) => [
      `entre ${lo} y ${hi}`,
      `mejora en ${pct} de cada 100 futuros`,
    ],
  },
  demo: { line: "Ahora te lo muestro" },
  gracias: { word: "Gracias" },
  cierre: { url: "moirai.uo.ar", qrAlt: "Código QR que lleva a moirai.uo.ar" },
} as const;
