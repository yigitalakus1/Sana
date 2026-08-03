"""OpenAI-compatible chat completions LLM sağlayıcısı.

- Retrieved chunk'lar + soru + lab_test + değer bağlamıyla sade, kaynağa dayalı,
  TANI KOYMAYAN Türkçe açıklama üretir.
- Citation UYDURMAZ; kaynaklar backend'in mevcut citation mekanizmasından gelir.
- Ağ çağrısı yalnız `generate()` içinde yapılır (import/örnekleme güvenlidir).
- Testler `_http_post_json`'ı monkeypatch ederek ağ olmadan çalışır.
- Yeni paket eklenmez: HTTP için stdlib `urllib` kullanılır.
"""

import json
import logging
import urllib.error
import urllib.request
from typing import Callable, List, Optional

from app.core.config import LLMSettings, get_llm_settings
from app.services.llm.prompts import SYSTEM_PROMPT, build_prompt

logger = logging.getLogger(__name__)

# Ağ katmanı: (url, headers, payload, timeout) -> parsed dict
PostFn = Callable[[str, dict, dict, int], dict]


class LLMConfigError(Exception):
    """Sağlayıcı seçili ama yapılandırma (api_key/base_url/model) eksik."""


class LLMProviderError(Exception):
    """Sağlayıcı çağrısı/çözümlemesi başarısız (kullanıcıya güvenli mesaj)."""


def _http_post_json(url: str, headers: dict, payload: dict, timeout: int) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            body = resp.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        # Teknik detay/secret sızdırmadan yukarı taşınır.
        raise LLMProviderError("Açıklama servisine ulaşılamadı.") from exc
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise LLMProviderError("Açıklama servisi yanıtı çözümlenemedi.") from exc


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


class OpenAICompatibleProvider:
    """OpenAI-compatible /chat/completions sağlayıcısı."""

    name = "openai_compatible"

    def __init__(
        self,
        settings: Optional[LLMSettings] = None,
        post_fn: Optional[PostFn] = None,
    ):
        self._settings = settings or get_llm_settings()
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
    ) -> str:
        s = self._settings
        if not s.api_key or not s.base_url or not s.model:
            # Secret loglanmaz; yalnız eksik yapılandırma bildirilir.
            logger.warning("LLM yapılandırması eksik (provider=%s).", self.name)
            raise LLMConfigError("LLM sağlayıcı yapılandırması eksik.")

        prompt = user_prompt or build_prompt(
            question=question,
            lab_test=lab_test,
            result_context=_format_result_context(result_context),
            chunks=_format_chunks(retrieved),
        )
        payload = {
            "model": s.model,
            "messages": [
                {"role": "system", "content": system_prompt or SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        headers = {
            "Authorization": f"Bearer {s.api_key}",
            "Content-Type": "application/json",
        }
        url = s.base_url.rstrip("/") + "/chat/completions"

        post = self._post_fn if self._post_fn is not None else _http_post_json
        data = post(url, headers, payload, s.timeout_seconds)

        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise LLMProviderError("Açıklama servisi beklenmeyen yanıt verdi.") from exc
        if not isinstance(content, str) or not content.strip():
            raise LLMProviderError("Açıklama servisi boş yanıt verdi.")
        return content.strip()
