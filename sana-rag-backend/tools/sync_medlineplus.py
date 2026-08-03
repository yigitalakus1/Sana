"""MedlinePlus Connect kayıtlarını yerel staging tablosuna senkronize eder."""

import argparse
import sys
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.data.loinc_catalog import (  # noqa: E402
    LAB_SOURCE_DEFINITIONS,
    LoincCatalogError,
    load_catalog_csv,
    merge_catalogs,
)
from app.services.medlineplus_client import MedlinePlusClient  # noqa: E402
from app.services.source_sync_service import sync_medlineplus  # noqa: E402
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="MedlinePlus Connect kaynaklarını SQLite staging'e alır."
    )
    parser.add_argument("--db-path", default=None, help="SQLite RAG/store yolu.")
    parser.add_argument(
        "--lab-test",
        action="append",
        default=[],
        help="Yalnız belirtilen tahlili senkronize et; birden çok kez verilebilir.",
    )
    parser.add_argument(
        "--force", action="store_true", help="12-24 saatlik önbelleği yok say."
    )
    parser.add_argument(
        "--catalog-csv",
        help="Ek LOINC kayıtlarını içeren UTF-8 CSV dosyası.",
    )
    parser.add_argument(
        "--catalog-only",
        action="store_true",
        help="Yerleşik 10 kayıt yerine yalnız --catalog-csv içeriğini kullan.",
    )
    parser.add_argument(
        "--max-common-rank",
        type=int,
        default=None,
        help="Resmi LOINC.csv için yalnız bu COMMON_TEST_RANK değerine kadar yükle.",
    )
    parser.add_argument("--offset", type=int, default=0, help="İlk atlanacak katalog kaydı.")
    parser.add_argument("--limit", type=int, default=0, help="En fazla işlenecek kayıt; 0=tümü.")
    parser.add_argument(
        "--request-interval-seconds",
        type=float,
        default=0.65,
        help="API çağrıları arasındaki bekleme; varsayılan NLM sınırına uygundur.",
    )
    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="Ağ çağrısı yapmadan mevcut eşlemelerin LOINC metadata alanlarını güncelle.",
    )
    args = parser.parse_args(argv)

    if args.catalog_only and not args.catalog_csv:
        parser.error("--catalog-only için --catalog-csv gerekli")
    if (
        args.offset < 0
        or args.limit < 0
        or args.request_interval_seconds < 0
        or (args.max_common_rank is not None and args.max_common_rank < 1)
    ):
        parser.error("offset, limit ve istek aralığı negatif olamaz")

    try:
        external = (
            load_catalog_csv(
                args.catalog_csv, max_common_rank=args.max_common_rank
            )
            if args.catalog_csv
            else ()
        )
        definitions = (
            external
            if args.catalog_only
            else merge_catalogs(LAB_SOURCE_DEFINITIONS, external)
        )
    except LoincCatalogError as exc:
        parser.error(str(exc))

    by_name = {item.lab_test: item for item in definitions}
    unknown = [name for name in args.lab_test if name not in by_name]
    if unknown:
        parser.error(f"desteklenmeyen tahlil: {', '.join(unknown)}")

    definitions = (
        tuple(by_name[name] for name in args.lab_test)
        if args.lab_test
        else definitions
    )
    definitions = definitions[args.offset :]
    if args.limit:
        definitions = definitions[: args.limit]
    store = SourceSyncStore(db_path=args.db_path)
    if args.metadata_only:
        updated = store.refresh_mapping_catalog(list(definitions))
        print("LOINC eşleme metadata yenilemesi tamamlandı:")
        print(f"  Katalog toplamı : {len(definitions)}")
        print(f"  Güncellenen     : {updated}")
        print(f"  Kod eşlemesi    : {store.mapping_count()}")
        return 0

    result = sync_medlineplus(
        definitions=definitions,
        client=MedlinePlusClient(),
        store=store,
        force=args.force,
        request_interval_seconds=args.request_interval_seconds,
    )

    print("MedlinePlus kaynak senkronizasyonu tamamlandı:")
    print(f"  Katalog toplamı : {result.total}")
    print(f"  Servisten alınan: {result.fetched}")
    print(f"  Yeni kayıt      : {result.created}")
    print(f"  Değişen kayıt   : {result.changed}")
    print(f"  Aynı kalan      : {result.unchanged}")
    print(f"  Cache nedeniyle : {result.skipped_fresh}")
    print(f"  Eşleşme yok     : {result.no_match}")
    print(f"  Tekrarlı eşleme : {result.duplicate}")
    print(f"  Birleştirilen   : {result.consolidated}")
    print(f"  Hata            : {result.failed}")
    print(f"  Kod eşlemesi    : {store.mapping_count()}")
    print(f"  Pending toplam  : {len(store.list_by_status('pending'))}")
    for error in result.errors:
        print(f"  - {error['lab_test']}: {error['message']}")
    return 1 if result.failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
