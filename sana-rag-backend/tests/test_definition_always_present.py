"""Tanım sorusu sorulduğunda cevap terimi HER ZAMAN açıklamalı.

Regresyon: Türk tahlil raporlarında değer/referans sütununda sık geçen
"Yüksek"/"Düşük" kelimeleri bölüm tespitini kaydırıyordu. Bu durumda yalnız
"Yüksek ne anlama gelebilir?" parçası getiriliyor ve cevapta tahlilin ne
olduğunu anlatan metin hiç bulunmuyordu.
"""

from app.core import constants as C
from app.models.schemas import QueryRequest
from app.services import rag_service


def _sections(question: str, lab_test: str = "Hemoglobin"):
    response = rag_service.process(QueryRequest(question=question, lab_test=lab_test))
    return [chunk.section for chunk in (response.retrieved_chunks or [])], response


def test_temiz_referansta_tanim_ve_amac_gelir():
    sections, response = _sections(
        "Hemoglobin 160 g/L çıktı. Rapor referans aralığı: 132 - 173. "
        "Bu tahlil nedir, neyi ölçer ve neden ölçülür?"
    )
    assert sections[0] == C.SECTION_WHAT
    assert C.SECTION_WHY in sections
    assert response.response_type == "answer"


def test_referansta_yuksek_kelimesi_gecse_de_tanim_gelir():
    sections, _ = _sections(
        "Hemoglobin 160 g/L çıktı. Rapor referans aralığı: Düşük <132, Yüksek >173. "
        "Bu tahlil nedir, neyi ölçer ve neden ölçülür?"
    )
    assert C.SECTION_WHAT in sections


def test_degerde_yuksek_bayragi_olsa_da_tanim_gelir():
    sections, _ = _sections(
        "Hemoglobin 160 Yüksek g/L çıktı. Rapor referans aralığı: 132 - 173. "
        "Bu tahlil nedir, neyi ölçer ve neden ölçülür?"
    )
    assert C.SECTION_WHAT in sections


def test_degerde_dusuk_bayragi_olsa_da_tanim_gelir():
    sections, _ = _sections(
        "Ferritin 8 Düşük ng/mL çıktı. Bu tahlil nedir, neyi ölçer ve neden ölçülür?",
        lab_test="Ferritin",
    )
    assert C.SECTION_WHAT in sections


def test_tanim_sorulmayan_yuksek_sorusunda_yalniz_yuksek_bolumu_kalir():
    """Kullanıcı gerçekten 'yüksekliği' sorduysa davranış değişmemeli."""
    sections, _ = _sections("Hemoglobin yüksekliği neye işaret eder?")
    assert sections == [C.SECTION_HIGH]


def test_tanim_ilk_sirada_kalmaz_birincil_bolum_korunur():
    """Yüksek sorusu + tanım isteğinde birincil bölüm yine yüksek olmalı."""
    sections, _ = _sections(
        "Hemoglobin 160 Yüksek g/L çıktı. Bu tahlil nedir?"
    )
    assert sections[0] == C.SECTION_HIGH
    assert sections[1] == C.SECTION_WHAT
