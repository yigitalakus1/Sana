"""MedlinePlus Connect laboratuvar testi istemcisi.

Yalnız ``fetch_lab`` çağrıldığında HTTPS isteği yapar. Ağ katmanı constructor'dan
enjekte edilebilir; otomatik testler gerçek MedlinePlus veya ağ kullanmaz.
"""

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import Any, Callable, Dict, Optional

from app.core.config import MedlinePlusSettings, get_medlineplus_settings
from app.data.loinc_catalog import LOINC_CODE_SYSTEM_OID, LabSourceDefinition


class MedlinePlusError(RuntimeError):
    """Kontrollü MedlinePlus kaynak hatası."""


class MedlinePlusTransportError(MedlinePlusError):
    pass


class MedlinePlusResponseError(MedlinePlusError):
    pass


@dataclass(frozen=True)
class MedlinePlusRecord:
    lab_test: str
    loinc_code: str
    title: str
    source_url: str
    summary: str
    attribution: str
    language: str
    raw_payload: Dict[str, Any]


GetFn = Callable[[str, int], Dict[str, Any]]


def _http_get_json(url: str, timeout: int) -> Dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "SanaHealthLiteracy/1.0",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
            body = response.read().decode("utf-8")
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError) as exc:
        raise MedlinePlusTransportError(
            "MedlinePlus kaynak servisine ulaşılamadı."
        ) from exc
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise MedlinePlusResponseError(
            "MedlinePlus kaynak yanıtı çözümlenemedi."
        ) from exc
    if not isinstance(payload, dict):
        raise MedlinePlusResponseError("MedlinePlus kaynak yanıtı geçersiz.")
    return payload


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data: str) -> None:
        if data.strip():
            self.parts.append(data.strip())


def _strip_html(value: str) -> str:
    parser = _TextExtractor()
    parser.feed(value)
    return " ".join(parser.parts).strip()


def _node_text(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        return next((text for item in value if (text := _node_text(item))), "")
    if isinstance(value, dict):
        for key in ("_value", "value", "$", "content", "name"):
            if key in value:
                text = _node_text(value[key])
                if text:
                    return text
    return ""


def _entry_url(value: Any) -> str:
    links = value if isinstance(value, list) else [value]
    for link in links:
        if isinstance(link, str) and link.strip():
            return link.strip()
        if isinstance(link, dict):
            for key in ("href", "_href", "@href", "_value", "value"):
                candidate = link.get(key)
                if isinstance(candidate, str) and candidate.strip():
                    return candidate.strip()
    return ""


def _is_official_source_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    return parsed.scheme == "https" and (
        host == "medlineplus.gov" or host.endswith(".medlineplus.gov")
    )


def _canonicalize_source_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    return urllib.parse.urlunparse(
        (parsed.scheme, parsed.netloc, parsed.path, "", "", "")
    )


class MedlinePlusClient:
    def __init__(
        self,
        settings: Optional[MedlinePlusSettings] = None,
        get_fn: Optional[GetFn] = None,
    ):
        self.settings = settings or get_medlineplus_settings()
        self._get = get_fn or _http_get_json

    def build_lab_url(self, definition: LabSourceDefinition) -> str:
        params = {
            "mainSearchCriteria.v.cs": LOINC_CODE_SYSTEM_OID,
            "mainSearchCriteria.v.c": definition.loinc_code,
            "mainSearchCriteria.v.dn": definition.loinc_name,
            "informationRecipient.languageCode.c": "en",
            "knowledgeResponseType": "application/json",
        }
        return f"{self.settings.base_url.rstrip('?')}?{urllib.parse.urlencode(params)}"

    def fetch_lab(
        self, definition: LabSourceDefinition
    ) -> Optional[MedlinePlusRecord]:
        payload = self._get(
            self.build_lab_url(definition), self.settings.timeout_seconds
        )
        feed = payload.get("feed")
        if not isinstance(feed, dict):
            raise MedlinePlusResponseError("MedlinePlus kaynak yanıtı geçersiz.")

        entries = feed.get("entry") or []
        if isinstance(entries, dict):
            entries = [entries]
        if not isinstance(entries, list):
            raise MedlinePlusResponseError("MedlinePlus kaynak yanıtı geçersiz.")
        if not entries:
            return None

        entry = entries[0]
        if not isinstance(entry, dict):
            raise MedlinePlusResponseError("MedlinePlus kaynak kaydı geçersiz.")

        title = _node_text(entry.get("title"))
        source_url = _entry_url(entry.get("link"))
        summary = _strip_html(_node_text(entry.get("summary")))
        attribution = _node_text(entry.get("author")) or "MedlinePlus"

        if not title or not summary or not _is_official_source_url(source_url):
            raise MedlinePlusResponseError("MedlinePlus kaynak kaydı eksik veya geçersiz.")
        source_url = _canonicalize_source_url(source_url)

        return MedlinePlusRecord(
            lab_test=definition.lab_test,
            loinc_code=definition.loinc_code,
            title=title,
            source_url=source_url,
            summary=summary,
            attribution=attribution,
            language="en",
            raw_payload=payload,
        )
