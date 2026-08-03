"""Onaylı resmî kaynaktan local Ollama ile Türkçe inceleme taslağı üretir."""

import argparse
import sys
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.source_draft_service import (  # noqa: E402
    SourceDraftError,
    generate_and_stage_source_draft,
)
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Onaylı kaynaktan pending Türkçe taslak üretir."
    )
    parser.add_argument("source_key")
    parser.add_argument("--db-path", default=None)
    args = parser.parse_args(argv)

    store = SourceSyncStore(db_path=args.db_path)
    try:
        result = generate_and_stage_source_draft(args.source_key, store=store)
    except SourceDraftError as exc:
        print(f"Taslak üretilemedi: {exc}")
        return 1

    print(f"Taslak staging sonucu: {result.outcome}")
    print(f"Kaynak: {result.draft.source_key}")
    print(f"Durum: {result.draft.review_status}")
    print(f"Taslak: {result.draft.content}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
