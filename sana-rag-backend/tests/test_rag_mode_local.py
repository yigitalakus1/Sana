"""S97 — SANA_RAG_MODE=local entegrasyon testleri.

Local store'daki chunk'lar S94 markdown'larından gelir. Seed ve local içerik aynı
resmî MedlinePlus citation metadata'sını taşır; local yol chunk id biçimiyle
(``crp-nedir``) ayırt edilir.
"""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.services.chat_service as chat_service
import app.services.llm.foundry_local_provider as fp
import app.services.rag_service as rag_service
from app.core import config
from app.data.loinc_catalog import LAB_SOURCE_BY_NAME
from app.main import app
from app.services import local_retrieval_service as lrs
from app.services.rag_store import LocalRagStore
from app.services.retrieval_service import retrieve_for_query
from tools import ingest_docs

client = TestClient(app)
DOCS_DIR = Path(__file__).resolve().parents[1] / "data" / "medical_docs"

OFFICIAL_URL_PREFIX = "https://medlineplus.gov/"
SOURCE_TITLE = "MedlinePlus"


class RecordingProvider:
    """generate() çağrılarını kaydeden fake provider."""

    name = "fake"

    def __init__(self):
        self.calls = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return "FAKE_CEVAP: kaynaklara göre açıklama."


@pytest.fixture
def local_db(tmp_path, monkeypatch):
    """Gerçek medical_docs ingest edilmiş geçici DB + local mode env."""
    db = tmp_path / "rag.db"
    ingest_docs.ingest(str(DOCS_DIR), str(db))
    monkeypatch.setenv("SANA_RAG_MODE", "local")
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(db))
    return db


@pytest.fixture
def recording_provider(monkeypatch):
    provider = RecordingProvider()
    monkeypatch.setattr(rag_service, "get_llm_provider", lambda: provider)
    monkeypatch.setattr(chat_service, "get_llm_provider", lambda: provider)
    return provider


def _explain(question, lab_test=None):
    payload = {"question": question, "options": {"language": "tr"}}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/explain", json=payload)


def _chat(text, lab_test=None):
    payload = {"messages": [{"role": "user", "content": text}]}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/chat", json=payload)


# --- Config helper ---

def test_rag_mode_default_is_seed(monkeypatch):
    monkeypatch.delenv("SANA_RAG_MODE", raising=False)
    assert config.get_rag_mode() == "seed"


def test_rag_mode_unknown_falls_back_to_seed(monkeypatch):
    monkeypatch.setenv("SANA_RAG_MODE", "quantum")
    assert config.get_rag_mode() == "seed"


def test_rag_mode_local_selected(monkeypatch):
    monkeypatch.setenv("SANA_RAG_MODE", "LOCAL")
    assert config.get_rag_mode() == "local"


# 1) Default: seed davranışı korunur
def test_default_mode_uses_seed_retrieval(monkeypatch):
    monkeypatch.delenv("SANA_RAG_MODE", raising=False)
    retrieved = retrieve_for_query("crp nedir", "CRP", "Nedir?")
    assert retrieved
    assert all("medlineplus.gov" in rc.chunk.source_url for rc in retrieved)


def test_default_mode_explain_unchanged(monkeypatch):
    monkeypatch.delenv("SANA_RAG_MODE", raising=False)
    body = _explain("CRP nedir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert any("medlineplus.gov" in c["source_url"] for c in body["citations"])


# 2) local mode: store + LocalRetriever kullanılır
def test_local_mode_uses_store(local_db):
    retrieved = retrieve_for_query("crp nedir", "CRP", "Nedir?")
    assert retrieved
    assert all(rc.chunk.source_url.startswith(OFFICIAL_URL_PREFIX) for rc in retrieved)
    assert all(rc.chunk.lab_test == "CRP" for rc in retrieved)
    assert all(rc.chunk.chunk_id.startswith("crp-") for rc in retrieved)


# 3) Provider'a local CRP context'i gider
def test_local_mode_provider_receives_local_crp_context(local_db, recording_provider):
    body = _explain("CRP yüksek çıktı ne anlama gelir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert len(recording_provider.calls) == 1

    retrieved = recording_provider.calls[0]["retrieved"]
    assert retrieved
    top = retrieved[0].chunk
    assert top.lab_test == "CRP"
    assert top.section == "Yüksek ne anlama gelebilir?"
    assert top.source_url == LAB_SOURCE_BY_NAME["CRP"].medlineplus_url
    assert top.source_title == SOURCE_TITLE
    assert top.safety_level == "general"
    assert top.content  # içerik boş değil


# 4) DB boşsa: no_results, provider çağrılmaz
def test_local_mode_empty_db_no_results(tmp_path, monkeypatch, recording_provider):
    db = tmp_path / "empty.db"
    LocalRagStore(db_path=str(db))  # şema var, chunk yok
    monkeypatch.setenv("SANA_RAG_MODE", "local")
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(db))

    body = _explain("CRP nedir?", "CRP").json()
    assert body["response_type"] == "no_results"
    assert recording_provider.calls == []


# 5) DB dosyası yoksa: crash yok, dosya oluşturulmaz, provider çağrılmaz
def test_local_mode_missing_db_no_crash(tmp_path, monkeypatch, recording_provider):
    db = tmp_path / "does_not_exist.db"
    monkeypatch.setenv("SANA_RAG_MODE", "local")
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(db))

    r = _explain("CRP nedir?", "CRP")
    assert r.status_code == 200
    assert r.json()["response_type"] == "no_results"
    assert recording_provider.calls == []
    assert not db.exists()  # runtime sorgusu dosya OLUŞTURMAZ


