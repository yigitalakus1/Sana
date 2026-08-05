"""API request/response şemaları (Pydantic)."""

from typing import List, Literal, Optional
from pydantic import BaseModel, Field


# --- Request ---
class Profile(BaseModel):
    age: Optional[int] = None
    sex: Optional[str] = None
    conditions: Optional[List[str]] = Field(default_factory=list)


class QueryOptions(BaseModel):
    language: str = "tr"
    include_sources: bool = True
    include_doctor_questions: bool = True
    # Cevabı yerel modelle yeniden ifade etmeden, onaylı kaynak metninden
    # doğrudan üretir. Sözlükteki bölüm açıklamaları gibi zaten hazır ve
    # hekim onaylı içeriklerde beklemeyi ortadan kaldırır. Güvenlik ve
    # no-results dalları değişmez. Varsayılan kapalı (geriye uyumlu).
    use_source_text: bool = False


class QueryRequest(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "question": "CRP 13.5 çıktı",
                    "lab_test": "CRP",
                    "options": {
                        "language": "tr",
                        "include_sources": True,
                        "include_doctor_questions": True,
                    },
                }
            ]
        }
    }

    question: str = ""
    lab_test: Optional[str] = None
    profile: Optional[Profile] = None
    options: Optional[QueryOptions] = None


class ReportParseRequest(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {"text": "CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nB12 350 pg/mL"}
            ]
        }
    }

    text: str = ""


class PdfReportParseRequest(BaseModel):
    file_name: str = "report.pdf"
    content_base64: str = ""


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "messages": [
                        {
                            "role": "user",
                            "content": "CRP 13.5 çıktı ne anlama gelir?",
                        }
                    ],
                    "lab_test": "CRP",
                    "include_sources": True,
                }
            ]
        }
    }

    messages: List[ChatMessage]
    lab_test: Optional[str] = None
    include_sources: bool = True


# --- Response parçaları ---
class Citation(BaseModel):
    source_title: str
    source_url: Optional[str] = None
    section: Optional[str] = None


class RetrievedChunkMeta(BaseModel):
    """Kullanılan bilgi parçalarının hafif metadata temsili.

    DECISIONS §6/§10/§11 gereği `chunk_id` ve içerik (`content`) public yanıta
    konmaz; burada yalnız kaynak/section düzeyi metadata tutulur.
    """

    lab_test: str
    section: Optional[str] = None
    source_title: Optional[str] = None


class ResultContext(BaseModel):
    """Kullanıcı sorusundan çıkarılan sayısal değer bağlamı.

    Yalnız veri taşır; medikal yorum ÜRETMEZ. Rapor kartından gelen açık
    referans aralığı varsa parser bunu ve deterministik durumunu taşıyabilir.
    """

    raw_value: Optional[str] = None
    value: Optional[float] = None
    unit: Optional[str] = None
    reference_range: Optional[str] = None
    interpretation: Optional[str] = None


class ExplainResponse(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "request_id": "9669c8b6-4ee8-4999-9862-a4b34b6b03be",
                    "response_type": "answer",
                    "lab_test": "CRP",
                    "matched_term": "crp",
                    "answer": "CRP, vücutta iltihaplanma olduğunda yükselebilen bir proteindir. Tek başına tanı koydurmaz.",
                    "confidence": 0.8,
                    "confidence_label": "high",
                    "result_context": {
                        "raw_value": "13.5",
                        "value": 13.5,
                        "unit": None,
                        "reference_range": None,
                        "interpretation": None,
                    },
                    "citations": [
                        {
                            "source_title": "MedlinePlus",
                            "source_url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/",
                            "section": "Nedir?",
                        }
                    ],
                    "doctor_questions": ["CRP yüksekliğim hangi durumlarla ilişkili olabilir?"],
                    "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; tanı, tedavi veya tıbbi karar önerisi değildir. Sonuçlarınızı doktorunuzla birlikte değerlendiriniz.",
                    "normalized_query": "crp 13 5 çıktı",
                    "llm_provider": "dummy",
                    "safety_notes": [],
                    "retrieved_chunks": [
                        {"lab_test": "CRP", "section": "Nedir?", "source_title": "MedlinePlus"}
                    ],
                }
            ]
        }
    }

    request_id: str
    response_type: str
    lab_test: Optional[str] = None
    matched_term: Optional[str] = None
    answer: str
    confidence: float
    confidence_label: str
    result_context: Optional[ResultContext] = None
    citations: List[Citation] = Field(default_factory=list)
    doctor_questions: List[str] = Field(default_factory=list)
    disclaimer: str
    # --- S13 additive metadata (DECISIONS §6) ---
    normalized_query: Optional[str] = None
    llm_provider: Optional[str] = None
    safety_notes: List[str] = Field(default_factory=list)
    retrieved_chunks: List[RetrievedChunkMeta] = Field(default_factory=list)


