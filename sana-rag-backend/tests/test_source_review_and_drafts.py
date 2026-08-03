"""Kaynak inceleme raporu ve Türkçe taslak kapıları - gerçek ağ/LLM yok."""

import json
from pathlib import Path

import pytest

from app.data.loinc_catalog import LAB_SOURCE_BY_NAME
from app.services.medlineplus_client import MedlinePlusRecord
from app.services.source_draft_service import (
    SourceDraftError,
    generate_and_stage_source_draft,
    validate_source_draft,
)
from app.services.source_review_report_service import (
    build_source_review_report,
    render_markdown,
    write_source_review_report,
)
from app.services.source_sync_store import SourceSyncStore


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def source_record(summary="CRP is a protein in the blood.", source_url=None):
    return MedlinePlusRecord(
        lab_test="CRP",
        loinc_code="1988-5",
        title="C-Reactive Protein (CRP) Test",
        source_url=(
            source_url
            or "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/"
        ),
        summary=summary,
        attribution="MedlinePlus",
        language="en",
        raw_payload={"feed": {"entry": []}},
    )


def make_store(tmp_path):
    return SourceSyncStore(str(tmp_path / "review.db"))


def stage_source(store, *, approve=False, summary=None):
    definition = LAB_SOURCE_BY_NAME["CRP"]
    store.upsert_medlineplus(
        definition, source_record(summary or "CRP is a protein in the blood.")
    )
    if approve:
        store.approve(definition.source_key, "source-reviewer")
    return definition


class FakeDraftProvider:
    name = "fake-local"

    def __init__(self, answer="CRP, kanda bulunan bir proteindir."):
        self.answer = answer
        self.calls = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return self.answer


def test_unapproved_source_blocks_draft_before_provider_call(tmp_path):
    store = make_store(tmp_path)
    definition = stage_source(store)
    provider = FakeDraftProvider()

    with pytest.raises(SourceDraftError, match="onaylanmadan"):
        generate_and_stage_source_draft(
            definition.source_key, store=store, provider=provider
        )
    assert provider.calls == []
    assert store.list_drafts("pending") == []


def test_approved_source_generates_pending_draft_with_strict_prompt(tmp_path):
    store = make_store(tmp_path)
    definition = stage_source(store, approve=True)
    provider = FakeDraftProvider()

    result = generate_and_stage_source_draft(
        definition.source_key, store=store, provider=provider
    )

    assert result.outcome == "created"
    assert result.draft.review_status == "pending"
    assert result.draft.generator == "fake-local"
    assert result.draft.published_at is None
    assert len(provider.calls) == 1
    call = provider.calls[0]
    assert call["retrieved"] == []
    assert "Yeni tıbbi bilgi" in call["system_prompt"]
    assert "CRP is a protein" in call["user_prompt"]


@pytest.mark.parametrize(
    "answer,error",
    [
        ("", "boş"),
        ("Tamamlanmamış taslak", "tamamlanmamış"),
        ("The blood level is important.", "yabancı dil"),
        (
            "I can't provide medical advice, but I can offer some general information.",
            "yabancı dil",
        ),
        ("Bu nedenle ilaca başlayın.", "yönlendirme"),
        ("CRP için değer 99 olabilir.", "sayı veya referans aralığı"),
        ("Kaynakta 12 yazsa bile taslakta 12 olmamalıdır.", "sayı veya referans aralığı"),
        ("# Başlık. CRP bir proteindir.", "biçimlendirme"),
    ],
)
def test_draft_quality_gate_rejects_unsafe_or_ungrounded_output(answer, error):
    with pytest.raises(SourceDraftError, match=error):
        validate_source_draft(answer, "CRP is a protein in the blood.")


def test_common_batches_have_unique_drafts_that_pass_quality_gate():
    batch_dir = PROJECT_ROOT / "data" / "source_batches"
    paths = sorted(batch_dir.glob("medlineplus_common_*_drafts.json"))
    assert len(paths) >= 2
    for batch_path in paths:
        payload = json.loads(batch_path.read_text(encoding="utf-8"))
        drafts = payload["drafts"]
        assert payload["generator"] == "codex-grounded-manual-v1"
        assert len(drafts) == 25
        assert len({item["source_key"] for item in drafts}) == 25
        for item in drafts:
            assert validate_source_draft(item["content"], "official source")


