"""S99 — Gerçek Foundry Local runtime smoke testi (OPSİYONEL, skip-korumalı).

Varsayılan pytest çalıştırmasında SKIP edilir; yalnız açıkça istendiğinde çalışır:

    SANA_RUN_FOUNDRY_SMOKE=1  ve  SANA_FOUNDRY_MODEL=<model>  (+ gerekirse
    SANA_FOUNDRY_BASE_URL) ayarlıyken:

    python -m pytest tests/test_foundry_runtime_smoke.py -v

Yalnız LOCAL Foundry endpoint'i kullanılır; dış AI / ücretli API'ye gidilmez,
API key gerekmez. Ayrıntılar: docs/FOUNDRY_LOCAL_SMOKE_TEST.md
"""

import os
from pathlib import Path

import pytest

_RUN = os.getenv("SANA_RUN_FOUNDRY_SMOKE", "") == "1"
_MODEL = (os.getenv("SANA_FOUNDRY_MODEL") or "").strip()

pytestmark = [
    pytest.mark.skipif(
        not _RUN,
        reason="Gerçek Foundry smoke yalnız SANA_RUN_FOUNDRY_SMOKE=1 ile çalışır",
    ),
    pytest.mark.skipif(
        _RUN and not _MODEL,
        reason="SANA_FOUNDRY_MODEL ayarlı değil; Foundry smoke atlandı",
    ),
]

DOCS_DIR = Path(__file__).resolve().parents[1] / "data" / "medical_docs"
OFFICIAL_URL_PREFIX = "https://medlineplus.gov/"


@pytest.fixture
def local_foundry_env(tmp_path, monkeypatch):
    """Geçici DB'ye gerçek medical_docs ingest edilir; local+foundry env kurulur.

    SANA_FOUNDRY_MODEL ve (varsa) SANA_FOUNDRY_BASE_URL kullanıcı ortamından
    olduğu gibi gelir; onlara dokunulmaz.
    """
    from tools import ingest_docs

    db = tmp_path / "smoke_rag.db"
    ingest_docs.ingest(str(DOCS_DIR), str(db))
    monkeypatch.setenv("SANA_RAG_MODE", "local")
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(db))
    monkeypatch.setenv("SANA_ENABLE_EXTERNAL_AI", "false")


def test_provider_generate_minimal(local_foundry_env):
    """Provider seviyesinde: local store context'i ile GERÇEK model cevabı."""
    from app.services.llm_provider import get_llm_provider
    from app.services.retrieval_service import retrieve_for_query

    retrieved = retrieve_for_query("crp nedir", "CRP", "Nedir?")
    assert retrieved, "smoke öncesi ingestion başarısız görünüyor"

    provider = get_llm_provider()
    assert provider.name == "foundry_local"

    answer = provider.generate(
        question="CRP nedir?",
        lab_test="CRP",
        intent="definition",
        retrieved=retrieved,
    )
    assert isinstance(answer, str) and answer.strip(), "model boş cevap döndürdü"


def test_explain_end_to_end_real_foundry(local_foundry_env):
    """/explain uçtan uca: local RAG + gerçek Foundry Local."""
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    r = client.post(
        "/explain",
        json={"question": "CRP nedir?", "lab_test": "CRP", "options": {"language": "tr"}},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "foundry_local"
    assert body["answer"].strip()
    assert body["disclaimer"]
    # Kaynak zorunluluğu: local store'dan citation gelmiş olmalı
    assert body["citations"]
    assert any(c["source_url"].startswith(OFFICIAL_URL_PREFIX) for c in body["citations"])
