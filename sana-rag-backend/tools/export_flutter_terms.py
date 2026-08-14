"""Export reviewed lab terms to the Flutter offline asset.

The backend seed remains the canonical source. This command creates a stable,
versioned JSON catalog without making a network request.
"""

from __future__ import annotations

import argparse
import json
from collections import OrderedDict
from pathlib import Path

from app.core import constants as C
from app.data import seed_documents
from app.data.synonyms import SYNONYM_MAP


DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[2]
    / "sana-app"
    / "assets"
    / "data"
    / "lab_terms_v1.json"
)
EXPECTED_TERM_COUNT = 240


def build_catalog() -> dict:
    terms: OrderedDict[str, dict] = OrderedDict()
    for chunk in seed_documents.get_all_chunks():
        term = terms.setdefault(
            chunk.lab_test,
            {
                "lab_test": chunk.lab_test,
                "title": chunk.title,
                "aliases": list(SYNONYM_MAP.get(chunk.lab_test, [])),
                "sections": [],
                "section_contents": {},
                "sources": [],
            },
        )
        if chunk.section not in term["sections"]:
            term["sections"].append(chunk.section)
        term["section_contents"][chunk.section] = chunk.content.strip()

        source = {
            "source_title": chunk.source_title,
            "source_url": chunk.source_url,
            "section": None,
        }
        if source not in term["sources"]:
            term["sources"].append(source)

    if len(terms) != EXPECTED_TERM_COUNT:
        raise RuntimeError(
            f"Expected {EXPECTED_TERM_COUNT} terms, found {len(terms)}. "
            "Review the mobile catalog version before exporting."
        )

    for term in terms.values():
        missing = [
            section
            for section in term["sections"]
            if not term["section_contents"].get(section)
        ]
        if missing:
            raise RuntimeError(f"{term['lab_test']} has empty sections: {missing}")

    return {
        "schema_version": 1,
        "term_count": len(terms),
        "disclaimer": C.DISCLAIMER,
        "terms": list(terms.values()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    payload = build_catalog()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Exported {payload['term_count']} terms to {args.output}")


if __name__ == "__main__":
    main()
