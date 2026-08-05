"""Ollama local /api/chat LLM sağlayıcısı.

- Local/offline Ollama chat API'sine yalnız generate() içinde istek atar.
- Prompt ve grounding kuralları mevcut prompts.py üzerinden ortak kullanılır.
- Testler `_http_post_json`'ı monkeypatch ederek gerçek Ollama/ağ çağrısı yapmaz.
- Yeni paket eklenmez: HTTP için stdlib `urllib` kullanılır.
"""

import json
import logging
import re
import urllib.error
import urllib.request
from typing import Callable, List, Optional

from app.core.config import OllamaSettings, get_ollama_settings
from app.services.llm.openai_compatible_provider import (
    LLMConfigError,
    LLMProviderError,
)
from app.services.llm.prompts import SYSTEM_PROMPT, build_prompt
from app.services.llm.source_content import combine_source_content

logger = logging.getLogger(__name__)

_LANGUAGE_LEAK_RE = re.compile(
    r"\b(indicate|however|therefore|because|means|levels?|inflammation|disease|patient|avanz)\b",
    re.IGNORECASE,
)
_QUALITY_LEAK_RE = re.compile(
    r"\b(merhaba|sensana)\b|\bkaynak\s*:|sana seed medical notes|\bcevap\s*:",
    re.IGNORECASE,
)
_NUMBER_RE = re.compile(r"\d+(?:[.,]\d+)?")
_COMMON_GROUNDING_STEMS = {
    "ancak",
    "başın",
    "bilgi",
    "birli",
    "değer",
    "durum",
    "genel",
    "gerek",
    "göste",
    "hakkı",
    "kanda",
    "koydu",
    "kulla",
    "neden",
    "olarak",
    "ölçül",
    "sağlı",
    "şekil",
    "temel",
    "testl",
    "vücut",
    "yorum",
}

# Ağ katmanı: (url, headers, payload, timeout) -> parsed dict
PostFn = Callable[[str, dict, dict, int], dict]


def _http_post_json(url: str, headers: dict, payload: dict, timeout: int) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            body = resp.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise LLMProviderError("Yerel açıklama servisine ulaşılamadı.") from exc
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise LLMProviderError("Yerel açıklama servisi yanıtı çözümlenemedi.") from exc


def _format_chunks(retrieved) -> str:
    parts: List[str] = []
    for rc in retrieved:
        c = rc.chunk
        parts.append(f"[{c.section}] {c.content}\n(Kaynak: {c.source_title})")
    return "\n\n".join(parts)


def _format_result_context(result_context: Optional[dict]) -> str:
    if not result_context:
        return "Belirtilmedi"
    raw = result_context.get("raw_value")
    if raw is None:
        return "Belirtilmedi"
    unit = result_context.get("unit")
    measured = f"{raw} {unit}".strip() if unit else str(raw)
    parts = [f"Ölçülen değer: {measured}"]
    reference_range = result_context.get("reference_range")
    if reference_range:
        parts.append(f"Rapor referans aralığı: {reference_range}")
    interpretation = result_context.get("interpretation")
    if interpretation in {"low", "normal", "high"}:
        parts.append(f"Parser durumu: {interpretation}")
    return "; ".join(parts)


def _trim_truncated_content(content: str) -> str:
    """Token sınırında yarım kalan son cümleyi kullanıcıya gösterme."""
    stripped = content.strip()
    if stripped.endswith((".", "!", "?")):
        return stripped
    boundary = max(stripped.rfind(mark) for mark in (".", "!", "?"))
    return stripped[: boundary + 1].strip() if boundary >= 0 else ""


def _limit_complete_sentences(content: str, max_sentences: int = 4) -> str:
    """Küçük local modelin başlık/liste üretmesini ve konudan uzaklaşmasını sınırla."""
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if len(lines) > 1 and len(lines[0].split()) <= 6 and lines[0].endswith(("?", ":")):
        lines = lines[1:]
    flattened = " ".join(lines)
    sentences = re.split(r"(?<=[.!?])\s+", flattened)
    complete = [sentence.strip() for sentence in sentences if sentence.strip()]
    return " ".join(complete[:max_sentences]).strip()


