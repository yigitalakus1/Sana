"""Local medical_docs -> LocalRagStore ingestion aracı (S94).

Komut satırından çalıştırılır; markdown dosyalarını parse eder ve chunk'ları
S93'teki idempotent LocalRagStore.upsert_chunks ile yazar. Tekrar çalıştırmak
güvenlidir: satır çoğaltmaz, içerik değişmedikçe updated_at değişmez.

Kullanım:
    python -m tools.ingest_docs
    python -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db

Ücretli/dış AI bağımlılığı yoktur; yalnız stdlib + mevcut proje servisleri.
"""

import argparse
import sys
from pathlib import Path
from typing import List

# Script doğrudan çalıştırıldığında (python tools/ingest_docs.py) proje kökü
# import edilebilir olsun diye eklenir; modül olarak (-m) çalıştırıldığında etkisiz.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import config  # noqa: E402
from app.data.seed_documents import Chunk  # noqa: E402
from app.services import chunking_service  # noqa: E402
from app.services.rag_store import LocalRagStore  # noqa: E402

DEFAULT_DOCS_DIR = "data/medical_docs"


def ingest(docs_dir: str, db_path: str) -> dict:
    """Docs klasörünü store'a yazar; özet sözlük döndürür."""
    docs_path = Path(docs_dir)
    if not docs_path.is_dir():
        raise ValueError(f"Doküman klasörü bulunamadı: {docs_dir}")

    md_files = sorted(docs_path.glob("*.md"))
    all_chunks: List[Chunk] = []
    for md in md_files:
        all_chunks.extend(chunking_service.chunk_file(md))

    store = LocalRagStore(db_path=db_path)
    before = store.count()
    store.upsert_chunks(all_chunks)
    after = store.count()

    return {
        "files_read": len(md_files),
        "chunks_parsed": len(all_chunks),
        "chunks_written": len(all_chunks),
        "store_count_before": before,
        "store_count_after": after,
        "db_path": store.db_path,
    }


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sana local medical_docs ingestion.")
    parser.add_argument("--docs-dir", default=DEFAULT_DOCS_DIR, help="Markdown doküman klasörü.")
    parser.add_argument("--db-path", default=None, help="SQLite RAG store yolu (varsayılan: config).")
    args = parser.parse_args(argv)

    db_path = args.db_path or config.get_rag_db_path()
    summary = ingest(args.docs_dir, db_path)

    print("Sana ingestion tamamlandı:")
    print(f"  Okunan dosya    : {summary['files_read']}")
    print(f"  Parse edilen chunk: {summary['chunks_parsed']}")
    print(f"  Store'a yazılan  : {summary['chunks_written']}")
    print(f"  Store toplam     : {summary['store_count_before']} -> {summary['store_count_after']}")
    print(f"  DB yolu          : {summary['db_path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
