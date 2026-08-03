"""MedlinePlus source sync testleri - gerçek ağ çağrısı yoktur."""

import urllib.error
import urllib.parse

import pytest

from app.core.config import MedlinePlusSettings
from app.data.loinc_catalog import (
    LAB_SOURCE_BY_NAME,
    LAB_SOURCE_DEFINITIONS,
    LOINC_CODE_SYSTEM_OID,
    LoincCatalogError,
    load_catalog_csv,
    merge_catalogs,
)
from app.data.synonyms import LAB_VALUES
from app.services import medlineplus_client as mc
from app.services.medlineplus_client import (
    MedlinePlusClient,
    MedlinePlusRecord,
    MedlinePlusResponseError,
    MedlinePlusTransportError,
)
from app.services.source_sync_service import sync_medlineplus
from app.services.source_sync_store import SourceSyncStore


def settings(cache_hours=24):
    return MedlinePlusSettings(
        base_url="https://connect.medlineplus.gov/service",
        timeout_seconds=17,
        cache_hours=cache_hours,
    )


def payload(summary="<p>CRP is a protein.</p>"):
    return {
        "feed": {
            "entry": [
                {
                    "title": {"_value": "C-Reactive Protein (CRP) Test"},
                    "link": [
                        {
                            "href": (
                                "https://medlineplus.gov/lab-tests/"
                                "c-reactive-protein-crp-test/?utm_source=mplusconnect"
                            )
                        }
                    ],
                    "summary": {"_value": summary},
                    "author": [{"name": {"_value": "MedlinePlus"}}],
                }
            ]
        }
    }


def record(summary="CRP is a protein."):
    return MedlinePlusRecord(
        lab_test="CRP",
        loinc_code="1988-5",
        title="C-Reactive Protein (CRP) Test",
        source_url=(
            "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/"
        ),
        summary=summary,
        attribution="MedlinePlus",
        language="en",
        raw_payload=payload(summary),
    )


def make_store(tmp_path):
    return SourceSyncStore(db_path=str(tmp_path / "sources.db"))


def test_curated_sync_catalog_is_supported_and_has_unique_loinc_codes():
    assert set(LAB_SOURCE_BY_NAME).issubset(LAB_VALUES)
    assert len(LAB_SOURCE_DEFINITIONS) == 10
    assert len({item.loinc_code for item in LAB_SOURCE_DEFINITIONS}) == 10
    assert all(item.medlineplus_url.startswith("https://medlineplus.gov/") for item in LAB_SOURCE_DEFINITIONS)


def test_loads_expandable_sana_catalog_without_network(tmp_path):
    catalog = tmp_path / "catalog.csv"
    catalog.write_text(
        "lab_test,loinc_code,loinc_name,medlineplus_url\n"
        "Sodyum,2951-2,Sodium [Moles/volume] in Serum or Plasma,\n",
        encoding="utf-8",
    )

    loaded = load_catalog_csv(catalog)

    assert len(loaded) == 1
    assert loaded[0].lab_test == "Sodyum"
    assert loaded[0].loinc_code == "2951-2"
    assert loaded[0].medlineplus_url == ""


def test_loads_official_loinc_csv_and_filters_common_rank(tmp_path):
    catalog = tmp_path / "Loinc.csv"
    catalog.write_text(
        "LOINC_NUM,LONG_COMMON_NAME,STATUS,COMMON_TEST_RANK\n"
        "2951-2,Sodium [Moles/volume] in Serum or Plasma,ACTIVE,12\n"
        "2823-3,Potassium [Moles/volume] in Serum or Plasma,ACTIVE,35\n"
        "9999-9,Inactive example,DEPRECATED,1\n"
        "2222-2,Zero rank example,ACTIVE,0\n"
        "1111-1,Unranked example,ACTIVE,\n",
        encoding="utf-8",
    )

    loaded = load_catalog_csv(catalog, max_common_rank=20)

    assert [item.loinc_code for item in loaded] == ["2951-2"]
    assert loaded[0].common_test_rank == 12


def test_merge_preserves_builtin_definition_for_duplicate_loinc():
    duplicate = type(LAB_SOURCE_BY_NAME["CRP"])(
        "Different name", "1988-5", "Different title"
    )
    merged = merge_catalogs(LAB_SOURCE_DEFINITIONS, [duplicate])
    assert len(merged) == len(LAB_SOURCE_DEFINITIONS)
    assert merged[0] == LAB_SOURCE_BY_NAME["CRP"]


