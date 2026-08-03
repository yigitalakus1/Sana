from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def post(question, lab_test=None, profile=None, language="tr"):
    payload = {
        "question": question,
        "options": {"language": language, "include_sources": True, "include_doctor_questions": True},
    }
    if lab_test is not None:
        payload["lab_test"] = lab_test
    if profile is not None:
        payload["profile"] = profile
    return client.post("/query", json=payload)


def test_empty_question_validation_error():
    r = post("")
    body = r.json()
    assert r.status_code == 400
    assert body["response_type"] == "error"
    assert body["error"]["code"] == "VALIDATION_ERROR"


def test_unsupported_language_error():
    r = post("CRP nedir?", language="en")
    body = r.json()
    assert r.status_code == 400
    assert body["response_type"] == "error"
    assert body["error"]["code"] == "UNSUPPORTED_LANGUAGE"


def test_crp_definition_answer():
    r = post("CRP nedir?", lab_test="CRP")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "answer"
    assert body["confidence"] > 0
    assert any("c-reactive-protein" in c["source_url"] for c in body["citations"])
    assert body["disclaimer"]


def test_synonym_iltihap_maps_to_crp():
    r = post("İltihap değerim yüksek çıkmış, bu ne demek?")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "answer"
    assert any("c-reactive-protein" in c["source_url"] for c in body["citations"])


def test_synonym_aclik_sekeri_maps_to_glukoz():
    r = post("Açlık şekerim yüksek, ne anlama gelir?")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "answer"
    assert any("blood-glucose" in c["source_url"] for c in body["citations"])


def test_unknown_value_no_results():
    r = post("Miyoglobin değerim ne anlama gelir?")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "no_results"
    assert body["confidence"] == 0.0
    assert body["citations"] == []


def test_citation_dedup_single_source():
    # Aynı lab değerinden birden fazla chunk gelse de kaynak tek olmalı
    r = post("CRP nedir?", lab_test="CRP")
    body = r.json()
    urls = [c["source_url"] for c in body["citations"]]
    assert len(urls) == len(set(urls))
    assert len(urls) == 1


def test_confidence_label_matches_threshold():
    r = post("CRP nedir?", lab_test="CRP")
    body = r.json()
    score = body["confidence"]
    label = body["confidence_label"]
    if score >= 0.71:
        assert label == "high"
    elif score >= 0.41:
        assert label == "medium"
    else:
        assert label == "low"


def test_explain_response_envelope_shape():
    r = post("CRP nedir?", lab_test="CRP")
    assert r.status_code == 200
    body = r.json()
    # Stabil zarf alanları (Flutter bunlara güvenecek)
    assert body["response_type"] == "answer"
    assert body["lab_test"] == "CRP"
    assert "matched_term" in body
    assert "result_context" in body
    assert isinstance(body["doctor_questions"], list)
    assert body["disclaimer"]
    # Citation yeni şekli: yalnız source_title / source_url / section
    assert body["citations"]
    c = body["citations"][0]
    assert set(c.keys()) == {"source_title", "source_url", "section"}
    assert c["source_title"] == "MedlinePlus"
    assert "c-reactive-protein" in c["source_url"]
