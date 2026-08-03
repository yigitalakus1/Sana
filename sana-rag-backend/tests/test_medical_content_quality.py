import json
from pathlib import Path

from app.core import constants as C
from app.services.medical_content_audit import build_medical_content_audit
from tools.publish_source_batch import _sections


ROOT = Path(__file__).resolve().parents[1]


def test_all_240_medical_documents_pass_content_audit():
    report = build_medical_content_audit(
        ROOT / "data" / "medical_docs",
        ROOT / "data" / "source_batches",
    )

    assert report["summary"]["documents"] == 240
    assert report["summary"]["catalog_items"] == 230
    assert report["issues"] == []


def test_heavy_metal_content_is_specific_and_does_not_claim_low_excludes_exposure():
    text = (ROOT / "data" / "medical_docs" / "agir-metal-kan-testi.md").read_text(encoding="utf-8")

    assert all(term in text.casefold() for term in ("kurşun", "cıva", "arsenik", "kadmiyum"))
    assert "her zaman dışlamaz" in text.casefold()
    assert "bakır testi" not in text.casefold()


def test_section_overrides_replace_generated_defaults():
    item = {
        "lab_test": "Test",
        "purpose": "Olcum amaci.",
        "result_kind": "panel",
        "section_overrides": {C.SECTION_LOW: "Teste ozgu dusuk sonuc aciklamasi."},
    }

    sections = _sections(item, "Test tanimi.")

    assert sections[C.SECTION_LOW] == "Teste ozgu dusuk sonuc aciklamasi."
    assert sections[C.SECTION_WHAT] == "Test tanimi."


def test_heavy_metal_aliases_do_not_capture_the_separate_copper_test():
    catalog = json.loads(
        (ROOT / "data" / "source_batches" / "medlineplus_remaining_rag.json").read_text(encoding="utf-8")
    )
    item = next(item for item in catalog["items"] if item["lab_test"] == "Ağır Metal Kan Testi")

    assert "bakır testi" not in item["aliases"]
    assert "ağır metal paneli" in item["aliases"]
