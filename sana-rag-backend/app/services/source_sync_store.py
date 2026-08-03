"""Harici resmî kaynaklar için SQLite staging ve inceleme deposu.

Bu tablo kullanıcıya sunulan RAG chunk'larından bilinçli olarak ayrıdır. Yeni veya
değişen kaynak kaydı ``pending`` olur; yalnız açık inceleme sonrası onaylanabilir.
"""

import hashlib
import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from app.core import config
from app.data.loinc_catalog import LOINC_CODE_SYSTEM_OID, LabSourceDefinition
from app.services.medlineplus_client import MedlinePlusRecord


_CREATE_SOURCES_SQL = """
CREATE TABLE IF NOT EXISTS source_records (
    source_key     TEXT PRIMARY KEY,
    provider       TEXT NOT NULL,
    lab_test       TEXT NOT NULL,
    code_system    TEXT NOT NULL,
    code           TEXT NOT NULL,
    language       TEXT NOT NULL,
    title          TEXT NOT NULL,
    source_url     TEXT NOT NULL,
    summary        TEXT NOT NULL,
    attribution    TEXT NOT NULL,
    content_hash   TEXT NOT NULL,
    review_status  TEXT NOT NULL CHECK(review_status IN ('pending', 'approved', 'rejected')),
    reviewed_by    TEXT,
    first_seen_at  TEXT NOT NULL,
    fetched_at     TEXT NOT NULL,
    changed_at     TEXT NOT NULL,
    reviewed_at    TEXT,
    published_at   TEXT,
    raw_payload    TEXT NOT NULL
)
"""

_CREATE_STATUS_INDEX_SQL = (
    "CREATE INDEX IF NOT EXISTS idx_source_records_status "
    "ON source_records (review_status, lab_test)"
)

_CREATE_MAPPINGS_SQL = """
CREATE TABLE IF NOT EXISTS source_mappings (
    mapping_key          TEXT PRIMARY KEY,
    provider             TEXT NOT NULL,
    lab_test             TEXT NOT NULL,
    code_system          TEXT NOT NULL,
    code                 TEXT NOT NULL,
    loinc_name           TEXT NOT NULL DEFAULT '',
    common_test_rank     INTEGER,
    language             TEXT NOT NULL,
    source_url           TEXT NOT NULL,
    canonical_source_key TEXT NOT NULL,
    first_seen_at        TEXT NOT NULL,
    fetched_at           TEXT NOT NULL,
    FOREIGN KEY(canonical_source_key) REFERENCES source_records(source_key)
)
"""

_CREATE_MAPPING_URL_INDEX_SQL = (
    "CREATE INDEX IF NOT EXISTS idx_source_mappings_url "
    "ON source_mappings (source_url, canonical_source_key)"
)

_CREATE_DRAFTS_SQL = """
CREATE TABLE IF NOT EXISTS source_drafts (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    source_key     TEXT NOT NULL,
    source_hash    TEXT NOT NULL,
    language       TEXT NOT NULL,
    content        TEXT NOT NULL,
    content_hash   TEXT NOT NULL,
    generator      TEXT NOT NULL,
    review_status  TEXT NOT NULL CHECK(review_status IN ('pending', 'approved', 'rejected', 'stale')),
    reviewed_by    TEXT,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL,
    reviewed_at    TEXT,
    published_at   TEXT,
    UNIQUE(source_key, source_hash, language),
    FOREIGN KEY(source_key) REFERENCES source_records(source_key)
)
"""