class ChatResponse(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "request_id": "9669c8b6-4ee8-4999-9862-a4b34b6b03be",
                    "response_type": "answer",
                    "answer": "CRP, vücutta iltihaplanma olduğunda yükselebilen bir proteindir. Tek başına tanı koydurmaz.",
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
                    "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; tanı, tedavi veya tıbbi karar önerisi değildir. Sonuçlarınızı doktorunuzla birlikte değerlendiriniz.",
                    "safety_notes": [],
                    "retrieved_chunks": [
                        {"lab_test": "CRP", "section": "Nedir?", "source_title": "MedlinePlus"}
                    ],
                    "llm_provider": "dummy",
                }
            ]
        }
    }

    request_id: str
    response_type: Literal["answer", "safety_block", "no_results", "error"]
    answer: str
    lab_test: Optional[str] = None
    matched_term: Optional[str] = None
    citations: List[Citation] = Field(default_factory=list)
    confidence: float
    confidence_label: str
    disclaimer: str
    safety_notes: List[str] = Field(default_factory=list)
    retrieved_chunks: List[RetrievedChunkMeta] = Field(default_factory=list)
    llm_provider: str


class TermSummary(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "lab_test": "CRP",
                    "title": "C-Reaktif Protein (CRP)",
                    "sections": ["Nedir?", "Neden ölçülür?"],
                }
            ]
        }
    }

    lab_test: str
    title: Optional[str] = None
    sections: List[str] = Field(default_factory=list)


class TermDetail(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "lab_test": "CRP",
                    "title": "C-Reaktif Protein (CRP)",
                    "sections": ["Nedir?", "Neden ölçülür?"],
                    "sources": [
                        {
                            "source_title": "MedlinePlus",
                            "source_url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/",
                            "section": None,
                        }
                    ],
                }
            ]
        }
    }

    lab_test: str
    title: Optional[str] = None
    sections: List[str] = Field(default_factory=list)
    sources: List[Citation] = Field(default_factory=list)


class ParsedLabResult(BaseModel):
    # Alan adları ExplainResponse.ResultContext ile uyumlu (S18).
    lab_test: str
    matched_term: Optional[str] = None
    raw_value: Optional[str] = None
    value: Optional[float] = None
    unit: Optional[str] = None
    reference_range: Optional[str] = None
    interpretation: Optional[str] = None


class ReportParseResponse(BaseModel):
    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "parser_status": "parsed",
                    "results": [
                        {
                            "lab_test": "CRP",
                            "matched_term": "crp",
                            "raw_value": "13.5",
                            "value": 13.5,
                            "unit": "mg/L",
                            "reference_range": None,
                            "interpretation": None,
                        },
                        {
                            "lab_test": "Glukoz",
                            "matched_term": "glukoz",
                            "raw_value": "92",
                            "value": 92.0,
                            "unit": "mg/dL",
                            "reference_range": None,
                            "interpretation": None,
                        },
                    ],
                    "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; tanı, tedavi veya tıbbi karar önerisi değildir. Sonuçlarınızı doktorunuzla birlikte değerlendiriniz.",
                }
            ]
        }
    }

    parser_status: str  # "parsed" | "no_results"
    results: List[ParsedLabResult] = Field(default_factory=list)
    disclaimer: str
    # Rapor metnindeki ETİKETLİ tarih (ISO YYYY-MM-DD). Emin olunamayan her
    # durumda None döner; istemci dosya adı / kayıt zamanı yedeğine düşer.
    report_date: Optional[str] = None


class HealthResponse(BaseModel):
    status: str
    version: str
