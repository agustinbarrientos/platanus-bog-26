"""Biological-age compute: PhenoAge and the Monte Carlo intervention simulation.

Pure functions only — no FastAPI, no database. `app/routers/biological_age.py`
is the only caller; keeping this package framework-free is what makes the
formula and the simulation independently testable.
"""
