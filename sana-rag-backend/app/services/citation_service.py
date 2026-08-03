"""Citation: sadece retrieval'dan gelen kaynaklardan, source_url'e göre tekilleştirilmiş liste.

chunk_id asla public response'a eklenmez. Skor public yanıta dahil edilmez;
yalnız tekilleştirme/sıralama için kullanılır.
"""

from typing import Dict, List

from app.services.retrieval_service import RetrievedChunk


def build(retrieved: List[RetrievedChunk]) -> List[dict]:
    """Aynı source_url'yi tekilleştirir; her kaynak için en yüksek skorlu chunk'ın
    section'ını kullanır. Sonuç skora göre azalan sırada döner."""
    by_url: Dict[str, dict] = {}
    scores: Dict[str, float] = {}
    for item in retrieved:
        c = item.chunk
        if c.source_url not in by_url or item.score > scores[c.source_url]:
            by_url[c.source_url] = {
                "source_title": c.source_title,
                "source_url": c.source_url,
                "section": c.section,
            }
            scores[c.source_url] = item.score
    citations = sorted(by_url.values(), key=lambda s: scores[s["source_url"]], reverse=True)
    return citations