def _source_fallback(retrieved) -> str:
    return combine_source_content(retrieved)


def _word_stems(text: str) -> set[str]:
    words = re.findall(r"[^\W\d_]+", text.casefold(), flags=re.UNICODE)
    return {word[:5] for word in words if len(word) >= 5}


def _has_ungrounded_vocabulary(content: str, source: str) -> bool:
    source_stems = _word_stems(source)
    generated_stems = _word_stems(content)
    return bool(generated_stems - source_stems - _COMMON_GROUNDING_STEMS)


def _requires_source_fallback(
    content: str, source: str, *, strict_grounding: bool = False
) -> bool:
    if _LANGUAGE_LEAK_RE.search(content) or _QUALITY_LEAK_RE.search(content):
        return True
    generated_numbers = set(_NUMBER_RE.findall(content))
    source_numbers = set(_NUMBER_RE.findall(source))
    if not generated_numbers.issubset(source_numbers):
        return True
    return strict_grounding and _has_ungrounded_vocabulary(content, source)


class OllamaProvider:
    """Ollama /api/chat sağlayıcısı."""

    name = "ollama"

    def __init__(
        self,
        settings: Optional[OllamaSettings] = None,
        post_fn: Optional[PostFn] = None,
    ):
        self._settings = settings or get_ollama_settings()
        # None ise generate() sırasında modül düzeyi _http_post_json kullanılır
        # (monkeypatch dostu).
        self._post_fn = post_fn

    def generate(
        self,
        *,
        question: str,
        lab_test: str,
        intent: str,
        retrieved,
        result_context: Optional[dict] = None,
        system_prompt: Optional[str] = None,
        user_prompt: Optional[str] = None,
        num_ctx: int = 2048,
        # Cevaplar 2-4 cümledir; üretim süresi token sayısıyla doğru orantılı
        # olduğu için üst sınır beklemeyi doğrudan kısaltır. Uzun üretimler
        # zaten kalite kontrolünde eleniyordu.
        num_predict: int = 160,
    ) -> str:
        s = self._settings
        if not s.model:
            logger.warning("LLM yapılandırması eksik (provider=%s).", self.name)
            raise LLMConfigError("Ollama sağlayıcı yapılandırması eksik.")

        prompt = user_prompt or build_prompt(
            question=question,
            lab_test=lab_test,
            result_context=_format_result_context(result_context),
            chunks=_format_chunks(retrieved),
        )
        payload = {
            "model": s.model,
            "stream": False,
            "think": False,
            "options": {
                "num_ctx": num_ctx,
                "num_predict": num_predict,
                "temperature": 0.2,
            },
            "messages": [
                {"role": "system", "content": system_prompt or SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        }
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        url = s.base_url.rstrip("/") + "/api/chat"

        post = self._post_fn if self._post_fn is not None else _http_post_json
        data = post(url, headers, payload, s.timeout_seconds)

        try:
            content = data["message"]["content"]
        except (KeyError, TypeError) as exc:
            raise LLMProviderError("Yerel açıklama servisi beklenmeyen yanıt verdi.") from exc
        if not isinstance(content, str) or not content.strip():
            raise LLMProviderError("Yerel açıklama servisi boş yanıt verdi.")
        if data.get("done_reason") == "length":
            content = _trim_truncated_content(content)
            if not content:
                raise LLMProviderError("Yerel açıklama servisi yanıtı tamamlayamadı.")
        content = _limit_complete_sentences(content)
        if not content:
            raise LLMProviderError("Yerel açıklama servisi boş yanıt verdi.")
        fallback = _source_fallback(retrieved)
        if fallback and _requires_source_fallback(
            content, fallback, strict_grounding=bool(data.get("model"))
        ):
            logger.warning("Ollama yanıtı kalite kontrolünden geçemedi; kaynak metne dönüldü.")
            return fallback
        return content
