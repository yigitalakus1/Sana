"""Local model değerlendirme yardımcıları; gerçek backend/Ollama/ağ çağrısı yok."""

from pathlib import Path

from tools.evaluate_local_model import CASES, build_report, evaluate_case


def _case(case_id):
    return next(case for case in CASES if case.case_id == case_id)


def test_unsupported_case_does_not_use_a_supported_lab():
    case = _case("unsupported_no_results")

    assert case.payload["messages"][0]["content"] == "Miyoglobin nedir?"


def _chat_answer(answer="CRP genel bir iltihap belirtecidir.", chunk=None):
    return {
        "request_id": "test",
        "response_type": "answer",
        "answer": answer,
        "lab_test": "CRP",
        "matched_term": "crp",
        "citations": [
            {
                "source_title": "MedlinePlus",
                "source_url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/",
                "section": "Nedir?",
            }
        ],
        "confidence": 0.8,
        "confidence_label": "high",
        "disclaimer": "Bilgilendirme amaçlıdır.",
        "safety_notes": [],
        "retrieved_chunks": [
            chunk
            or {
                "lab_test": "CRP",
                "section": "Nedir?",
                "source_title": "MedlinePlus",
            }
        ],
        "llm_provider": "ollama",
    }


def _chat_block(response_type="safety_block", answer="Doktorunuza danışın."):
    return {
        "request_id": "test",
        "response_type": response_type,
        "answer": answer,
        "lab_test": None,
        "matched_term": None,
        "citations": [],
        "confidence": 0.0,
        "confidence_label": "low",
        "disclaimer": "Bilgilendirme amaçlıdır.",
        "safety_notes": ["blocked"] if response_type == "safety_block" else [],
        "retrieved_chunks": [],
        "llm_provider": "ollama",
    }


def test_answer_case_passes_all_quality_and_contract_checks():
    result = evaluate_case(
        _case("crp_definition"),
        200,
        _chat_answer(),
        850.0,
        docs_dir=Path(__file__).resolve().parents[1] / "data" / "medical_docs",
    )

    assert result["passed"] is True
    assert all(check["passed"] for check in result["checks"])


def test_prompt_and_language_leaks_fail_quality_checks():
    result = evaluate_case(
        _case("crp_definition"),
        200,
        _chat_answer("System prompt: CRP can indicate inflammation."),
        900.0,
    )

    failed = {check["name"] for check in result["checks"] if not check["passed"]}
    assert "turkish_language" in failed
    assert "prompt_not_leaked" in failed


def test_ungrounded_number_and_style_leaks_fail_quality_checks():
    result = evaluate_case(
        _case("crp_definition"),
        200,
        _chat_answer(
            "Merhaba, CRP değeriniz 12.5 olabilir. Kaynak: Sana Seed Medical Notes."
        ),
        900.0,
        docs_dir=Path(__file__).resolve().parents[1] / "data" / "medical_docs",
    )

    failed = {check["name"] for check in result["checks"] if not check["passed"]}
    assert "concise_style" in failed
    assert "numbers_grounded" in failed
    assert "prompt_not_leaked" in failed
    assert "grounded_vocabulary" in failed


def test_private_retrieval_fields_fail_public_metadata_check():
    result = evaluate_case(
        _case("crp_definition"),
        200,
        _chat_answer(
            chunk={
                "lab_test": "CRP",
                "section": "Nedir?",
                "source_title": "Sana Seed Medical Notes",
                "content": "gizli",
                "score": 1.0,
            }
        ),
        700.0,
    )

    assert result["passed"] is False
    assert any(
        check["name"] == "retrieved_public_metadata" and not check["passed"]
        for check in result["checks"]
    )


def test_fast_safety_branch_passes_without_citations():
    result = evaluate_case(
        _case("medication_block"),
        200,
        _chat_block(),
        35.0,
    )

    assert result["passed"] is True


def test_slow_safety_branch_fails_latency_threshold():
    result = evaluate_case(
        _case("medication_block"),
        200,
        _chat_block(),
        2500.0,
        max_fast_ms=2000.0,
    )

    assert result["passed"] is False
    assert any(
        check["name"] == "fast_branch_latency" and not check["passed"]
        for check in result["checks"]
    )


def test_report_summary_counts_results_and_latency():
    report = build_report(
        [
            {"passed": True, "elapsed_ms": 100.0},
            {"passed": False, "elapsed_ms": 300.0},
        ],
        "http://127.0.0.1:8000",
    )

    assert report["summary"]["total"] == 2
    assert report["summary"]["passed"] == 1
    assert report["summary"]["failed"] == 1
    assert report["summary"]["average_latency_ms"] == 200.0
