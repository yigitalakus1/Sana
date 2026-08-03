"""Microsoft Foundry Local LLM sağlayıcısı (S96).

Foundry Local, cihaz üzerinde OpenAI-uyumlu bir chat endpoint'i açan local
inference katmanıdır; backend FastAPI olarak kalır, bu sınıf yalnız cevap
üretim çağrısını yapar. API KEY YOKTUR ve istenmez.

Tasarım:
- `foundry_local` SDK import'u OPSİYONELDİR ve yalnız generate() sırasında,
  `_load_sdk_manager_cls` adapter'ı üzerinden denenir. SDK kurulu değilken
  modül import'u ve provider örneklemesi güvenlidir (uygulama çökmez).
- `SANA_FOUNDRY_BASE_URL` verilirse SDK hiç gerekmez: endpoint'e stdlib
  urllib ile doğrudan istek atılır (ollama/openai_compatible ile aynı kalıp).
- SDK/servis/model hazır değilse kontrollü LLMConfigError/LLMProviderError
  yükselir; kullanıcıya teknik detay/secret sızmaz.
- Testler `_http_post_json` ve `_load_sdk_manager_cls`'i monkeypatch eder;
  gerçek Foundry kurulumu gerekmez.
"""

import json
import logging
import urllib.error
import urllib.request
from typing import Callable, List, Optional, Tuple

from app.core.config import FoundrySettings, get_foundry_settings
from app.services.llm.openai_compatible_provider import (
    LLMConfigError,
    LLMProviderError,
)
from app.services.llm.prompts import SYSTEM_PROMPT, build_prompt

logger = logging.getLogger(__name__)

# Ağ katmanı: (url, headers, payload, timeout) -> parsed dict
PostFn = Callable[[str, dict, dict, int], dict]

UNAVAILABLE_MESSAGE = (
    "Foundry Local sağlayıcısı kullanılamıyor. Foundry Local'ı kurup bir model "
    "yükleyin (veya SANA_FOUNDRY_BASE_URL verin) ya da SANA_PROVIDER=dummy kullanın."
)
MODEL_MISSING_MESSAGE = (
    "Foundry Local model adı eksik: SANA_FOUNDRY_MODEL ortam değişkenini ayarlayın "
    "ya da SANA_PROVIDER=dummy kullanın."
)
RUNTIME_ERROR_MESSAGE = (
    "Yerel açıklama servisi (Foundry Local) şu anda hazır değil. "
    "Servisin çalıştığını ve modelin yüklü olduğunu kontrol edin."
)


def _load_sdk_manager_cls():
    """Opsiyonel foundry-local-sdk adapter'ı; kurulu değilse None döner."""
    try:
        from foundry_local import FoundryLocalManager  # noqa: PLC0415
    except ImportError:
        return None
    return FoundryLocalManager


def _http_post_json(url: str, headers: dict, payload: dict, timeout: int) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            body = resp.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise LLMProviderError(RUNTIME_ERROR_MESSAGE) from exc
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


class FoundryLocalProvider:
    """Foundry Local OpenAI-uyumlu /chat/completions sağlayıcısı."""

    name = "foundry_local"

    def __init__(
        self,
        settings: Optional[FoundrySettings] = None,
        post_fn: Optional[PostFn] = None,
    ):
        # SDK'ya DOKUNULMAZ; örnekleme her zaman güvenlidir.
        self._settings = settings or get_foundry_settings()
        self._post_fn = post_fn

    def _resolve_endpoint_and_model(self) -> Tuple[str, str]:
        """(base_url, model_id) döndürür.

        Öncelik: açık SANA_FOUNDRY_BASE_URL (SDK'sız yol). Yoksa opsiyonel SDK
        üzerinden endpoint/model keşfi. Her iki yol da API key istemez.
        """
        s = self._settings
        if not s.model:
            logger.warning("LLM yapılandırması eksik (provider=%s).", self.name)
            raise LLMConfigError(MODEL_MISSING_MESSAGE)

        if s.base_url:
            return s.base_url, s.model

        manager_cls = _load_sdk_manager_cls()
        if manager_cls is None:
            logger.warning("foundry-local-sdk kurulu değil (provider=%s).", self.name)
            raise LLMConfigError(UNAVAILABLE_MESSAGE)

        # SDK etkileşimi izole: servis kapalı / model yüklü değil / API farkı
        # gibi tüm durumlar kullanıcıya güvenli tek hataya çevrilir.
        try:
            manager = manager_cls(s.model)
            endpoint = str(manager.endpoint)
            info = manager.get_model_info(s.model)
            model_id = getattr(info, "id", None) or s.model
            return endpoint, model_id
        except Exception as exc:  # noqa: BLE001
            logger.warning("Foundry Local çalışma zamanı hazır değil: %s", type(exc).__name__)
            raise LLMProviderError(RUNTIME_ERROR_MESSAGE) from exc

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
        base_url, model_id = self._resolve_endpoint_and_model()

        prompt = user_prompt or build_prompt(
            question=question,
            lab_test=lab_test,
            result_context=_format_result_context(result_context),
            chunks=_format_chunks(retrieved),
        )
        payload = {
            "model": model_id,
            "messages": [
                {"role": "system", "content": system_prompt or SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        # API key yok: Authorization başlığı bilinçli olarak GÖNDERİLMEZ.
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        url = base_url.rstrip("/") + "/chat/completions"

        post = self._post_fn if self._post_fn is not None else _http_post_json
        data = post(url, headers, payload, self._settings.timeout_seconds)

        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise LLMProviderError("Yerel açıklama servisi beklenmeyen yanıt verdi.") from exc
        if not isinstance(content, str) or not content.strip():
            raise LLMProviderError("Yerel açıklama servisi boş yanıt verdi.")
        return content.strip()
