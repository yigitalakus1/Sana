"""Local retrieval (S95): LocalRagStore üzerinde BM25-benzeri lexical arama.

Embedding/dış servis YOK; yalnız stdlib. Bu katman bu sprintte STANDALONE'dur:
hiçbir endpoint buna bağlı değildir; runtime retrieval hâlâ
retrieval_service.py + seed_documents üzerinden çalışır. Bağlama S97'de,
kontrollü şekilde yapılacaktır.

Skorlama:
- Ana skor: içerik token'ları üzerinde IDF x doygun TF (BM25-benzeri;
  uzun chunk'ın tek kelime tekrarıyla şişmesini engeller).
- title/section token eşleşmeleri daha düşük ağırlıkla katkı verir.
- lab_test çözümlemesi (mevcut retrieval_service.resolve_lab_test, synonym'lı)
  eşleşen lab'ın chunk'larına sabit boost ekler.
- Section tespiti (mevcut intent_service.detect_section) eşleşen section'a
  küçük boost ekler.
- En az bir sorgu token'ı eşleşmeyen chunk'lar sonuçtan ELENİR; böylece
  alakasız sorgular boş liste döndürür (no-results davranışı).

Türkçe eşleştirme: normalize (Türkçe küçük harf + noktalama) sonrası
çğıöşü -> cgiosu katlaması yapılır; 'düşük' ve 'dusuk' aynı token'a düşer.
"""

import logging
import math
import os
from collections import Counter
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from app.core import config
from app.data.seed_documents import Chunk
from app.services import intent_service, retrieval_service
from app.services.normalization_service import normalize
from app.services.rag_store import LocalRagStore
from app.utils import text_utils

logger = logging.getLogger(__name__)

# Alan ağırlıkları: content ana sinyal, section/title destekleyici.
W_CONTENT = 1.0
W_SECTION = 0.5
W_TITLE = 0.3

# Sabit boost'lar (token skorunun üstüne eklenir; yalnız token eşleşmesi olan
# chunk'lar aday olduğundan alakasız sonuçları yukarı çekemez).
LAB_TEST_BOOST = 1.5
# Buyuyen corpus'ta genel terimlerin IDF etkisi acik section niyetini
# bastirmasin; "neden olculur" gibi sorgularda hedef section once gelmelidir.
SECTION_BOOST = 2.0

# TF doygunluk sabiti: tf/(tf+K). K büyüdükçe tekrarın etkisi artar.
TF_SATURATION_K = 1.0

_TR_ASCII = str.maketrans("çğıöşü", "cgiosu")


def fold_tokens(text: str) -> List[str]:
    """Türkçe-duyarlı normalize + ASCII katlama + stopword ayıklama."""
    folded = normalize(text).translate(_TR_ASCII)
    return text_utils.tokenize(folded)


@dataclass
class RetrievalResult:
    chunk: Chunk
    score: float
    matched_terms: List[str]


class _IndexedChunk:
    """Skorlama için önceden hesaplanmış token sayımları."""

    __slots__ = ("chunk", "content_tf", "section_tf", "title_tf", "all_terms")

    def __init__(self, chunk: Chunk):
        self.chunk = chunk
        self.content_tf = Counter(fold_tokens(chunk.content))
        self.section_tf = Counter(fold_tokens(chunk.section))
        self.title_tf = Counter(fold_tokens(chunk.title))
        self.all_terms = (
            set(self.content_tf) | set(self.section_tf) | set(self.title_tf)
        )


