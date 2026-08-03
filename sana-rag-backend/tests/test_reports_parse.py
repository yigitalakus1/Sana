import json
import base64

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def post(text):
    return client.post("/reports/parse", json={"text": text})


def test_empty_text_returns_400():
    r = post("")
    assert r.status_code == 400


def test_unsupported_text_no_results():
    r = post("lorem ipsum dolor sit amet")
    assert r.status_code == 200
    body = r.json()
    assert body["parser_status"] == "no_results"
    assert body["results"] == []
    assert body["disclaimer"]


def test_crp_with_unit():
    r = post("CRP: 13.5 mg/L")
    assert r.status_code == 200
    body = r.json()
    assert body["parser_status"] == "parsed"
    res = body["results"][0]
    assert res["lab_test"] == "CRP"
    assert res["raw_value"] == "13.5"
    assert res["value"] == 13.5
    assert res["unit"] == "mg/L"


def test_crp_synonym_comma_value():
    r = post("C reaktif protein 13,5")
    body = r.json()
    res = body["results"][0]
    assert res["lab_test"] == "CRP"
    assert res["value"] == 13.5


def test_b12_name_digit_not_value():
    r = post("B12 nedir?")
    body = r.json()
    # B12'nin "12"si değer sanılmaz -> değer yok -> no_results
    assert body["parser_status"] == "no_results"
    assert body["results"] == []


def test_b12_with_value_and_unit():
    r = post("B12 350 pg/mL")
    body = r.json()
    res = body["results"][0]
    assert res["lab_test"] == "B12"
    assert res["value"] == 350.0
    assert res["unit"] == "pg/mL"


def test_multi_line_at_least_three():
    text = "CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nFerritin: 8 ng/mL"
    r = post(text)
    body = r.json()
    assert body["parser_status"] == "parsed"
    assert len(body["results"]) >= 3
    labs = {res["lab_test"] for res in body["results"]}
    assert {"CRP", "Glukoz", "Ferritin"} <= labs


def test_multi_line_report_supports_new_lab_values_without_interpretation():
    text = (
        "TSH 2.1 mIU/L\n"
        "Kreatinin 0.9 mg/dL\n"
        "ALT 25 U/L\n"
        "AST 22 U/L\n"
        "PLT 250"
    )
    body = post(text).json()
    assert body["parser_status"] == "parsed"
    assert {result["lab_test"] for result in body["results"]} == {
        "TSH", "Kreatinin", "ALT", "AST", "Trombosit",
    }
    assert all(result["interpretation"] is None for result in body["results"])
    assert all(result["reference_range"] is None for result in body["results"])


def test_public_has_no_internal_fields():
    body = post("CRP: 13.5 mg/L").json()
    res = body["results"][0]
    assert "chunk_id" not in res
    assert "content" not in res
    assert "score" not in res
    blob = json.dumps(body)
    assert "chunk_id" not in blob
    assert "content" not in blob
    assert "score" not in blob


def test_interpretation_and_reference_range_null():
    text = "CRP: 13.5 mg/L\nGlukoz 92 mg/dL"
    body = post(text).json()
    for res in body["results"]:
        assert res["interpretation"] is None
        assert res["reference_range"] is None


