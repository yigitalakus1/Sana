"""openai_compatible provider testleri — GERÇEK AĞ YOK (monkeypatch)."""

import pytest
from fastapi.testclient import TestClient

import app.services.llm.openai_compatible_provider as ocp
from app.core.config import LLMSettings
from app.main import app
from app.services.llm.openai_compatible_provider import (
    LLMConfigError,
    OpenAICompatibleProvider,
)
from app.services.llm_provider import get_llm_provider

client = TestClient(app)


def _fake_ok(url, headers, payload, timeout):
    return {
        "choices": [
            {"message": {"content": "SAHTE_LLM_CEVABI: CRP inflamasyonla ilişkili olabilir."}}
        ]
    }


def _explain(question, lab_test=None):
    payload = {"question": question, "options": {"language": "tr"}}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/explain", json=payload)


def test_env_default_is_dummy(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    assert get_llm_provider().name == "dummy"


def test_env_selects_openai_compatible(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "openai_compatible")
    p = get_llm_provider()
    assert p.name == "openai_compatible"
    assert isinstance(p, OpenAICompatibleProvider)


def test_missing_api_key_raises_config_error():
    # Import/örnekleme patlamaz; hata yalnız generate() sırasında yükselir.
    settings = LLMSettings(
        provider="openai_compatible",
        model="m",
        api_key="",
        base_url="http://example.invalid/v1",
        timeout_seconds=5,
    )
    provider = OpenAICompatibleProvider(settings=settings)
    with pytest.raises(LLMConfigError):
        provider.generate(
            question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[]
        )


def test_explain_uses_provider_answer(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "openai_compatible")
    monkeypatch.setenv("LLM_MODEL", "test-model")
    monkeypatch.setenv("LLM_API_KEY", "sk-test-secret")
    monkeypatch.setenv("LLM_BASE_URL", "http://example.invalid/v1")
    monkeypatch.setattr(ocp, "_http_post_json", _fake_ok)

    body = _explain("CRP 13.5 mg/L çıktı", "CRP").json()
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "openai_compatible"
    assert "SAHTE_LLM_CEVABI" in body["answer"]
    # Kaynaklar backend seed'inden gelir (LLM uydurmaz)
    assert body["citations"]
    # Contract korunur: retrieved_chunks içinde content/chunk_id/score YOK
    for rc in body["retrieved_chunks"]:
        assert set(rc.keys()) == {"lab_test", "section", "source_title"}
    # Secret answer'a sızmaz
    assert "sk-test-secret" not in body["answer"]


def test_safety_block_does_not_call_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "openai_compatible")
    monkeypatch.setenv("LLM_MODEL", "m")
    monkeypatch.setenv("LLM_API_KEY", "sk-test")
    monkeypatch.setenv("LLM_BASE_URL", "http://example.invalid/v1")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(ocp, "_http_post_json", _boom)

    body = _explain("CRP yüksekse hangi antibiyotiği almalıyım?").json()
    assert body["response_type"] == "safety_block"
    assert calls["n"] == 0


def test_no_results_does_not_call_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "openai_compatible")
    monkeypatch.setenv("LLM_MODEL", "m")
    monkeypatch.setenv("LLM_API_KEY", "sk-test")
    monkeypatch.setenv("LLM_BASE_URL", "http://example.invalid/v1")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(ocp, "_http_post_json", _boom)

    body = _explain("Miyoglobin değerim ne anlama gelir?").json()
    assert body["response_type"] == "no_results"
    assert calls["n"] == 0


def test_explain_missing_key_returns_controlled_error(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "openai_compatible")
    monkeypatch.delenv("LLM_API_KEY", raising=False)
    monkeypatch.setenv("LLM_MODEL", "m")
    monkeypatch.setenv("LLM_BASE_URL", "http://example.invalid/v1")

    r = _explain("CRP 13.5 çıktı", "CRP")
    assert r.status_code == 500
    body = r.json()
    assert body["response_type"] == "error"
    assert body["error"]["code"] == "INTERNAL_ERROR"
    # Secret/teknik detay kullanıcıya sızmaz
    blob = str(body).lower()
    assert "api_key" not in blob
    assert "bearer" not in blob
    assert body["disclaimer"]
