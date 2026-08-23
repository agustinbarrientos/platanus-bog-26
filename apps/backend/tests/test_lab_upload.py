"""`POST /me/health-context/biomarkers/extract` through FastAPI's TestClient,
with the database session and the Anthropic client faked: the biomarker
upsert-by-name merge, the `hallazgos`-to-`notas_incertidumbre` merge (append,
dedup, never overwrite), and the file-count/content-type guardrails."""

from __future__ import annotations

import uuid
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import CurrentUser, get_current_user
from app.db import get_db
from app.lab_extraction import ExtractedReading, ExtractionResult
from app.main import create_app
from app.models import HealthContext
from app.routers import lab_upload

USER_ID = uuid.uuid4()

_PDF_BYTES = b"%PDF-1.4\n%%EOF"


class FakeSession:
    """Just enough of `AsyncSession` for `get_or_create_health_context`
    (insert-on-conflict-do-nothing, then a locked `get`) and the router's
    flush/refresh — no real upsert semantics needed since there's only ever
    one row and it already exists."""

    def __init__(self, health: HealthContext) -> None:
        self.health = health

    async def execute(self, *args, **kwargs):
        return None

    async def get(self, model, key, with_for_update: bool = False):
        return self.health if model is HealthContext else None

    async def flush(self) -> None:
        pass

    async def refresh(self, row) -> None:
        pass


class FakeAnthropic:
    """Quacks like `AsyncAnthropic` for `client.messages.parse(...)`."""

    def __init__(self, result: ExtractionResult) -> None:
        self._result = result
        self.calls: list[dict] = []
        self.messages = self

    async def parse(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(parsed_output=self._result)


@pytest.fixture
def health(monkeypatch):
    row = HealthContext(user_id=USER_ID, biomarcadores=[], notas_incertidumbre=None)
    return row


@pytest.fixture
def client(health, monkeypatch):
    app = create_app()

    async def fake_db():
        yield FakeSession(health)

    app.dependency_overrides[get_db] = fake_db
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        id=USER_ID, email="ana@moirai.test", token_id=uuid.uuid4()
    )
    holder: dict = {}
    monkeypatch.setattr(lab_upload, "get_anthropic_client", lambda: holder["fake"])
    with TestClient(app) as c:
        c.holder = holder  # type: ignore[attr-defined]
        yield c


def _upload(client, filename="informe.pdf", content_type="application/pdf", n=1):
    files = [("files", (filename, _PDF_BYTES, content_type))] * n
    return client.post("/me/health-context/biomarkers/extract", files=files)


def test_extraction_saves_biomarkers_and_hallazgos(client, health):
    result = ExtractionResult(
        lecturas=[ExtractedReading(nombre="glucosa", valor_reportado=92.0, unidad_reportada="mg/dL", fuente_texto="Glucosa: 92")],
        hallazgos=["Médico recomienda control en 3 meses"],
    )
    client.holder["fake"] = FakeAnthropic(result)

    r = _upload(client)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["guardados"][0]["nombre"] == "glucosa"
    assert body["hallazgos"] == ["Médico recomienda control en 3 meses"]
    assert body["notas_incertidumbre"] == "Médico recomienda control en 3 meses"
    assert health.biomarcadores == [{"nombre": "glucosa", "valor": 92.0, "unidad": "mg/dL", "fuente": "documento"}]
    assert health.notas_incertidumbre == "Médico recomienda control en 3 meses"


def test_second_upload_merges_without_clobbering_or_duplicating(client, health):
    health.biomarcadores = [{"nombre": "colesterol_total", "valor": 180.0, "unidad": "mg/dL", "fuente": "documento"}]
    health.notas_incertidumbre = "Alergia registrada: penicilina"

    result = ExtractionResult(
        lecturas=[ExtractedReading(nombre="glucosa", valor_reportado=92.0, unidad_reportada="mg/dL", fuente_texto="Glucosa: 92")],
        # one repeat finding (already stored) + one genuinely new one
        hallazgos=["Alergia registrada: penicilina", "Nódulo tiroideo benigno de 4mm"],
    )
    client.holder["fake"] = FakeAnthropic(result)

    r = _upload(client)
    assert r.status_code == 200, r.text
    body = r.json()

    nombres = {b["nombre"] for b in body["biomarcadores"]}
    assert nombres == {"colesterol_total", "glucosa"}  # old biomarker survives, new one merged in

    assert body["notas_incertidumbre"] == "Alergia registrada: penicilina; Nódulo tiroideo benigno de 4mm"
    assert health.notas_incertidumbre.count("penicilina") == 1  # not duplicated


def test_implausible_reading_goes_to_advertencias_not_storage(client, health):
    result = ExtractionResult(
        lecturas=[ExtractedReading(nombre="glucosa", valor_reportado=9000.0, unidad_reportada="mg/dL", fuente_texto="Glucosa: 9000")],
    )
    client.holder["fake"] = FakeAnthropic(result)

    r = _upload(client)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["guardados"] == []
    assert body["advertencias"][0]["nombre"] == "glucosa"
    assert health.biomarcadores == []


def test_no_files_is_422(client, health):
    r = client.post("/me/health-context/biomarkers/extract", files=[])
    assert r.status_code == 422


def test_too_many_files_is_422(client, health):
    client.holder["fake"] = FakeAnthropic(ExtractionResult(lecturas=[]))
    r = _upload(client, n=lab_upload.MAX_FILES_PER_REQUEST + 1)
    assert r.status_code == 422


def test_unsupported_content_type_is_422(client, health):
    r = _upload(client, content_type="text/plain")
    assert r.status_code == 422
