"""Onaylı MedlinePlus kaydından kontrollü Türkçe inceleme taslağı üretir.

Taslak hiçbir zaman otomatik olarak RAG chunk'larına yazılmaz. Kaynak ve taslak
onayları iki ayrı insan inceleme kapısıdır.
"""

import re
from dataclasses import dataclass
from typing import Optional

from app.services.llm.ollama_provider import OllamaProvider
from app.services.source_sync_store import SourceDraftSnapshot, SourceSyncStore


class SourceDraftError(RuntimeError):
    pass


DRAFT_SYSTEM_PROMPT = """Yalnızca çeviri ve sadeleştirme yap.
Verilen MedlinePlus metnindeki bilgileri doğal Türkçeye aktar.
Yeni tıbbi bilgi, hastalık, sayı, referans aralığı, tanı, tedavi, ilaç veya doz önerisi ekleme.
Kullanıcıya doğrudan talimat verme. En fazla dört kısa, tamamlanmış cümle yaz.
Başlık, madde işareti, kaynak etiketi, analiz, giriş veya teknik açıklama yazma.
İngilizce sözcük kullanma. Yalnız nihai Türkçe metni döndür."""

_NUMBER_RE = re.compile(r"\d+(?:[.,]\d+)?")
_ENGLISH_RE = re.compile(
    r"\b(the|and|blood|your|levels?|should|means|because|however|disease|"
    r"cannot|can't|provide|medical|advice|would|that|help|offer|information)\b",
    re.IGNORECASE,
)
_REFUSAL_RE = re.compile(
    r"\b(i\s+can(?:not|'t)|yard[ıi]m\s+edemem|t[ıi]bbi\s+tavsiye\s+veremem)\b",
    re.IGNORECASE,
)
_DIRECT_ADVICE_RE = re.compile(
    r"\b(kullanmal[ıi]s[ıi]n[ıi]z|almal[ıi]s[ıi]n[ıi]z|başlay[ıi]n|"
    r"b[ıi]rak[ıi]n|doz(?:u|un|unu)?\s+(?:art[ıi]r|azalt|değiştir))",
    re.IGNORECASE,
)
_PROMPT_LEAK_RE = re.compile(
    r"system prompt|sistem prompt|önceki talimat|kaynak\s*:|medlineplus özeti",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class DraftGenerationResult:
    outcome: str
    draft: SourceDraftSnapshot


def validate_source_draft(content: str, source_summary: str) -> str:
    cleaned = " ".join(content.split()).strip()
    if not cleaned:
        raise SourceDraftError("Türkçe kaynak taslağı boş olamaz.")
    if len(cleaned.split()) > 120:
        raise SourceDraftError("Türkçe kaynak taslağı çok uzun.")
    if not cleaned.endswith((".", "!", "?")):
        raise SourceDraftError("Türkçe kaynak taslağı tamamlanmamış.")

    sentences = [part for part in re.split(r"(?<=[.!?])\s+", cleaned) if part]
    if len(sentences) > 4:
        raise SourceDraftError("Türkçe kaynak taslağı dört cümleyi aşamaz.")
    if _ENGLISH_RE.search(cleaned):
        raise SourceDraftError("Türkçe kaynak taslağında yabancı dil sızıntısı var.")
    if _REFUSAL_RE.search(cleaned):
        raise SourceDraftError("Türkçe kaynak taslağı model reddi içeriyor.")
    if _DIRECT_ADVICE_RE.search(cleaned):
        raise SourceDraftError("Türkçe kaynak taslağı doğrudan tıbbi yönlendirme içeriyor.")
    if _PROMPT_LEAK_RE.search(cleaned):
        raise SourceDraftError("Türkçe kaynak taslağı teknik talimat sızıntısı içeriyor.")
    if any(marker in cleaned for marker in ("```", "# ", "* ", "- ")):
        raise SourceDraftError("Türkçe kaynak taslağı biçimlendirme içeremez.")

    generated_numbers = set(_NUMBER_RE.findall(cleaned))
    if generated_numbers:
        raise SourceDraftError("Türkçe kaynak taslağı sayı veya referans aralığı içeremez.")
    return cleaned


def _source_excerpt(source_summary: str, max_chars: int = 1800) -> str:
    compact = " ".join(source_summary.split())
    if len(compact) <= max_chars:
        return compact
    excerpt = compact[:max_chars]
    boundary = excerpt.rfind(".")
    return excerpt[: boundary + 1] if boundary >= max_chars // 2 else excerpt


def build_draft_prompt(title: str, source_summary: str) -> str:
    return (
        "Aşağıdaki metni yalnız içindeki bilgilerle sade Türkçeye aktar. "
        "Düşünme sürecini yazma.\n\n"
        f"Konu: {title}\n"
        f"Çevrilecek metin: {_source_excerpt(source_summary)}\n\n"
        "Nihai Türkçe metin:"
    )


def generate_and_stage_source_draft(
    source_key: str,
    *,
    store: SourceSyncStore,
    provider: Optional[OllamaProvider] = None,
) -> DraftGenerationResult:
    source = store.get(source_key)
    if source is None:
        raise SourceDraftError("Kaynak kaydı bulunamadı.")
    if source.review_status != "approved":
        raise SourceDraftError("Kaynak onaylanmadan Türkçe taslak üretilemez.")

    selected_provider = provider or OllamaProvider()
    try:
        generated = selected_provider.generate(
            question=source.summary,
            lab_test=source.lab_test,
            intent="source_translation",
            retrieved=[],
            system_prompt=DRAFT_SYSTEM_PROMPT,
            user_prompt=build_draft_prompt(source.title, source.summary),
            num_ctx=4096,
            num_predict=768,
        )
    except Exception as exc:
        if isinstance(exc, SourceDraftError):
            raise
        raise SourceDraftError("Yerel model Türkçe kaynak taslağı üretemedi.") from exc

    content = validate_source_draft(generated, source.summary)
    generator = getattr(selected_provider, "name", "local")
    outcome = store.stage_draft(source_key, content, generator)
    draft = store.get_current_draft(source_key)
    if draft is None:
        raise SourceDraftError("Türkçe kaynak taslağı staging'e yazılamadı.")
    return DraftGenerationResult(outcome=outcome, draft=draft)
