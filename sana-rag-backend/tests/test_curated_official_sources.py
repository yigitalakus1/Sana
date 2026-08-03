import json
from pathlib import Path

import pytest

from app.data.seed_documents import SEED_DOCUMENTS
from app.data.synonyms import LAB_VALUES, SYNONYM_MAP
from tools.publish_curated_source_batch import validate_catalog


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = (
    PROJECT_ROOT / "data" / "source_batches" / "official_labs_01_rag.json"
)
EXPECTED_NEW_LABS = {
    "Sodyum",
    "Potasyum",
    "Fibrinojen",
    "Çinko",
    "Protein C",
    "Protein S",
    "Bakır",
    "HDL Kolesterol",
    "Serbest T4",
    "Büyüme Hormonu",
    "Serum ACE",
    "Lipoprotein(a)",
    "LDL Kolesterol",
    "Folat",
    "LDH İzoenzimleri",
    "Oral Glukoz Tolerans Testi",
    "Gestasyonel Diyabet Tarama Testi",
}


def catalog_payload():
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def test_curated_catalog_is_reviewed_and_uses_only_official_hosts():
    items = validate_catalog(catalog_payload())
    assert {item["lab_test"] for item in items} == EXPECTED_NEW_LABS


def test_curated_catalog_is_loaded_into_public_lab_values_and_seed_docs():
    assert EXPECTED_NEW_LABS.issubset(LAB_VALUES)
    assert EXPECTED_NEW_LABS.issubset({doc["lab_test"] for doc in SEED_DOCUMENTS})
    assert SYNONYM_MAP["Sodyum"] == ["sodyum", "sodium", "na", "serum sodyum"]
    assert "ogtt" in SYNONYM_MAP["Oral Glukoz Tolerans Testi"]


def test_curated_documents_have_six_safe_sections_and_official_citations():
    documents = {
        doc["lab_test"]: doc for doc in SEED_DOCUMENTS if doc["lab_test"] in EXPECTED_NEW_LABS
    }
    assert set(documents) == EXPECTED_NEW_LABS
    for document in documents.values():
        assert len(document["sections"]) == 6
        assert document["source_url"].startswith("https://")
        assert "tek başına tanı koydurmaz" in document["sections"]["Nedir?"].casefold()


def test_unreviewed_curated_catalog_is_rejected():
    payload = catalog_payload()
    payload["review_status"] = "pending"
    with pytest.raises(ValueError, match="onaylanmis"):
        validate_catalog(payload)


def test_non_official_source_host_is_rejected():
    payload = catalog_payload()
    payload["items"][0]["source_url"] = "https://example.com/lab-test"
    with pytest.raises(ValueError, match="Resmi kaynak"):
        validate_catalog(payload)
