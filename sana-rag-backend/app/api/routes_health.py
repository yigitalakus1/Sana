"""GET /health endpoint'i."""

from fastapi import APIRouter

from app.core import constants as C
from app.models.schemas import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", version=C.APP_VERSION)
