"""Retrieval v0: lab_test çözümleme + keyword tabanlı chunk sıralama.

Embedding yok; sadece exact match, synonym map ve kelime örtüşmesi.
"""

from dataclasses import dataclass
import re
from typing import List, Optional, Tuple

from app.core import config
from app.core import constants as C
from app.data import seed_documents
from app.data.synonyms import SYNONYM_MAP, LAB_VALUES
from app.services.normalization_service import normalize
from app.utils import text_utils

# Tüm chunk'ları bir kez yükle
_ALL_CHUNKS = seed_documents.get_all_chunks()

# Synonym'leri ve kanonik tokenleri normalize ederek önceden hesapla
_SYNONYMS_NORM = {
    lab: [normalize(s) for s in syns] for lab, syns in SYNONYM_MAP.items()
}
_CANONICAL = {lab: normalize(lab) for lab in LAB_VALUES}


def _contains_term(text: str, term: str) -> bool:
    """Kısa lab kodlarını sınırlar; uzun Türkçe terimlerde çekim eklerini korur."""
    if " " not in term and len(term) <= 3:
        return bool(re.search(rf"(?<!\w){re.escape(term)}(?!\w)", text))
    return term in text


@dataclass
class RetrievedChunk:
    chunk: seed_documents.Chunk
    score: float


@dataclass
class LabMatch:
    lab_test: Optional[str]
    exact: bool          # kanonik ad metinde geçti veya request'te verildi
    synonym: bool        # kanonik olmayan bir eş anlamlı geçti
    matched_term: Optional[str] = None  # kullanıcı girdisinden eşleşen terim (varsa)


def resolve_lab_test(normalized_text: str, explicit: Optional[str]) -> LabMatch:
    """İstekteki lab_test veya metindeki eşleşmeden kanonik lab değerini bulur."""
    exact = False
    synonym = False
    resolved: Optional[str] = None
    matched_term: Optional[str] = None

    # 1) Açıkça verilmiş lab_test
    if explicit:
        e = normalize(explicit)
        for lab in LAB_VALUES:
            if e == _CANONICAL[lab] or e in _SYNONYMS_NORM[lab]:
                resolved = lab
                exact = True
                matched_term = e
                break

    # 2) Kanonik token metinde geçiyor mu?
    if resolved is None:
        for lab in LAB_VALUES:
            if _contains_term(normalized_text, _CANONICAL[lab]):
                resolved = lab
                exact = True
                matched_term = _CANONICAL[lab]
                break

    # 3) Eş anlamlı arama (en uzun eşleşme önce -> daha spesifik)
    if resolved is None:
        candidates: List[Tuple[int, str, str]] = []
        for lab, syns in _SYNONYMS_NORM.items():
            for syn in syns:
                if syn and _contains_term(normalized_text, syn):
                    candidates.append((len(syn), lab, syn))
        if candidates:
            candidates.sort(reverse=True)
            _, lab, syn = candidates[0]
            resolved = lab
            matched_term = syn
            if syn == _CANONICAL[lab]:
                exact = True
            else:
                synonym = True

    # Çözülen lab için ayrıca: kanonik olmayan bir synonym de geçti mi?
    if resolved is not None:
        for syn in _SYNONYMS_NORM[resolved]:
            if syn != _CANONICAL[resolved] and _contains_term(normalized_text, syn):
                synonym = True
                break
        if _contains_term(normalized_text, _CANONICAL[resolved]):
            exact = True

    return LabMatch(lab_test=resolved, exact=exact, synonym=synonym, matched_term=matched_term)


def _score_chunk(query_tokens, chunk, detected_section) -> float:
    chunk_tokens = text_utils.tokenize(normalize(chunk.section + " " + chunk.content))
    ratio = text_utils.overlap_ratio(query_tokens, chunk_tokens)
    boost = 0.25 if chunk.section == detected_section else 0.0
    return round(min(1.0, ratio + boost), 2)


def retrieve(normalized_text: str, lab_test: str, detected_section: str, top_k: int = 3) -> List[RetrievedChunk]:
    """Belirtilen lab değeri için chunk'ları kelime örtüşmesine göre sıralar."""
    query_tokens = text_utils.tokenize(normalized_text)
    results: List[RetrievedChunk] = []
    for chunk in _ALL_CHUNKS:
        if chunk.lab_test != lab_test:
            continue
        score = _score_chunk(query_tokens, chunk, detected_section)
        results.append(RetrievedChunk(chunk=chunk, score=score))

    # Açıkça tespit edilen bölüm niyeti genel kelime örtüşmesinden daha güçlüdür.
    # Böylece seed ve local mod aynı deterministik davranışı gösterir.
    results.sort(
        key=lambda r: (
            r.chunk.section != detected_section,
            -r.score,
            r.chunk.chunk_id,
        )
    )
    return results[:top_k]


def retrieve_for_query(
    normalized_text: str, lab_test: str, detected_section: str, top_k: int = 3
) -> List[RetrievedChunk]:
    """Mode-aware retrieval (S97): endpoint akışlarının tek giriş noktası.

    SANA_RAG_MODE=local -> SQLite LocalRagStore + LocalRetriever;
    aksi halde (varsayılan "seed") mevcut bellek-içi retrieve() aynen çalışır.
    Dönüş tipi her iki modda da RetrievedChunk'tır.
    """
    if config.get_rag_mode() == "local":
        # Döngüsel import'u önlemek için lazy (local_retrieval_service bu modülü kullanır).
        from app.services import local_retrieval_service

        return local_retrieval_service.retrieve_from_store(
            normalized_text, lab_test, detected_section, top_k
        )
    return retrieve(normalized_text, lab_test, detected_section, top_k)
