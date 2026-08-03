"""POST /chat — kontrollü RAG + LLM destekli Sana Asistan endpoint'i."""

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.core import constants as C
from app.models.schemas import ChatRequest, ChatResponse
from app.services import chat_service
from app.services.llm_provider import get_llm_provider

router = APIRouter()


def _error(request_id: str, message: str, status_code: int = 400) -> JSONResponse:
    body = {
        "request_id": request_id,
        "response_type": C.RESPONSE_ERROR,
        "answer": message,
        "lab_test": None,
        "matched_term": None,
        "citations": [],
        "confidence": 0.0,
        "confidence_label": "low",
        "disclaimer": C.DISCLAIMER,
        "safety_notes": [],
        "retrieved_chunks": [],
        "llm_provider": get_llm_provider().name,
    }
    return JSONResponse(status_code=status_code, content=body)


@router.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    request_id = chat_service.new_request_id()

    if not request.messages:
        return _error(request_id, "Mesaj listesi boş olamaz.")

    if not any(m.role == "user" and m.content.strip() for m in request.messages):
        return _error(request_id, "Son kullanıcı mesajı bulunamadı.")

    try:
        return chat_service.process(request, request_id)
    except Exception:  # pragma: no cover - güvenli son durak
        return _error(
            request_id,
            "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.",
            status_code=500,
        )
