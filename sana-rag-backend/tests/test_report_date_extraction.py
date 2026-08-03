"""Rapor tarihi çıkarımı: yalnız etiketli ve güvenli tarihler kabul edilir."""

from datetime import date

from app.services.report_parse_service import extract_report_date, parse_report

TODAY = date(2026, 7, 27)


def test_etiketli_tarih_okunur():
    text = "Rapor Tarihi: 03.02.2026\nCRP 13.5 mg/L"
    assert extract_report_date(text, today=TODAY) == "2026-02-03"


def test_buyuk_harfli_turkce_etiket_okunur():
    # "TARİH" -> turkish_lower ile "tarih"; standart lower() bunu bozar.
    text = "RAPOR TARİHİ : 15/06/2026"
    assert extract_report_date(text, today=TODAY) == "2026-06-15"


def test_iso_bicimi_okunur():
    assert extract_report_date("Onay Tarihi 2026-01-09", today=TODAY) == "2026-01-09"


def test_dogum_tarihi_rapor_tarihi_sayilmaz():
    text = "Doğum Tarihi: 12.05.1980\nCRP 13.5 mg/L"
    assert extract_report_date(text, today=TODAY) is None


def test_dogum_tarihi_varken_rapor_tarihi_secilir():
    text = "Doğum Tarihi: 12.05.1980\nRapor Tarihi: 03.02.2026"
    assert extract_report_date(text, today=TODAY) == "2026-02-03"


def test_etiketsiz_tarih_alinmaz():
    assert extract_report_date("03.02.2026\nCRP 13.5 mg/L", today=TODAY) is None


def test_gelecek_tarih_alinmaz():
    assert extract_report_date("Rapor Tarihi: 01.01.2030", today=TODAY) is None


def test_gecersiz_takvim_tarihi_alinmaz():
    assert extract_report_date("Rapor Tarihi: 31.02.2026", today=TODAY) is None


def test_cok_eski_tarih_alinmaz():
    assert extract_report_date("Rapor Tarihi: 05.05.1980", today=TODAY) is None


def test_oncelik_rapor_tarihinde():
    text = "Numune Tarihi: 01.02.2026\nRapor Tarihi: 03.02.2026"
    assert extract_report_date(text, today=TODAY) == "2026-02-03"


def test_tarih_yoksa_none():
    assert extract_report_date("CRP 13.5 mg/L", today=TODAY) is None


def test_parse_report_report_date_alanini_dondurur():
    parsed = parse_report("Rapor Tarihi: 03.02.2026\nCRP 13.5 mg/L")
    assert parsed["report_date"] == "2026-02-03"
    assert parsed["parser_status"] == "parsed"
    assert parsed["results"]


def test_parse_report_tarihsiz_metinde_none_dondurur():
    parsed = parse_report("CRP 13.5 mg/L")
    assert parsed["report_date"] is None
    assert parsed["parser_status"] == "parsed"
