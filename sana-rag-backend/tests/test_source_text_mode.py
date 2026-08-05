"""`use_source_text` açıkken model çağrılmaz, onaylı kaynak metni sunulur."""

import pytest

from app.core import constants as C
from app.models.schemas import QueryOptions, QueryRequest
from app.services import rag_service
from app.services.llm.source_content import combine_source_content


class _ExplodingProvider:
    """Çağrılırsa test patlar: kaynak modunda model kullanılmamalı."""

    name = "patlayan"

    def generate(self, **kwargs):  # noqa: ANN003
        raise AssertionError("Kaynak metin modunda LLM çağrılmamalı.")


@pytest.fixture
def exploding_provider(monkeypatch):
    provider = _ExplodingProvider()
    monkeypatch.setattr(rag_service, "get_llm_provider", lambda: provider)
    return provider


def _ask(use_source_text: bool):
    return rag_service.process(
        QueryRequest(
            question="Hemoglobin nedir?",
            lab_test="Hemoglobin",
            options=QueryOptions(use_source_text=use_source_text),
        )
    )


def test_kaynak_modunda_model_cagrilmaz(exploding_provider):
    response = _ask(True)

    assert response.response_type == "answer"
    assert response.answer.strip()
    assert response.llm_provider == C.PROVIDER_SOURCE


def test_kaynak_modunda_cevap_onayli_metinden_gelir(exploding_provider):
    response = _ask(True)

    normalized = rag_service.normalize("Hemoglobin nedir?")
    retrieved = rag_service._retrieve_explanation_context(
        normalized, "Hemoglobin", C.SECTION_WHAT
    )
    expected = combine_source_content(retrieved)

    # Güvenlik filtreleri metne ek yapabilir; kaynak içerik cevapta yer almalı.
    assert expected.split(".")[0].strip() in response.answer


def test_kaynak_modunda_kaynak_ve_disclaimer_korunur(exploding_provider):
    response = _ask(True)

    assert response.citations
    assert response.disclaimer
    assert response.doctor_questions is not None


def test_varsayilan_kapali_oldugu_icin_model_yolu_kullanilir():
    """Seçenek verilmezse davranış değişmemeli (geriye uyumluluk)."""
    response = rag_service.process(
        QueryRequest(question="Hemoglobin nedir?", lab_test="Hemoglobin")
    )
    assert response.llm_provider != C.PROVIDER_SOURCE


def test_kaynak_modu_guvenlik_blogunu_atlamaz(exploding_provider):
    """İlaç/doz sorusu kaynak modunda da bloklanır ve model çağrılmaz."""
    response = rag_service.process(
        QueryRequest(
            question="Hangi antibiyotiği kaç doz kullanmalıyım?",
            options=QueryOptions(use_source_text=True),
        )
    )
    assert response.response_type == "safety_block"
