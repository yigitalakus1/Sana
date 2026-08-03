"""Rule-based intent ve section tespiti + güvenlik bağlam bayrakları.

Tüm fonksiyonlar NORMALIZE EDİLMİŞ metin bekler.
"""

from dataclasses import dataclass
from typing import Optional

from app.core import constants as C


def _any(text: str, patterns) -> bool:
    return any(p in text for p in patterns)


@dataclass
class SafetyContext:
    is_emergency: bool = False
    is_pediatric: bool = False
    is_diagnosis: bool = False
    is_treatment: bool = False


def detect_intent(normalized_text: str, age: Optional[int] = None) -> str:
    """Öncelik sırasına göre tek bir birincil intent döndürür.

    Güvenlik açısından kritik intentler (acil, ilaç/doz, doktordan kaçınma, teşhis,
    tedavi, pediatrik) yüksek/düşük gibi içerik intentlerinden önce gelir.
    """
    t = normalized_text

    # İlaç/doz/takviye/tedavi istekleri emergency'den ÖNCE bloklanır: medikal-blok
    # her zaman güvenli bir yanıttır ve sonuçtaki sayısal değerin (örn. "350")
    # yanlışlıkla emergency tetiklemesinden etkilenmez.
    if _any(t, C.MED_DOSAGE_PATTERNS):
        return C.INTENT_MED_DOSAGE
    if _any(t, C.MED_SUPPLEMENT_PATTERNS):
        return C.INTENT_MED_SUPPLEMENT
    if _any(t, C.EMERGENCY_PATTERNS):
        return C.INTENT_EMERGENCY
    if _any(t, C.DOCTOR_AVOIDANCE_PATTERNS):
        return C.INTENT_DOCTOR_AVOIDANCE
    if _any(t, C.DIAGNOSIS_PATTERNS):
        return C.INTENT_DIAGNOSIS
    if _any(t, C.TREATMENT_PATTERNS):
        return C.INTENT_TREATMENT
    if (age is not None and age < C.PEDIATRIC_AGE_LIMIT) or _any(t, C.PEDIATRIC_PATTERNS):
        return C.INTENT_PEDIATRIC
    if _any(t, C.NORMAL_RANGE_PATTERNS):
        return C.INTENT_NORMAL_RANGE
    if _any(t, C.DOCTOR_QUESTION_PATTERNS):
        return C.INTENT_DOCTOR_QUESTIONS
    if _any(t, C.HIGH_PATTERNS):
        return C.INTENT_HIGH
    if _any(t, C.LOW_PATTERNS):
        return C.INTENT_LOW
    if _any(t, C.DEFINITION_PATTERNS):
        return C.INTENT_DEFINITION
    return C.INTENT_GENERAL


def detect_safety_context(normalized_text: str, age: Optional[int] = None) -> SafetyContext:
    """Birincil intent'ten bağımsız olarak güvenlik bayraklarını çıkarır.

    Böylece 'pediatrik + düşük' gibi durumlar hem doğru section'a hem de doğru
    uyarıya ulaşabilir.
    """
    t = normalized_text
    return SafetyContext(
        is_emergency=_any(t, C.EMERGENCY_PATTERNS),
        is_pediatric=(age is not None and age < C.PEDIATRIC_AGE_LIMIT) or _any(t, C.PEDIATRIC_PATTERNS),
        is_diagnosis=_any(t, C.DIAGNOSIS_PATTERNS),
        is_treatment=_any(t, C.TREATMENT_PATTERNS),
    )


def detect_section(normalized_text: str) -> str:
    """Retrieval sıralaması ve confidence için hedef section'ı tahmin eder."""
    t = normalized_text
    if _any(t, C.HIGH_PATTERNS):
        return C.SECTION_HIGH
    if _any(t, C.LOW_PATTERNS):
        return C.SECTION_LOW
    if _any(t, C.WHY_PATTERNS):
        return C.SECTION_WHY
    if _any(t, C.WHEN_DOCTOR_PATTERNS):
        return C.SECTION_WHEN_DOCTOR
    if _any(t, C.DOCTOR_QUESTION_PATTERNS):
        return C.SECTION_DOCTOR_QUESTIONS
    if _any(t, C.NORMAL_RANGE_PATTERNS):
        return C.SECTION_WHEN_DOCTOR
    return C.SECTION_WHAT
