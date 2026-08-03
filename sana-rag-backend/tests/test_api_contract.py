"""Public API sözleşmesini OpenAPI üzerinden kilitleyen regresyon testleri."""

from app.main import app

OPENAPI = app.openapi()
SCHEMAS = OPENAPI["components"]["schemas"]

EXPECTED_PATHS = [
    "/health",
    "/explain",
    "/query",
    "/chat",
    "/terms",
    "/terms/{lab_test}",
    "/reports/parse",
]

EXPLAIN_FIELDS = [
    "request_id",
    "response_type",
    "lab_test",
    "matched_term",
    "answer",
    "confidence",
    "confidence_label",
    "result_context",
    "citations",
    "doctor_questions",
    "disclaimer",
    "normalized_query",
    "llm_provider",
    "safety_notes",
    "retrieved_chunks",
]

CHAT_FIELDS = [
    "request_id",
    "response_type",
    "answer",
    "lab_test",
    "matched_term",
    "citations",
    "confidence",
    "confidence_label",
    "disclaimer",
    "safety_notes",
    "retrieved_chunks",
    "llm_provider",
]

PUBLIC_RESPONSE_SCHEMAS = [
    "ExplainResponse",
    "ChatResponse",
    "TermSummary",
    "TermDetail",
    "ReportParseResponse",
    "ParsedLabResult",
    "HealthResponse",
    "Citation",
    "RetrievedChunkMeta",
    "ResultContext",
]


def test_openapi_generates():
    assert OPENAPI.get("openapi")
    assert "paths" in OPENAPI


def test_expected_paths_present():
    for path in EXPECTED_PATHS:
        assert path in OPENAPI["paths"], path


def test_query_is_deprecated():
    assert OPENAPI["paths"]["/query"]["post"].get("deprecated") is True


def test_explain_not_deprecated():
    assert OPENAPI["paths"]["/explain"]["post"].get("deprecated", False) is False


def test_explain_response_schema_fields():
    props = SCHEMAS["ExplainResponse"]["properties"]
    for field in EXPLAIN_FIELDS:
        assert field in props, field


def test_chat_response_schema_fields():
    props = SCHEMAS["ChatResponse"]["properties"]
    for field in CHAT_FIELDS:
        assert field in props, field


def test_no_internal_fields_in_public_response_schemas():
    forbidden = {"chunk_id", "content", "score"}
    for name in PUBLIC_RESPONSE_SCHEMAS:
        schema = SCHEMAS[name]
        props = set(schema.get("properties", {}).keys())
        leaked = props & forbidden
        assert not leaked, (name, leaked)


def test_reports_parse_schema_present():
    assert "/reports/parse" in OPENAPI["paths"]
    post = OPENAPI["paths"]["/reports/parse"]["post"]
    assert "requestBody" in post
    assert "ReportParseRequest" in SCHEMAS
    assert "ReportParseResponse" in SCHEMAS
    assert "ParsedLabResult" in SCHEMAS


def test_reports_parse_pdf_schema_present():
    assert "/reports/parse-pdf" in OPENAPI["paths"]
    post = OPENAPI["paths"]["/reports/parse-pdf"]["post"]
    assert "requestBody" in post
    assert "PdfReportParseRequest" in SCHEMAS
    assert "ReportParseResponse" in SCHEMAS
