"""LLM provider factory testleri (gerçek LLM yok; seam davranışını kilitler)."""

from fastapi.testclient import TestClient

from app.main import app
from app.services.llm_provider import DummyLLMProvider, get_llm_provider

client = TestClient(app)


def test_default_provider_is_dummy(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    p = get_llm_provider()
    assert p.name == "dummy"
    assert isinstance(p, DummyLLMProvider)


def test_explicit_dummy_provider():
    assert get_llm_provider("dummy").name == "dummy"


def test_unknown_provider_falls_back_to_dummy():
    # DECISIONS §7/§13: demo asla kırılmaz -> bilinmeyen ad güvenli şekilde dummy'ye düşer
    assert get_llm_provider("foundry").name == "dummy"
    assert get_llm_provider("nonexistent-xyz").name == "dummy"


def test_explain_reports_dummy_provider(monkeypatch):
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    body = client.post(
        "/explain",
        json={"question": "CRP nedir?", "lab_test": "CRP", "options": {"language": "tr"}},
    ).json()
    assert body["llm_provider"] == "dummy"
