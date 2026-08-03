"""S95 — local_retrieval_service testleri.

Gerçek data/medical_docs dosyaları ingest_docs ile geçici bir DB'ye yazılır,
retrieval bu store üzerinden çalışır. Standalone katman; endpoint'e bağlı değil.
"""

from pathlib import Path

import pytest

from app.services import local_retrieval_service as lrs
from app.services.local_retrieval_service import LocalRetriever
from app.services.rag_store import LocalRagStore
from tools import ingest_docs

DOCS_DIR = Path(__file__).resolve().parents[1] / "data" / "medical_docs"


@pytest.fixture
def retriever(tmp_path):
    db = tmp_path / "rag.db"
    ingest_docs.ingest(str(DOCS_DIR), str(db))
    return LocalRetriever(LocalRagStore(db_path=str(db)))


# 1) Token normalization
def test_fold_tokens_handles_turkish():
    toks = lrs.fold_tokens("Düşük ölçüm ÇÖZÜM")
    assert "dusuk" in toks
    assert "olcum" in toks
    assert "cozum" in toks
    # 'düşük' ve ASCII 'dusuk' aynı token'a katlanır
    assert lrs.fold_tokens("düşük") == lrs.fold_tokens("dusuk")


def test_fold_tokens_drops_stopwords_and_punct():
    assert lrs.fold_tokens("bu ne için?!") == []


# 2) CRP sorgusu CRP chunk'larını üstte getirir
def test_crp_query_ranks_crp_first(retriever):
    results = retriever.get_top_chunks("CRP nedir", top_k=3)
    assert results
    assert results[0].chunk.lab_test == "CRP"


# 3) B12 eksikliği -> B12 üstte
def test_b12_query_ranks_b12_first(retriever):
    results = retriever.get_top_chunks("B12 eksikliği", top_k=3)
    assert results
    assert results[0].chunk.lab_test == "B12"


# 4) ferritin neden ölçülür -> Ferritin + "Neden ölçülür?" section üstte
def test_ferritin_why_section_first(retriever):
    results = retriever.get_top_chunks("ferritin neden ölçülür", top_k=3)
    assert results
    top = results[0].chunk
    assert top.lab_test == "Ferritin"
    assert top.section == "Neden ölçülür?"


def test_explicit_target_section_beats_overlap_in_combined_alt_question(retriever):
    question = (
        "ALT 25 U/L çıktı. Bu tahlilin neyi ölçtüğünü ve sonucun "
        "genel olarak ne anlama gelebileceğini açıkla."
    )

    results = retriever.get_top_chunks_for_lab(
        question,
        "ALT",
        "Nedir?",
        top_k=6,
    )

    assert results[0].chunk.section == "Nedir?"


# 5) top_k sınırı
def test_top_k_limit(retriever):
    assert len(retriever.get_top_chunks("CRP", top_k=1)) == 1
    assert len(retriever.get_top_chunks("CRP", top_k=2)) == 2
    assert retriever.get_top_chunks("CRP", top_k=0) == []


# 6) Boş DB -> boş sonuç
def test_empty_store_returns_empty(tmp_path):
    empty = LocalRetriever(LocalRagStore(db_path=str(tmp_path / "empty.db")))
    assert empty.get_top_chunks("CRP nedir") == []


# 7) Alakasız sorgu -> no-results
def test_irrelevant_query_returns_empty(retriever):
    assert retriever.get_top_chunks("otomobil lastiği fiyatları") == []


def test_empty_query_returns_empty(retriever):
    assert retriever.get_top_chunks("") == []
    assert retriever.get_top_chunks("   ") == []
    assert retriever.get_top_chunks("ve bu için") == []  # sadece stopword


# 8) Skorlar azalan sıralı
def test_scores_descending(retriever):
    results = retriever.get_top_chunks("hemoglobin düşük ne anlama gelebilir", top_k=6)
    scores = [r.score for r in results]
    assert scores == sorted(scores, reverse=True)


# 9) Metadata korunur
def test_metadata_preserved(retriever):
    r = retriever.get_top_chunks("glukoz nedir", top_k=1)[0]
    c = r.chunk
    assert c.lab_test == "Glukoz"
    assert c.source_title == "MedlinePlus"
    assert c.source_url == "https://medlineplus.gov/lab-tests/blood-glucose-test/"
    assert c.safety_level == "general"
    assert c.title and c.section and c.content
    assert r.matched_terms  # eşleşen terimler raporlanır


# 10) Determinizm
def test_retrieval_is_deterministic(retriever):
    q = "ferritin yüksek ne anlama gelir"
    first = retriever.get_top_chunks(q, top_k=5)
    second = retriever.get_top_chunks(q, top_k=5)
    assert [(r.chunk.chunk_id, r.score) for r in first] == [
        (r.chunk.chunk_id, r.score) for r in second
    ]


def test_tie_break_by_chunk_id():
    """Eşit skorda chunk_id artan sırada olmalı."""
    import tempfile

    with tempfile.TemporaryDirectory() as d:
        store = LocalRagStore(db_path=str(Path(d) / "t.db"))
        from app.data.seed_documents import Chunk

        # 'zzz' token'ı iki chunk'ta birebir aynı skorla eşleşir.
        store.upsert_chunks([
            Chunk("b-id", "X", "X - S", "S", "zzz", "T", "local://x", "general"),
            Chunk("a-id", "X", "X - S", "S", "zzz", "T", "local://x", "general"),
        ])
        r = LocalRetriever(store).get_top_chunks("zzz", top_k=2)
        assert [x.chunk.chunk_id for x in r] == ["a-id", "b-id"]
