"""MedlinePlus Connect -> SQLite staging senkronizasyon akışı."""

from dataclasses import dataclass, field
import time
from typing import Callable, Iterable, List, Optional

from app.data.loinc_catalog import LAB_SOURCE_DEFINITIONS, LabSourceDefinition
from app.services.medlineplus_client import MedlinePlusClient, MedlinePlusError
from app.services.source_sync_store import SourceSyncStore


@dataclass
class SourceSyncResult:
    total: int = 0
    fetched: int = 0
    created: int = 0
    changed: int = 0
    unchanged: int = 0
    skipped_fresh: int = 0
    no_match: int = 0
    duplicate: int = 0
    consolidated: int = 0
    failed: int = 0
    errors: List[dict] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "total": self.total,
            "fetched": self.fetched,
            "created": self.created,
            "changed": self.changed,
            "unchanged": self.unchanged,
            "skipped_fresh": self.skipped_fresh,
            "no_match": self.no_match,
            "duplicate": self.duplicate,
            "consolidated": self.consolidated,
            "failed": self.failed,
            "errors": list(self.errors),
        }


def sync_medlineplus(
    *,
    definitions: Iterable[LabSourceDefinition] = LAB_SOURCE_DEFINITIONS,
    client: Optional[MedlinePlusClient] = None,
    store: Optional[SourceSyncStore] = None,
    force: bool = False,
    request_interval_seconds: float = 0.0,
    sleep_fn: Callable[[float], None] = time.sleep,
) -> SourceSyncResult:
    client = client or MedlinePlusClient()
    store = store or SourceSyncStore()
    selected = tuple(definitions)
    result = SourceSyncResult(total=len(selected))
    result.consolidated = store.consolidate_pending_duplicates()

    remote_request_count = 0
    for definition in selected:
        if not force and store.is_fresh(
            definition.source_key, client.settings.cache_hours
        ):
            store.refresh_mapping_metadata(definition)
            result.skipped_fresh += 1
            continue
        if remote_request_count and request_interval_seconds > 0:
            sleep_fn(request_interval_seconds)
        remote_request_count += 1
        try:
            record = client.fetch_lab(definition)
        except MedlinePlusError as exc:
            result.failed += 1
            result.errors.append(
                {"lab_test": definition.lab_test, "message": str(exc)}
            )
            continue

        result.fetched += 1
        if record is None:
            result.no_match += 1
            continue

        outcome = store.upsert_medlineplus(definition, record)
        setattr(result, outcome, getattr(result, outcome) + 1)

    return result