class LocalRetriever:
    """LocalRagStore'daki chunk'lar üzerinde top-K lexical retrieval.

    İndeks kurucuda bir kez yüklenir; store sonradan değiştiyse `refresh()`
    çağrılmalıdır.
    """

    def __init__(self, store: LocalRagStore):
        self.store = store
        self.refresh()

    def refresh(self) -> None:
        self._indexed = [_IndexedChunk(c) for c in self.store.get_all_chunks()]
        # Doküman frekansı (IDF için) tüm alanlardaki terimler üzerinden
        df: Dict[str, int] = Counter()
        for ic in self._indexed:
            for term in ic.all_terms:
                df[term] += 1
        self._df = df
        self._n = len(self._indexed)

    def _idf(self, term: str) -> float:
        df = self._df.get(term, 0)
        return math.log(1.0 + (self._n - df + 0.5) / (df + 0.5))

    def _score(self, query_tokens: List[str], ic: _IndexedChunk):
        score = 0.0
        matched: List[str] = []
        for t in set(query_tokens):
            wtf = (
                W_CONTENT * ic.content_tf.get(t, 0)
                + W_SECTION * ic.section_tf.get(t, 0)
                + W_TITLE * ic.title_tf.get(t, 0)
            )
            if wtf <= 0:
                continue
            matched.append(t)
            score += self._idf(t) * (wtf / (wtf + TF_SATURATION_K))
        return score, sorted(matched)

    def get_top_chunks(self, query: str, top_k: int = 3) -> List[RetrievalResult]:
        """Sorguya en alakalı top-K chunk'ı skor azalan sırada döndürür.

        Boş/anlamsız sorgu, boş store veya hiç token eşleşmemesi -> boş liste
        (hata değil); no-results kararını çağıran katman verir.
        """
        if top_k <= 0 or self._n == 0:
            return []
        normalized = normalize(query)
        query_tokens = fold_tokens(query)
        if not query_tokens:
            return []

        # Mevcut resolver/section mantığı yeniden yazılmaz, olduğu gibi kullanılır.
        lab_match = retrieval_service.resolve_lab_test(normalized, None)
        section = intent_service.detect_section(normalized)

        results: List[RetrievalResult] = []
        for ic in self._indexed:
            score, matched = self._score(query_tokens, ic)
            if not matched:
                continue  # hiç token eşleşmedi -> aday değil
            if lab_match.lab_test == ic.chunk.lab_test:
                score += LAB_TEST_BOOST
            if ic.chunk.section == section:
                score += SECTION_BOOST
            results.append(
                RetrievalResult(chunk=ic.chunk, score=round(score, 4), matched_terms=matched)
            )

        # Deterministik sıralama: skor azalan, eşitlikte chunk_id artan.
        results.sort(key=lambda r: (-r.score, r.chunk.chunk_id))
        return results[:top_k]

    def get_top_chunks_for_lab(
        self, query: str, lab_test: str, section: str, top_k: int = 3
    ) -> List[RetrievalResult]:
        """Çözülmüş bir lab değeri için chunk'ları sıralar (endpoint akışı, S97).

        seed retrieve() ile davranış paritesi: lab'ın chunk'ları token eşleşmesi
        OLMASA da döner (skor 0 olabilir); verilen section'a boost eklenir.
        Lab çözümü ve section tespiti çağıran katmanda zaten yapılmıştır,
        burada tekrarlanmaz. Store'da lab yoksa boş liste döner.
        """
        if top_k <= 0 or self._n == 0:
            return []
        query_tokens = fold_tokens(query)

        results: List[RetrievalResult] = []
        for ic in self._indexed:
            if ic.chunk.lab_test != lab_test:
                continue
            score, matched = self._score(query_tokens, ic)
            if ic.chunk.section == section:
                score += SECTION_BOOST
            results.append(
                RetrievalResult(chunk=ic.chunk, score=round(score, 4), matched_terms=matched)
            )

        # Çağıran katmanın belirlediği bölüm, uzun/birleşik sorulardaki genel
        # kelime örtüşmesinden daha güçlüdür. Örneğin PDF ekranındaki birleşik
        # ALT sorusu "Nedir?" yerine yanlışlıkla "Düşük" bölümüne gitmemeli.
        results.sort(
            key=lambda r: (
                r.chunk.section != section,
                -r.score,
                r.chunk.chunk_id,
            )
        )
        return results[:top_k]


# --- Endpoint akışı için store erişimi (S97) ---
# Retriever, dosya imzasına (mtime+boyut) göre önbelleklenir: her istekte
# yeniden indeksleme yapılmaz, ingestion sonrası değişiklik otomatik yansır.
_RETRIEVER_CACHE: Dict[str, Tuple[Tuple[int, int], LocalRetriever]] = {}


def _get_cached_retriever(db_path: str) -> Optional[LocalRetriever]:
    """DB dosyası varsa retriever döndürür; yoksa None (dosya OLUŞTURULMAZ).

    Bozuk/okunamayan DB crash'e değil None'a (-> no_results) çevrilir.
    """
    try:
        stat = os.stat(db_path)
    except OSError:
        return None
    signature = (stat.st_mtime_ns, stat.st_size)

    cached = _RETRIEVER_CACHE.get(db_path)
    if cached and cached[0] == signature:
        return cached[1]
    try:
        retriever = LocalRetriever(LocalRagStore(db_path=db_path))
    except Exception:  # noqa: BLE001 - bozuk DB endpoint'i düşürmemeli
        logger.warning("Local RAG store okunamadı: %s", db_path)
        return None
    _RETRIEVER_CACHE[db_path] = (signature, retriever)
    return retriever


def retrieve_from_store(
    normalized_text: str, lab_test: str, section: str, top_k: int = 3
) -> List["retrieval_service.RetrievedChunk"]:
    """SANA_RAG_MODE=local akışı: SQLite store'dan RetrievedChunk listesi.

    Dönüş tipi seed retrieval ile aynıdır; downstream (confidence, citation,
    provider.generate) hiçbir değişiklik görmez. DB yok/boş/bozuk -> boş liste
    (çağıran katman no_results döner, provider ÇAĞRILMAZ).
    """
    retriever = _get_cached_retriever(config.get_rag_db_path())
    if retriever is None:
        return []
    results = retriever.get_top_chunks_for_lab(normalized_text, lab_test, section, top_k)
    return [
        retrieval_service.RetrievedChunk(chunk=r.chunk, score=r.score) for r in results
    ]
