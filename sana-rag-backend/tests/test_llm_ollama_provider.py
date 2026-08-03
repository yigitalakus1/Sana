"""Ollama provider testleri — GERÇEK AĞ YOK (monkeypatch)."""

import pytest
from fastapi.testclient import TestClient

import app.services.llm.ollama_provider as op
from app.core.config import OllamaSettings
from app.main import app
from app.services.llm.ollama_provider import OllamaProvider
from app.services.llm.source_content import combine_source_content
from app.services.llm.openai_compatible_provider import (
    LLMConfigError,
    LLMProviderError,
)
from app.services.llm_provider import DummyLLMProvider, get_llm_provider
from app.services.retrieval_service import retrieve
from app.services.normalization_service import normalize
from app.core import constants as C

client = TestClient(app)


def _explain(question, lab_test=None):
    payload = {"question": question, "options": {"language": "tr"}}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/explain", json=payload)


def test_env_default_is_dummy(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    p = get_llm_provider()
    assert p.name == "dummy"
    assert isinstance(p, DummyLLMProvider)


def test_env_selects_ollama(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")
    p = get_llm_provider()
    assert p.name == "ollama"
    assert isinstance(p, OllamaProvider)


def test_ollama_provider_parses_successful_response():
    calls = []

    def _fake_ok(url, headers, payload, timeout):
        calls.append((url, headers, payload, timeout))
        return {"message": {"content": "Türkçe test cevap"}}

    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=_fake_ok,
    )
    retrieved = retrieve(normalize("CRP nedir?"), "CRP", C.SECTION_WHAT)

    answer = provider.generate(
        question="CRP nedir?",
        lab_test="CRP",
        intent="definition",
        retrieved=retrieved,
        result_context={"raw_value": "13.5", "unit": "mg/L"},
    )

    assert answer == "Türkçe test cevap"
    assert len(calls) == 1
    url, headers, payload, timeout = calls[0]
    assert url == "http://127.0.0.1:11434/api/chat"
    assert headers["Content-Type"] == "application/json"
    assert timeout == 60


def test_ollama_payload_has_stream_false_and_messages():
    captured = {}

    def _fake_ok(url, headers, payload, timeout):
        captured["payload"] = payload
        return {"message": {"content": "ok"}}

    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://localhost:11434",
            timeout_seconds=12,
        ),
        post_fn=_fake_ok,
    )
    retrieved = retrieve(normalize("CRP 13.5 çıktı"), "CRP", C.SECTION_WHAT)

    provider.generate(
        question="CRP 13.5 çıktı",
        lab_test="CRP",
        intent="general",
        retrieved=retrieved,
        result_context={"raw_value": "13.5", "unit": None},
    )

    payload = captured["payload"]
    assert payload["model"] == "test-model"
    assert payload["stream"] is False
    assert payload["think"] is False
    assert payload["options"] == {
        "num_ctx": 2048,
        "num_predict": 256,
        "temperature": 0.2,
    }
    assert [m["role"] for m in payload["messages"]] == ["system", "user"]
    assert "Sana adlı sağlık okuryazarlığı" in payload["messages"][0]["content"]
    assert "CRP 13.5 çıktı" in payload["messages"][1]["content"]
    assert "13.5" in payload["messages"][1]["content"]
    assert "Kaynak parçaları" in payload["messages"][1]["content"]


def test_missing_ollama_model_raises_config_error():
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        )
    )
    with pytest.raises(LLMConfigError):
        provider.generate(
            question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[]
        )


def test_empty_ollama_content_raises_provider_error():
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {"message": {"content": "  "}},
    )
    with pytest.raises(LLMProviderError):
        provider.generate(
            question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[]
        )


def test_length_limited_response_drops_incomplete_last_sentence():
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {
            "message": {
                "content": "CRP genel bir iltihap göstergesidir. Yarım kalan açıklama"
            },
            "done_reason": "length",
        },
    )

    answer = provider.generate(
        question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[]
    )

    assert answer == "CRP genel bir iltihap göstergesidir."