@pytest.mark.parametrize(
    "body",
    [
        "lab_test,loinc_code,loinc_name\nBad,not-loinc,Name\n",
        (
            "lab_test,loinc_code,loinc_name,medlineplus_url\n"
            "Bad,1234-5,Name,https://example.com/test\n"
        ),
    ],
)
def test_catalog_rejects_invalid_code_or_nonofficial_url(tmp_path, body):
    catalog = tmp_path / "bad.csv"
    catalog.write_text(body, encoding="utf-8")
    with pytest.raises(LoincCatalogError):
        load_catalog_csv(catalog)


def test_client_builds_official_loinc_request_and_parses_response():
    calls = []

    def fake_get(url, timeout):
        calls.append((url, timeout))
        return payload("<p>First sentence.</p><p>Second sentence.</p>")

    client = MedlinePlusClient(settings=settings(), get_fn=fake_get)
    result = client.fetch_lab(LAB_SOURCE_BY_NAME["CRP"])

    assert result.lab_test == "CRP"
    assert result.loinc_code == "1988-5"
    assert result.summary == "First sentence. Second sentence."
    assert result.attribution == "MedlinePlus"
    assert result.source_url == (
        "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/"
    )
    assert len(calls) == 1
    url, timeout = calls[0]
    query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    assert query["mainSearchCriteria.v.cs"] == [LOINC_CODE_SYSTEM_OID]
    assert query["mainSearchCriteria.v.c"] == ["1988-5"]
    assert query["knowledgeResponseType"] == ["application/json"]
    assert timeout == 17


def test_client_returns_none_for_no_match():
    client = MedlinePlusClient(
        settings=settings(), get_fn=lambda _url, _timeout: {"feed": {}}
    )
    assert client.fetch_lab(LAB_SOURCE_BY_NAME["CRP"]) is None


@pytest.mark.parametrize(
    "bad_payload",
    [
        {},
        {"feed": {"entry": "invalid"}},
        {"feed": {"entry": [{"title": "Missing fields"}]}},
        {
            "feed": {
                "entry": [
                    {
                        "title": "Bad source",
                        "link": [{"href": "https://example.com/not-official"}],
                        "summary": "Text",
                    }
                ]
            }
        },
    ],
)
def test_client_rejects_malformed_or_nonofficial_records(bad_payload):
    client = MedlinePlusClient(
        settings=settings(), get_fn=lambda _url, _timeout: bad_payload
    )
    with pytest.raises(MedlinePlusResponseError):
        client.fetch_lab(LAB_SOURCE_BY_NAME["CRP"])


def test_http_transport_failure_is_controlled(monkeypatch):
    def fail(*_args, **_kwargs):
        raise urllib.error.URLError("secret technical detail")

    monkeypatch.setattr(mc.urllib.request, "urlopen", fail)
    with pytest.raises(MedlinePlusTransportError) as exc:
        mc._http_get_json("https://connect.medlineplus.gov/service", 10)
    assert "secret technical detail" not in str(exc.value)


def test_new_source_is_staged_as_pending(tmp_path):
    store = make_store(tmp_path)
    outcome = store.upsert_medlineplus(LAB_SOURCE_BY_NAME["CRP"], record())
    saved = store.get("medlineplus:1988-5:en")

    assert outcome == "created"
    assert store.count() == 1
    assert saved.review_status == "pending"
    assert saved.published_at is None
    assert saved.code_system == LOINC_CODE_SYSTEM_OID
    assert saved.source_url.startswith("https://medlineplus.gov/")


def test_unchanged_source_preserves_approval_and_changed_source_resets_it(tmp_path):
    store = make_store(tmp_path)
    definition = LAB_SOURCE_BY_NAME["CRP"]
    store.upsert_medlineplus(definition, record())
    store.approve(definition.source_key, "reviewer@example.test")
    store.mark_published(definition.source_key)

    assert store.upsert_medlineplus(definition, record()) == "unchanged"
    unchanged = store.get(definition.source_key)
    assert unchanged.review_status == "approved"
    assert unchanged.published_at is not None

    assert store.upsert_medlineplus(definition, record("Changed summary.")) == "changed"
    changed = store.get(definition.source_key)
    assert changed.review_status == "pending"
    assert changed.reviewed_by is None
    assert changed.reviewed_at is None
    assert changed.published_at is None


def test_unapproved_source_cannot_be_published(tmp_path):
    store = make_store(tmp_path)
    definition = LAB_SOURCE_BY_NAME["CRP"]
    store.upsert_medlineplus(definition, record())
    with pytest.raises(ValueError, match="onaylanmış"):
        store.mark_published(definition.source_key)


