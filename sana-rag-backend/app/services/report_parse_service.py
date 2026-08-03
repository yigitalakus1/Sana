"""Düz metin laboratuvar raporundan desteklenen test + değer çıkarımı.

Deterministik, satır-bazlı. PDF metni ayrı serviste çıkarılır; OCR/LLM YOK.
Yalnız raporda açıkça yazılı basit referans aralıkları kullanılır.
"""

import re
from datetime import date
from typing import List, Optional, Tuple

from app.core import constants as C
from app.services import retrieval_service
from app.services.normalization_service import normalize, turkish_lower
from app.services.reference_range_service import classify_value, extract_reference_range

# İlk basit sayı: bir word karakterinin hemen ardından gelen rakamı yakalamayız;
# böylece "B12" gibi test adlarındaki rakam değer sanılmaz.
_NUMBER_RE = re.compile(r"(?<!\w)[<>]?\s*-?\d+(?:[.,]\d+)?")

# mg/dL yanında hemogramlarda sık görülen fL, pg ve 10^3/uL biçimlerini de
# korur. Birim değerin hemen ardından gelmelidir.
_UNIT_RE = re.compile(
    r"\s*(%|(?:[xX]\s*)?10(?:\^?\d+|[⁰¹²³⁴⁵⁶⁷⁸⁹]+)\s*/\s*[A-Za-zµμ]+|"
    r"[A-Za-zµμ]+(?:\s*/\s*[A-Za-zµμ]+)?)"
)

_REPORT_LABEL_MAP = {
    "rbc": "Eritrosit Sayımı",
    "rbc count": "Eritrosit Sayımı",
    "mch": "MCH",
    "mchc": "MCHC",
    "rdw": "RDW",
    "rdw cv": "RDW",
    "rdw sd": "RDW",
    "neu": "Nötrofil",
    "neut": "Nötrofil",
    "neutrofil": "Nötrofil",
    "lym": "Lenfosit",
    "lymph": "Lenfosit",
    "mono": "Monosit",
    "mon": "Monosit",
    "eos": "Eozinofil",
    "baso": "Bazofil",
    "pdw": "PDW",
    "tibc": "Total Demir Bağlama Kapasitesi",
    "tıbc": "Total Demir Bağlama Kapasitesi",
    "tdbk": "Total Demir Bağlama Kapasitesi",
    "uibc": "Doymamış Demir Bağlama Kapasitesi",
    "uıbc": "Doymamış Demir Bağlama Kapasitesi",
    "transferrin saturation": "Transferrin Saturasyonu",
    "transferrin saturasyonu": "Transferrin Saturasyonu",
    "direkt bilirubin": "Direkt Bilirubin",
    "direct bilirubin": "Direkt Bilirubin",
    "indirekt bilirubin": "İndirekt Bilirubin",
    "indirect bilirubin": "İndirekt Bilirubin",
    "ındirect bilirubin": "İndirekt Bilirubin",
    "dbil": "Direkt Bilirubin",
    "ibil": "İndirekt Bilirubin",
    "ft3": "Serbest T3",
}
_REPORT_LABELS_BY_LENGTH = sorted(_REPORT_LABEL_MAP, key=len, reverse=True)
_RESULT_FLAG_RE = re.compile(r"^(?:h|l|high|low|yüksek|düşük|\*)$", re.IGNORECASE)


def _extract_value_unit(raw_line: str) -> Optional[Tuple[str, float, Optional[str]]]:
    m = _NUMBER_RE.search(raw_line)
    if not m:
        return None
    raw = m.group(0).replace("<", "").replace(">", "").strip()
    try:
        value = float(raw.replace(",", "."))
    except ValueError:
        return None
    um = _UNIT_RE.match(raw_line[m.end():])
    unit = um.group(1) if um else None
    return raw, value, unit


