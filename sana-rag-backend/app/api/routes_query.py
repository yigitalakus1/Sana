"""Açıklama endpoint'leri: doğrulama + RAG servisine yönlendirme.

İki route aynı akışı paylaşır:
- POST /query   (mevcut, korunuyor)
- POST /explain (DECISIONS §6 ile hizalı yeni ad)
İkisi de aynı QueryRequest gövdesini alır ve aynı ExplainResponse'u döndürür.
"""

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.core import constants as C
from app.models.schemas import ExplainResponse, QueryRequest
from app.services import rag_service

router = APIRouter()


def _error(request_id: str, code: str, message: str, status_code: int = 400) -> JSONResponse:
    body = {
        "request_id": request_id,
        "response_type": C.RESPONSE_ERROR,
        "error": {"code": code, "message": message, "details": {}},
        "disclaimer": C.DISCLAIMER,
    }
    return JSONResponse(status_code=status_code, content=body)


def _handle(request: QueryRequest):
    """Doğrulama + RAG akışı. /query ve /explain bunu paylaşır."""
    request_id = rag_service.new_request_id()

    # Dil kontrolü (MVP'de yalnız 'tr')
    language = request.options.language if request.options else "tr"
    if language not in C.SUPPORTED_LANGUAGES:
        return _error(
            request_id,
            C.ERR_UNSUPPORTED_LANGUAGE,
            "Şu an yalnızca Türkçe (tr) desteklenmektedir.",
        )

    # Boş soru kontrolü
    if not request.question or not request.question.strip():
        return _error(request_id, C.ERR_VALIDATION, "Soru alanı boş olamaz.")

    try:
        return rag_service.process(request, request_id)
    except Exception:  # pragma: no cover - güvenli son durak
        return _error(
            request_id,
            C.ERR_INTERNAL,
            "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.",
            status_code=500,
        )


@router.post("/query", response_model=ExplainResponse, deprecated=True)
def query(request: QueryRequest):
    return _handle(request)


@router.post("/explain", response_model=ExplainResponse)
def explain(request: QueryRequest):
    return _handle(request)
