"""Yerel tahlil sozlugu icin deterministik icerik kalite denetimi."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from app.core import constants as C
from app.services.normalization_service import normalize
from tools.publish_curated_source_batch import ALLOWED_SOURCE_HOSTS
from tools.publish_source_batch import SECTIONS


EXPECTED_DOCUMENT_COUNT = 240
MIN_SECTION_LENGTH = 45
MIN_SECTION_LENGTHS = {
    C.SECTION_WHAT: 100,
    C.SECTION_WHY: 50,
    C.SECTION_HIGH: 120,
    C.SECTION_LOW: 120,
    C.SECTION_WHEN_DOCTOR: 120,
    C.SECTION_DOCTOR_QUESTIONS: 120,
}
_FRONT_MATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_HEADING = re.compile(r"^## (.+?)\s*$", re.MULTILINE)
_UNSAFE_PATTERNS = (
    re.compile(r"\b(?:ilac|ilaç)\s+(?:al|kullan)(?:in|ın|iniz|ınız)?\b", re.IGNORECASE),
    re.compile(r"\bdoz(?:u|unu)?\s+(?:artir|artır|azalt|degistir|değiştir)\b", re.IGNORECASE),
    re.compile(r"\btedaviye\s+basla(?:yin|yın)?\b", re.IGNORECASE),
)


def _parse_document(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    front_match = _FRONT_MATTER.search(text)
    metadata: dict[str, str] = {}
    if front_match:
        for line in front_match.group(1).splitlines():
            key, separator, value = line.partition(":")
            if separator:
                metadata[key.strip()] = value.strip()

    matches = list(_HEADING.finditer(text))
    sections = {
        match.group(1): text[match.end() : matches[index + 1].start() if index + 1 < len(matches) else None].strip()
        for index, match in enumerate(matches)
    }
    return {"path": path, "metadata": metadata, "sections": sections, "text": text}


def _catalog_items(batch_dir: Path) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for path in sorted(batch_dir.glob("*_rag.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for item in payload.get("items", []):
            items.append({**item, "_catalog": path.name})
    return items


def _is_allowed_source(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    return (
        parsed.scheme == "https"
        and bool(parsed.path)
        and (host in ALLOWED_SOURCE_HOSTS or host.endswith(".saglik.gov.tr"))
    )


def build_medical_content_audit(docs_dir: Path, batch_dir: Path) -> dict[str, Any]:
    documents = [_parse_document(path) for path in sorted(docs_dir.glob("*.md"))]
    catalog = _catalog_items(batch_dir)
    issues: list[dict[str, str]] = []

    def add(code: str, subject: str, detail: str) -> None:
        issues.append({"code": code, "subject": subject, "detail": detail})

    if len(documents) != EXPECTED_DOCUMENT_COUNT:
        add("document_count", "medical_docs", f"Beklenen {EXPECTED_DOCUMENT_COUNT}, bulunan {len(documents)}")

    docs_by_lab: dict[str, dict[str, Any]] = {}
    source_hosts: Counter[str] = Counter()
    for document in documents:
        path = document["path"]
        metadata = document["metadata"]
        lab = metadata.get("lab_test", "")
        lab_key = normalize(lab)
        if not lab:
            add("missing_lab_test", path.name, "Front matter lab_test alani yok")
        elif lab_key in docs_by_lab:
            add("duplicate_lab_test", lab, f"Birden fazla belge: {path.name}")
        else:
            docs_by_lab[lab_key] = document

        url = metadata.get("source_url", "")
        if not _is_allowed_source(url):
            add("untrusted_source", lab or path.name, url or "Kaynak URL'si yok")
        else:
            source_hosts[(urlparse(url).hostname or "").lower()] += 1

        if tuple(document["sections"].keys()) != SECTIONS:
            add("section_contract", lab or path.name, "Zorunlu alti bolum eksik veya sirasi hatali")
        for heading in SECTIONS:
            content = document["sections"].get(heading, "")
            minimum = MIN_SECTION_LENGTHS.get(heading, MIN_SECTION_LENGTH)
            if len(content) < minimum:
                add("short_section", lab or path.name, f"{heading}: {len(content)} karakter")
        for pattern in _UNSAFE_PATTERNS:
            if pattern.search(document["text"]):
                add("unsafe_instruction", lab or path.name, pattern.pattern)

    catalog_by_lab = {normalize(item["lab_test"]): item for item in catalog}
    for key, item in catalog_by_lab.items():
        document = docs_by_lab.get(key)
        if document is None:
            add("missing_document", item["lab_test"], item["_catalog"])
            continue
        metadata = document["metadata"]
        expected_url = item.get("source_url")
        if expected_url and metadata.get("source_url", "").rstrip("/") != str(expected_url).rstrip("/"):
            add("source_mismatch", item["lab_test"], f"{metadata.get('source_url')} != {expected_url}")

    exact_labs = set(docs_by_lab)
    for item in catalog:
        for alias in item.get("aliases", []):
            alias_key = normalize(str(alias))
            if alias_key in exact_labs and alias_key != normalize(item["lab_test"]):
                add("alias_collision", item["lab_test"], f"'{alias}' baska bir testin tam adiyla cakisti")

    return {
        "summary": {
            "documents": len(documents),
            "catalog_items": len(catalog),
            "source_hosts": dict(sorted(source_hosts.items())),
            "issues": len(issues),
            "passed": not issues,
        },
        "issues": issues,
    }