_CREATE_DRAFT_STATUS_INDEX_SQL = (
    "CREATE INDEX IF NOT EXISTS idx_source_drafts_status "
    "ON source_drafts (review_status, source_key)"
)


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _content_hash(record: MedlinePlusRecord) -> str:
    canonical = json.dumps(
        {
            "title": record.title,
            "source_url": record.source_url,
            "summary": record.summary,
            "attribution": record.attribution,
            "language": record.language,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class SourceSnapshot:
    source_key: str
    provider: str
    lab_test: str
    code_system: str
    code: str
    language: str
    title: str
    source_url: str
    summary: str
    attribution: str
    content_hash: str
    review_status: str
    reviewed_by: Optional[str]
    first_seen_at: str
    fetched_at: str
    changed_at: str
    reviewed_at: Optional[str]
    published_at: Optional[str]
    raw_payload: Dict[str, Any]


@dataclass(frozen=True)
class SourceDraftSnapshot:
    id: int
    source_key: str
    source_hash: str
    language: str
    content: str
    content_hash: str
    generator: str
    review_status: str
    reviewed_by: Optional[str]
    created_at: str
    updated_at: str
    reviewed_at: Optional[str]
    published_at: Optional[str]


def _row_to_snapshot(row: sqlite3.Row) -> SourceSnapshot:
    return SourceSnapshot(
        source_key=row["source_key"],
        provider=row["provider"],
        lab_test=row["lab_test"],
        code_system=row["code_system"],
        code=row["code"],
        language=row["language"],
        title=row["title"],
        source_url=row["source_url"],
        summary=row["summary"],
        attribution=row["attribution"],
        content_hash=row["content_hash"],
        review_status=row["review_status"],
        reviewed_by=row["reviewed_by"],
        first_seen_at=row["first_seen_at"],
        fetched_at=row["fetched_at"],
        changed_at=row["changed_at"],
        reviewed_at=row["reviewed_at"],
        published_at=row["published_at"],
        raw_payload=json.loads(row["raw_payload"]),
    )


def _row_to_draft(row: sqlite3.Row) -> SourceDraftSnapshot:
    return SourceDraftSnapshot(
        id=int(row["id"]),
        source_key=row["source_key"],
        source_hash=row["source_hash"],
        language=row["language"],
        content=row["content"],
        content_hash=row["content_hash"],
        generator=row["generator"],
        review_status=row["review_status"],
        reviewed_by=row["reviewed_by"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        reviewed_at=row["reviewed_at"],
        published_at=row["published_at"],
    )


class SourceSyncStore:
    def __init__(self, db_path: Optional[str] = None):
        self.db_path = str(db_path or config.get_rag_db_path())
        parent = Path(self.db_path).parent
        if str(parent) not in ("", "."):
            parent.mkdir(parents=True, exist_ok=True)
        self.init_schema()

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA foreign_keys = ON")
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(_CREATE_SOURCES_SQL)
            conn.execute(_CREATE_STATUS_INDEX_SQL)
            conn.execute(_CREATE_MAPPINGS_SQL)
            mapping_columns = {
                row[1] for row in conn.execute("PRAGMA table_info(source_mappings)")
            }
            if "loinc_name" not in mapping_columns:
                conn.execute(
                    "ALTER TABLE source_mappings ADD COLUMN loinc_name TEXT NOT NULL DEFAULT ''"
                )
            if "common_test_rank" not in mapping_columns:
                conn.execute(
                    "ALTER TABLE source_mappings ADD COLUMN common_test_rank INTEGER"
                )
            conn.execute(_CREATE_MAPPING_URL_INDEX_SQL)
            conn.execute(_CREATE_DRAFTS_SQL)
            conn.execute(_CREATE_DRAFT_STATUS_INDEX_SQL)

    def upsert_medlineplus(
        self,
        definition: LabSourceDefinition,
        record: MedlinePlusRecord,
    ) -> str:
        """Kaydı ekler/günceller; ``created``, ``changed`` veya ``unchanged`` döner."""
        now = _utcnow_iso()
        digest = _content_hash(record)
        raw_payload = json.dumps(record.raw_payload, ensure_ascii=False, sort_keys=True)
        source_key = definition.source_key

        with self._connect() as conn:
            canonical = conn.execute(
                """
                SELECT source_key, content_hash FROM source_records
                WHERE source_url = ?
                ORDER BY CASE review_status WHEN 'approved' THEN 0 ELSE 1 END,
                         first_seen_at, source_key
                LIMIT 1
                """,
                (record.source_url,),
            ).fetchone()
            if canonical is not None and canonical["source_key"] != source_key:
                self._upsert_mapping(
                    conn, definition, record, canonical["source_key"], now
                )
                return "duplicate"

            existing = conn.execute(
                "SELECT content_hash FROM source_records WHERE source_key = ?",
                (source_key,),
            ).fetchone()
            if existing is None:
                conn.execute(
                    """
                    INSERT INTO source_records (
                        source_key, provider, lab_test, code_system, code, language,
                        title, source_url, summary, attribution, content_hash,
                        review_status, reviewed_by, first_seen_at, fetched_at,
                        changed_at, reviewed_at, published_at, raw_payload
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL,
                              ?, ?, ?, NULL, NULL, ?)
                    """,
                    (
                        source_key, "medlineplus", definition.lab_test,
                        LOINC_CODE_SYSTEM_OID, definition.loinc_code, record.language,
                        record.title, record.source_url, record.summary,
                        record.attribution, digest, now, now, now, raw_payload,
                    ),
                )
                self._upsert_mapping(conn, definition, record, source_key, now)
                return "created"

            if existing["content_hash"] == digest:
                conn.execute(
                    """
                    UPDATE source_records
                    SET fetched_at = ?, raw_payload = ?
                    WHERE source_key = ?
                    """,
                    (now, raw_payload, source_key),
                )
                self._upsert_mapping(conn, definition, record, source_key, now)
                return "unchanged"

            conn.execute(
                """
                UPDATE source_records
                SET title = ?, source_url = ?, summary = ?, attribution = ?,
                    content_hash = ?, review_status = 'pending', reviewed_by = NULL,
                    fetched_at = ?, changed_at = ?, reviewed_at = NULL,
                    published_at = NULL, raw_payload = ?
                WHERE source_key = ?
                """,
                (
                    record.title, record.source_url, record.summary,
                    record.attribution, digest, now, now, raw_payload, source_key,
                ),
            )
            conn.execute(
                """
                UPDATE source_drafts
                SET review_status = 'stale', published_at = NULL,
                    updated_at = ?
                WHERE source_key = ? AND source_hash != ?
                  AND review_status != 'stale'
                """,
                (now, source_key, digest),
            )
            self._upsert_mapping(conn, definition, record, source_key, now)
            return "changed"

    @staticmethod
    def _upsert_mapping(
        conn: sqlite3.Connection,
        definition: LabSourceDefinition,
        record: MedlinePlusRecord,
        canonical_source_key: str,
        now: str,
    ) -> None:
        conn.execute(
            """
            INSERT INTO source_mappings (
                mapping_key, provider, lab_test, code_system, code, language,
                loinc_name, common_test_rank, source_url, canonical_source_key,
                first_seen_at, fetched_at
            ) VALUES (?, 'medlineplus', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(mapping_key) DO UPDATE SET
                lab_test = excluded.lab_test,
                loinc_name = excluded.loinc_name,
                common_test_rank = excluded.common_test_rank,
                source_url = excluded.source_url,
                canonical_source_key = excluded.canonical_source_key,
                fetched_at = excluded.fetched_at
            """,
            (
                definition.source_key,
                definition.lab_test,
                LOINC_CODE_SYSTEM_OID,
                definition.loinc_code,
                record.language,
                definition.loinc_name,
                definition.common_test_rank,
                record.source_url,
                canonical_source_key,
                now,
                now,
            ),
        )

    def consolidate_pending_duplicates(self) -> int:
        """Taslağı olmayan pending URL tekrarlarını eşleme tablosunda birleştirir."""
        removed = 0
        now = _utcnow_iso()
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM source_records
                ORDER BY source_url,
                         CASE review_status WHEN 'approved' THEN 0 ELSE 1 END,
                         first_seen_at, source_key
                """
            ).fetchall()
            keepers: Dict[str, str] = {}
            for row in rows:
                keeper = keepers.setdefault(row["source_url"], row["source_key"])
                conn.execute(
                    """
                    INSERT INTO source_mappings (
                        mapping_key, provider, lab_test, code_system, code,
                        loinc_name, common_test_rank, language, source_url, canonical_source_key,
                        first_seen_at, fetched_at
                    ) VALUES (?, ?, ?, ?, ?, '', NULL, ?, ?, ?, ?, ?)
                    ON CONFLICT(mapping_key) DO UPDATE SET
                        source_url = excluded.source_url,
                        canonical_source_key = excluded.canonical_source_key,
                        fetched_at = excluded.fetched_at
                    """,
                    (
                        row["source_key"], row["provider"], row["lab_test"],
                        row["code_system"], row["code"], row["language"],
                        row["source_url"], keeper, row["first_seen_at"], now,
                    ),
                )
                if row["source_key"] == keeper or row["review_status"] != "pending":
                    continue
                has_draft = conn.execute(
                    "SELECT 1 FROM source_drafts WHERE source_key = ? LIMIT 1",
                    (row["source_key"],),
                ).fetchone()
                if has_draft:
                    continue
                conn.execute(
                    "UPDATE source_mappings SET canonical_source_key = ? WHERE canonical_source_key = ?",
                    (keeper, row["source_key"]),
                )
                conn.execute(
                    "DELETE FROM source_records WHERE source_key = ?",
                    (row["source_key"],),
                )
                removed += 1
        return removed

    def mapping_count(self) -> int:
        with self._connect() as conn:
            (count,) = conn.execute("SELECT COUNT(*) FROM source_mappings").fetchone()
        return int(count)

    def refresh_mapping_metadata(self, definition: LabSourceDefinition) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE source_mappings
                SET lab_test = ?, loinc_name = ?, common_test_rank = ?
                WHERE mapping_key = ?
                """,
                (
                    definition.lab_test,
                    definition.loinc_name,
                    definition.common_test_rank,
                    definition.source_key,
                ),
            )

    def refresh_mapping_catalog(
        self, definitions: List[LabSourceDefinition]
    ) -> int:
        updated = 0
        with self._connect() as conn:
            for definition in definitions:
                cursor = conn.execute(
                    """
                    UPDATE source_mappings
                    SET lab_test = ?, loinc_name = ?, common_test_rank = ?
                    WHERE mapping_key = ?
                    """,
                    (
                        definition.lab_test,
                        definition.loinc_name,
                        definition.common_test_rank,
                        definition.source_key,
                    ),
                )
                updated += cursor.rowcount
        return updated

    def mapping_stats_by_source(self) -> Dict[str, dict]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT canonical_source_key, COUNT(*) AS mapping_count,
                       MIN(common_test_rank) AS best_common_rank
                FROM source_mappings
                GROUP BY canonical_source_key
                """
            ).fetchall()
        return {
            row["canonical_source_key"]: {
                "mapping_count": int(row["mapping_count"]),
                "best_common_rank": row["best_common_rank"],
            }
            for row in rows
        }

    def get(self, source_key: str) -> Optional[SourceSnapshot]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM source_records WHERE source_key = ?", (source_key,)
            ).fetchone()
        return _row_to_snapshot(row) if row else None

    def list_by_status(self, status: str) -> List[SourceSnapshot]:
        if status not in {"pending", "approved", "rejected"}:
            raise ValueError("Geçersiz inceleme durumu.")
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM source_records
                WHERE review_status = ? ORDER BY lab_test, source_key
                """,
                (status,),
            ).fetchall()
        return [_row_to_snapshot(row) for row in rows]

    def list_all(self) -> List[SourceSnapshot]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM source_records ORDER BY lab_test, source_key"
            ).fetchall()
        return [_row_to_snapshot(row) for row in rows]

    def is_fresh(self, source_key: str, max_age_hours: int) -> bool:
        snapshot = self.get(source_key)
        fetched_value = snapshot.fetched_at if snapshot is not None else None
        if fetched_value is None:
            with self._connect() as conn:
                row = conn.execute(
                    "SELECT fetched_at FROM source_mappings WHERE mapping_key = ?",
                    (source_key,),
                ).fetchone()
            fetched_value = row["fetched_at"] if row else None
        if fetched_value is None:
            return False
        try:
            fetched_at = datetime.fromisoformat(fetched_value)
        except ValueError:
            return False
        if fetched_at.tzinfo is None:
            fetched_at = fetched_at.replace(tzinfo=timezone.utc)
        return datetime.now(timezone.utc) - fetched_at < timedelta(hours=max_age_hours)

    def approve(self, source_key: str, reviewer: str) -> None:
        reviewer = reviewer.strip()
        if not reviewer:
            raise ValueError("İnceleyen kişi boş olamaz.")
        now = _utcnow_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE source_records
                SET review_status = 'approved', reviewed_by = ?, reviewed_at = ?
                WHERE source_key = ?
                """,
                (reviewer, now, source_key),
            )
            if cursor.rowcount != 1:
                raise ValueError("Kaynak kaydı bulunamadı.")

    def reject(self, source_key: str, reviewer: str) -> None:
        reviewer = reviewer.strip()
        if not reviewer:
            raise ValueError("İnceleyen kişi boş olamaz.")
        now = _utcnow_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE source_records
                SET review_status = 'rejected', reviewed_by = ?, reviewed_at = ?,
                    published_at = NULL
                WHERE source_key = ?
                """,
                (reviewer, now, source_key),
            )
            if cursor.rowcount != 1:
                raise ValueError("Kaynak kaydı bulunamadı.")

    def mark_published(self, source_key: str) -> None:
        now = _utcnow_iso()
        with self._connect() as conn:
            row = conn.execute(
                "SELECT review_status FROM source_records WHERE source_key = ?",
                (source_key,),
            ).fetchone()
            if row is None:
                raise ValueError("Kaynak kaydı bulunamadı.")
            if row["review_status"] != "approved":
                raise ValueError("Yalnız onaylanmış kaynak yayınlanabilir.")
            conn.execute(
                "UPDATE source_records SET published_at = ? WHERE source_key = ?",
                (now, source_key),
            )

    def stage_draft(
        self,
        source_key: str,
        content: str,
        generator: str,
        language: str = "tr",
    ) -> str:
        """Onaylı kaynağa taslak ekler; kullanıcı RAG içeriğini değiştirmez."""
        content = content.strip()
        generator = generator.strip()
        if not content or not generator:
            raise ValueError("Taslak içeriği ve üretici boş olamaz.")
        now = _utcnow_iso()
        digest = hashlib.sha256(content.encode("utf-8")).hexdigest()

        with self._connect() as conn:
            source = conn.execute(
                """
                SELECT content_hash, review_status FROM source_records
                WHERE source_key = ?
                """,
                (source_key,),
            ).fetchone()
            if source is None:
                raise ValueError("Kaynak kaydı bulunamadı.")
            if source["review_status"] != "approved":
                raise ValueError("Yalnız onaylanmış kaynaktan taslak üretilebilir.")

            existing = conn.execute(
                """
                SELECT content_hash FROM source_drafts
                WHERE source_key = ? AND source_hash = ? AND language = ?
                """,
                (source_key, source["content_hash"], language),
            ).fetchone()
            if existing is None:
                conn.execute(
                    """
                    INSERT INTO source_drafts (
                        source_key, source_hash, language, content, content_hash,
                        generator, review_status, reviewed_by, created_at,
                        updated_at, reviewed_at, published_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 'pending', NULL, ?, ?, NULL, NULL)
                    """,
                    (
                        source_key, source["content_hash"], language, content,
                        digest, generator, now, now,
                    ),
                )
                return "created"
            if existing["content_hash"] == digest:
                return "unchanged"

            conn.execute(
                """
                UPDATE source_drafts
                SET content = ?, content_hash = ?, generator = ?,
                    review_status = 'pending', reviewed_by = NULL,
                    updated_at = ?, reviewed_at = NULL, published_at = NULL
                WHERE source_key = ? AND source_hash = ? AND language = ?
                """,
                (
                    content, digest, generator, now, source_key,
                    source["content_hash"], language,
                ),
            )
            return "changed"

    def get_current_draft(
        self, source_key: str, language: str = "tr"
    ) -> Optional[SourceDraftSnapshot]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT d.* FROM source_drafts d
                JOIN source_records s ON s.source_key = d.source_key
                WHERE d.source_key = ? AND d.source_hash = s.content_hash
                  AND d.language = ?
                """,
                (source_key, language),
            ).fetchone()
        return _row_to_draft(row) if row else None

    def list_drafts(self, status: str) -> List[SourceDraftSnapshot]:
        if status not in {"pending", "approved", "rejected", "stale"}:
            raise ValueError("Geçersiz taslak inceleme durumu.")
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT * FROM source_drafts
                WHERE review_status = ? ORDER BY source_key, id
                """,
                (status,),
            ).fetchall()
        return [_row_to_draft(row) for row in rows]

    def approve_draft(self, source_key: str, reviewer: str) -> None:
        self._review_draft(source_key, reviewer, "approved")

    def reject_draft(self, source_key: str, reviewer: str) -> None:
        self._review_draft(source_key, reviewer, "rejected")

    def _review_draft(self, source_key: str, reviewer: str, status: str) -> None:
        reviewer = reviewer.strip()
        if not reviewer:
            raise ValueError("İnceleyen kişi boş olamaz.")
        now = _utcnow_iso()
        with self._connect() as conn:
            source = conn.execute(
                "SELECT content_hash FROM source_records WHERE source_key = ?",
                (source_key,),
            ).fetchone()
            if source is None:
                raise ValueError("Kaynak kaydı bulunamadı.")
            cursor = conn.execute(
                """
                UPDATE source_drafts
                SET review_status = ?, reviewed_by = ?, reviewed_at = ?,
                    updated_at = ?, published_at = NULL
                WHERE source_key = ? AND source_hash = ? AND language = 'tr'
                  AND review_status != 'stale'
                """,
                (status, reviewer, now, now, source_key, source["content_hash"]),
            )
            if cursor.rowcount != 1:
                raise ValueError("Güncel taslak bulunamadı.")

    def mark_draft_published(self, source_key: str) -> None:
        now = _utcnow_iso()
        with self._connect() as conn:
            source = conn.execute(
                "SELECT content_hash FROM source_records WHERE source_key = ?",
                (source_key,),
            ).fetchone()
            if source is None:
                raise ValueError("Kaynak kaydı bulunamadı.")
            cursor = conn.execute(
                """
                UPDATE source_drafts SET published_at = ?, updated_at = ?
                WHERE source_key = ? AND source_hash = ? AND language = 'tr'
                  AND review_status = 'approved'
                """,
                (now, now, source_key, source["content_hash"]),
            )
            if cursor.rowcount != 1:
                raise ValueError("Yalnız onaylanmış güncel taslak yayınlanabilir.")

    def count(self) -> int:
        with self._connect() as conn:
            (count,) = conn.execute("SELECT COUNT(*) FROM source_records").fetchone()
        return int(count)
