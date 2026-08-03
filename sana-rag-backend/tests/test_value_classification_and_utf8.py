"""Değer sınıflandırma filtresi + unit parsing + UTF-8 testleri.

GERÇEK AĞ YOK: LLM cevapları fake provider ile enjekte edilir.
"""

import pytest
from fastapi.testclient import TestClient

import app.services.chat_service as chat_service
import app.services.rag_service as rag_service
from app.core import constants as C
from app.main import app
from app.services.result_context_service import extract_result_context

client = TestClient(app)


class FakeProvider:
    """generate() çağrılarını kaydeden, sabit metin dönen fake provider."""

    name = "fake"

    def __init__(self, text: str):
        self.text = text
        self.calls = 0

    def generate(self, **kwargs):
        self.calls += 1
        return self.text


@pytest.fixture
def fake_llm(monkeypatch):
    def _install(text: str) -> FakeProvider:
        provider = FakeProvider(text)
        monkeypatch.setattr(rag_service, "get_llm_provider", lambda: provider)
        monkeypatch.setattr(chat_service, "get_llm_provider", lambda: provider)
        return provider
    return _install


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


# ============ A) Değer sınıflandırma filtresi ============

def test_normalden_yuksek_is_stripped(fake_llm):
    fake_llm("CRP 13.5 mg/L değeri normalden yüksek.")
    body = _explain("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert "normalden yüksek" not in body["answer"]
    # Güvenli sınıflandırmama metni gelmeli
    assert "sınıflandırılamaz" in body["answer"]
    assert "doktorunuz tarafından değerlendirilmelidir" in body["answer"]


def test_normaldir_is_stripped(fake_llm):
    fake_llm("Glukoz 92 mg/dL normaldir.")
    body = _explain("Glukoz 92 mg/dL çıktı ne anlama gelir?", "Glukoz").json()
    assert body["response_type"] == "answer"
    assert "normaldir" not in body["answer"]
    assert "sınıflandırılamaz" in body["answer"]


def test_various_classification_words_stripped(fake_llm):
    for bad in ("yüksektir", "düşük çıkmış", "referans üstünde", "sınırda"):
        fake_llm(f"CRP değeri {bad}.")
        body = _explain("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
        assert body["response_type"] == "answer"
        assert bad not in body["answer"], f"'{bad}' cevaptan temizlenmeliydi"
        assert "sınıflandırılamaz" in body["answer"]


def test_indirect_result_interpretation_is_stripped(fake_llm):
    bad = "CRP belirgin bir iltihap bulgusu göstermediğini düşündürür."
    fake_llm(bad)
    body = _explain("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert "bulgusu göstermediğini" not in body["answer"]
    assert "sınıflandırılamaz" in body["answer"]


def test_chat_classification_stripped(fake_llm):
    fake_llm("CRP 13.5 düşüktür.")
    body = _chat("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert "düşüktür" not in body["answer"]
    assert "sınıflandırılamaz" in body["answer"]


def test_clean_answer_passes_through_unchanged(fake_llm):
    """Temiz içerik korunur; eksik referans aralığı kullanıcıya açıklanır."""
    clean = "CRP, iltihaplanma süreçleriyle ilişkili bir belirteçtir."
    fake_llm(clean)
    body = _explain("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
    assert clean in body["answer"]
    assert "referans aralığı" in body["answer"]
    assert "sınıflandırılamaz" in body["answer"]


def test_chat_clean_numeric_answer_explains_missing_reference_range(fake_llm):
    fake_llm("ALT karaciğerde bulunan bir enzimdir.")

    body = _chat("ALT 25 U/L çıktı", "ALT").json()

    assert body["response_type"] == "answer"
    assert "referans aralığı" in body["answer"]
    assert "sınıflandırılamaz" in body["answer"]


def test_no_value_means_no_filter(fake_llm):
    """Sayısal değer yokken (result_context None) eğitsel cevap korunur."""
    fake_llm("Yüksek CRP genellikle iltihaplanmayı düşündürür.")
    body = _explain("CRP yüksekliği ne anlama gelebilir?", "CRP").json()
    assert body["response_type"] == "answer"
    assert body["result_context"] is None
    # Değer bağlamı olmadığı için filtre devreye girmez; eğitsel içerik kalır
    assert "Yüksek CRP" in body["answer"]
    assert "sınıflandırılamaz" not in body["answer"]


# ============ B) Unit parsing ============

@pytest.mark.parametrize("question,expected", [
    ("CRP 13.5 mg/L çıktı", "mg/L"),
    ("Glukoz 92 mg/dL çıktı", "mg/dL"),
    ("Hemoglobin 13,2 g/dL", "g/dL"),
    ("Ferritin 45 ng/mL", "ng/mL"),
    ("B12 350 pg/mL", "pg/mL"),
    ("TSH 2.1 mIU/L", "mIU/L"),
    ("ALT 30 U/L", "U/L"),
    ("D vitamini 25 IU/L", "IU/L"),
    ("Kortizol 15 µg/dL", "µg/dL"),
    ("Kortizol 15 ug/dL", "ug/dL"),
    ("Hematokrit 40 %", "%"),
    ("Lökosit 7.5 10^3/µL", "10^3/µL"),
    ("Lökosit 7.5 10^3/uL", "10^3/uL"),
])
def test_unit_extraction(question, expected):
    rc = extract_result_context(question)
    assert rc is not None
    assert rc["unit"] == expected


def test_unit_none_when_absent():
    rc = extract_result_context("CRP 13.5 çıktı")
    assert rc is not None
    assert rc["unit"] is None
    assert rc["raw_value"] == "13.5"


def test_unit_via_explain_response():
    body = _explain("CRP 13.5 mg/L çıktı ne anlama gelir?", "CRP").json()
    assert body["result_context"]["unit"] == "mg/L"
    assert body["result_context"]["raw_value"] == "13.5"


def test_raw_value_excludes_unit():
    rc = extract_result_context("Glukoz 92 mg/dL çıktı")
    assert rc["raw_value"] == "92"
    assert rc["value"] == 92.0
    assert rc["unit"] == "mg/dL"


def test_explicit_report_reference_range_is_parsed_and_classified():
    rc = extract_result_context(
        "CRP 13.5 mg/L çıktı. Rapor referans aralığı: 0 - 5."
    )

    assert rc["reference_range"] == "0 - 5"
    assert rc["interpretation"] == "high"


def test_unlabeled_numbers_are_not_used_as_reference_range():
    rc = extract_result_context("CRP 13.5 mg/L çıktı, 2 gün önce ölçüldü")

    assert rc["reference_range"] is None
    assert rc["interpretation"] is None


# ============ C) UTF-8 / Türkçe karakter ============

def test_turkish_chars_intact_in_response(fake_llm):
    fake_llm("CRP değeri tek başına tanı koydurmaz; sonuçlarınızı doktorunuzla değerlendirin.")
    r = _explain("CRP nedir?", "CRP")
    # Ham byte'lar geçerli UTF-8 olmalı ve Türkçe kelimeleri içermeli
    decoded = r.content.decode("utf-8")
    for word in ("değeri", "tanı", "sonuçlarınızı", "değerlendirin"):
        assert word in decoded
    body = r.json()
    for word in ("değeri", "tanı", "sonuçlarınızı", "değerlendirin"):
        assert word in body["answer"]


def test_content_type_is_json(fake_llm):
    fake_llm("CRP değeri tek başına tanı koydurmaz.")
    r = _explain("CRP nedir?", "CRP")
    assert r.headers["content-type"].startswith("application/json")


def test_disclaimer_turkish_intact():
    r = _explain("CRP nedir?", "CRP")
    body = r.json()
    # Sabit disclaimer Türkçe karakterlerini korumalı
    assert "değerlendiriniz" in body["disclaimer"]


# ============ D) Safety (provider çağrılmaz) ============

def test_medication_safety_block_no_provider_call(fake_llm):
    provider = fake_llm("BU CEVAP DÖNMEMELİ")
    body = _chat("B12 350 çıktı, ilaç alayım mı?", "B12").json()
    assert body["response_type"] == "safety_block"
    assert provider.calls == 0
    assert "BU CEVAP" not in body["answer"]


def test_medication_safety_block_explain_no_provider_call(fake_llm):
    provider = fake_llm("BU CEVAP DÖNMEMELİ")
    body = _explain("B12 350 çıktı, ilaç alayım mı?", "B12").json()
    assert body["response_type"] == "safety_block"
    assert provider.calls == 0