def _extract_standalone_value(raw_line: str) -> Optional[Tuple[str, float, Optional[str]]]:
    """Yalnız değer/birim içeren PDF tablo satırını güvenli biçimde çözer."""
    match = _NUMBER_RE.match(raw_line)
    if not match:
        return None
    raw = match.group(0).replace("<", "").replace(">", "").strip()
    try:
        value = float(raw.replace(",", "."))
    except ValueError:
        return None

    remainder = raw_line[match.end():].strip()
    unit = None
    if remainder:
        unit_match = _UNIT_RE.match(remainder)
        if unit_match:
            unit = unit_match.group(1)
            remainder = remainder[unit_match.end():].strip()
    if remainder and not _RESULT_FLAG_RE.fullmatch(remainder):
        # "0 - 7" gibi referans aralıklarını sonuç olarak kabul etme.
        return None
    return raw, value, unit


def _extract_unit_only(raw_line: str) -> Optional[str]:
    match = _UNIT_RE.fullmatch(raw_line.strip())
    return match.group(1) if match else None


def _range_after_value(raw_line: str) -> Optional[str]:
    """Sonuç ve birimden sonra kalan aynı-satır referans aralığını çıkarır."""
    value_match = _NUMBER_RE.search(raw_line)
    if value_match is None:
        return None
    offset = value_match.end()
    unit_match = _UNIT_RE.match(raw_line[offset:])
    if unit_match is not None:
        offset += unit_match.end()
    remainder = raw_line[offset:].strip()
    remainder = re.sub(
        r"^(?:h|l|high|low|yüksek|düşük|\*)\s+",
        "",
        remainder,
        flags=re.IGNORECASE,
    )
    return extract_reference_range(remainder)


def _range_from_following_lines(lines: List[str], start: int) -> Optional[str]:
    """Değer satırından sonraki en fazla üç satırda açık aralık arar."""
    for candidate in lines[start : start + 3]:
        if _resolve_report_lab(candidate, None).lab_test is not None:
            break
        reference_range = extract_reference_range(candidate)
        if reference_range is not None:
            return reference_range
    return None


def _resolve_report_lab(raw_line: str, unit: Optional[str]):
    number_match = _NUMBER_RE.search(raw_line)
    label = normalize(raw_line[: number_match.start()] if number_match else raw_line)
    label = re.sub(r"\b(?:high|low|yuksek|dusuk|yüksek|düşük)\b", "", label)
    label = re.sub(r"\s+", " ", label).strip()

    # PCT, hemogramda plateletkrit; farklı birimde ise prokalsitonin olabilir.
    if label == "pct":
        explicit = "Plateletkrit" if unit == "%" else "Prokalsitonin"
        return retrieval_service.resolve_lab_test(normalize(explicit), explicit)

    for report_label in _REPORT_LABELS_BY_LENGTH:
        normalized_label = normalize(report_label)
        if label == normalized_label or label.startswith(f"{normalized_label} "):
            explicit = _REPORT_LABEL_MAP[report_label]
            return retrieval_service.resolve_lab_test(normalize(explicit), explicit)
    return retrieval_service.resolve_lab_test(normalize(raw_line), None)


# --- Rapor tarihi çıkarımı -------------------------------------------------
#
# Yalnız ETİKETLİ tarihler kabul edilir. Etiketsiz bir sayı dizisini tarih
# saymak yanlış tarih üretebileceği için bilinçli olarak yapılmaz; tarih
# bulunamazsa None döner ve istemci dosya adı / kayıt zamanı yedeğine düşer.

# "Doğum tarihi" asla rapor tarihi değildir; bu satırlar atlanır.
_DATE_BLOCKLIST = ("doğum", "dogum")

# Öncelik sırası: en güvenilir etiket en başta.
_DATE_LABELS = (
    "rapor tarihi",
    "sonuç tarihi",
    "sonuc tarihi",
    "onay tarihi",
    "numune tarihi",
    "numune alma",
    "alınma tarihi",
    "alinma tarihi",
    "kabul tarihi",
    "işlem tarihi",
    "islem tarihi",
    "tarih",
)

