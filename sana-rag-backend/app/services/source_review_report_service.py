"""Resmî kaynak, mevcut Türkçe RAG ve taslak durumunu karşılaştıran rapor."""

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict
from urllib.parse import urlparse, urlunparse

from app.data.loinc_catalog import LAB_SOURCE_BY_NAME
from app.services import chunking_service
from app.services.source_sync_store import SourceSyncStore


def _current_sections(docs_dir: Path) -> Dict[str, list]:
    grouped: Dict[str, list] = {}
    for path in sorted(docs_dir.glob("*.md")):
        for chunk in chunking_service.chunk_file(path):
            grouped.setdefault(chunk.lab_test, []).append(
                {"section": chunk.section, "content": chunk.content}
            )
    return grouped


def _reviewed_rag_names() -> Dict[str, str]:
    directory = (
        Path(__file__).resolve().parents[2]
        / "data"
        / "source_batches"
    )
    result = {}
    for path in sorted(directory.glob("medlineplus_*_rag.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        result.update(
            (item["source_key"], item["lab_test"])
            for item in payload.get("items", [])
        )
    return result


def _canonical_url(value: str) -> str:
    parsed = urlparse(value)
    path = parsed.path.rstrip("/") or "/"
    return urlunparse((parsed.scheme.lower(), parsed.netloc.lower(), path, "", "", ""))


def build_source_review_report(store: SourceSyncStore, docs_dir: Path) -> dict:
    sections = _current_sections(docs_dir)
    reviewed_rag_names = _reviewed_rag_names()
    records = []
    for source in store.list_all():
        definition = LAB_SOURCE_BY_NAME.get(source.lab_test)
        draft = store.get_current_draft(source.source_key)
        reviewed_lab_test = reviewed_rag_names.get(source.source_key)
        curated_url = (
            definition.medlineplus_url
            if definition
            else source.source_url if reviewed_lab_test else None
        )
        records.append(
            {
                "source_key": source.source_key,
                "lab_test": source.lab_test,
                "loinc_code": source.code,
                "review_status": source.review_status,
                "connect_title": source.title,
                "connect_url": source.source_url,
                "curated_medical_test_url": curated_url,
                "match_scope": (
                    "exact"
                    if curated_url
                    and _canonical_url(curated_url) == _canonical_url(source.source_url)
                    else "broader_topic"
                    if curated_url
                    else "unclassified"
                ),
                "source_summary": source.summary,
                "content_hash": source.content_hash,
                "fetched_at": source.fetched_at,
                "current_turkish_sections": sections.get(
                    reviewed_lab_test or source.lab_test, []
                ),
                "draft": (
                    {
                        "content": draft.content,
                        "review_status": draft.review_status,
                        "generator": draft.generator,
                    }
                    if draft
                    else None
                ),
            }
        )
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "total": len(records),
            "loinc_mappings": store.mapping_count(),
            "pending_sources": sum(
                item["review_status"] == "pending" for item in records
            ),
            "approved_sources": sum(
                item["review_status"] == "approved" for item in records
            ),
            "broader_matches": sum(
                item["match_scope"] == "broader_topic" for item in records
            ),
            "unclassified_matches": sum(
                item["match_scope"] == "unclassified" for item in records
            ),
            "pending_drafts": sum(
                bool(item["draft"])
                and item["draft"]["review_status"] == "pending"
                for item in records
            ),
        },
        "records": records,
    }


def render_markdown(report: dict) -> str:
    summary = report["summary"]
    lines = [
        "# Sana Resmi Kaynak Inceleme Raporu",
        "",
        f"- Uretim zamani: `{report['generated_at']}`",
        f"- Kaynak kaydi: **{summary['total']}**",
        f"- LOINC kod eslemesi: **{summary['loinc_mappings']}**",
        f"- Kaynak onayi bekleyen: **{summary['pending_sources']}**",
        f"- Onayli kaynak: **{summary['approved_sources']}**",
        f"- Genis konu eslesmesi: **{summary['broader_matches']}**",
        f"- Henuz siniflandirilmamis eslesme: **{summary['unclassified_matches']}**",
        f"- Taslak onayi bekleyen: **{summary['pending_drafts']}**",
        "",
    ]
    for item in report["records"]:
        lines.extend(
            [
                f"## {item['lab_test']} ({item['loinc_code']})",
                "",
                f"- Kaynak anahtari: `{item['source_key']}`",
                f"- Durum: `{item['review_status']}`",
                f"- Connect eslesmesi: `{item['match_scope']}`",
                f"- Connect basligi: {item['connect_title']}",
                f"- Connect URL: {item['connect_url']}",
                f"- Dogrudan test URL: {item['curated_medical_test_url']}",
                f"- Checksum: `{item['content_hash']}`",
                "",
                "### MedlinePlus Ozeti",
                "",
                item["source_summary"],
                "",
                "### Mevcut Turkce RAG Icerigi",
                "",
            ]
        )
        for section in item["current_turkish_sections"]:
            lines.extend(
                [f"**{section['section']}**", "", section["content"], ""]
            )
        if item["draft"]:
            lines.extend(
                [
                    "### Turkce Taslak",
                    "",
                    f"Durum: `{item['draft']['review_status']}`",
                    "",
                    item["draft"]["content"],
                    "",
                ]
            )
    return "\n".join(lines).rstrip() + "\n"


def write_source_review_report(
    report: dict, json_path: Path, markdown_path: Path
) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    markdown_path.write_text(render_markdown(report), encoding="utf-8")
