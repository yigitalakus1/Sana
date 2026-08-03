"""PDF bytes -> plain text extraction for the deterministic report parser."""

import base64
import binascii
from io import BytesIO
from pathlib import Path
import shutil
import subprocess
import tempfile

MAX_PDF_BYTES = 10 * 1024 * 1024
MAX_PDF_PAGES = 100
MAX_OCR_IMAGES = 30
OCR_TIMEOUT_SECONDS = 60


class PdfReportError(ValueError):
    def __init__(self, message: str, *, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def _run_tesseract(image_path: Path, executable: str) -> str:
    for language in ("tur+eng", "eng"):
        try:
            result = subprocess.run(
                [executable, str(image_path), "stdout", "-l", language, "--psm", "6"],
                capture_output=True,
                check=False,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=OCR_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.TimeoutExpired):
            return ""
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    return ""


def _extract_ocr_text(reader) -> str:
    """Tesseract kuruluysa taranmış PDF sayfa görsellerini yerel olarak okur."""
    executable = shutil.which("tesseract")
    if not executable:
        return ""

    extracted = []
    image_count = 0
    with tempfile.TemporaryDirectory(prefix="sana-ocr-") as temp_dir:
        for page_index, page in enumerate(reader.pages):
            for image_index, image in enumerate(page.images):
                if image_count >= MAX_OCR_IMAGES:
                    return "\n".join(extracted)
                suffix = Path(image.name or "").suffix.lower()
                if suffix not in {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"}:
                    suffix = ".png"
                image_path = Path(temp_dir) / f"page-{page_index}-{image_index}{suffix}"
                try:
                    image_path.write_bytes(image.data)
                except OSError:
                    continue
                image_count += 1
                text = _run_tesseract(image_path, executable)
                if text:
                    extracted.append(text)
    return "\n".join(extracted)


def extract_pdf_text(*, file_name: str, content_base64: str) -> str:
    if not file_name.lower().endswith(".pdf"):
        raise PdfReportError("Yalnızca PDF dosyaları yüklenebilir.")
    if not content_base64:
        raise PdfReportError("PDF dosyası boş olamaz.")

    try:
        pdf_bytes = base64.b64decode(content_base64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise PdfReportError("PDF dosyası okunamadı.") from exc

    if len(pdf_bytes) > MAX_PDF_BYTES:
        raise PdfReportError("PDF dosyası en fazla 10 MB olabilir.", status_code=413)
    if not pdf_bytes.startswith(b"%PDF-"):
        raise PdfReportError("Seçilen dosya geçerli bir PDF değil.")

    try:
        from pypdf import PdfReader

        reader = PdfReader(BytesIO(pdf_bytes), strict=False)
        if reader.is_encrypted and not reader.decrypt(""):
            raise PdfReportError("Şifreli PDF dosyaları okunamaz.")
        if len(reader.pages) > MAX_PDF_PAGES:
            raise PdfReportError("PDF en fazla 100 sayfa olabilir.", status_code=413)
        text = "\n".join(page.extract_text() or "" for page in reader.pages)
        if not text.strip():
            text = _extract_ocr_text(reader)
    except PdfReportError:
        raise
    except ImportError as exc:
        raise PdfReportError("PDF okuma servisi kullanılamıyor.", status_code=503) from exc
    except Exception as exc:
        raise PdfReportError("PDF dosyası açılamadı veya bozuk.") from exc

    text = text.replace("\x00", "").strip()
    if not text:
        raise PdfReportError(
            "PDF içinde okunabilir metin bulunamadı. Taranmış belgeler için OCR gerekir.",
            status_code=422,
        )
    return text