def test_remaining_catalog_generates_safe_drafts():
    path = (
        PROJECT_ROOT
        / "data"
        / "source_batches"
        / "medlineplus_remaining_rag.json"
    )
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert len(payload["items"]) == 46
    for item in payload["items"]:
        content = (
            item["purpose"]
            + " Sonuç kullanılan örnek ve yöntemle birlikte değerlendirilir. "
            + "Tek başına tanı koydurmaz."
        )
        assert validate_source_draft(content, "official source")


def test_draft_requires_own_review_before_publish(tmp_path):
    store = make_store(tmp_path)
    definition = stage_source(store, approve=True)
    store.stage_draft(
        definition.source_key, "CRP, kanda bulunan bir proteindir.", "fake"
    )

    with pytest.raises(ValueError, match="onaylanmış"):
        store.mark_draft_published(definition.source_key)

    store.approve_draft(definition.source_key, "draft-reviewer")
    store.mark_draft_published(definition.source_key)
    draft = store.get_current_draft(definition.source_key)
    assert draft.review_status == "approved"
    assert draft.reviewed_by == "draft-reviewer"
    assert draft.published_at is not None


def test_source_change_marks_previous_draft_stale(tmp_path):
    store = make_store(tmp_path)
    definition = stage_source(store, approve=True)
    store.stage_draft(
        definition.source_key, "CRP, kanda bulunan bir proteindir.", "fake"
    )
    store.approve_draft(definition.source_key, "draft-reviewer")

    store.upsert_medlineplus(
        definition, source_record("CRP is an updated protein summary.")
    )

    assert store.get_current_draft(definition.source_key) is None
    stale = store.list_drafts("stale")
    assert len(stale) == 1
    assert stale[0].source_key == definition.source_key
    assert stale[0].published_at is None


def test_same_draft_does_not_reset_existing_approval(tmp_path):
    store = make_store(tmp_path)
    definition = stage_source(store, approve=True)
    content = "CRP, kanda bulunan bir proteindir."
    assert store.stage_draft(definition.source_key, content, "fake") == "created"
    store.approve_draft(definition.source_key, "draft-reviewer")
    assert store.stage_draft(definition.source_key, content, "fake") == "unchanged"
    assert store.get_current_draft(definition.source_key).review_status == "approved"


def test_review_report_compares_connect_record_with_current_turkish_sections(tmp_path):
    store = make_store(tmp_path)
    stage_source(store)
    docs_dir = PROJECT_ROOT / "data" / "medical_docs"

    report = build_source_review_report(store, docs_dir)
    assert report["summary"] == {
        "total": 1,
        "loinc_mappings": 1,
        "pending_sources": 1,
        "approved_sources": 0,
        "broader_matches": 0,
        "unclassified_matches": 0,
        "pending_drafts": 0,
    }
    item = report["records"][0]
    assert item["lab_test"] == "CRP"
    assert item["match_scope"] == "exact"
    assert len(item["current_turkish_sections"]) == 6
    assert "CRP" in render_markdown(report)


def test_review_report_ignores_trailing_slash_difference(tmp_path):
    store = make_store(tmp_path)
    definition = LAB_SOURCE_BY_NAME["CRP"]
    store.upsert_medlineplus(
        definition,
        source_record(
            source_url="https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test"
        ),
    )
    docs_dir = PROJECT_ROOT / "data" / "medical_docs"
    report = build_source_review_report(store, docs_dir)
    assert report["summary"]["broader_matches"] == 0


def test_review_report_marks_broader_connect_match_and_writes_files(tmp_path):
    store = make_store(tmp_path)
    definition = LAB_SOURCE_BY_NAME["Glukoz"]
    store.upsert_medlineplus(
        definition,
        source_record(
            source_url="https://medlineplus.gov/bloodglucose.html",
        ),
    )
    docs_dir = PROJECT_ROOT / "data" / "medical_docs"
    report = build_source_review_report(store, docs_dir)
    assert report["summary"]["broader_matches"] == 1

    json_path = tmp_path / "report.json"
    md_path = tmp_path / "report.md"
    write_source_review_report(report, json_path, md_path)
    assert json_path.is_file()
    assert md_path.is_file()
    assert "broader_topic" in md_path.read_text(encoding="utf-8")
