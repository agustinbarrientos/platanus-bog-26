"""Auditoría rápida del motor con personas sintéticas (ver docs/AUDITORIA_MOTOR_2026-08-22.md).

Corre PhenoAge + Monte Carlo (hábitos, pareado, imputación muestreada) para 7
perfiles —hábitos excelentes, hábitos malos + fumador, sin exámenes, caso §9,
72 años, atleta de 19, sin hábitos ni exámenes— e imprime lo que la app
mostraría: edad biológica hoy, percentil, banda hoy y a 10 años, palancas
ordenadas por ratio con su rango, valor de información y contribuciones de
hábitos. Uso: `.venv/bin/python scripts/audit_personas.py` desde apps/backend.
"""
import sys, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from app.health_metrics import phenoage, montecarlo
from app.health_metrics.interventions import brechas_desde_habitos, PALANCAS, aplica
from itertools import combinations

PERSONAS = {
 "A_sana_32F_habitos_buenos": dict(edad=32, sexo="F",
    bm={"albumina":4.6,"creatinina":0.7,"glucosa":82,"hs_CRP":0.4,"rdw":12.3,"leucocitos":5.2,"linfocitos_pct":36,"vcm":89,"fosfatasa_alcalina":55},
    hab={"sueno_h":8,"tabaco":False,"actividad":"alta","alimentacion":"alta","estres":"bajo","alcohol":"ocasional"}),
 "B_mala_48M_fuma_sedentario": dict(edad=48, sexo="M",
    bm={"albumina":3.9,"creatinina":1.1,"glucosa":112,"hs_CRP":5.5,"rdw":14.6,"leucocitos":8.9,"linfocitos_pct":24,"vcm":96,"fosfatasa_alcalina":95},
    hab={"sueno_h":5.5,"tabaco":True,"actividad":"baja","alimentacion":"baja","estres":"alto","alcohol":"alto"}),
 "C_sin_examenes_40F": dict(edad=40, sexo="F", bm={}, hab={"sueno_h":7,"tabaco":False,"actividad":"media","alimentacion":"media","estres":"medio","alcohol":"ocasional"}),
 "D_spec9_34F": dict(edad=34, sexo="F",
    bm={"albumina":4.4,"creatinina":0.8,"glucosa":92,"hs_CRP":2.1,"rdw":13.1,"leucocitos":6.2},
    hab={"sueno_h":6,"tabaco":False,"actividad":"baja","alimentacion":"media","estres":"alto"}),
 "E_mayor_72M": dict(edad=72, sexo="M",
    bm={"albumina":4.0,"creatinina":1.05,"glucosa":104,"hs_CRP":2.4,"rdw":14.0,"leucocitos":7.1},
    hab={"sueno_h":6.5,"tabaco":False,"actividad":"media","alimentacion":"media","estres":"bajo"}),
 "F_joven_19M_atleta": dict(edad=19, sexo="M",
    bm={"albumina":5.0,"creatinina":0.9,"glucosa":78,"hs_CRP":0.2,"rdw":11.8,"leucocitos":4.8,"linfocitos_pct":38,"vcm":88,"fosfatasa_alcalina":60},
    hab={"sueno_h":8.5,"tabaco":False,"actividad":"alta","alimentacion":"alta","estres":"bajo","alcohol":"nunca"}),
 "G_sin_habitos_ni_examenes_55M": dict(edad=55, sexo="M", bm={}, hab=None),
}
for name, p in PERSONAS.items():
    print("="*90); print(name, p["hab"])
    r = phenoage.compute(p["bm"], p["edad"], p["sexo"])
    top = sorted(r.contribuciones.items(), key=lambda kv: -abs(kv[1]))[:3]
    print(f"  PhenoAge hoy {r.edad_biologica:6.2f} (acel {r.aceleracion:+.2f}; ref {r.aceleracion_referencia:+.2f}) percentil {r.percentil_poblacional:4.1f}  imputados {len(r.campos_inferidos)}  top contrib: {[(k, round(v,1)) for k,v in top]}")
    br = brechas_desde_habitos(p["hab"]) if p["hab"] is not None else None
    singles = [k for k in PALANCAS if aplica(k, br)]
    combos = ["+".join(c) for k in (2,3) for c in combinations(singles, k)]
    t0=time.time()
    res = montecarlo.simular(p["bm"], p["edad"], p["sexo"], ["ninguna", *singles, *combos], montecarlo.DEFAULT_TRAYECTORIAS, 10, brechas=br)
    dt=time.time()-t0
    b = res.escenarios[0]
    print(f"  [{dt:.2f}s, {len(res.escenarios)} escenarios] brechas={ {k:v for k,v in (br or {}).items()} }")
    print(f"  HOY banda {b.curva_p10[0]:6.2f}-{b.curva_p90[0]:6.2f} (ancho {res.ancho_banda_hoy:.2f}) | 10y: mediana {b.edad_biologica_mediana:6.2f} P10 {b.edad_biologica_p10:6.2f} P90 {b.edad_biologica_p90:6.2f} ancho {b.edad_biologica_p90-b.edad_biologica_p10:.2f} | envejece {b.edad_biologica_mediana-b.curva_mediana[0]:+.2f}")
    rank = sorted(res.escenarios[1:], key=lambda e: -e.ratio_impacto_esfuerzo)
    for e in rank[:8]:
        print(f"    {e.escenario:55s} ganados {e.anios_ganados:+5.2f} [{e.anios_ganados_p10:+5.2f},{e.anios_ganados_p90:+5.2f}] mejora {e.pct_futuros_que_mejoran:5.1f}% esf {e.esfuerzo:2d} ratio {e.ratio_impacto_esfuerzo:5.2f} aplica={e.aplica}")
    if res.valor_de_informacion:
        print("  VOI:", [(v.nombre, round(v.reduccion_banda_anios,2), round(v.fraccion,2)) for v in res.valor_de_informacion])
    if res.contribuciones_habitos:
        print("  habitos:", [(c['habito'], round(c['contribucion'],2), c['direccion']) for c in res.contribuciones_habitos])