# 6-7) Safety branchleri local modda da provider çağırmaz
def test_local_mode_safety_block_no_provider_call(local_db, recording_provider):
    body = _explain("B12 350 çıktı, ilaç alayım mı?", "B12").json()
    assert body["response_type"] == "safety_block"
    assert recording_provider.calls == []


def test_local_mode_chat_treatment_blocked(local_db, recording_provider):
    body = _chat("CRP yüksekliği nasıl tedavi edilir?").json()
    assert body["response_type"] == "safety_block"
    assert recording_provider.calls == []


# 8) /explain contract'ı local modda değişmez
def test_explain_contract_same_keys_in_both_modes(local_db, monkeypatch):
    local_body = _explain("CRP nedir?", "CRP").json()
    monkeypatch.setenv("SANA_RAG_MODE", "seed")
    seed_body = _explain("CRP nedir?", "CRP").json()

    assert set(local_body.keys()) == set(seed_body.keys())
    assert local_body["response_type"] == seed_body["response_type"] == "answer"
    for rc in local_body["retrieved_chunks"]:
        assert set(rc.keys()) == {"lab_test", "section", "source_title"}


# 9) /chat local modda çalışır, contract korunur
def test_chat_works_in_local_mode(local_db, recording_provider):
    body = _chat("Ferritin düşük çıktı ne anlama gelir?").json()
    assert body["response_type"] == "answer"
    assert body["lab_test"] == "Ferritin"
    assert "FAKE_CEVAP" in body["answer"]
    assert body["disclaimer"]
    assert any(c["source_url"].startswith(OFFICIAL_URL_PREFIX) for c in body["citations"])

    retrieved = recording_provider.calls[0]["retrieved"]
    assert all(rc.chunk.lab_test == "Ferritin" for rc in retrieved)


# 10) foundry_local + local mode birlikte çalışır (fake Foundry)
def test_foundry_local_with_local_rag_mode(local_db, monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("SANA_FOUNDRY_MODEL", "test-model")
    monkeypatch.setenv("SANA_FOUNDRY_BASE_URL", "http://127.0.0.1:5273/v1")

    captured = {}

    def _fake_ok(url, headers, payload, timeout):
        captured["payload"] = payload
        return {"choices": [{"message": {"content": "FOUNDRY_LOCAL_RAG_CEVABI"}}]}

    monkeypatch.setattr(fp, "_http_post_json", _fake_ok)

    body = _explain("Hemoglobin nedir?", "Hemoglobin").json()
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "foundry_local"
    assert "FOUNDRY_LOCAL_RAG_CEVABI" in body["answer"]

    # Prompt'a giden kaynak parçaları LOCAL store'dan gelmiş olmalı
    user_msg = captured["payload"]["messages"][1]["content"]
    assert "Kaynak parçaları" in user_msg
    assert SOURCE_TITLE in user_msg
    assert "Hemoglobin" in user_msg


# 11) Kaynak metadata response'ta korunur
def test_local_mode_citations_preserve_source_metadata(local_db, recording_provider):
    body = _explain("glukoz neden ölçülür?", "Glukoz").json()
    assert body["response_type"] == "answer"
    assert body["citations"]
    cite = body["citations"][0]
    assert cite["source_title"] == SOURCE_TITLE
    assert cite["source_url"] == LAB_SOURCE_BY_NAME["Glukoz"].medlineplus_url
    assert cite["section"]


# Cache: ingestion sonrası değişiklik yeniden yüklenir
def test_retriever_cache_refreshes_on_db_change(local_db, monkeypatch):
    first = retrieve_for_query("crp nedir", "CRP", "Nedir?")
    assert first

    # Store'a yeni içerik yaz (mtime/size değişir) -> cache tazelenmeli
    from app.data.seed_documents import Chunk

    store = LocalRagStore(db_path=str(local_db))
    store.upsert_chunks([
        Chunk(
            chunk_id="crp-ek-bilgi",
            lab_test="CRP",
            title="CRP - Ek bilgi",
            section="Nedir?",
            content="Yeni eklenen benzersiz ek açıklama metni tazelenme testi için.",
            source_title=SOURCE_TITLE,
            source_url=LAB_SOURCE_BY_NAME["CRP"].medlineplus_url,
            safety_level="general",
        )
    ])

    second = retrieve_for_query("tazelenme testi benzersiz", "CRP", "Nedir?")
    assert any(rc.chunk.chunk_id == "crp-ek-bilgi" for rc in second)


# Lab store'da yoksa boş -> no_results (parity)
def test_local_mode_lab_without_chunks_returns_empty(local_db):
    assert retrieve_for_query("bilinmeyen", "OlmayanLab", "Nedir?") == []