def test_pdf_report_uses_existing_deterministic_parser(monkeypatch):
    monkeypatch.setattr(
        "app.services.pdf_report_service.extract_pdf_text",
        lambda **_: "CRP: 13.5 mg/L\nGlukoz 92 mg/dL",
    )

    response = client.post(
        "/reports/parse-pdf",
        json={"file_name": "rapor.pdf", "content_base64": "ZmFrZQ=="},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["parser_status"] == "parsed"
    assert {item["lab_test"] for item in body["results"]} == {"CRP", "Glukoz"}
    assert all(item["interpretation"] is None for item in body["results"])


def test_scanned_pdf_uses_local_ocr_text_without_network(monkeypatch):
    monkeypatch.setattr(
        "app.services.pdf_report_service._extract_ocr_text",
        lambda _reader: "AFP 2.3 ng/mL",
    )

    class FakePage:
        def extract_text(self):
            return ""

    class FakeReader:
        is_encrypted = False
        pages = [FakePage()]

    monkeypatch.setattr("pypdf.PdfReader", lambda *_args, **_kwargs: FakeReader())
    response = client.post(
        "/reports/parse-pdf",
        json={
            "file_name": "tarama.pdf",
            "content_base64": base64.b64encode(b"%PDF-fake").decode("ascii"),
        },
    )

    assert response.status_code == 200
    assert response.json()["results"][0]["lab_test"] == "AFP"


def test_pdf_report_rejects_non_pdf_content():
    response = client.post(
        "/reports/parse-pdf",
        json={
            "file_name": "rapor.pdf",
            "content_base64": base64.b64encode(b"not a pdf").decode("ascii"),
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Seçilen dosya geçerli bir PDF değil."


def test_pdf_report_rejects_invalid_base64():
    response = client.post(
        "/reports/parse-pdf",
        json={"file_name": "rapor.pdf", "content_base64": "%%%"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "PDF dosyası okunamadı."


def test_pdf_style_multiline_afp_value_unit_and_range_are_parsed():
    body = post("AFP\n2.3\nng/mL\n0.0 - 8.0").json()

    assert body["parser_status"] == "parsed"
    assert body["results"] == [
        {
            "lab_test": "AFP",
            "matched_term": "afp",
            "raw_value": "2.3",
            "value": 2.3,
            "unit": "ng/mL",
            "reference_range": "0.0 - 8.0",
            "interpretation": "normal",
        }
    ]


def test_multiline_reference_range_is_not_mistaken_for_result():
    body = post("AFP\n0.0 - 8.0").json()

    assert body["parser_status"] == "no_results"
    assert body["results"] == []


def test_same_line_bounded_reference_range_is_extracted_and_classified():
    result = post("CRP 13.5 mg/L Referans: 0 - 5").json()["results"][0]

    assert result["reference_range"] == "0 - 5"
    assert result["interpretation"] == "high"


def test_same_line_parenthesized_decimal_comma_range_is_supported():
    result = post("TSH 2,1 mIU/L (0,27–4,20)").json()["results"][0]

    assert result["reference_range"] == "0,27 - 4,20"
    assert result["interpretation"] == "normal"


def test_labeled_limit_reference_range_is_supported():
    result = post("CRP 3 mg/L\nReferans Aralığı: < 5").json()["results"][0]

    assert result["reference_range"] == "< 5"
    assert result["interpretation"] == "normal"


def test_value_outside_lower_limit_is_classified_low():
    result = post("HDL Kolesterol 35 mg/dL Referans: >= 40").json()["results"][0]

    assert result["reference_range"] == ">= 40"
    assert result["interpretation"] == "low"


def test_ambiguous_multiple_ranges_are_not_guessed():
    result = post(
        "Ferritin 20 ng/mL Referans: kadın 10-120 erkek 20-250"
    ).json()["results"][0]

    assert result["reference_range"] is None
    assert result["interpretation"] is None


def test_next_result_line_range_is_not_attached_to_previous_test():
    results = post("ALT 25 U/L\nAST 60 U/L 0-40").json()["results"]
    by_lab = {item["lab_test"]: item for item in results}

    assert by_lab["ALT"]["reference_range"] is None
    assert by_lab["AST"]["reference_range"] == "0 - 40"


def test_multiline_next_result_range_is_not_attached_to_previous_test():
    results = post("ALT 25 U/L\nAST\n60\nU/L\n0-40").json()["results"]
    by_lab = {item["lab_test"]: item for item in results}

    assert by_lab["ALT"]["reference_range"] is None
    assert by_lab["AST"]["reference_range"] == "0 - 40"


def test_reversed_reference_range_is_rejected():
    result = post("CRP 3 mg/L Referans: 5-0").json()["results"][0]

    assert result["reference_range"] is None
    assert result["interpretation"] is None
