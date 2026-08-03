"""RAG katalog amacindan guvenli, sayisiz Turkce kaynak taslagi asamalar."""

import argparse
import json
import sys
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.source_draft_service import validate_source_draft  # noqa: E402
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="RAG katalogundan pending taslak asamalar.")
    parser.add_argument("catalog_path", type=Path)
    parser.add_argument("--db-path", default="data/sana_rag.db")
    args = parser.parse_args(argv)

    payload = json.loads(args.catalog_path.read_text(encoding="utf-8"))
    items = payload.get("items", [])
    store = SourceSyncStore(args.db_path)
    prepared = []
    seen = set()
    for item in items:
        source_key = item["source_key"]
        if source_key in seen:
            raise ValueError(f"Yinelenen kaynak: {source_key}")
        seen.add(source_key)
        source = store.get(source_key)
        if source is None or source.review_status != "approved":
            raise ValueError(f"Kaynak onayli degil: {source_key}")
        content = (
            f"{item['purpose']} Sonuç kullanılan örnek ve yöntemle birlikte "
            "değerlendirilir. Tek başına tanı koydurmaz."
        )
        prepared.append(
            (source_key, validate_source_draft(content, source.summary))
        )

    outcomes = {"created": 0, "changed": 0, "unchanged": 0}
    for source_key, content in prepared:
        outcome = store.stage_draft(
            source_key, content, "codex-grounded-catalog-v1"
        )
        outcomes[outcome] += 1
    print(f"Dogrulanan taslak: {len(prepared)}")
    print(json.dumps(outcomes, ensure_ascii=False))
    print("Durum: pending")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
