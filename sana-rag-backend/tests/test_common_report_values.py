from app.data import seed_documents
from app.data.synonyms import SYNONYM_MAP
from app.services.report_parse_service import parse_report


def test_common_cbc_codes_are_parsed_as_individual_values():
    text = (
        "RBC 4.8 10^6/uL\n"
        "MCH 29 pg\n"
        "MCHC 34 g/dL\n"
        "RDW-CV 13.2 %\n"
        "NEU% 55 %\n"
        "LYM# 2.1 10^3/uL\n"
        "MONO 7 %\n"
        "EOS 2 %\n"
        "BASO 1 %\n"
        "PDW 12 fL"
    )

    results = parse_report(text)["results"]
    assert {item["lab_test"] for item in results} == {
        "Eritrosit Sayımı",
        "MCH",
        "MCHC",
        "RDW",
        "Nötrofil",
        "Lenfosit",
        "Monosit",
        "Eozinofil",
        "Bazofil",
        "PDW",
    }
    assert next(item for item in results if item["lab_test"] == "MCH")["unit"] == "pg"
    assert next(item for item in results if item["lab_test"] == "Lenfosit")["unit"] == "10^3/uL"


def test_pct_is_plateletcrit_with_percent_and_procalcitonin_with_mass_unit():
    plateletcrit = parse_report("PCT 0.24 %")["results"][0]
    procalcitonin = parse_report("PCT 0.12 ng/mL")["results"][0]

    assert plateletcrit["lab_test"] == "Plateletkrit"
    assert procalcitonin["lab_test"] == "Prokalsitonin"


def test_common_chemistry_codes_are_parsed():
    text = (
        "TIBC 320 ug/dL\n"
        "UIBC 210 ug/dL\n"
        "Transferrin saturation 28 %\n"
        "Direct bilirubin 0.2 mg/dL\n"
        "Indirect bilirubin 0.5 mg/dL\n"
        "FT3 3.1 pg/mL\n"
        "UREA 28 mg/dL"
    )

    results = parse_report(text)["results"]
    assert {item["lab_test"] for item in results} == {
        "Total Demir Bağlama Kapasitesi",
        "Doymamış Demir Bağlama Kapasitesi",
        "Transferrin Saturasyonu",
        "Direkt Bilirubin",
        "İndirekt Bilirubin",
        "Serbest T3",
        "Üre",
    }
    assert all(item["interpretation"] is None for item in results)


def test_each_new_report_value_has_seed_content_and_aliases():
    expected = {
        "MCH",
        "MCHC",
        "RDW",
        "Nötrofil",
        "Lenfosit",
        "Monosit",
        "Eozinofil",
        "Bazofil",
        "PDW",
        "Plateletkrit",
        "Total Demir Bağlama Kapasitesi",
        "Doymamış Demir Bağlama Kapasitesi",
        "Transferrin",
        "Transferrin Saturasyonu",
        "Direkt Bilirubin",
        "İndirekt Bilirubin",
        "Serbest T3",
        "Üre",
    }
    labs_with_chunks = {chunk.lab_test for chunk in seed_documents.get_all_chunks()}

    assert expected <= labs_with_chunks
    assert expected <= set(SYNONYM_MAP)
    for lab_test in expected:
        assert SYNONYM_MAP[lab_test]
