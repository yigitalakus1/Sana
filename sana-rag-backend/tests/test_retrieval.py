from app.services.normalization_service import normalize
from app.services import retrieval_service
from app.services.intent_service import detect_section
from app.core import constants as C
from app.data import seed_documents


def test_resolve_exact_lab_test():
    m = retrieval_service.resolve_lab_test(normalize("CRP nedir"), None)
    assert m.lab_test == "CRP"
    assert m.exact is True


def test_resolve_synonym_lab_test():
    m = retrieval_service.resolve_lab_test(normalize("iltihap değerim yüksek"), None)
    assert m.lab_test == "CRP"
    assert m.synonym is True


def test_resolve_glukoz_from_aclik_sekeri():
    m = retrieval_service.resolve_lab_test(normalize("açlık şekerim yüksek"), None)
    assert m.lab_test == "Glukoz"


def test_resolve_unknown_returns_none():
    m = retrieval_service.resolve_lab_test(normalize("bilinmeyen değerim"), None)
    assert m.lab_test is None


def test_resolve_common_batch_names_and_synonyms():
    cases = [
        ("troponin değerim", "Troponin"),
        ("akyuvar yüksek", "Lökosit"),
        ("üç aylık şeker sonucu", "HbA1c"),
        ("anyon acigi nedir", "Anyon Açığı"),
        ("PT/INR sonucu", "PT INR"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_second_common_batch_names_and_synonyms():
    cases = [
        ("hemogram sonucu", "Tam Kan Sayımı"),
        ("sedim yüksek", "Sedimentasyon"),
        ("proteinüri ne demek", "İdrarda Protein"),
        ("d dimer sonucu", "D-dimer"),
        ("serum amilaz yüksek", "Amilaz"),
        ("gama gt sonucu", "GGT"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_third_common_batch_names_and_synonyms():
    cases = [
        ("25 oh d düşük", "D Vitamini"),
        ("karaciğer paneli sonucu", "Karaciğer Fonksiyon Testleri"),
        ("anti tpo yüksek", "Tiroid Antikorları"),
        ("süt hormonu sonucu", "Prolaktin"),
        ("gaitada gizli kan", "Dışkıda Gizli Kan"),
        ("retikülosit sayımı", "Retikülosit"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_fourth_common_batch_names_and_synonyms():
    cases = [
        ("egfr düşük", "GFR"),
        ("anti ccp pozitif", "CCP Antikoru"),
        ("gaita kalprotektin sonucu", "Dışkıda Kalprotektin"),
        ("açlık insülini yüksek", "İnsülin"),
        ("idrar keton pozitif", "İdrarda Keton"),
        ("metilmalonik asit sonucu", "Metilmalonik Asit"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_fifth_common_batch_names_and_synonyms():
    cases = [
        ("beta hcg sonucu", "Gebelik Testi"),
        ("quantiferon pozitif", "Tüberküloz Taraması"),
        ("antibiyogram sonucu", "Antibiyotik Duyarlılık Testi"),
        ("smear testi", "Pap Smear"),
        ("anti hcv sonucu", "Hepatit Testleri"),
        ("gbs testi pozitif", "Strep B Testi"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_remaining_direct_source_names_and_synonyms():
    cases = [
        ("renin sonucu", "Renin"),
        ("spermiogram sonucu", "Semen Analizi"),
        ("h pylori testi", "Helicobacter pylori Testi"),
        ("t3 testi", "T3 Testleri"),
        ("bos analizi", "Beyin Omurilik Sıvısı Analizi"),
        ("idrar şekeri pozitif", "İdrarda Glukoz"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_resolve_new_lab_names_and_synonyms():
    cases = [
        ("TSH nedir?", "TSH"),
        ("serum kreatinin yüksek", "Kreatinin"),
        ("ALT değerim", "ALT"),
        ("SGOT yüksek", "AST"),
        ("PLT sonucu", "Trombosit"),
    ]
    for question, expected in cases:
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test == expected


def test_short_lab_codes_do_not_match_inside_other_words():
    for question in ("hastalık nedir", "değer referansın altında", "gösterge"):
        match = retrieval_service.resolve_lab_test(normalize(question), None)
        assert match.lab_test is None


def test_retrieve_ranks_high_section_for_high_query():
    norm = normalize("ferritinim yüksek ne anlama gelir")
    section = detect_section(norm)
    assert section == C.SECTION_HIGH
    results = retrieval_service.retrieve(norm, "Ferritin", section)
    assert results
    assert results[0].chunk.section == C.SECTION_HIGH


def test_seed_retrieval_keeps_detected_section_first_for_combined_alt_question():
    norm = normalize(
        "ALT 25 U/L çıktı. Bu tahlilin neyi ölçtüğünü ve sonucun "
        "genel olarak ne anlama gelebileceğini açıkla."
    )

    results = retrieval_service.retrieve(norm, "ALT", C.SECTION_WHAT, top_k=6)

    assert results[0].chunk.section == C.SECTION_WHAT


def test_detect_section_recognizes_when_to_consult_a_doctor():
    section = detect_section(normalize("CRP sonucunda ne zaman doktora danışılmalı?"))

    assert section == C.SECTION_WHEN_DOCTOR


def test_retrieve_only_returns_target_lab():
    norm = normalize("hemoglobin nedir")
    section = detect_section(norm)
    results = retrieval_service.retrieve(norm, "Hemoglobin", section)
    assert all(r.chunk.lab_test == "Hemoglobin" for r in results)


def test_all_chunks_embedding_defaults_none():
    chunks = seed_documents.get_all_chunks()
    assert chunks
    assert all(c.embedding is None for c in chunks)
