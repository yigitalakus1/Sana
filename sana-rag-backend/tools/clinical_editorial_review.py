"""Klinik editoryal inceleme kuyruğunu JSON ve Markdown olarak üretir."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.clinical_editorial_review import build_clinical_editorial_review  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs-dir", type=Path, default=Path("data/medical_docs"))
    parser.add_argument("--batch-dir", type=Path, default=Path("data/source_batches"))
    parser.add_argument(
        "--signoffs", type=Path, default=Path("data/clinical_editorial_signoffs.json")
    )
    parser.add_argument("--json-output", type=Path, default=Path("reports/clinical_editorial_review_latest.json"))
    parser.add_argument("--markdown-output", type=Path, default=Path("reports/clinical_editorial_review_latest.md"))
    args = parser.parse_args()

    report = build_clinical_editorial_review(args.docs_dir, args.batch_dir, args.signoffs)
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = report["summary"]
    lines = [
        "# Klinik Editoryal Inceleme Kuyrugu",
        "",
        f"> {report['scope_note']}",
        "",
        f"- Belge: **{summary['documents']}**",
        f"- Klinik uzman onayi tamamlanan: **{summary['clinical_signoff_completed']}**",
        f"- Klinik uzman onayi bekleyen: **{summary['clinical_signoff_pending']}**",
        f"- Oncelik dagilimi: `{json.dumps(summary['priority'], ensure_ascii=False)}`",
        f"- Kaynak gucu: `{json.dumps(summary['source_strength'], ensure_ascii=False)}`",
        "",
        "## Yuksek Oncelikli Kuyruk",
        "",
        "| Tahlil | Sonuc turu | Kaynak gucu | Neden |",
        "|---|---|---|---|",
    ]
    for record in report["records"]:
        if record["editorial_priority"] != "high":
            continue
        reasons = ", ".join(record["reason_codes"]) or "-"
        lines.append(
            f"| {record['lab_test']} | {record['result_kind']} | "
            f"{record['source_strength']} | {reasons} |"
        )
    lines.extend(
        (
            "",
            "## Inceleme Kurali",
            "",
            "Bir kayit ancak lisansli klinik uzman; kaynak uygunlugunu, testin neyi "
            "olctugunu, sonuc dilini, takip/aciliyet metnini ve hasta dilindeki "
            "anlasilirligi kontrol edip ad/tarih kaydi girdikten sonra klinik olarak "
            "onaylanmis sayilmalidir. JSON raporu 240 kaydin tam kuyrugunu icerir.",
        )
    )
    args.markdown_output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
