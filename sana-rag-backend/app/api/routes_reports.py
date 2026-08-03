"""Düz metin ve PDF laboratuvar raporu ayrıştırma endpoint'leri."""

from fastapi import APIRouter, HTTPException

from app.models.schemas import (
    PdfReportParseRequest,
    ReportParseRequest,
    ReportParseResponse,
)
from app.services import pdf_report_service, report_parse_service

router = APIRouter()


@router.post("/reports/parse", response_model=ReportParseResponse)
def parse(request: ReportParseRequest):
    if not request.text or not request.text.strip():
        raise HTTPException(status_code=400, detail="text alanı boş olamaz.")
    return report_parse_service.parse_report(request.text)


@router.post("/reports/parse-pdf", response_model=ReportParseResponse)
def parse_pdf(request: PdfReportParseRequest):
    try:
        text = pdf_report_service.extract_pdf_text(
            file_name=request.file_name,
            content_base64=request.content_base64,
        )
    except pdf_report_service.PdfReportError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    return report_parse_service.parse_report(text)
