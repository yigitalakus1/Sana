"""Laboratuvar raporunda açıkça yazılı basit referans aralıklarını işler."""

import re
from typing import Optional, Tuple


_NUMBER = r"-?\d+(?:[.,]\d+)?"
_LABEL = (
    r"(?:rapor\s+)?(?:referans(?:\s+aral(?:ı|i)ğ(?:ı|i))?|"
    r"normal\s+(?:değer|deger|aralık|aralik))\s*[:=]?\s*"
)
_BOUNDED_RE = re.compile(
    rf"(?P<low>{_NUMBER})\s*(?P<separator>[-–—]|\.\.|…|ile)\s*"
    rf"(?P<high>{_NUMBER})",
    re.IGNORECASE,
)
_LIMIT_RE = re.compile(rf"(?P<operator><=|>=|<|>|≤|≥)\s*(?P<limit>{_NUMBER})")
_LABELED_RE = re.compile(_LABEL, re.IGNORECASE)


def _to_float(value: str) -> float:
    return float(value.replace(",", "."))


def _clean_match(match: re.Match) -> str:
    if "low" in match.groupdict():
        return f"{match.group('low')} - {match.group('high')}"
    operator = match.group("operator").replace("≤", "<=").replace("≥", ">=")
    return f"{operator} {match.group('limit')}"


def extract_reference_range(text: str, *, require_label: bool = False) -> Optional[str]:
    """Metindeki basit sayısal aralığı döndürür; belirsiz biçimleri reddeder."""
    if not text:
        return None

    search_text = text.strip().strip("()[]{}")
    label = _LABELED_RE.search(search_text)
    if require_label and label is None:
        return None
    if label is not None:
        search_text = search_text[label.end():]

    matches = list(_BOUNDED_RE.finditer(search_text)) + list(_LIMIT_RE.finditer(search_text))
    if len(matches) != 1:
        return None

    match = matches[0]
    # Ek sayılar yaşa/cinsiyete göre birden çok aralık bulunduğunu gösterebilir.
    remainder = search_text[: match.start()] + " " + search_text[match.end():]
    if re.search(_NUMBER, remainder):
        return None
    if "low" in match.groupdict():
        if _to_float(match.group("low")) > _to_float(match.group("high")):
            return None
    return _clean_match(match)


def _parse_range(reference_range: str) -> Optional[Tuple[str, float, Optional[float]]]:
    bounded = _BOUNDED_RE.fullmatch(reference_range.strip())
    if bounded:
        low = _to_float(bounded.group("low"))
        high = _to_float(bounded.group("high"))
        if low > high:
            return None
        return "bounded", low, high

    limit = _LIMIT_RE.fullmatch(reference_range.strip())
    if limit:
        operator = limit.group("operator").replace("≤", "<=").replace("≥", ">=")
        return operator, _to_float(limit.group("limit")), None
    return None


def classify_value(value: float, reference_range: Optional[str]) -> Optional[str]:
    """Basit bir rapor aralığına göre yalnız low/normal/high hesaplar."""
    if reference_range is None:
        return None
    parsed = _parse_range(reference_range)
    if parsed is None:
        return None

    kind, first, second = parsed
    if kind == "bounded" and second is not None:
        if value < first:
            return "low"
        if value > second:
            return "high"
        return "normal"
    if kind in ("<", "<="):
        inside = value < first if kind == "<" else value <= first
        return "normal" if inside else "high"
    if kind in (">", ">="):
        inside = value > first if kind == ">" else value >= first
        return "normal" if inside else "low"
    return None