# 01.02.2026 / 01-02-2026 / 01/02/2026 ve 2026-02-01
_DATE_DMY_RE = re.compile(r"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?!\d)")
_DATE_YMD_RE = re.compile(r"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)")

_MIN_REPORT_YEAR = 1990


def _safe_date(year: int, month: int, day: int, today: date) -> Optional[date]:
    """Takvimde gerçekten var olan, geçmiş ve makul bir tarih mi?"""
    try:
        parsed = date(year, month, day)
    except ValueError:
        return None
    if parsed.year < _MIN_REPORT_YEAR or parsed > today:
        return None
    return parsed


def _dates_in_line(line: str, today: date) -> List[date]:
    found: List[date] = []
    for match in _DATE_DMY_RE.finditer(line):
        day, month, year = (int(part) for part in match.groups())
        parsed = _safe_date(year, month, day, today)
        if parsed is not None:
            found.append(parsed)
    for match in _DATE_YMD_RE.finditer(line):
        year, month, day = (int(part) for part in match.groups())
        parsed = _safe_date(year, month, day, today)
        if parsed is not None:
            found.append(parsed)
    return found


def extract_report_date(text: str, today: Optional[date] = None) -> Optional[str]:
    """Rapor metnindeki etiketli tarihi ISO (YYYY-MM-DD) biçiminde döndürür.

    Emin olunamayan her durumda None döner: etiket yoksa, tarih takvimde
    geçersizse, gelecekteyse veya doğum tarihi satırındaysa alınmaz.
    """
    today = today or date.today()
    # Etiket önceliğine göre tara: önce "rapor tarihi", en son genel "tarih".
    candidates: dict[int, date] = {}
    for raw_line in text.splitlines():
        low = turkish_lower(raw_line)
        if any(blocked in low for blocked in _DATE_BLOCKLIST):
            continue
        label_index = next(
            (i for i, label in enumerate(_DATE_LABELS) if label in low), None
        )
        if label_index is None:
            continue
        dates = _dates_in_line(raw_line, today)
        if not dates:
            continue
        # Aynı etiket birden çok kez geçerse ilk görülen satır korunur.
        candidates.setdefault(label_index, dates[0])
    if not candidates:
        return None
    best = candidates[min(candidates)]
    return best.isoformat()


def parse_report(text: str) -> dict:
    """Metni satır satır tarar; desteklenen testleri değeriyle birlikte döndürür."""
    results: List[dict] = []
    seen = set()
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for index, line in enumerate(lines):
        vu = _extract_value_unit(line)
        if vu is None:
            # PDF tablo çıkarımında test adı, değer ve birim ayrı satırlara
            # düşebilir. Yalnız bir sonraki tek-değer satırını eşleştir.
            match = _resolve_report_lab(line, None)
            if match.lab_test is None or index + 1 >= len(lines):
                continue
            vu = _extract_standalone_value(lines[index + 1])
            if vu is None:
                continue
            raw, value, unit = vu
            consumed_through = index + 1
            if unit is None and index + 2 < len(lines):
                unit = _extract_unit_only(lines[index + 2])
                if unit is not None:
                    consumed_through = index + 2
            reference_range = _range_from_following_lines(
                lines, consumed_through + 1
            )
        else:
            raw, value, unit = vu
            match = _resolve_report_lab(line, unit)
            reference_range = _range_after_value(line)
            if reference_range is None:
                reference_range = _range_from_following_lines(lines, index + 1)
        if match.lab_test is None or match.lab_test in seen:
            continue
        seen.add(match.lab_test)
        results.append(
            {
                "lab_test": match.lab_test,
                "matched_term": match.matched_term,
                "raw_value": raw,
                "value": value,
                "unit": unit,
                "reference_range": reference_range,
                "interpretation": classify_value(value, reference_range),
            }
        )

    status = "parsed" if results else "no_results"
    return {
        "parser_status": status,
        "results": results,
        "disclaimer": C.DISCLAIMER,
        "report_date": extract_report_date(text),
    }
