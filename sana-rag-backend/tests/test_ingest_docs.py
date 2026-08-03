"""S94 — tools/ingest_docs testleri (geçici docs dir + geçici db)."""

from pathlib import Path

import pytest

from app.services.rag_store import LocalRagStore
from tools import ingest_docs

DOC_A = """---
lab_test: CRP
source_title: Sana Seed Medical Notes
source_url: local://sana/medical_docs/crp
safety_level: general
---

## Nedir?
CRP bir iltihap belirtecidir.

## Neden ölçülür?
Enfeksiyon veya iltihap şüphesinde istenir.
"""

DOC_B = """---
lab_test: B12
source_title: Sana Seed Medical Notes
source_url: local://sana/medical_docs/b12
safety_level: general
---

## Nedir?
B12 bir vitamindir.
"""


def _write_docs(tmp_path) -> Path:
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "crp.md").write_text(DOC_A, encoding="utf-8")
    (docs / "b12.md").write_text(DOC_B, encoding="utf-8")
    return docs


def test_ingest_multiple_files(tmp_path):
    docs = _write_docs(tmp_path)
    db = tmp_path / "rag.db"
    summary = ingest_docs.ingest(str(docs), str(db))
    assert summary["files_read"] == 2
    assert summary["chunks_parsed"] == 3
    assert summary["chunks_written"] == 3
    assert summary["store_count_after"] == 3

    store = LocalRagStore(db_path=str(db))
    assert store.count() == 3
    assert {c.lab_test for c in store.get_all_chunks()} == {"CRP", "B12"}


def test_ingest_is_idempotent(tmp_path):
    docs = _write_docs(tmp_path)
    db = tmp_path / "rag.db"

    ingest_docs.ingest(str(docs), str(db))
    store = LocalRagStore(db_path=str(db))
    ts_before = store.get_timestamps("crp-nedir")

    second = ingest_docs.ingest(str(docs), str(db))  # tekrar
    assert second["store_count_after"] == 3  # satır çoğalmadı
    assert store.count() == 3
    # İçerik değişmedi -> updated_at korunur
    assert store.get_timestamps("crp-nedir") == ts_before


def test_ingest_updates_changed_content(tmp_path, monkeypatch):
    docs = _write_docs(tmp_path)
    db = tmp_path / "rag.db"

    monkeypatch.setattr(
        "app.services.rag_store._utcnow_iso", lambda: "2026-07-02T10:00:00+00:00"
    )
    ingest_docs.ingest(str(docs), str(db))

    (docs / "crp.md").write_text(
        DOC_A.replace("CRP bir iltihap belirtecidir.", "CRP güncellenmiş içerik."),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "app.services.rag_store._utcnow_iso", lambda: "2026-07-02T12:00:00+00:00"
    )
    ingest_docs.ingest(str(docs), str(db))

    store = LocalRagStore(db_path=str(db))
    assert store.count() == 3  # çoğalmadı
    assert store.get_chunk("crp-nedir").content == "CRP güncellenmiş içerik."
    created_at, updated_at = store.get_timestamps("crp-nedir")
    assert created_at == "2026-07-02T10:00:00+00:00"
    assert updated_at == "2026-07-02T12:00:00+00:00"


def test_ingest_missing_dir_raises(tmp_path):
    with pytest.raises(ValueError, match="bulunamadı"):
        ingest_docs.ingest(str(tmp_path / "yok"), str(tmp_path / "rag.db"))


def test_main_uses_config_db_path(tmp_path, monkeypatch, capsys):
    docs = _write_docs(tmp_path)
    db = tmp_path / "env_rag.db"
    monkeypatch.setenv("SANA_RAG_DB_PATH", str(db))

    rc = ingest_docs.main(["--docs-dir", str(docs)])
    assert rc == 0
    assert db.exists()
    out = capsys.readouterr().out
    assert "ingestion tamamlandı" in out
    assert "Parse edilen chunk: 3" in out


def test_main_db_path_override(tmp_path, capsys):
    docs = _write_docs(tmp_path)
    db = tmp_path / "override.db"
    rc = ingest_docs.main(["--docs-dir", str(docs), "--db-path", str(db)])
    assert rc == 0
    assert LocalRagStore(db_path=str(db)).count() == 3
