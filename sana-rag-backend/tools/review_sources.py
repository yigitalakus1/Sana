"""Staging kaynaklarını listeler ve açık insan inceleme durumunu yönetir."""

import argparse
import sys
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def _print_records(records) -> None:
    if not records:
        print("Kayıt bulunamadı.")
        return
    for record in records:
        print(
            f"{record.source_key} | {record.lab_test} | {record.review_status} | "
            f"{record.title} | {record.source_url}"
        )


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resmî kaynak inceleme kuyruğu.")
    parser.add_argument("--db-path", default=None, help="SQLite RAG/store yolu.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list")
    list_parser.add_argument(
        "--status", choices=("pending", "approved", "rejected"), default="pending"
    )

    for command in ("approve", "reject"):
        action = subparsers.add_parser(command)
        action.add_argument("source_key")
        action.add_argument("--reviewer", required=True)

    publish = subparsers.add_parser("publish")
    publish.add_argument("source_key")

    draft_list = subparsers.add_parser("draft-list")
    draft_list.add_argument(
        "--status",
        choices=("pending", "approved", "rejected", "stale"),
        default="pending",
    )

    for command in ("draft-approve", "draft-reject"):
        action = subparsers.add_parser(command)
        action.add_argument("source_key")
        action.add_argument("--reviewer", required=True)

    draft_publish = subparsers.add_parser("draft-publish")
    draft_publish.add_argument("source_key")

    args = parser.parse_args(argv)
    store = SourceSyncStore(db_path=args.db_path)

    if args.command == "list":
        _print_records(store.list_by_status(args.status))
    elif args.command == "approve":
        store.approve(args.source_key, args.reviewer)
        print(f"Onaylandı: {args.source_key}")
    elif args.command == "reject":
        store.reject(args.source_key, args.reviewer)
        print(f"Reddedildi: {args.source_key}")
    elif args.command == "publish":
        store.mark_published(args.source_key)
        print(f"Yayın işareti eklendi: {args.source_key}")
    elif args.command == "draft-list":
        drafts = store.list_drafts(args.status)
        if not drafts:
            print("Taslak bulunamadı.")
        for draft in drafts:
            print(
                f"{draft.source_key} | {draft.review_status} | "
                f"{draft.generator} | {draft.content}"
            )
    elif args.command == "draft-approve":
        store.approve_draft(args.source_key, args.reviewer)
        print(f"Taslak onaylandı: {args.source_key}")
    elif args.command == "draft-reject":
        store.reject_draft(args.source_key, args.reviewer)
        print(f"Taslak reddedildi: {args.source_key}")
    elif args.command == "draft-publish":
        store.mark_draft_published(args.source_key)
        print(f"Taslak yayın işareti eklendi: {args.source_key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
