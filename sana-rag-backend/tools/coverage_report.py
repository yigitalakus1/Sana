"""Sözlük kapsam analizi: neyi tanıyoruz, neyi açıklayabiliyoruz?

Üç boşluğu ayrı ayrı raporlar:

1. **Sessiz boşluk (kritik):** rapor ayrıştırıcı bir tahlili tanıyor ama o
   tahlilin sözlük belgesi yok. Kullanıcı değeri görür, açıklamayı göremez.
2. **Rapor etiketi boşluğu:** `_REPORT_LABEL_MAP` bir kısaltmayı kanonik bir
   test adına eşliyor ama o testin belgesi yok.
3. **Öncelik listesi:** Türkiye'de yaygın panellerde geçen ama katalogda
   bulunmayan testler (sıradaki batch adayları).

Ağ çağrısı yapmaz; yalnız yereldeki katalog ve belgeleri okur.

Kullanım:
    .venv\\Scripts\\python.exe -m tools.coverage_report
"""

import re
import sys
from pathlib import Path
from typing import Dict, List, Set

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.data.seed_documents import SEED_DOCUMENTS  # noqa: E402
from app.data.synonyms import SYNONYM_MAP  # noqa: E402
from app.services.report_parse_service import _REPORT_LABEL_MAP  # noqa: E402

DOCS_DIR = Path(__file__).resolve().parents[1] / "data" / "medical_docs"

# Türkiye'de sık istenen panellerde geçen analitler. Kaynak: WHO Temel İn Vitro
# Tanı Listesi (EDL 4) ve T.C. Sağlık Bakanlığı akılcı laboratuvar kullanımı
# belgelerindeki yaygın testler. Bu liste ÖNCELİKLENDİRME içindir; içerik
# üretmez ve hekim onayının yerine geçmez.
COMMON_PANELS: Dict[str, List[str]] = {
    "Hemogram": [
        "Hemoglobin", "Hematokrit", "Eritrosit Sayımı", "Lökosit Sayımı",
        "Trombosit", "MCV", "MCH", "MCHC", "RDW", "Nötrofil", "Lenfosit",
        "Monosit", "Eozinofil", "Bazofil", "MPV",
    ],
    "Biyokimya": [
        "Glukoz", "HbA1c", "Üre", "Kreatinin", "Ürik Asit", "ALT", "AST",
        "ALP", "GGT", "Total Bilirubin", "Direkt Bilirubin", "Albümin",
        "Total Protein", "LDH", "Amilaz", "Lipaz", "CRP", "Sedimentasyon",
    ],
    "Lipid": [
        "Total Kolesterol", "LDL Kolesterol", "HDL Kolesterol", "Trigliserit",
    ],
    "Tiroid": ["TSH", "Serbest T4", "Serbest T3", "Anti-TPO", "Anti-Tiroglobulin"],
    "Elektrolit": ["Sodyum", "Potasyum", "Klor", "Kalsiyum", "Magnezyum", "Fosfor"],
    "Vitamin/Mineral": ["B12", "Folat", "Ferritin", "Demir", "Vitamin D", "Transferrin"],
    "Koagülasyon": ["INR", "Protrombin Zamanı", "aPTT", "Fibrinojen", "D-Dimer"],
    "İdrar": ["Tam İdrar Tetkiki", "İdrar Protein", "İdrar Glukoz", "Mikroalbüminüri"],
}


def _norm(text: str) -> str:
    """Karşılaştırma için sadeleştirir (Türkçe I/İ duyarlı)."""
    text = text.replace("I", "ı").replace("İ", "i").lower()
    return re.sub(r"[^a-z0-9çğıöşü]+", "", text)


def documented_lab_tests() -> Set[str]:
    """`data/medical_docs` altındaki belgelerin lab_test değerleri."""
    found: Set[str] = set()
    for path in DOCS_DIR.glob("*.md"):
        for line in path.read_text(encoding="utf-8").splitlines()[:12]:
            match = re.match(r"^lab_test:\s*(.+?)\s*$", line)
            if match:
                found.add(match.group(1))
                break
    return found


def known_lab_tests() -> Set[str]:
    """Ayrıştırıcı/retrieval tarafından tanınan kanonik test adları."""
    known = {doc["lab_test"] for doc in SEED_DOCUMENTS}
    known |= set(SYNONYM_MAP.keys())
    return known


def main() -> int:
    documented = documented_lab_tests()
    documented_norm = {_norm(name) for name in documented}
    known = known_lab_tests()

    print(f"Sözlük belgesi olan test  : {len(documented)}")
    print(f"Tanınan (katalog) test    : {len(known)}")
    print()

    # 1) Tanınıyor ama belgesi yok
    silent = sorted(
        name for name in known if _norm(name) not in documented_norm
    )
    print(f"[1] Tanınıyor ama açıklaması YOK : {len(silent)}")
    for name in silent:
        print(f"    - {name}")
    print()

    # 2) Rapor kısaltması belgesiz bir teste eşleniyor
    label_gaps = sorted(
        {
            f"{label} -> {canonical}"
            for label, canonical in _REPORT_LABEL_MAP.items()
            if _norm(canonical) not in documented_norm
        }
    )
    print(f"[2] Rapor kısaltması belgesiz teste gidiyor : {len(label_gaps)}")
    for row in label_gaps:
        print(f"    - {row}")
    print()

    # 3) Yaygın panellerde eksik olanlar (sıradaki batch adayları)
    print("[3] Yaygın panellerde eksik olanlar (öncelikli adaylar)")
    total_missing = 0
    for panel, tests in COMMON_PANELS.items():
        missing = [t for t in tests if _norm(t) not in documented_norm]
        total_missing += len(missing)
        covered = len(tests) - len(missing)
        print(f"    {panel}: {covered}/{len(tests)} kapsandı")
        for name in missing:
            print(f"        eksik: {name}")
    print()
    print(f"Toplam eksik yaygın test: {total_missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
