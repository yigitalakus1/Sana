"""POST /chat endpoint testleri — gerçek ağ/Ollama çağrısı yok."""

from fastapi.testclient import TestClient

import app.services.llm.ollama_provider as op
from app.main import app

client = TestClient(app)


def _chat(messages, lab_test=None, include_sources=True):
    payload = {"messages": messages, "include_sources": include_sources}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/chat", json=payload)


def test_chat_crp_simple_answer(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    r = _chat(
        [{"role": "user", "content": "CRP 13.5 çıktı ne anlama gelir?"}],
        lab_test="CRP",
    )
    body = r.json()
    assert r.status_code == 200
    assert body["response_type"] == "answer"
    assert body["lab_test"] == "CRP"
    assert body["citations"]
    assert body["retrieved_chunks"]
    assert body["disclaimer"]


def test_chat_dummy_provider_returns_seed_answer(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    body = _chat([{"role": "user", "content": "CRP nedir?"}], lab_test="CRP").json()
    assert body["llm_provider"] == "dummy"
    assert "CRP, karaciğerde üretilen" in body["answer"]


def test_chat_ollama_fake_transport_answer(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")

    calls = {"n": 0}

    def _fake_ok(url, headers, payload, timeout):
        calls["n"] += 1
        assert url == "http://127.0.0.1:11434/api/chat"
        assert payload["stream"] is False
        assert [m["role"] for m in payload["messages"]] == ["system", "user"]
        assert "kontrollü sohbet asistanısın" in payload["messages"][0]["content"]
        assert "Kısa mesaj geçmişi" in payload["messages"][1]["content"]
        return {"message": {"content": "Yerel modelden Türkçe cevap"}}

    monkeypatch.setattr(op, "_http_post_json", _fake_ok)

    body = _chat(
        [
            {"role": "user", "content": "Merhaba"},
            {"role": "assistant", "content": "Merhaba, hangi tahlili açıklayayım?"},
            {"role": "user", "content": "CRP 13.5 çıktı ne anlama gelir?"},
        ],
        lab_test="CRP",
    ).json()

    assert calls["n"] == 1
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "ollama"
    assert "Yerel modelden Türkçe cevap" in body["answer"]
    assert body["citations"]


def test_chat_safety_query_does_not_call_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("provider çağrılmamalı")

    monkeypatch.setattr(op, "_http_post_json", _boom)

    body = _chat(
        [{"role": "user", "content": "B12 350 çıktı, ilaç alayım mı?"}],
        lab_test="B12",
    ).json()
    assert body["response_type"] == "safety_block"
    assert calls["n"] == 0


def test_chat_unknown_general_medical_question_is_bounded(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("genel soru provider'a gitmemeli")

    monkeypatch.setattr(op, "_http_post_json", _boom)

    body = _chat([{"role": "user", "content": "Bugün başım ağrıyor ne yapayım?"}]).json()
    assert body["response_type"] == "no_results"
    assert "tahlil adı veya sonucu" in body["answer"]
    assert calls["n"] == 0


def test_chat_public_contract_has_no_internal_retrieval_fields(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    body = _chat([{"role": "user", "content": "CRP nedir?"}], lab_test="CRP").json()
    assert body["response_type"] == "answer"
    assert body["citations"]
    assert body["retrieved_chunks"]
    for rc in body["retrieved_chunks"]:
        assert set(rc.keys()) == {"lab_test", "section", "source_title"}
        assert "content" not in rc
        assert "chunk_id" not in rc
        assert "score" not in rc
    blob = str(body["citations"]).lower()
    assert "chunk_id" not in blob
    assert "score" not in blob


def test_chat_empty_messages_returns_400():
    r = _chat([])
    body = r.json()
    assert r.status_code == 400
    assert body["response_type"] == "error"


def test_chat_without_user_message_returns_400():
    r = _chat([{"role": "assistant", "content": "Size nasıl yardımcı olabilirim?"}])
    body = r.json()
    assert r.status_code == 400
    assert body["response_type"] == "error"


def test_query_remains_deprecated():
    assert app.openapi()["paths"]["/query"]["post"].get("deprecated") is True
