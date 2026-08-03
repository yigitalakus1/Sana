"""S96 — Foundry Local provider testleri.

GERÇEK FOUNDRY / SDK / AĞ GEREKMEZ: SDK adapter'ı (_load_sdk_manager_cls) ve
ağ katmanı (_http_post_json) monkeypatch edilir.
"""

import pytest
from fastapi.testclient import TestClient

import app.services.llm.foundry_local_provider as fp
from app.core import constants as C
from app.core.config import FoundrySettings, get_foundry_settings, get_llm_settings
from app.main import app
from app.services.llm.foundry_local_provider import FoundryLocalProvider
from app.services.llm.openai_compatible_provider import (
    LLMConfigError,
    LLMProviderError,
)
from app.services.llm_provider import DummyLLMProvider, get_llm_provider
from app.services.normalization_service import normalize
from app.services.retrieval_service import retrieve

client = TestClient(app)


def _explain(question, lab_test=None):
    payload = {"question": question, "options": {"language": "tr"}}
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/explain", json=payload)


def _settings(model="test-foundry-model", base_url="http://127.0.0.1:5273/v1", timeout=30):
    return FoundrySettings(model=model, base_url=base_url, timeout_seconds=timeout)


# 1) Provider seçimi
def test_sana_provider_env_selects_foundry_local(monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    p = get_llm_provider()
    assert p.name == "foundry_local"
    assert isinstance(p, FoundryLocalProvider)


def test_sana_provider_takes_precedence_over_llm_provider(monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("LLM_PROVIDER", "ollama")
    assert get_llm_provider().name == "foundry_local"


# 2) Default değişmedi
def test_default_provider_is_still_dummy(monkeypatch):
    monkeypatch.delenv("SANA_PROVIDER", raising=False)
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    p = get_llm_provider()
    assert p.name == "dummy"
    assert isinstance(p, DummyLLMProvider)
    assert get_llm_settings().provider == "dummy"


def test_legacy_llm_provider_env_still_works(monkeypatch):
    monkeypatch.delenv("SANA_PROVIDER", raising=False)
    monkeypatch.setenv("LLM_PROVIDER", "foundry_local")
    assert get_llm_provider().name == "foundry_local"


# 3) API key istemez
def test_foundry_settings_have_no_api_key_field():
    assert "api_key" not in FoundrySettings.__dataclass_fields__


def test_generate_sends_no_authorization_header():
    captured = {}

    def _fake_ok(url, headers, payload, timeout):
        captured.update(url=url, headers=headers, payload=payload, timeout=timeout)
        return {"choices": [{"message": {"content": "Türkçe test cevap"}}]}

    provider = FoundryLocalProvider(settings=_settings(), post_fn=_fake_ok)
    retrieved = retrieve(normalize("CRP nedir?"), "CRP", C.SECTION_WHAT)
    answer = provider.generate(
        question="CRP nedir?", lab_test="CRP", intent="definition", retrieved=retrieved
    )

    assert answer == "Türkçe test cevap"
    assert "Authorization" not in captured["headers"]
    assert captured["url"] == "http://127.0.0.1:5273/v1/chat/completions"
    assert captured["payload"]["model"] == "test-foundry-model"
    assert [m["role"] for m in captured["payload"]["messages"]] == ["system", "user"]


# 4) SDK yokken import-time crash olmaz
def test_module_imports_and_instantiates_without_sdk(monkeypatch):
    monkeypatch.setattr(fp, "_load_sdk_manager_cls", lambda: None)
    provider = FoundryLocalProvider()  # örnekleme de güvenli olmalı
    assert provider.name == "foundry_local"


# 5) SDK yokken graceful, anlamlı hata
def test_missing_sdk_raises_helpful_config_error(monkeypatch):
    monkeypatch.setattr(fp, "_load_sdk_manager_cls", lambda: None)
    provider = FoundryLocalProvider(settings=_settings(base_url=""))
    with pytest.raises(LLMConfigError) as exc:
        provider.generate(question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[])
    assert "SANA_PROVIDER=dummy" in str(exc.value)


def test_missing_model_raises_config_error():
    provider = FoundryLocalProvider(settings=_settings(model="", base_url=""))
    with pytest.raises(LLMConfigError) as exc:
        provider.generate(question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[])
    assert "SANA_FOUNDRY_MODEL" in str(exc.value)


def test_sdk_runtime_failure_is_wrapped(monkeypatch):
    class _BrokenManager:
        def __init__(self, alias):
            raise RuntimeError("service not running; port=51234 secret-detail")

    monkeypatch.setattr(fp, "_load_sdk_manager_cls", lambda: _BrokenManager)
    provider = FoundryLocalProvider(settings=_settings(base_url=""))
    with pytest.raises(LLMProviderError) as exc:
        provider.generate(question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[])
    # Kullanıcıya güvenli mesaj; teknik detay sızmaz
    assert "secret-detail" not in str(exc.value)
    assert "Foundry Local" in str(exc.value)


def test_sdk_path_resolves_endpoint_and_model_id(monkeypatch):
    class _ModelInfo:
        id = "resolved-model-id"

    class _FakeManager:
        def __init__(self, alias):
            self.alias = alias
            self.endpoint = "http://127.0.0.1:59999/v1"

        def get_model_info(self, alias):
            return _ModelInfo()

    monkeypatch.setattr(fp, "_load_sdk_manager_cls", lambda: _FakeManager)
    captured = {}

    def _fake_ok(url, headers, payload, timeout):
        captured.update(url=url, payload=payload)
        return {"choices": [{"message": {"content": "ok"}}]}

    provider = FoundryLocalProvider(settings=_settings(base_url=""), post_fn=_fake_ok)
    provider.generate(question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[])
    assert captured["url"] == "http://127.0.0.1:59999/v1/chat/completions"
    assert captured["payload"]["model"] == "resolved-model-id"


# 6) Model adı env'den okunur
def test_model_read_from_env(monkeypatch):
    monkeypatch.setenv("SANA_FOUNDRY_MODEL", "env-model")
    monkeypatch.setenv("SANA_FOUNDRY_BASE_URL", "http://127.0.0.1:5273/v1")
    s = get_foundry_settings()
    assert s.model == "env-model"
    assert s.base_url == "http://127.0.0.1:5273/v1"


# Boş içerik güvenli hataya çevrilir
def test_empty_content_raises_provider_error():
    provider = FoundryLocalProvider(
        settings=_settings(),
        post_fn=lambda url, headers, payload, timeout: {
            "choices": [{"message": {"content": "  "}}]
        },
    )
    with pytest.raises(LLMProviderError):
        provider.generate(question="CRP nedir?", lab_test="CRP", intent="general", retrieved=[])


# 9) Safety/no-results branchlerinde provider çağrılmaz
def test_safety_query_does_not_call_foundry_provider(monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("SANA_FOUNDRY_MODEL", "test-model")
    monkeypatch.setenv("SANA_FOUNDRY_BASE_URL", "http://127.0.0.1:5273/v1")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("foundry provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(fp, "_http_post_json", _boom)

    body = _explain("B12 350 çıktı, ilaç alayım mı?", "B12").json()
    assert body["response_type"] == "safety_block"
    assert calls["n"] == 0


def test_no_results_query_does_not_call_foundry_provider(monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("SANA_FOUNDRY_MODEL", "test-model")
    monkeypatch.setenv("SANA_FOUNDRY_BASE_URL", "http://127.0.0.1:5273/v1")

    calls = {"n": 0}

    def _boom(url, headers, payload, timeout):
        calls["n"] += 1
        raise AssertionError("foundry provider ağ çağrısı yapılmamalı")

    monkeypatch.setattr(fp, "_http_post_json", _boom)

    body = _explain("Miyoglobin değerim ne anlama gelir?").json()
    assert body["response_type"] == "no_results"
    assert calls["n"] == 0


# /explain uçtan uca fake Foundry ile
def test_explain_uses_fake_foundry_provider(monkeypatch):
    monkeypatch.setenv("SANA_PROVIDER", "foundry_local")
    monkeypatch.setenv("SANA_FOUNDRY_MODEL", "test-model")
    monkeypatch.setenv("SANA_FOUNDRY_BASE_URL", "http://127.0.0.1:5273/v1")

    def _fake_ok(url, headers, payload, timeout):
        return {"choices": [{"message": {"content": "FOUNDRY_CEVABI: CRP iltihapla ilişkili olabilir."}}]}

    monkeypatch.setattr(fp, "_http_post_json", _fake_ok)

    body = _explain("CRP 13.5 mg/L çıktı", "CRP").json()
    assert body["response_type"] == "answer"
    assert body["llm_provider"] == "foundry_local"
    assert "FOUNDRY_CEVABI" in body["answer"]
    assert body["citations"]
    assert body["disclaimer"]
