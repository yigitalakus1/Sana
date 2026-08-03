"""Uygulama yapılandırması (MVP'de minimal)."""

import os
from dataclasses import dataclass

from app.core import constants

APP_NAME = "sana-rag-backend"
APP_VERSION = constants.APP_VERSION
APP_DESCRIPTION = (
    "Sana — Türkçe, kaynak gösterimli, güven skorlu, teşhis koymayan tıbbi açıklama backend'i (MVP)."
)


@dataclass(frozen=True)
class LLMSettings:
    """Ortam değişkenlerinden okunan LLM sağlayıcı ayarları.

    Hiçbir env yoksa provider `dummy` olur; gizli anahtar zorunlu değildir.
    Ayarlar HER OKUMADA env'den alınır (test/monkeypatch dostu).
    """

    provider: str
    model: str
    api_key: str
    base_url: str
    timeout_seconds: int


@dataclass(frozen=True)
class OllamaSettings:
    """Ollama sağlayıcısı için ortam değişkenlerinden okunan ayarlar.

    Bağlantı denemesi yapılmaz; eksik/hatalı yapılandırma generate() sırasında
    kontrollü hataya çevrilir.
    """

    model: str
    base_url: str
    timeout_seconds: int


@dataclass(frozen=True)
class MedlinePlusSettings:
    """MedlinePlus Connect kaynak senkronizasyonu ayarları."""

    base_url: str
    timeout_seconds: int
    cache_hours: int


def _env(key: str) -> str:
    return (os.getenv(key) or "").strip()


def _int_env(key: str, default: int) -> int:
    try:
        return int(_env(key) or str(default))
    except ValueError:
        return default


def get_llm_settings() -> LLMSettings:
    # SANA_PROVIDER yeni kanonik değişkendir; LLM_PROVIDER geriye dönük uyum
    # için okunmaya devam eder. İkisi de yoksa güvenli varsayılan: dummy.
    return LLMSettings(
        provider=(_env("SANA_PROVIDER") or _env("LLM_PROVIDER") or "dummy").lower(),
        model=_env("LLM_MODEL"),
        api_key=_env("LLM_API_KEY"),
        base_url=_env("LLM_BASE_URL"),
        timeout_seconds=_int_env("LLM_TIMEOUT_SECONDS", 30),
    )


@dataclass(frozen=True)
class FoundrySettings:
    """Foundry Local sağlayıcısı ayarları (API key YOKTUR; local inference).

    `base_url` verilirse SDK'ya gerek kalmadan doğrudan Foundry Local'ın
    OpenAI-uyumlu endpoint'i kullanılır (örn. http://127.0.0.1:5273/v1).
    Verilmezse endpoint, opsiyonel foundry-local-sdk üzerinden keşfedilir.
    """

    model: str
    base_url: str
    timeout_seconds: int


def get_foundry_settings() -> FoundrySettings:
    return FoundrySettings(
        model=_env("SANA_FOUNDRY_MODEL"),
        base_url=_env("SANA_FOUNDRY_BASE_URL"),
        timeout_seconds=_int_env("SANA_FOUNDRY_TIMEOUT_SECONDS", 120),
    )


def external_ai_disabled() -> bool:
    """SANA_ENABLE_EXTERNAL_AI=false/0/no ise dış (OpenAI-uyumlu) sağlayıcı
    seçimi engellenir ve güvenli şekilde dummy'ye düşülür.

    Ayarlanmadıysa engel YOKTUR (geriye dönük uyum); local sağlayıcıları
    (dummy/ollama/foundry_local) hiçbir zaman etkilemez.
    """
    return _env("SANA_ENABLE_EXTERNAL_AI").lower() in {"false", "0", "no"}


def get_rag_mode() -> str:
    """Retrieval kaynağı: "seed" (varsayılan) veya "local" (SQLite RAG store).

    `SANA_RAG_MODE` env'inden okunur; bilinmeyen/boş değer güvenli şekilde
    "seed"e düşer (mevcut davranış korunur).
    """
    mode = _env("SANA_RAG_MODE").lower()
    return "local" if mode == "local" else "seed"


def get_rag_db_path() -> str:
    """Local RAG store (SQLite) dosya yolu.

    `SANA_RAG_DB_PATH` env'inden okunur; yoksa backend kökünde `data/sana_rag.db`.
    Her okumada env'den alınır (test/monkeypatch dostu).
    """
    return _env("SANA_RAG_DB_PATH") or "data/sana_rag.db"


def get_ollama_settings() -> OllamaSettings:
    return OllamaSettings(
        model=_env("OLLAMA_MODEL"),
        base_url=_env("OLLAMA_BASE_URL") or "http://127.0.0.1:11434",
        timeout_seconds=_int_env("OLLAMA_TIMEOUT_SECONDS", 60),
    )


def get_medlineplus_settings() -> MedlinePlusSettings:
    return MedlinePlusSettings(
        base_url=(
            _env("MEDLINEPLUS_BASE_URL")
            or "https://connect.medlineplus.gov/service"
        ),
        timeout_seconds=max(1, _int_env("MEDLINEPLUS_TIMEOUT_SECONDS", 20)),
        cache_hours=max(12, _int_env("MEDLINEPLUS_CACHE_HOURS", 24)),
    )