def test_ollama_answer_drops_heading_and_limits_sentence_count():
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {
            "message": {
                "content": (
                    "CRP Nedir?\n\nBirinci cümle. İkinci cümle. Üçüncü cümle. "
                    "Dördüncü cümle. Beşinci cümle."
                )
            }
        },
    )

    answer = provider.generate(
        question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[]
    )

    assert answer == "Birinci cümle. İkinci cümle. Üçüncü cümle. Dördüncü cümle."


def test_ollama_language_leak_falls_back_to_backend_source():
    retrieved = retrieve(normalize("CRP nedir?"), "CRP", C.SECTION_WHAT)
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {
            "message": {"content": "CRP can indicate inflammation."}
        },
    )

    answer = provider.generate(
        question="CRP nedir?",
        lab_test="CRP",
        intent="general",
        retrieved=retrieved,
    )

    assert answer == combine_source_content(retrieved)


@pytest.mark.parametrize(
    "generated",
    [
        "Merhaba, ben SenSana. CRP hakkında bilgi verebilirim.",
        "CRP için normal aralık 3.9 ile 6.1 arasındadır.",
        "Kaynak: Sana Seed Medical Notes. CRP bir proteindir.",
    ],
)
def test_ollama_quality_artifacts_fall_back_to_backend_source(generated):
    retrieved = retrieve(normalize("CRP nedir?"), "CRP", C.SECTION_WHAT)
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {
            "message": {"content": generated}
        },
    )

    answer = provider.generate(
        question="CRP nedir?",
        lab_test="CRP",
        intent="general",
        retrieved=retrieved,
    )

    assert answer == combine_source_content(retrieved)


def test_real_ollama_metadata_enables_strict_vocabulary_grounding():
    retrieved = retrieve(normalize("CRP nedir?"), "CRP", C.SECTION_WHAT)
    provider = OllamaProvider(
        settings=OllamaSettings(
            model="test-model",
            base_url="http://127.0.0.1:11434",
            timeout_seconds=60,
        ),
        post_fn=lambda url, headers, payload, timeout: {
            "model": "test-model",
            "message": {
                "content": (
                    "CRP bir iltihap belirtecidir. Hastalığın ne kadar seriousi "
                    "olduğu hakkında bilgi verir."
                )
            },
        },
    )

    answer = provider.generate(
        question="CRP nedir?",
        lab_test="CRP",
        intent="general",
        retrieved=retrieved,
    )

    assert answer == combine_source_content(retrieved)


def test_safety_query_does_not_call_ollama_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("ollama provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(op, "_http_post_json", _boom)

    body = _explain("B12 350 çıktı, ilaç alayım mı?", "B12").json()
    assert body["response_type"] == "safety_block"
    assert calls["n"] == 0


def test_no_results_query_does_not_call_ollama_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("ollama provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(op, "_http_post_json", _boom)

    body = _explain("Miyoglobin değerim ne anlama gelir?").json()
    assert body["response_type"] == "no_results"
    assert calls["n"] == 0


def test_explain_uses_fake_ollama_provider(monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    monkeypatch.setenv("OLLAMA_MODEL", "test-model")
    monkeypatch.setenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

    def _fake_ok(url, headers, payload, timeout):
        return {"message": {"content": "OLLAMA_CEVABI: CRP iltihapla ilişkili olabilir."}}

    monkeypatch.setattr(op, "_http_post_json", _fake_ok)

    body = _explain("CRP 13.5 mg/L çıktı", "CRP").json()
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "ollama"
    assert "OLLAMA_CEVABI" in body["answer"]
    assert body["citations"]
    assert body["disclaimer"]
    for rc in body["retrieved_chunks"]:
        assert set(rc.keys()) == {"lab_test", "section", "source_title"}