def test_sync_uses_cache_and_never_calls_transport_when_fresh(tmp_path):
    store = make_store(tmp_path)
    definition = LAB_SOURCE_BY_NAME["CRP"]
    store.upsert_medlineplus(definition, record())

    def must_not_call(_url, _timeout):
        pytest.fail("fresh kaynak için transport çağrılmamalı")

    client = MedlinePlusClient(settings=settings(), get_fn=must_not_call)
    result = sync_medlineplus(
        definitions=[definition], client=client, store=store
    )
    assert result.skipped_fresh == 1
    assert result.fetched == 0


def test_force_sync_fetches_and_stages_without_publishing(tmp_path):
    store = make_store(tmp_path)
    client = MedlinePlusClient(settings=settings(), get_fn=lambda _u, _t: payload())
    result = sync_medlineplus(
        definitions=[LAB_SOURCE_BY_NAME["CRP"]],
        client=client,
        store=store,
        force=True,
    )
    assert result.as_dict() == {
        "total": 1,
        "fetched": 1,
        "created": 1,
        "changed": 0,
        "unchanged": 0,
        "skipped_fresh": 0,
        "no_match": 0,
        "duplicate": 0,
        "consolidated": 0,
        "failed": 0,
        "errors": [],
    }
    assert store.get(LAB_SOURCE_BY_NAME["CRP"].source_key).review_status == "pending"


def test_sync_continues_after_controlled_provider_error(tmp_path):
    store = make_store(tmp_path)
    calls = 0

    def mixed_get(_url, _timeout):
        nonlocal calls
        calls += 1
        if calls == 1:
            raise MedlinePlusTransportError("MedlinePlus kaynak servisine ulaşılamadı.")
        return payload()

    client = MedlinePlusClient(settings=settings(), get_fn=mixed_get)
    result = sync_medlineplus(
        definitions=[
            LAB_SOURCE_BY_NAME["CRP"],
            LAB_SOURCE_BY_NAME["Glukoz"],
        ],
        client=client,
        store=store,
        force=True,
    )
    assert result.failed == 1
    assert result.created == 1
    assert result.errors == [
        {
            "lab_test": "CRP",
            "message": "MedlinePlus kaynak servisine ulaşılamadı.",
        }
    ]


def test_bulk_sync_waits_between_remote_calls_without_real_sleep(tmp_path):
    store = make_store(tmp_path)

    def unique_payload(url, _timeout):
        code = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)[
            "mainSearchCriteria.v.c"
        ][0]
        result = payload()
        result["feed"]["entry"][0]["link"][0]["href"] = (
            f"https://medlineplus.gov/lab-tests/test-{code}/"
        )
        return result

    client = MedlinePlusClient(settings=settings(), get_fn=unique_payload)
    sleeps = []

    result = sync_medlineplus(
        definitions=[
            LAB_SOURCE_BY_NAME["CRP"],
            LAB_SOURCE_BY_NAME["Glukoz"],
            LAB_SOURCE_BY_NAME["Ferritin"],
        ],
        client=client,
        store=store,
        force=True,
        request_interval_seconds=0.65,
        sleep_fn=sleeps.append,
    )

    assert result.created == 3
    assert sleeps == [0.65, 0.65]


def test_multiple_loinc_codes_share_one_canonical_source(tmp_path):
    store = make_store(tmp_path)
    client = MedlinePlusClient(settings=settings(), get_fn=lambda _u, _t: payload())

    result = sync_medlineplus(
        definitions=[
            LAB_SOURCE_BY_NAME["CRP"],
            LAB_SOURCE_BY_NAME["Glukoz"],
            LAB_SOURCE_BY_NAME["Ferritin"],
        ],
        client=client,
        store=store,
        force=True,
        sleep_fn=lambda _seconds: None,
    )

    assert result.created == 1
    assert result.duplicate == 2
    assert store.count() == 1
    assert store.mapping_count() == 3

    stats = store.mapping_stats_by_source()
    assert stats[LAB_SOURCE_BY_NAME["CRP"].source_key]["mapping_count"] == 3


def test_duplicate_loinc_mappings_are_cacheable_without_network(tmp_path):
    store = make_store(tmp_path)
    definitions = [
        LAB_SOURCE_BY_NAME["CRP"],
        LAB_SOURCE_BY_NAME["Glukoz"],
        LAB_SOURCE_BY_NAME["Ferritin"],
    ]
    client = MedlinePlusClient(settings=settings(), get_fn=lambda _u, _t: payload())
    sync_medlineplus(
        definitions=definitions, client=client, store=store, force=True
    )

    def must_not_call(_url, _timeout):
        pytest.fail("tekilleştirilmiş LOINC eşlemesi yeniden çağrılmamalı")

    cached_client = MedlinePlusClient(settings=settings(), get_fn=must_not_call)
    result = sync_medlineplus(
        definitions=definitions, client=cached_client, store=store
    )

    assert result.skipped_fresh == 3
    assert result.fetched == 0
