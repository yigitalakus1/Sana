"""Safety katmanı: retrieval öncesi blok kararları + cevap sonrası filtreleme."""

import re
from typing import Optional

from app.core import constants as C
from app.services.intent_service import SafetyContext
from app.services.normalization_service import turkish_lower

# LLM cevabında referans aralığı/yorum yokken bulunmaması gereken sınıflandırma
# ifadeleri (normalize edilmiş, Türkçe küçük harf üzerinde word-boundary ile aranır).
_CLASSIFICATION_PATTERNS = [
    "normalden yüksek", "yüksek çıkmış", "düşük çıkmış",
    "referans üstünde", "referans altında",
    "normaldir", "normal", "yüksektir", "yüksek",
    "düşüktür", "düşük", "sınırda",
    # Küçük local modeller sonucu normal/yüksek/düşük demeden de dolaylı
    # yorumlayabilir. Referans aralığı yokken bu çıkarımlar da güvenli metne
    # dönüştürülmelidir.
    "bulgusu göstermediğini", "bulgu göstermediğini",
    "iltihap olmadığını", "enfeksiyon olmadığını",
    "sorun olmadığını", "endişe verici olmadığını",
]
_CLASSIFICATION_RE = re.compile(
    r"\b(?:" + "|".join(re.escape(p) for p in _CLASSIFICATION_PATTERNS) + r")\b"
)

_PROMPT_INJECTION_PATTERNS = (
    "sistem prompt",
    "system prompt",
    "sistem mesajını göster",
    "sistem mesajini goster",
    "gizli talimat",
    "talimatlarını göster",
    "talimatlarini goster",
    "önceki talimatları unut",
    "onceki talimatlari unut",
    "developer message",
    "kaynak parçalarını göster",
    "kaynak parcalarini goster",
)


def _has_value_classification(answer: str) -> bool:
    return bool(_CLASSIFICATION_RE.search(turkish_lower(answer)))


def strip_value_classification(
    answer: str, lab_test: Optional[str], result_context: Optional[dict]
) -> str:
    """Referans aralığı/yorum yokken sayısal değer sınıflandırmasını engeller.

    Yalnız bir sayısal değer bağlamı (result_context) varken devreye girer:
    reference_range VEYA interpretation boşken cevap normal/yüksek/düşük gibi
    bir sınıflandırma içeriyorsa, cevabın tamamı güvenli metinle değiştirilir.
    Değer bağlamı yoksa (yalnız eğitsel açıklama) cevaba dokunulmaz.
    """
    if not result_context:
        return answer
    if result_context.get("reference_range") and result_context.get("interpretation"):
        return answer  # sınıflandırma için gerekli bağlam mevcut
    if _has_value_classification(answer):
        return C.VALUE_CLASSIFICATION_SAFE_TEXT.format(lab_test=(lab_test or "Bu test"))
    return answer


def add_missing_reference_range_note(answer: str, result_context: Optional[dict]) -> str:
    """Sayısal sonuç var ama laboratuvar aralığı yoksa sınırı açıkça belirtir."""
    if not result_context:
        return answer
    if result_context.get("reference_range") or result_context.get("interpretation"):
        return answer
    lowered = turkish_lower(answer)
    if "sınıflandırılamaz" in lowered or "siniflandirilamaz" in lowered:
        return answer
    return f"{answer.strip()} {C.VALUE_CONTEXT_MISSING_RANGE_NOTE}".strip()


def should_block_before_retrieval(intent: str) -> bool:
    return intent in C.BLOCK_BEFORE_RETRIEVAL


def is_prompt_injection(normalized_query: str) -> bool:
    return any(pattern in normalized_query for pattern in _PROMPT_INJECTION_PATTERNS)


def block_message(intent: str) -> str:
    """Retrieval yapılmadan dönülecek güvenli mesaj."""
    if intent == C.INTENT_DOCTOR_AVOIDANCE:
        return C.DOCTOR_AVOIDANCE_MESSAGE
    if intent == C.INTENT_PROMPT_INJECTION:
        return C.PROMPT_INJECTION_BLOCK_MESSAGE
    # medication_or_dosage_advice / medication_or_supplement_advice
    return C.MEDICATION_BLOCK_MESSAGE


def apply_answer_filters(answer: str, intent: str, ctx: SafetyContext) -> str:
    """Üretilen cevaba güvenlik çerçevesi ekler.

    - acil/panik  -> başa acil yönlendirme
    - teşhis      -> başa 'tanı koydurmaz' notu
    - tedavi      -> başa tedavi reddi notu
    - pediatrik   -> sona pediatrik uyarı
    Her cevapta 'tek başına tanı koydurmaz' mantığı korunur.
    """
    text = answer.strip()

    # Genel kaçınılmaz teşhis-karşıtı çerçeve
    if "tanı koydurmaz" not in text.lower() and "tanısı koydurmaz" not in text.lower():
        text = text + C.GENERIC_CAVEAT

    if intent == C.INTENT_TREATMENT or ctx.is_treatment:
        text = C.TREATMENT_NOTE + text

    if intent == C.INTENT_DIAGNOSIS or ctx.is_diagnosis:
        text = C.DIAGNOSIS_NOTE + text

    if ctx.is_pediatric or intent == C.INTENT_PEDIATRIC:
        text = text + C.PEDIATRIC_SUFFIX

    # Acil durum en öne alınır
    if ctx.is_emergency or intent == C.INTENT_EMERGENCY:
        text = C.EMERGENCY_PREFIX + text

    return text.strip()
