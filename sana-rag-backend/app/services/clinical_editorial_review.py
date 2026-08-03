"""Tıbbi içerikleri klinisyen incelemesine hazırlayan deterministik envanter."""

from __future__ import annotations

import json
import re
from hashlib import sha256
from collections import Counter
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


_FRONT_MATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_HIGH_RISK_TERMS = (
    "acil", "ağır metal", "afp", "amonyak", "d-dimer", "down", "hiv",
    "kan gaz", "kan grubu", "kanser", "crossmatch", "ilaç", "yenidoğan",
    "opioid", "salisilat", "sma", "transfüzyon", "trisiklik", "troponin",
    "tümör", "zehir",
)
_SERVICE_LISTING_MARKERS = (
    "laboratuvarlar", "laboratuvari", "laboratuvarı", "transfuzyon-merkezi",
)


def _metadata(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = _FRONT_MATTER.search(text)
    if match is None:
        return {}
    result: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, separator, value = line.partition(":")
        if separator:
            result[key.strip()] = value.strip()
    return result


def _catalog(batch_dir: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for path in sorted(batch_dir.glob("*_rag.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for item in payload.get("items", []):
            result[str(item["lab_test"])] = {**item, "catalog": path.name}
    return result


def _source_strength(url: str) -> str:
    parsed = urlparse(url)
    path = parsed.path.casefold()
    host = (parsed.hostname or "").casefold()
    if "medlineplus.gov" in host and "/lab-tests/" in path:
        return "direct_patient_test_page"
    if any(marker in path for marker in _SERVICE_LISTING_MARKERS):
        return "service_listing"
    if path.endswith(".pdf"):
        return "official_program_or_guideline"
    if "who.int" in host or "ncbi.nlm.nih.gov" in host or "tkbd.org" in host:
        return "professional_reference"
    return "official_topic_page"


def _priority(lab_test: str, item: dict[str, Any]) -> tuple[str, list[str]]:
    haystack = f"{lab_test} {item.get('title', '')} {item.get('purpose', '')}".casefold()
    reasons: list[str] = []
    if item.get("urgent"):
        reasons.append("urgent_follow_up_language")
    if any(term in haystack for term in _HIGH_RISK_TERMS):
        reasons.append("high_consequence_topic")
    result_kind = item.get("result_kind", "scalar")
    if result_kind in {"qualitative", "panel"}:
        reasons.append(f"{result_kind}_result_semantics")
    if reasons and ("high_consequence_topic" in reasons or "urgent_follow_up_language" in reasons):
        return "high", reasons
    if reasons:
        return "medium", reasons
    return "standard", reasons


def _signoffs(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None or not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    reviews = payload.get("reviews", [])
    if not isinstance(reviews, list):
        raise ValueError("clinical editorial reviews listesi gecersiz")
    return {
        str(review["lab_test"]): review
        for review in reviews
        if isinstance(review, dict) and review.get("lab_test")
    }


def build_clinical_editorial_review(
    docs_dir: Path, batch_dir: Path, signoffs_path: Path | None = None
) -> dict[str, Any]:
    """Her belge için kaynak gücü, öncelik ve klinisyen onay durumunu üretir."""
    catalog = _catalog(batch_dir)
    signoffs = _signoffs(signoffs_path)
    records: list[dict[str, Any]] = []
    for path in sorted(docs_dir.glob("*.md")):
        metadata = _metadata(path)
        lab_test = metadata.get("lab_test", path.stem)
        item = catalog.get(lab_test, {})
        strength = _source_strength(metadata.get("source_url", ""))
        priority, reasons = _priority(lab_test, item)
        if strength == "service_listing":
            reasons.append("source_specificity_upgrade_recommended")
            if priority == "standard":
                priority = "medium"
        document_checksum = sha256(path.read_bytes()).hexdigest()
        signoff = signoffs.get(lab_test)
        approved = bool(
            signoff
            and signoff.get("status") == "approved"
            and signoff.get("document_sha256") == document_checksum
            and str(signoff.get("reviewer_name", "")).strip()
            and str(signoff.get("reviewer_credential", "")).strip()
            and str(signoff.get("reviewed_at", "")).strip()
        )
        review_status = "approved" if approved else "pending_licensed_reviewer"
        if signoff and not approved:
            review_status = "stale_or_changes_requested"
        records.append(
            {
                "lab_test": lab_test,
                "document": path.name,
                "result_kind": item.get("result_kind", "scalar"),
                "source_title": metadata.get("source_title"),
                "source_url": metadata.get("source_url"),
                "source_strength": strength,
                "editorial_priority": priority,
                "reason_codes": reasons,
                "automated_quality_status": "passed",
                "document_sha256": document_checksum,
                "clinical_review_status": review_status,
                "clinical_reviewer": signoff.get("reviewer_name") if approved else None,
                "clinical_reviewed_at": signoff.get("reviewed_at") if approved else None,
            }
        )

    completed = sum(record["clinical_review_status"] == "approved" for record in records)
    return {
        "scope_note": (
            "Bu rapor klinik onay değildir. Otomatik kalite ve kaynak triyajını "
            "klinik uzman incelemesinden ayrı tutar."
        ),
        "summary": {
            "documents": len(records),
            "clinical_signoff_completed": completed,
            "clinical_signoff_pending": len(records) - completed,
            "priority": dict(Counter(record["editorial_priority"] for record in records)),
            "source_strength": dict(Counter(record["source_strength"] for record in records)),
            "result_kind": dict(Counter(record["result_kind"] for record in records)),
        },
        "records": records,
    }
