"""S93 — Local RAG Store (SQLite) testleri.

Store bu sprintte dormant altyapıdır; retrieval hâlâ bellek-içi seed'den
çalışır. Burada şema, idempotent ingestion ve okuma yolları doğrulanır.
"""

import sqlite3
from dataclasses import replace

from app.core import config
from app.data import seed_documents
from app.services import rag_store
from app.services.rag_store import LocalRagStore


def make_store(tmp_path) -> LocalRagStore:
    return LocalRagStore(db_path=str(tmp_path / "test_rag.db"))


# --- Şema ---

def test_init_creates_schema_and_version(tmp_path):
    store = make_store(tmp_path)
    conn = sqlite3.connect(store.db_path)
    try:
        cols = {r[1] for r in conn.execute("PRAGMA table_info(chunks)")}
        assert cols == {
            "id", "lab_test", "title", "section", "content",
            "source_title", "source_url", "safety_level",
            "created_at", "updated_at",
        }
        (version,) = conn.execute(
            "SELECT value FROM store_meta WHERE key = 'schema_version'"
        ).fetchone()
        assert version == str(rag_store.SCHEMA_VERSION)
    finally:
        conn.close()


def test_init_is_reentrant(tmp_path):
    store = make_store(tmp_path)
    store.init_schema()  # ikinci çağrı hata vermemeli
    assert store.count() == 0


def test_db_parent_directory_is_created(tmp_path):
    nested = tmp_path / "data" / "nested" / "rag.db"
    store = LocalRagStore(db_path=str(nested))
    assert nested.exists()
    assert store.count() == 0


def test_default_path_comes_from_env(tmp_path, monkeypatch):
    env_path = tmp_path / "env_rag.db"
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(env_path))
    assert config.get_rag_db_path() == str(env_path)
    store = LocalRagStore()
    assert store.db_path == str(env_path)
    assert env_path.exists()


# --- Seed ingestion ---

def test_sync_from_seed_writes_all_chunks(tmp_path):
    store = make_store(tmp_path)
    n = store.sync_from_seed()
    expected = len(seed_documents.get_all_chunks())
    assert n == expected == store.count()
    assert expected == len(seed_documents.SEED_DOCUMENTS) * 6


def test_sync_from_seed_is_idempotent(tmp_path):
    store = make_store(tmp_path)
    store.sync_from_seed()
    first = {c.chunk_id: c for c in store.get_all_chunks()}
    ts_before = store.get_timestamps("CRP_0")

    store.sync_from_seed()  # tekrar çalıştırmak güvenli olmalı
    second = {c.chunk_id: c for c in store.get_all_chunks()}
    assert first == second
    # İçerik değişmediyse updated_at da değişmez
    assert store.get_timestamps("CRP_0") == ts_before


def test_seed_roundtrip_preserves_fields(tmp_path):
    store = make_store(tmp_path)
    store.sync_from_seed()
    original = {c.chunk_id: c for c in seed_documents.get_all_chunks()}
    stored = {c.chunk_id: c for c in store.get_all_chunks()}
    assert stored == original


# --- Upsert davranışı ---

def test_upsert_updates_changed_content(tmp_path, monkeypatch):
    store = make_store(tmp_path)
    chunk = seed_documents.get_all_chunks()[0]

    monkeypatch.setattr(rag_store, "_utcnow_iso", lambda: "2026-07-02T10:00:00+00:00")
    store.upsert_chunks([chunk])

    monkeypatch.setattr(rag_store, "_utcnow_iso", lambda: "2026-07-02T11:00:00+00:00")
    store.upsert_chunks([replace(chunk, content="Güncellenmiş içerik.")])

    assert store.count() == 1
    assert store.get_chunk(chunk.chunk_id).content == "Güncellenmiş içerik."
    created_at, updated_at = store.get_timestamps(chunk.chunk_id)
    assert created_at == "2026-07-02T10:00:00+00:00"
    assert updated_at == "2026-07-02T11:00:00+00:00"


def test_upsert_unchanged_keeps_updated_at(tmp_path, monkeypatch):
    store = make_store(tmp_path)
    chunk = seed_documents.get_all_chunks()[0]

    monkeypatch.setattr(rag_store, "_utcnow_iso", lambda: "2026-07-02T10:00:00+00:00")
    store.upsert_chunks([chunk])

    monkeypatch.setattr(rag_store, "_utcnow_iso", lambda: "2026-07-02T11:00:00+00:00")
    store.upsert_chunks([chunk])  # birebir aynı içerik

    created_at, updated_at = store.get_timestamps(chunk.chunk_id)
    assert created_at == updated_at == "2026-07-02T10:00:00+00:00"


# --- Okuma ---

def test_get_chunks_by_lab_test(tmp_path):
    store = make_store(tmp_path)
    store.sync_from_seed()
    crp = store.get_chunks_by_lab_test("CRP")
    assert len(crp) == 6
    assert all(c.lab_test == "CRP" for c in crp)
    assert store.get_chunks_by_lab_test("Bilinmeyen") == []


def test_get_chunk_missing_returns_none(tmp_path):
    store = make_store(tmp_path)
    assert store.get_chunk("yok_0") is None
    assert store.get_timestamps("yok_0") is None


def test_safety_level_defaults_to_general(tmp_path):
    store = make_store(tmp_path)
    store.sync_from_seed()
    assert all(c.safety_level == "general" for c in store.get_all_chunks())
