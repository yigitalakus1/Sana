"""Read-only terim endpoint'leri: GET /terms, GET /terms/{lab_test}."""

from typing import List

from fastapi import APIRouter, HTTPException

from app.models.schemas import TermDetail, TermSummary
from app.services import terms_service

router = APIRouter()


@router.get("/terms", response_model=List[TermSummary])
def terms():
    return terms_service.list_terms()


@router.get("/terms/{lab_test}", response_model=TermDetail)
def term_detail(lab_test: str):
    detail = terms_service.get_term(lab_test)
    if detail is None:
        raise HTTPException(
            status_code=404,
            detail="Desteklenen bir laboratuvar testi bulunamadı.",
        )
    return detail
