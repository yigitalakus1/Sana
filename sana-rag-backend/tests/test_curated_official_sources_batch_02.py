import json
from pathlib import Path

from app.data.seed_documents import SEED_DOCUMENTS
from app.data.synonyms import LAB_VALUES, SYNONYM_MAP
from tools.publish_curated_source_batch import validate_catalog


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BATCH_DIR = PROJECT_ROOT / "data" / "source_batches"
CATALOG_PATH = BATCH_DIR / "official_labs_02_rag.json"
EXPECTED_LABS = {
    "Yenidoğan Metabolik ve Endokrin Tarama Paneli",
    "Fenilalanin",
    "Biyotinidaz Aktivitesi",
    "İmmünoreaktif Tripsinojen",
    "SMA Yenidoğan Tarama Testi",
    "Kalsitonin",
    "Eritropoietin",
    "Androstenedion",
    "IGF-BP3",
    "Metanefrinler",
    "Katekolaminler",
    "Gastrin",
    "Total T4",
    "11-Deoksikortizol",
    "21-Deoksikortizol",
    "ABO Kan Grubu",
    "RhD Tiplemesi",
    "Crossmatch",
    "Direkt Antiglobulin Testi",
    "Eritrosit Antikor Tanımlama",
    "Rh Alt Grup Tiplemesi",
    "Zayıf D Testi",
    "İzohemaglutinin Titresi",
    "Kleihauer-Betke Testi",
}


def test_second_curated_catalog_is_reviewed_and_complete():
    payload = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    items = validate_catalog(payload)
    assert {item["lab_test"] for item in items} == EXPECTED_LABS


def test_second_batch_is_loaded_with_aliases_and_seed_documents():
    assert EXPECTED_LABS.issubset(LAB_VALUES)
    assert EXPECTED_LABS.issubset({doc["lab_test"] for doc in SEED_DOCUMENTS})
    assert "topuk kanı testi" in SYNONYM_MAP["Yenidoğan Metabolik ve Endokrin Tarama Paneli"]
    assert "direkt coombs" in SYNONYM_MAP["Direkt Antiglobulin Testi"]


def test_all_rag_catalogs_have_unique_lab_names_and_source_keys():
    labs = []
    keys = []
    for path in sorted(BATCH_DIR.glob("*_rag.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        labs.extend(item["lab_test"] for item in payload["items"])
        keys.extend(item["source_key"] for item in payload["items"])
    assert len(labs) == len(set(labs))
    assert len(keys) == len(set(keys))


def test_screening_entries_distinguish_screening_from_diagnosis():
    docs = {doc["lab_test"]: doc for doc in SEED_DOCUMENTS}
    for lab in {
        "Yenidoğan Metabolik ve Endokrin Tarama Paneli",
        "Fenilalanin",
        "Biyotinidaz Aktivitesi",
        "İmmünoreaktif Tripsinojen",
        "SMA Yenidoğan Tarama Testi",
    }:
        text = docs[lab]["sections"]["Nedir?"].casefold()
        assert "tek başına tanı koydurmaz" in text


def test_new_citations_point_only_to_official_sources():
    docs = {doc["lab_test"]: doc for doc in SEED_DOCUMENTS}
    for lab in EXPECTED_LABS:
        url = docs[lab]["source_url"]
        assert url.startswith("https://")
        assert any(host in url for host in ("saglik.gov.tr", "who.int"))


def test_blood_typing_and_compatibility_content_does_not_treat_positive_as_disease():
    docs = {doc["lab_test"]: doc for doc in SEED_DOCUMENTS}

    abo = docs["ABO Kan Grubu"]["sections"]
    assert "A, B, AB ya da O" in abo["Yüksek ne anlama gelebilir?"]
    assert "pozitif, reaktif" not in abo["Ne zaman doktora danışılmalı?"]

    rhd = docs["RhD Tiplemesi"]["sections"]
    assert "tek başına hastalık anlamına gelmez" in rhd["Yüksek ne anlama gelebilir?"]

    crossmatch = docs["Crossmatch"]["sections"]
    assert "uyumsuz sonuç" in crossmatch["Düşük ne anlama gelebilir?"].casefold()
    assert "tek başına kan bileşeni seçimi" in crossmatch["Ne zaman doktora danışılmalı?"]
