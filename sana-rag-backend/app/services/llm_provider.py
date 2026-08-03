"""LLM Provider soyutlaması + factory.

Varsayılan `DummyLLMProvider` deterministik, kaynağa dayalı Türkçe cevap üretir
(gerçek model/ağ gerektirmez). Gerçek sağlayıcılar `openai_compatible` ve `ollama`
olarak kayıtlıdır; seçilmedikçe kullanılmaz. Varsayılan provider ortam değişkeni
yoksa `dummy`.
"""

import logging
from typing import List, Optional, Protocol

from app.core.config import external_ai_disabled, get_llm_settings
from app.services.llm.foundry_local_provider import FoundryLocalProvider
from app.services.llm.ollama_provider import OllamaProvider
from app.services.llm.openai_compatible_provider import OpenAICompatibleProvider
from app.services.llm.source_content import combine_source_content
from app.services.retrieval_service import RetrievedChunk


class LLMProvider(Protocol):
    name: str

    def generate(
        self,
        *,
        question: str,
        lab_test: str,
        intent: str,
        retrieved: List[RetrievedChunk],
        result_context: Optional[dict] = None,
        system_prompt: Optional[str] = None,
        user_prompt: Optional[str] = None,
    ) -> str:
        ...


class DummyLLMProvider:
    """Onaylı kaynak parçalarını birleştiren kontrollü cevap üreticisi (ağ yok)."""

    name = "dummy"

    def generate(
        self,
        *,
        question: str,
        lab_test: str,
        intent: str,
        retrieved: List[RetrievedChunk],
        result_context: Optional[dict] = None,
        system_prompt: Optional[str] = None,
        user_prompt: Optional[str] = None,
    ) -> str:
        if not retrieved:
            return ""
        # DummyLLM yeni tıbbi içerik üretmez; yalnızca onaylı kaynak metinlerini
        # tam cümlelerle birleştirir.
        return combine_source_content(retrieved)


logger = logging.getLogger(__name__)

# --- Provider factory ---
DEFAULT_PROVIDER = "dummy"

# Dış (cihaz dışına çıkan, potansiyel ücretli) sağlayıcılar.
# SANA_ENABLE_EXTERNAL_AI=false ile seçimi engellenir; local sağlayıcılar
# (dummy/ollama/foundry_local) bu kısıttan etkilenmez.
EXTERNAL_PROVIDERS = {"openai_compatible"}
_PROVIDERS = {
    "dummy": DummyLLMProvider,
    "ollama": OllamaProvider,
    "openai_compatible": OpenAICompatibleProvider,
    "foundry_local": FoundryLocalProvider,
}


def get_llm_provider(name: Optional[str] = None) -> LLMProvider:
    """Provider örneği döndürür.

    `name` verilmezse ortam değişkeni `LLM_PROVIDER` (yoksa `dummy`) kullanılır.
    **Bilinmeyen** ad güvenli şekilde `dummy`ye düşer. Kayıtlı ama yanlış
    yapılandırılmış (örn. API key eksik) bir sağlayıcı dummy'ye DÜŞMEZ; hata
    çağrı anında (`generate`) kontrollü şekilde yükselir.
    """
    key = (name or get_llm_settings().provider or DEFAULT_PROVIDER).strip().lower()
    if key in EXTERNAL_PROVIDERS and external_ai_disabled():
        logger.warning(
            "Dış AI sağlayıcısı (%s) SANA_ENABLE_EXTERNAL_AI=false ile engellendi; "
            "dummy kullanılacak.",
            key,
        )
        key = DEFAULT_PROVIDER
    provider_cls = _PROVIDERS.get(key, _PROVIDERS[DEFAULT_PROVIDER])
    return provider_cls()
