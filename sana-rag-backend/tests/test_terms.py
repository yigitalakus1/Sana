import json

from fastapi.testclient import TestClient

from app.data import seed_documents
from app.data.synonyms import LAB_VALUES
from app.main import app

client = TestClient(app)


def test_terms_list_ok_and_not_empty():
    r = client.get("/terms")
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list)
    assert body  # boş değil


def test_terms_list_contains_crp():
    body = client.get("/terms").json()
    labs = [t["lab_test"] for t in body]
    assert "CRP" in labs


def test_terms_list_contains_all_supported_labs():
    body = client.get("/terms").json()
    labs = {term["lab_test"] for term in body}
    assert labs == set(LAB_VALUES)


def test_terms_crp_sections_not_empty():
    body = client.get("/terms").json()
    crp = next(t for t in body if t["lab_test"] == "CRP")
    assert crp["sections"]
    assert crp["title"]


def test_term_detail_crp_uppercase():
    r = client.get("/terms/CRP")
    assert r.status_code == 200
    body = r.json()
    assert body["lab_test"] == "CRP"
    assert body["sections"]
    assert body["sources"]
    s = body["sources"][0]
    assert set(s.keys()) == {"source_title", "source_url", "section"}


def test_term_detail_crp_lowercase():
    r = client.get("/terms/crp")
    assert r.status_code == 200
    assert r.json()["lab_test"] == "CRP"


def test_term_detail_synonym_resolves():
    r = client.get("/terms/C%20reaktif%20protein")
    assert r.status_code == 200
    assert r.json()["lab_test"] == "CRP"


def test_term_detail_unknown_returns_404():
    r = client.get("/terms/bilinmeyen-tahlil")
    assert r.status_code == 404


def test_common_batch_is_visible_in_terms():
    terms = client.get("/terms").json()
    assert len(terms) == len(LAB_VALUES)
    detail = client.get("/terms/troponin")
    assert detail.status_code == 200
    assert detail.json()["lab_test"] == "Troponin"


def test_verified_medlineplus_content_is_seeded_for_b12_and_alt():
    chunks = seed_documents.get_all_chunks()
    b12_sections = " ".join(
        chunk.content for chunk in chunks if chunk.lab_test == "B12"
    )
    assert "iltihaplanma" in b12_sections
    assert "bazı ilaçlar" in b12_sections

    alt_sections = " ".join(
        chunk.content for chunk in chunks if chunk.lab_test == "ALT"
    )
    assert "B6 vitamini eksikliği" in alt_sections
    assert "kronik böbrek hastalığı" in alt_sections


def test_term_public_has_no_internal_fields():
    list_body = client.get("/terms").json()
    for t in list_body:
        assert set(t.keys()) == {"lab_test", "title", "sections"}

    detail = client.get("/terms/CRP").json()
    assert set(detail.keys()) == {"lab_test", "title", "sections", "sources"}

    # chunk_id / content / score hiçbir public term yanıtında olmamalı
    blob = json.dumps(list_body) + json.dumps(detail)
    assert "chunk_id" not in blob
    assert "content" not in blob
    assert "score" not in blob
