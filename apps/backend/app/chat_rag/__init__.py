"""Retrieval for the health chat (`POST /me/health-context/chat`).

The agent used to get the user's *entire* health context pasted into every
system prompt. That does not scale once the chat also has to answer about the
simulation result (best lever, every scenario, the P10–P90 band, SHAP, the
population percentile...) and explain the engine itself (PhenoAge, Monte
Carlo, imputation, each biomarker, each intervention): stuffing all of it in
costs ~8–10k tokens per turn, most of it irrelevant to the question asked.

So this package is a small RAG layer, framework-free like `app/health_metrics`:

- `chunks.py`     — the `Chunk` record + es-CO number formatting + token estimate.
- `knowledge.py`  — a static knowledge base about the engine (built from the
                    same tables the engine runs on, so it cannot drift from it).
- `documents.py`  — turns the user's stored data, a fresh PhenoAge and the
                    simulation result the app sends into per-topic chunks.
- `retriever.py`  — lexical retrieval (BM25 over accent-stripped Spanish stems
                    + a synonym map) picking the chunks that fit a token budget.
- `prompt.py`     — the system prompt (Moirai's voice), the rendering of the
                    retrieved chunks, and the `buscar_mis_datos` tool the model
                    can call when the first retrieval missed something.

No embeddings on purpose: Anthropic has no embeddings endpoint, the corpus is
tiny (≈60 short chunks per user) and keyword + synonym matching is
deterministic, testable and free. `retriever.retrieve()` is the only seam —
an embedding-based scorer could replace it behind the same signature.
"""
