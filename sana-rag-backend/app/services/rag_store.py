"""Local RAG store: SQLite tabanlı chunk deposu (S93).

Seed verinin (app/data/seed_documents.py) kalıcı ve tekrar çalıştırılabilir
şekilde saklanacağı zemin. Bu sprintte retrieval hâlâ bellek-içi seed'den
çalışır; store dormant altyapıdır ve S95'te retrieval buraya bağlanacaktır.

Tasarım notları:
- sqlite3 stdlib'dir; yeni bağımlılık eklenmez.
- Her işlem kısa ömürlü bir bağlantı açar/kapatır (FastAPI thread'leriyle güvenli).
- Upsert idempotenttir: içerik değişmedikçe updated_at değişmez, satır çoğalmaz.
- Zaman damgaları UTC ISO-8601 metindir.
"""

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Optional

from app.core import config
from app.data import seed_documents
from app.data.seed_documents import Chunk

# Şema sürümü: alan ekleme/değiştirme gerektiğinde artırılır (migration kararı için).
SCHEMA_VERSION = 1

_CREATE_CHUNKS_SQL = """
CREATE TABLE IF NOT EXISTS chunks (
    id           TEXT PRIMARY KEY,
    lab_test     TEXT NOT NULL,
    title        TEXT NOT NULL DEFAULT '',
    section      TEXT NOT NULL,
    content      TEXT NOT NULL,
    source_title TEXT NOT NULL DEFAULT '',
    source_url   TEXT NOT NULL DEFAULT '',
    safety_level TEXT NOT NULL DEFAULT 'general',
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
)
"""

_CREATE_LAB_INDEX_SQL = (
    "CREATE INDEX IF NOT EXISTS idx_chunks_lab_test ON chunks (lab_test)"
)

_CREATE_META_SQL = """
CREATE TABLE IF NOT EXISTS store_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
)
"""

# İçerik alanlarından herhangi biri değiştiyse günceller; değişmediyse satıra
# dokunmaz (updated_at korunur -> idempotent yeniden-ingestion).
_UPSERT_SQL = """
INSERT INTO chunks (id, lab_test, title, section, content, source_title,
                    source_url, safety_level, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
    lab_test     = excluded.lab_test,
    title        = excluded.title,
    section      = excluded.section,
    content      = excluded.content,
    source_title = excluded.source_title,
    source_url   = excluded.source_url,
    safety_level = excluded.safety_level,
    updated_at   = excluded.updated_at
WHERE chunks.lab_test     != excluded.lab_test
   OR chunks.title        != excluded.title
   OR chunks.section      != excluded.section
   OR chunks.content      != excluded.content
   OR chunks.source_title != excluded.source_title
   OR chunks.source_url   != excluded.source_url
   OR chunks.safety_level != excluded.safety_level
"""


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _row_to_chunk(row: sqlite3.Row) -> Chunk:
    return Chunk(
        chunk_id=row["id"],
        lab_test=row["lab_test"],
        title=row["title"],
        section=row["section"],
        content=row["content"],
        source_title=row["source_title"],
        source_url=row["source_url"],
        safety_level=row["safety_level"],
    )


class LocalRagStore:
    """SQLite üzerinde chunk + metadata deposu."""

    def __init__(self, db_path: Optional[str] = None):
        self.db_path = str(db_path or config.get_rag_db_path())
        parent = Path(self.db_path).parent
        if str(parent) not in ("", "."):
            parent.mkdir(parents=True, exist_ok=True)
        self.init_schema()

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(_CREATE_CHUNKS_SQL)
            conn.execute(_CREATE_LAB_INDEX_SQL)
            conn.execute(_CREATE_META_SQL)
            conn.execute(
                "INSERT OR REPLACE INTO store_meta (key, value) VALUES (?, ?)",
                ("schema_version", str(SCHEMA_VERSION)),
            )

    # --- Yazma ---

    def upsert_chunks(self, chunks: Iterable[Chunk]) -> None:
        now = _utcnow_iso()
        rows = [
            (
                c.chunk_id, c.lab_test, c.title, c.section, c.content,
                c.source_title, c.source_url, c.safety_level, now, now,
            )
            for c in chunks
        ]
        with self._connect() as conn:
            conn.executemany(_UPSERT_SQL, rows)

    def sync_from_seed(self) -> int:
        """Bellek-içi seed dokümanlarını store'a idempotent şekilde yazar.

        Tekrar çalıştırmak güvenlidir; satır çoğaltmaz. Yazılan/var olan
        toplam chunk sayısını döndürür.
        """
        chunks = seed_documents.get_all_chunks()
        self.upsert_chunks(chunks)
        return self.count()

    # --- Okuma ---

    def get_all_chunks(self) -> List[Chunk]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM chunks ORDER BY lab_test, id"
            ).fetchall()
        return [_row_to_chunk(r) for r in rows]

    def get_chunks_by_lab_test(self, lab_test: str) -> List[Chunk]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM chunks WHERE lab_test = ? ORDER BY id",
                (lab_test,),
            ).fetchall()
        return [_row_to_chunk(r) for r in rows]

    def get_chunk(self, chunk_id: str) -> Optional[Chunk]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM chunks WHERE id = ?", (chunk_id,)
            ).fetchone()
        return _row_to_chunk(row) if row else None

    def count(self) -> int:
        with self._connect() as conn:
            (n,) = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()
        return int(n)

    def get_timestamps(self, chunk_id: str) -> Optional[tuple[str, str]]:
        """(created_at, updated_at) döndürür; chunk yoksa None."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT created_at, updated_at FROM chunks WHERE id = ?",
                (chunk_id,),
            ).fetchone()
        return (row["created_at"], row["updated_at"]) if row else None
