"""Tahlil sozlugu kalite raporunu JSON ve Markdown olarak uretir."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.medical_content_audit import build_medical_content_audit  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs-dir", type=Path, default=Path("data/medical_docs"))
    parser.add_argument("--batch-dir", type=Path, default=Path("data/source_batches"))
    parser.add_argument("--json-output", type=Path, default=Path("reports/medical_content_audit_latest.json"))
    parser.add_argument("--markdown-output", type=Path, default=Path("reports/medical_content_audit_latest.md"))
    args = parser.parse_args()

    report = build_medical_content_audit(args.docs_dir, args.batch_dir)
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = report["summary"]
    lines = [
        "# Tahlil Sozlugu Icerik Denetimi",
        "",
        f"- Belge: {summary['documents']}",
        f"- Katalog kaydi: {summary['catalog_items']}",
        f"- Sorun: {summary['issues']}",
        f"- Sonuc: {'PASS' if summary['passed'] else 'FAIL'}",
        "",
        "## Sorunlar",
        "",
    ]
    lines.extend(
        f"- `{issue['code']}` - **{issue['subject']}**: {issue['detail']}"
        for issue in report["issues"]
    )
    if not report["issues"]:
        lines.append("- Kritik yapisal, kaynak, alias veya guvenlik sorunu bulunmadi.")
    args.markdown_output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
