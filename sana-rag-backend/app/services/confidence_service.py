"""Confidence skorlama: ağırlıklı bileşenler + eşikler + sert kurallar."""

from app.core import constants as C


def label_for(score: float) -> str:
    if score >= C.THRESHOLD_HIGH:
        return "high"
    if score >= C.THRESHOLD_MEDIUM:
        return "medium"
    return "low"


def compute(
    *,
    exact_match: bool,
    synonym_match: bool,
    keyword_overlap_ok: bool,
    source_exists: bool,
    section_match: bool,
):
    """Skoru ve etiketini döndürür. Sert kuralları uygular.

    Sert kurallar:
      - kaynak yoksa 'high' olamaz (en fazla 'medium').
    (retrieval yoksa / safety_block durumunda skor zaten 0.0 olarak ayarlanır.)
    """
    score = 0.0
    if exact_match:
        score += C.W_LAB_EXACT
    if synonym_match:
        score += C.W_SYNONYM
    if keyword_overlap_ok:
        score += C.W_KEYWORD
    if source_exists:
        score += C.W_SOURCE
    if section_match:
        score += C.W_INTENT_SECTION

    score = round(min(score, 1.0), 2)
    label = label_for(score)

    if not source_exists and label == "high":
        label = "medium"

    return score, label
