"""Section-aware /explain regresyon testleri.

Farklı bölüm soruları farklı section chunk'ı seçmeli ve aynı cevabı dönmemeli.
(/query DEĞİL, /explain test edilir.)
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def explain(question, lab_test="CRP"):
    return client.post(
        "/explain",
        json={"question": question, "lab_test": lab_test, "options": {"language": "tr"}},
    ).json()


def top_section(body):
    chunks = body.get("retrieved_chunks") or []
    return chunks[0]["section"] if chunks else None


def sections(body):
    return [c["section"] for c in (body.get("retrieved_chunks") or [])]


def test_section_nedir():
    b = explain("CRP nedir?")
    assert b["response_type"] == "answer"
    assert b["answer"]
    assert top_section(b) == "Nedir?" or "Nedir?" in sections(b)


def test_report_card_question_returns_specific_definition_content():
    body = explain(
        "Hemoglobin 160 g/L çıktı. Rapor referans aralığı: 132 - 173. "
        "Bu tahlil nedir, neyi ölçer ve neden ölçülür? "
        "Sonucu yalnızca genel bilgi olarak açıkla.",
        lab_test="Hemoglobin",
    )

    assert top_section(body) == "Nedir?"
    assert "oksijeni vücuda taşıyan" in body["answer"]
    assert "tam kan sayımının bir parçası" in body["answer"]
    assert "Değeriniz referans aralığının dışındaysa" not in body["answer"]


def test_section_neden_olculur_differs_from_nedir():
    nedir = explain("CRP nedir?")
    neden = explain("CRP neden ölçülür?")
    assert top_section(neden) == "Neden ölçülür?"
    # Aynı "Nedir?" cevabı dönmemeli
    assert neden["answer"] != nedir["answer"]


def test_section_yuksek():
    b = explain("CRP yüksekliği ne anlama gelebilir?")
    assert top_section(b) == "Yüksek ne anlama gelebilir?"


def test_section_dusuk():
    b = explain("CRP düşüklüğü ne anlama gelebilir?")
    assert top_section(b) == "Düşük ne anlama gelebilir?"


def test_section_ne_zaman_doktora():
    b = explain("CRP sonucunda ne zaman doktora danışılmalı?")
    assert top_section(b) == "Ne zaman doktora danışılmalı?"


def test_sections_are_not_all_identical():
    answers = {
        explain("CRP nedir?")["answer"],
        explain("CRP neden ölçülür?")["answer"],
        explain("CRP yüksekliği ne anlama gelebilir?")["answer"],
        explain("CRP düşüklüğü ne anlama gelebilir?")["answer"],
    }
    # En az 3 farklı cevap olmalı (hepsi aynı "Nedir?" değil)
    assert len(answers) >= 3
