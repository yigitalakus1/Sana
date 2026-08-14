from tools.export_flutter_terms import EXPECTED_TERM_COUNT, build_catalog


def test_flutter_catalog_exports_every_reviewed_term_with_content():
    catalog = build_catalog()

    assert catalog["schema_version"] == 1
    assert catalog["term_count"] == EXPECTED_TERM_COUNT == 240
    assert len(catalog["terms"]) == 240

    crp = next(term for term in catalog["terms"] if term["lab_test"] == "CRP")
    assert len(crp["sections"]) == 6
    assert "iltihap" in crp["section_contents"]["Nedir?"]
    assert crp["sources"]

    for term in catalog["terms"]:
        assert term["lab_test"]
        assert term["aliases"]
        assert term["sources"]
        assert all(term["section_contents"][section] for section in term["sections"])
