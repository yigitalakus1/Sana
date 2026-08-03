"""Desteklenen lab testleri ve detayları — seed verisinden, read-only.

Public yanıta yalnız lab_test / title / section / kaynak metadata çıkar;
chunk_id, content ve skor asla dışarı verilmez (DECISIONS §6/§10/§11).
"""

from typing import Dict, List, Optional, Tuple

from app.data import seed_documents
from app.services import retrieval_service
from app.services.normalization_service import normalize


def _grouped() -> Tuple[List[str], Dict[str, dict]]:
    """Seed chunk'larını lab_test'e göre (seed sırasını koruyarak) gruplar."""
    order: List[str] = []
    by_lab: Dict[str, dict] = {}
    for chunk in seed_documents.get_all_chunks():
        entry = by_lab.get(chunk.lab_test)
        if entry is None:
            entry = {
                "lab_test": chunk.lab_test,
                "title": chunk.title,
                "sections": [],
                "sources": {},  # source_url -> source_title (URL'e göre dedup)
            }
            by_lab[chunk.lab_test] = entry
            order.append(chunk.lab_test)
        if chunk.section not in entry["sections"]:
            entry["sections"].append(chunk.section)
        if chunk.source_url not in entry["sources"]:
            entry["sources"][chunk.source_url] = chunk.source_title
    return order, by_lab


def list_terms() -> List[dict]:
    """Desteklenen tüm lab testlerini seed sırasında döndürür."""
    order, by_lab = _grouped()
    return [
        {
            "lab_test": by_lab[lab]["lab_test"],
            "title": by_lab[lab]["title"],
            "sections": list(by_lab[lab]["sections"]),
        }
        for lab in order
    ]


def get_term(path_value: str) -> Optional[dict]:
    """Path değerini mevcut resolve mantığıyla kanonik lab test'e bağlar.

    Bulunamazsa None döner (route 404'e çevirir).
    """
    match = retrieval_service.resolve_lab_test(normalize(path_value), path_value)
    if match.lab_test is None:
        return None

    _, by_lab = _grouped()
    entry = by_lab.get(match.lab_test)
    if entry is None:
        return None

    sources = [
        {"source_title": title, "source_url": url, "section": None}
        for url, title in entry["sources"].items()
    ]
    return {
        "lab_test": entry["lab_test"],
        "title": entry["title"],
        "sections": list(entry["sections"]),
        "sources": sources,
    }
