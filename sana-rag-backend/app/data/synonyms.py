"""Lab değerleri için eş anlamlı / yaygın yazım haritası.

Çok geniş ifadeler ("kan değeri" gibi) bilinçli olarak hariç tutulmuştur.
"""

import json
from pathlib import Path

SYNONYM_MAP = {
    "CRP": [
        "crp", "c-reaktif protein", "c reaktif protein", "c reaktif",
        "creaktif protein", "c-reactive protein", "c reactive protein",
        "crp değeri", "iltihap değeri", "hs-crp", "hs crp",
    ],
    "Glukoz": [
        "glukoz", "glikoz", "glucose", "kan şekeri", "kan sekeri",
        "açlık şekeri", "aclik sekeri", "açlık kan şekeri", "açlık glukoz",
        "kan glukozu", "şeker",
    ],
    "Ferritin": [
        "ferritin", "ferritin değeri", "serum ferritin", "demir deposu",
        "demir deposu değeri", "depo demir", "demir depo proteini",
    ],
    "B12": [
        "b12", "b 12", "b-12", "vitamin b12", "vit b12", "b12 vitamini",
        "b12 değeri", "kobalamin", "cobalamin",
    ],
    "Hemoglobin": [
        "hemoglobin", "hgb", "hb", "hgb değeri", "hb değeri",
        "hemoglobin değeri", "hemoglobin düzeyi",
    ],
    "TSH": [
        "tsh", "tiroid stimülan hormon", "tiroid uyarıcı hormon", "tirotropin",
        "tsh değeri",
    ],
    "Kreatinin": [
        "kreatinin", "creatinine", "serum kreatinin", "kan kreatinin",
        "kreatinin değeri",
    ],
    "ALT": [
        "alt", "alanin aminotransferaz", "alanin transaminaz", "sgpt", "gpt",
        "alt değeri",
    ],
    "AST": [
        "ast", "aspartat aminotransferaz", "aspartat transaminaz", "sgot", "got",
        "ast değeri",
    ],
    "Trombosit": [
        "trombosit", "platelet", "platelet count", "plt", "trombosit sayısı",
        "trombosit değeri",
    ],
}


def _load_reviewed_batch_aliases():
    directory = (
        Path(__file__).resolve().parents[2]
        / "data"
        / "source_batches"
    )
    for path in sorted(directory.glob("*_rag.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for item in payload.get("items", []):
            SYNONYM_MAP[item["lab_test"]] = list(item["aliases"])


_load_reviewed_batch_aliases()

# Hastane raporlarında tam kan sayımı bileşenleri çoğunlukla yalnız teknik
# kısaltmayla yazılır. Mevcut kanonik seed'lere bu yaygın kodları bağla.
for _lab_test, _aliases in {
    "Eritrosit Sayımı": ["rbc", "rbc count"],
    "Lökosit": ["wbc", "wbc count"],
}.items():
    if _lab_test in SYNONYM_MAP:
        SYNONYM_MAP[_lab_test] = list(dict.fromkeys(SYNONYM_MAP[_lab_test] + _aliases))

LAB_VALUES = list(SYNONYM_MAP.keys())
