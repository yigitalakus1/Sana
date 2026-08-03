"""Dogrulanmis Turkce kaynak taslaklarini inceleme kuyruguna ekler."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.source_draft_service import (  # noqa: E402
    SourceDraftError,
    validate_source_draft,
)
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def load_and_validate_batch(
    batch_path: Path, store: SourceSyncStore
) -> Tuple[str, List[Tuple[str, str]]]:
    payload: Dict[str, Any] = json.loads(batch_path.read_text(encoding="utf-8"))
    generator = str(payload.get("generator", "")).strip()
    drafts = payload.get("drafts")
    if not generator or not isinstance(drafts, list) or not drafts:
        raise ValueError("Batch generator ve drafts listesi icermelidir.")

    prepared: List[Tuple[str, str]] = []
    seen = set()
    for item in drafts:
        if not isinstance(item, dict):
            raise ValueError("Her taslak bir nesne olmalidir.")
        source_key = str(item.get("source_key", "")).strip()
        content = str(item.get("content", "")).strip()
        if not source_key or source_key in seen:
            raise ValueError(f"Gecersiz veya yinelenen source_key: {source_key}")
        seen.add(source_key)

        source = store.get(source_key)
        if source is None:
            raise ValueError(f"Kaynak bulunamadi: {source_key}")
        if source.review_status != "approved":
            raise ValueError(f"Kaynak onayli degil: {source_key}")
        if not source.source_url.startswith("https://medlineplus.gov/lab-tests/"):
            raise ValueError(f"Dogrudan MedlinePlus test sayfasi degil: {source_key}")
        try:
            cleaned = validate_source_draft(content, source.summary)
        except SourceDraftError as exc:
            raise ValueError(f"Taslak kalite kapisini gecemedi ({source_key}): {exc}") from exc
        prepared.append((source_key, cleaned))
    return generator, prepared


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Kontrollu Turkce batch taslaklarini pending olarak asamalar."
    )
    parser.add_argument("batch_path", type=Path)
    parser.add_argument("--db-path", default="data/sana_rag.db")
    args = parser.parse_args(argv)

    store = SourceSyncStore(args.db_path)
    try:
        generator, drafts = load_and_validate_batch(args.batch_path, store)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Batch asamalanamadi: {exc}")
        return 1

    outcomes = {"created": 0, "changed": 0, "unchanged": 0}
    for source_key, content in drafts:
        outcome = store.stage_draft(source_key, content, generator)
        outcomes[outcome] += 1

    print(f"Dogrulanan taslak: {len(drafts)}")
    print(f"Olusturulan: {outcomes['created']}")
    print(f"Guncellenen: {outcomes['changed']}")
    print(f"Degismeyen: {outcomes['unchanged']}")
    print("Durum: pending")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
