import json
from hashlib import sha256
from pathlib import Path

from app.services.clinical_editorial_review import build_clinical_editorial_review
from tools.publish_source_batch import _sections


ROOT = Path(__file__).resolve().parents[1]


def test_all_documents_remain_pending_until_a_licensed_reviewer_signs_off():
    report = build_clinical_editorial_review(
        ROOT / "data" / "medical_docs", ROOT / "data" / "source_batches"
    )

    assert report["summary"]["documents"] == 240
    assert report["summary"]["clinical_signoff_completed"] == 0
    assert report["summary"]["clinical_signoff_pending"] == 240
    assert all(
        item["clinical_review_status"] == "pending_licensed_reviewer"
        for item in report["records"]
    )


def test_qualitative_follow_up_does_not_use_numeric_reference_range_language():
    sections = _sections(
        {
            "lab_test": "Örnek Tarama",
            "purpose": "Bir bulguyu araştırmak için yapılır.",
            "result_kind": "qualitative",
        },
        "Örnek tarama bir bulgunun varlığını araştırır.",
    )

    follow_up = sections["Ne zaman doktora danışılmalı?"]
    assert "referans aralığı dışındaysa" not in follow_up
    assert "pozitif, reaktif, saptandı, uyumsuz veya belirsiz" in follow_up


def test_service_listing_sources_are_queued_for_source_upgrade():
    report = build_clinical_editorial_review(
        ROOT / "data" / "medical_docs", ROOT / "data" / "source_batches"
    )
    service_records = [
        item for item in report["records"] if item["source_strength"] == "service_listing"
    ]

    assert service_records
    assert all(
        "source_specificity_upgrade_recommended" in item["reason_codes"]
        for item in service_records
    )


def test_clinical_signoff_requires_matching_document_checksum(tmp_path):
    docs = tmp_path / "docs"
    batches = tmp_path / "batches"
    docs.mkdir()
    batches.mkdir()
    document = docs / "test.md"
    document.write_text(
        "---\nlab_test: Test\nsource_title: MedlinePlus\n"
        "source_url: https://medlineplus.gov/lab-tests/test\n---\n",
        encoding="utf-8",
    )
    checksum = sha256(document.read_bytes()).hexdigest()
    signoffs = tmp_path / "signoffs.json"
    signoffs.write_text(
        json.dumps(
            {
                "reviews": [
                    {
                        "lab_test": "Test",
                        "status": "approved",
                        "reviewer_name": "Dr. Reviewer",
                        "reviewer_credential": "MD",
                        "reviewed_at": "2026-08-03",
                        "document_sha256": checksum,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    approved = build_clinical_editorial_review(docs, batches, signoffs)
    assert approved["summary"]["clinical_signoff_completed"] == 1

    document.write_text(document.read_text(encoding="utf-8") + "changed", encoding="utf-8")
    stale = build_clinical_editorial_review(docs, batches, signoffs)
    assert stale["records"][0]["clinical_review_status"] == "stale_or_changes_requested"
