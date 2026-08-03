from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

STABLE_FIELDS = (
    "response_type",
    "lab_test",
    "answer",
    "confidence",
    "confidence_label",
    "citations",
    "doctor_questions",
    "disclaimer",
    # S13 additive metadata
    "normalized_query",
    "llm_provider",
    "safety_notes",
    "retrieved_chunks",
)


def post(question, lab_test=None, language="tr"):
    payload = {
        "question": question,
        "options": {"language": language, "include_sources": True, "include_doctor_questions": True},
    }
    if lab_test is not None:
        payload["lab_test"] = lab_test
    return client.post("/explain", json=payload)


def test_explain_happy_path():
    r = post("CRP nedir?", lab_test="CRP")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "answer"
    assert body["lab_test"] == "CRP"
    assert body["confidence"] > 0
    assert body["confidence_label"] in ("low", "medium", "high")
    assert any("c-reactive-protein" in c["source_url"] for c in body["citations"])
    c = body["citations"][0]
    assert set(c.keys()) == {"source_title", "source_url", "section"}
    assert isinstance(body["doctor_questions"], list)
    assert body["disclaimer"]


def test_general_explanation_uses_what_and_why_sections():
    body = post(
        "ALT 25 U/L çıktı. Bu tahlilin neyi ölçtüğünü ve genel anlamını açıkla.",
        lab_test="ALT",
    ).json()

    assert body["response_type"] == "answer"
    assert [item["section"] for item in body["retrieved_chunks"]] == [
        "Nedir?",
        "Neden ölçülür?",
    ]
    assert "karaciğer" in body["answer"].casefold()


def test_combined_what_and_why_question_uses_both_sections():
    body = post("CRP nedir ve neden ölçülür?", lab_test="CRP").json()

    assert [item["section"] for item in body["retrieved_chunks"]] == [
        "Nedir?",
        "Neden ölçülür?",
    ]
    assert "protein" in body["answer"].casefold()
    assert "araştırmak için" in body["answer"].casefold()


def test_explain_safety_block_shape():
    r = post("CRP yüksekse hangi antibiyotiği almalıyım?")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "safety_block"
    assert body["answer"]
    assert body["confidence"] == 0.0
    assert body["confidence_label"] == "low"
    assert body["citations"] == []
    assert isinstance(body["doctor_questions"], list)
    assert body["disclaimer"]
    # S13 metadata: stabil şekil
    assert body["normalized_query"]
    assert body["llm_provider"] == "dummy"
    assert isinstance(body["safety_notes"], list) and body["safety_notes"]
    assert body["retrieved_chunks"] == []


def test_explain_no_results_shape():
    r = post("Miyoglobin değerim ne anlama gelir?")
    assert r.status_code == 200
    body = r.json()
    assert body["response_type"] == "no_results"
    assert body["answer"]
    assert body["confidence"] == 0.0
    assert body["confidence_label"] == "low"
    assert body["citations"] == []
    assert isinstance(body["doctor_questions"], list)
    assert body["disclaimer"]
    # S13 metadata: stabil şekil
    assert body["normalized_query"]
    assert body["llm_provider"] == "dummy"
    assert body["safety_notes"] == []
    assert body["retrieved_chunks"] == []


def test_explain_metadata_fields():
    r = post("CRP nedir?", lab_test="CRP")
    assert r.status_code == 200
    body = r.json()
    # normalized_query: mevcut normalize() çıktısı
    assert body["normalized_query"] == "crp nedir"
    # llm_provider: mevcut dummy provider adı
    assert body["llm_provider"] == "dummy"
    # answer durumunda güvenlik notu beklenmez
    assert body["safety_notes"] == []
    # retrieved_chunks: hafif metadata; content/chunk_id/skor YOK
    assert body["retrieved_chunks"]
    rc = body["retrieved_chunks"][0]
    assert set(rc.keys()) == {"lab_test", "section", "source_title"}
    assert rc["lab_test"] == "CRP"
    assert "chunk_id" not in rc
    assert "content" not in rc


def test_result_context_none_for_plain_question():
    body = post("CRP nedir?", lab_test="CRP").json()
    assert body["response_type"] == "answer"
    assert body["result_context"] is None


def test_result_context_with_dot_value():
    body = post("CRP 13.5 çıktı").json()
    assert body["response_type"] == "answer"
    rc = body["result_context"]
    assert rc is not None
    assert rc["raw_value"] == "13.5"
    assert rc["value"] == 13.5
    # Bu aşamada tanı/yorum YOK
    assert rc["interpretation"] is None
    assert rc["reference_range"] is None


def test_result_context_with_comma_value():
    body = post("CRP 13,5 çıktı").json()
    rc = body["result_context"]
    assert rc is not None
    assert rc["raw_value"] == "13,5"
    assert rc["value"] == 13.5


def test_result_context_ignores_lab_name_digits():
    # "B12" gibi test adındaki rakamlar result_context'e sızmamalı
    body = post("B12 nedir?", lab_test="B12").json()
    assert body["response_type"] == "answer"
    assert body["result_context"] is None
    # Gerçek değer varsa o yakalanır (test adındaki 12 değil)
    body2 = post("B12 350 çıktı", lab_test="B12").json()
    rc = body2["result_context"]
    assert rc is not None
    assert rc["value"] == 350.0


def test_result_context_null_on_safety_block():
    # Değer geçse bile safety block davranışı korunur; result_context null
    body = post("CRP 13.5 için hangi antibiyotiği almalıyım?").json()
    assert body["response_type"] == "safety_block"
    assert body["result_context"] is None


def test_result_context_null_on_no_results():
    # Lab test resolve edilemezse (no_results) değer olsa bile null
    body = post("Miyoglobin 13.5 çıktı").json()
    assert body["response_type"] == "no_results"
    assert body["result_context"] is None


def test_query_and_explain_field_compatibility():
    # Aynı gövde -> aynı alan kümesi ve (request_id hariç) aynı davranış.
    # request_id farklı olabileceği için tam eşitlik testi YOK.
    payload = {"question": "CRP nedir?", "lab_test": "CRP", "options": {"language": "tr"}}
    q = client.post("/query", json=payload).json()
    e = client.post("/explain", json=payload).json()
    assert q.keys() == e.keys()
    for field in STABLE_FIELDS:
        assert q[field] == e[field]
