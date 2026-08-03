"""Kullanıcı sorusundan basit sayısal değer bağlamı çıkarımı.

Yalnız veri çıkarımı yapar: ham değer + float karşılığı + (varsa) birim.
Referans aralığını yalnız açık bir "Rapor referans aralığı" etiketinden alır ve
durumu deterministik hesaplar. `unit` yalnız sayının hemen ardında bilinen bir
birim varsa doldurulur.
"""

import re
from typing import Optional

from app.services.reference_range_service import classify_value, extract_reference_range

# Bilinen laboratuvar birimleri. Örtüşen ekleri doğru yakalamak için UZUN olan
# önce gelir (örn. "mg/dL" < "mg/L" ayrımı, "mIU/L" < "IU/L" < "U/L").
_UNITS = [
    "10^3/µL", "10^3/uL",
    "mIU/L", "IU/L", "U/L",
    "mg/dL", "mg/L",
    "µg/dL", "ug/dL",
    "ng/mL", "pg/mL",
    "g/dL",
    "%",
]
_UNIT_ALT = "|".join(re.escape(u) for u in _UNITS)

# İlk basit sayı: ondalık ayracı . veya , olabilir. Bir word karakterinin
# (harf/rakam) hemen ardından gelen rakamı YAKALAMAYIZ; böylece "B12" gibi test
# adlarındaki rakamlar (ve içlerindeki 1/2) result_context'e sızmaz.
# Sayıdan hemen sonra (opsiyonel boşlukla) bilinen bir birim varsa yakalanır.
_NUMBER_UNIT_RE = re.compile(
    r"(?<!\w)(\d+(?:[.,]\d+)?)\s*(" + _UNIT_ALT + r")?",
    re.IGNORECASE,
)


def extract_result_context(question: str) -> Optional[dict]:
    """Soruda basit bir sayı varsa { raw_value, value, unit, ... } döndürür; yoksa None.

    Karmaşık parsing yok: yalnız ilk sayı ve onu izleyen bilinen birim alınır;
    negatif/aralık ve medikal yorum bu aşamanın dışındadır.
    """
    if not question:
        return None
    m = _NUMBER_UNIT_RE.search(question)
    if not m:
        return None
    raw = m.group(1)
    unit = m.group(2) or None
    try:
        value = float(raw.replace(",", "."))
    except ValueError:
        return None
    reference_range = extract_reference_range(question, require_label=True)
    return {
        "raw_value": raw,
        "value": value,
        "unit": unit,
        "reference_range": reference_range,
        "interpretation": classify_value(value, reference_range),
    }
