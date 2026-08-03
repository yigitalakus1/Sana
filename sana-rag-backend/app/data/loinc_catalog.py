"""Sana'nın desteklediği tahliller için doğrulanmış LOINC kataloğu.

Kodlar LOINC'in serum/plazma veya tam kan için yaygın nicel gözlem
tanımlarını kullanır. MedlinePlus Connect sorguları bu kodlarla yapılır.
"""

import csv
import re
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Tuple


LOINC_CODE_SYSTEM_OID = "2.16.840.1.113883.6.1"


@dataclass(frozen=True)
class LabSourceDefinition:
    lab_test: str
    loinc_code: str
    loinc_name: str
    medlineplus_url: str = ""
    common_test_rank: int | None = None

    @property
    def source_key(self) -> str:
        return f"medlineplus:{self.loinc_code}:en"


LAB_SOURCE_DEFINITIONS: Tuple[LabSourceDefinition, ...] = (
    LabSourceDefinition(
        "CRP",
        "1988-5",
        "C reactive protein [Mass/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/",
    ),
    LabSourceDefinition(
        "Glukoz",
        "2345-7",
        "Glucose [Mass/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/blood-glucose-test/",
    ),
    LabSourceDefinition(
        "Ferritin",
        "2276-4",
        "Ferritin [Mass/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/ferritin-blood-test/",
    ),
    LabSourceDefinition(
        "B12",
        "2132-9",
        "Cobalamin (Vitamin B12) [Mass/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/vitamin-b-test/",
    ),
    LabSourceDefinition(
        "Hemoglobin",
        "718-7",
        "Hemoglobin [Mass/volume] in Blood",
        "https://medlineplus.gov/lab-tests/hemoglobin-test/",
    ),
    LabSourceDefinition(
        "TSH",
        "3016-3",
        "Thyrotropin [Units/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/tsh-thyroid-stimulating-hormone-test/",
    ),
    LabSourceDefinition(
        "Kreatinin",
        "2160-0",
        "Creatinine [Mass/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/creatinine-test/",
    ),
    LabSourceDefinition(
        "ALT",
        "1742-6",
        "Alanine aminotransferase [Enzymatic activity/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/alt-blood-test/",
    ),
    LabSourceDefinition(
        "AST",
        "1920-8",
        "Aspartate aminotransferase [Enzymatic activity/volume] in Serum or Plasma",
        "https://medlineplus.gov/lab-tests/ast-test/",
    ),
    LabSourceDefinition(
        "Trombosit",
        "777-3",
        "Platelets [#/volume] in Blood by Automated count",
        "https://medlineplus.gov/lab-tests/platelet-tests/",
    ),
)

LAB_SOURCE_BY_NAME: Dict[str, LabSourceDefinition] = {
    item.lab_test: item for item in LAB_SOURCE_DEFINITIONS
}


class LoincCatalogError(ValueError):
    """Kontrollü LOINC katalog doğrulama hatası."""


_LOINC_CODE_RE = re.compile(r"^[0-9]{1,7}-[0-9]$")


def _validate_medlineplus_url(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    parsed = urllib.parse.urlparse(value)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or host != "medlineplus.gov":
        raise LoincCatalogError("medlineplus_url resmi bir HTTPS MedlinePlus URL'si olmalı.")
    return value


def _validate_catalog(definitions: Iterable[LabSourceDefinition]) -> Tuple[LabSourceDefinition, ...]:
    result = tuple(definitions)
    names = set()
    codes = set()
    for item in result:
        if not item.lab_test.strip() or not item.loinc_name.strip():
            raise LoincCatalogError("lab_test ve loinc_name boş olamaz.")
        if not _LOINC_CODE_RE.fullmatch(item.loinc_code.strip()):
            raise LoincCatalogError(f"Geçersiz LOINC kodu: {item.loinc_code}")
        name_key = item.lab_test.casefold()
        if name_key in names:
            raise LoincCatalogError(f"Yinelenen tahlil adı: {item.lab_test}")
        if item.loinc_code in codes:
            raise LoincCatalogError(f"Yinelenen LOINC kodu: {item.loinc_code}")
        _validate_medlineplus_url(item.medlineplus_url)
        names.add(name_key)
        codes.add(item.loinc_code)
    return result


def load_catalog_csv(
    path: str | Path, *, max_common_rank: int | None = None
) -> Tuple[LabSourceDefinition, ...]:
    """Sana veya resmi LOINC CSV'sini okur; ağ/yayın işlemi yapmaz."""
    catalog_path = Path(path)
    try:
        with catalog_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fields = set(reader.fieldnames or ())
            sana_fields = {"lab_test", "loinc_code", "loinc_name"}
            official_fields = {"LOINC_NUM", "LONG_COMMON_NAME"}
            if sana_fields.issubset(fields):
                rows = [
                    LabSourceDefinition(
                        lab_test=(row.get("lab_test") or "").strip(),
                        loinc_code=(row.get("loinc_code") or "").strip(),
                        loinc_name=(row.get("loinc_name") or "").strip(),
                        medlineplus_url=_validate_medlineplus_url(
                            row.get("medlineplus_url") or ""
                        ),
                        common_test_rank=(
                            int((row.get("common_test_rank") or "").strip())
                            if (row.get("common_test_rank") or "").strip().isdigit()
                            and int((row.get("common_test_rank") or "").strip()) > 0
                            else None
                        ),
                    )
                    for row in reader
                    if any((value or "").strip() for value in row.values())
                ]
            elif official_fields.issubset(fields):
                ranked_rows = []
                for row in reader:
                    if (row.get("STATUS") or "ACTIVE").strip() != "ACTIVE":
                        continue
                    if "CLASSTYPE" in fields and (row.get("CLASSTYPE") or "").strip() != "1":
                        continue
                    rank_text = (row.get("COMMON_TEST_RANK") or "").strip()
                    rank_value = int(rank_text) if rank_text.isdigit() else 0
                    rank = rank_value if rank_value > 0 else None
                    if max_common_rank is not None and (
                        rank is None or rank > max_common_rank
                    ):
                        continue
                    ranked_rows.append((rank if rank is not None else 10**9, row))
                ranked_rows.sort(key=lambda item: item[0])
                rows = [
                    LabSourceDefinition(
                        lab_test=(row.get("LONG_COMMON_NAME") or "").strip(),
                        loinc_code=(row.get("LOINC_NUM") or "").strip(),
                        loinc_name=(row.get("LONG_COMMON_NAME") or "").strip(),
                        common_test_rank=rank,
                    )
                    for rank, row in ranked_rows
                ]
            else:
                raise LoincCatalogError(
                    "CSV, Sana katalog veya resmi LOINC sütunlarını içermeli."
                )
    except OSError as exc:
        raise LoincCatalogError("LOINC katalog dosyası okunamadı.") from exc
    return _validate_catalog(rows)


def merge_catalogs(
    *catalogs: Iterable[LabSourceDefinition],
) -> Tuple[LabSourceDefinition, ...]:
    """Katalogları birleştirir; aynı kodda ilk/doğrulanmış tanımı korur."""
    merged = []
    seen_codes = set()
    for catalog in catalogs:
        for item in catalog:
            if item.loinc_code in seen_codes:
                continue
            seen_codes.add(item.loinc_code)
            merged.append(item)
    return _validate_catalog(merged)


def get_lab_source(lab_test: str) -> LabSourceDefinition:
    try:
        return LAB_SOURCE_BY_NAME[lab_test]
    except KeyError as exc:
        raise ValueError(f"Desteklenmeyen tahlil: {lab_test}") from exc
