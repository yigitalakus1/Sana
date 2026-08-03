"""MedlinePlus staging ve mevcut Türkçe RAG karşılaştırma raporu üretir."""

import argparse
import sys
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.source_review_report_service import (  # noqa: E402
    build_source_review_report,
    write_source_review_report,
)
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resmî kaynak inceleme raporu.")
    parser.add_argument("--db-path", default="data/sana_rag.db")
    parser.add_argument("--docs-dir", default="data/medical_docs")
    parser.add_argument(
        "--json-output", default="reports/source_review_latest.json"
    )
    parser.add_argument(
        "--markdown-output", default="reports/source_review_latest.md"
    )
    args = parser.parse_args(argv)

    report = build_source_review_report(
        SourceSyncStore(args.db_path), Path(args.docs_dir)
    )
    write_source_review_report(
        report, Path(args.json_output), Path(args.markdown_output)
    )
    summary = report["summary"]
    print(f"Kaynak raporu: {summary['total']} kayıt")
    print(f"Onay bekleyen kaynak: {summary['pending_sources']}")
    print(f"Geniş konu eşleşmesi: {summary['broader_matches']}")
    print(f"JSON: {Path(args.json_output).resolve()}")
    print(f"Markdown: {Path(args.markdown_output).resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
