"""Onaylanmis resmi kaynak kataloglarini Markdown ve seed verisine donusturur."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import constants as C  # noqa: E402
from tools.publish_source_batch import SECTIONS, _sections  # noqa: E402


ALLOWED_SOURCE_HOSTS = {
    "www.who.int",
    "who.int",
    "tkbd.org",
    "www.tkbd.org",
    "medlineplus.gov",
    "www.medlineplus.gov",
    "ncbi.nlm.nih.gov",
    "www.ncbi.nlm.nih.gov",
}


def _is_allowed_source_url(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    return (
        parsed.scheme == "https"
        and bool(parsed.path)
        and (host in ALLOWED_SOURCE_HOSTS or host.endswith(".saglik.gov.tr"))
    )


def validate_catalog(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    if payload.get("review_status") != "approved":
        raise ValueError("Katalog acikca onaylanmis olmalidir.")
    if not str(payload.get("reviewed_by", "")).strip():
        raise ValueError("Katalog reviewer bilgisi icermelidir.")
    if not str(payload.get("reviewed_at", "")).strip():
        raise ValueError("Katalog review tarihi icermelidir.")

    items = payload.get("items")
    if not isinstance(items, list) or not items:
        raise ValueError("Katalog items listesi icermelidir.")

    required = {
        "source_key",
        "source_title",
        "source_url",
        "lab_test",
        "slug",
        "title",
        "aliases",
        "definition",
        "purpose",
        "result_kind",
    }
    seen_keys = set()
    seen_labs = set()
    seen_slugs = set()
    for item in items:
        missing = required.difference(item)
        if missing:
            raise ValueError(f"Eksik katalog alani: {', '.join(sorted(missing))}")
        source_key = str(item["source_key"]).strip()
        lab = str(item["lab_test"]).strip()
        slug = str(item["slug"]).strip()
        if not source_key or source_key in seen_keys:
            raise ValueError(f"Gecersiz veya yinelenen source_key: {source_key}")
        if not lab or lab in seen_labs:
            raise ValueError(f"Gecersiz veya yinelenen lab_test: {lab}")
        if not slug or slug in seen_slugs:
            raise ValueError(f"Gecersiz veya yinelenen slug: {slug}")
        if item["result_kind"] not in {"scalar", "panel", "qualitative"}:
            raise ValueError(f"Gecersiz result_kind: {lab}")
        if not isinstance(item["aliases"], list) or not item["aliases"]:
            raise ValueError(f"Alias listesi bos: {lab}")
        if not str(item["definition"]).strip() or not str(item["purpose"]).strip():
            raise ValueError(f"Guvenli aciklama eksik: {lab}")
        if not _is_allowed_source_url(str(item["source_url"])):
            raise ValueError(f"Resmi kaynak URL'si gecersiz: {lab}")
        seen_keys.add(source_key)
        seen_labs.add(lab)
        seen_slugs.add(slug)
    return items


def _markdown(item: Dict[str, Any], sections: Dict[str, str]) -> str:
    lines = [
        "---",
        f"lab_test: {item['lab_test']}",
        f"source_title: {item['source_title']}",
        f"source_url: {item['source_url']}",
        "safety_level: general",
        "---",
        "",
    ]
    for heading in SECTIONS:
        lines.extend((f"## {heading}", sections[heading], ""))
    return "\n".join(lines)


def publish_catalog(catalog_path: Path, docs_dir: Path, seed_output: Path) -> int:
    payload = json.loads(catalog_path.read_text(encoding="utf-8"))
    items = validate_catalog(payload)
    docs_dir.mkdir(parents=True, exist_ok=True)
    seed_output.parent.mkdir(parents=True, exist_ok=True)
    documents = []
    for item in items:
        sections = _sections(item, item["definition"])
        (docs_dir / f"{item['slug']}.md").write_text(
            _markdown(item, sections), encoding="utf-8"
        )
        documents.append(
            {
                "lab_test": item["lab_test"],
                "title": item["title"],
                "source_title": item["source_title"],
                "source_url": item["source_url"],
                "sections": sections,
                "doctor_questions": [
                    part.strip() + "?"
                    for part in sections[C.SECTION_DOCTOR_QUESTIONS].split("?")
                    if part.strip()
                ],
            }
        )
    seed_output.write_text(
        json.dumps(
            {"batch_id": payload["batch_id"], "documents": documents},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return len(documents)


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Onayli resmi kaynak katalogunu yayinlar.")
    parser.add_argument("catalog_path", type=Path)
    parser.add_argument("--docs-dir", type=Path, default=Path("data/medical_docs"))
    parser.add_argument("--seed-output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        count = publish_catalog(args.catalog_path, args.docs_dir, args.seed_output)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Katalog yayinlanamadi: {exc}")
        return 1
    print(f"Yayinlanan resmi kaynak belgesi: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
