"""Markdown -> Chunk dönüşümü (S94 ingestion).

Format: dosya başında `---` ile ayrılmış front matter (key: value satırları),
ardından her `## Başlık` bir section/chunk. Parse deterministiktir; aynı dosya
her zaman aynı chunk id'lerini üretir.

Zorunlu front matter alanları: lab_test, source_title, source_url, safety_level.
Boş section içeriği ve yinelenen section başlığı HATA sayılır (fail-fast:
tıbbi içerik pipeline'ında sessiz atlama yerine yazarlık hatası erken görülür).
"""

import re
from pathlib import Path
from typing import Dict, List, Tuple

from app.data.seed_documents import Chunk
from app.services.normalization_service import turkish_lower

REQUIRED_METADATA = ("lab_test", "source_title", "source_url", "safety_level")

# Türkçe karakterlerin ASCII slug karşılıkları (chunk id'leri için)
_TR_ASCII = str.maketrans("çğıöşü", "cgiosu")


def slugify(text: str) -> str:
    """Deterministik ASCII slug: 'Neden ölçülür?' -> 'neden-olculur'."""
    text = turkish_lower(text).translate(_TR_ASCII)
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def parse_front_matter(text: str, source_name: str) -> Tuple[Dict[str, str], str]:
    """`---` bloklu front matter'ı ayrıştırır; (metadata, gövde) döndürür."""
    lines = text.splitlines()
    idx = 0
    while idx < len(lines) and not lines[idx].strip():
        idx += 1
    if idx >= len(lines) or lines[idx].strip() != "---":
        raise ValueError(f"{source_name}: front matter bulunamadı (dosya '---' ile başlamalı)")

    meta: Dict[str, str] = {}
    for j in range(idx + 1, len(lines)):
        stripped = lines[j].strip()
        if stripped == "---":
            body = "\n".join(lines[j + 1:])
            return meta, body
        if not stripped:
            continue
        key, sep, value = stripped.partition(":")
        if not sep or not key.strip():
            raise ValueError(f"{source_name}: geçersiz front matter satırı: {stripped!r}")
        meta[key.strip()] = value.strip()

    raise ValueError(f"{source_name}: front matter kapatılmamış ('---' eksik)")


def _split_sections(body: str) -> List[Tuple[str, str]]:
    """Gövdeyi '## ' başlıklarına göre (başlık, içerik) çiftlerine ayırır.

    İlk başlıktan önceki metin (varsa) yok sayılır.
    """
    sections: List[Tuple[str, str]] = []
    heading = None
    buf: List[str] = []
    for line in body.splitlines():
        if line.startswith("## "):
            if heading is not None:
                sections.append((heading, "\n".join(buf).strip()))
            heading = line[3:].strip()
            buf = []
        elif heading is not None:
            buf.append(line)
    if heading is not None:
        sections.append((heading, "\n".join(buf).strip()))
    return sections


def chunk_markdown(text: str, source_name: str = "<metin>") -> List[Chunk]:
    """Markdown metnini LocalRagStore şemasına uyumlu Chunk listesine çevirir."""
    meta, body = parse_front_matter(text, source_name)

    missing = [k for k in REQUIRED_METADATA if not meta.get(k)]
    if missing:
        raise ValueError(
            f"{source_name}: zorunlu front matter alanları eksik: {', '.join(missing)}"
        )

    sections = _split_sections(body)
    if not sections:
        raise ValueError(f"{source_name}: hiç section bulunamadı ('## Başlık' bekleniyor)")

    lab_test = meta["lab_test"]
    lab_slug = slugify(lab_test)
    chunks: List[Chunk] = []
    seen_ids = set()

    for section, content in sections:
        if not section:
            raise ValueError(f"{source_name}: boş section başlığı")
        if not content:
            raise ValueError(f"{source_name}: {section!r} section içeriği boş")
        chunk_id = f"{lab_slug}-{slugify(section)}"
        if chunk_id in seen_ids:
            raise ValueError(f"{source_name}: yinelenen section (id çakışması): {chunk_id}")
        seen_ids.add(chunk_id)
        chunks.append(
            Chunk(
                chunk_id=chunk_id,
                lab_test=lab_test,
                title=f"{lab_test} - {section}",
                section=section,
                content=content,
                source_title=meta["source_title"],
                source_url=meta["source_url"],
                safety_level=meta["safety_level"],
            )
        )
    return chunks


def chunk_file(path: Path) -> List[Chunk]:
    text = Path(path).read_text(encoding="utf-8")
    return chunk_markdown(text, source_name=Path(path).name)
