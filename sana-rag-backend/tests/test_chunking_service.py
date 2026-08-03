"""S94 — chunking_service testleri."""

import pytest

from app.services import chunking_service
from app.data.synonyms import LAB_VALUES

VALID_DOC = """---
lab_test: CRP
source_title: Sana Seed Medical Notes
source_url: local://sana/medical_docs/crp
safety_level: general
---

## Nedir?
CRP bir iltihap belirtecidir.

## Neden ölçülür?
Enfeksiyon veya iltihap şüphesinde istenir.
"""


def test_parse_metadata_from_single_doc():
    chunks = chunking_service.chunk_markdown(VALID_DOC, "crp.md")
    assert len(chunks) == 2
    c = chunks[0]
    assert c.lab_test == "CRP"
    assert c.source_title == "Sana Seed Medical Notes"
    assert c.source_url == "local://sana/medical_docs/crp"
    assert c.safety_level == "general"


def test_headings_become_sections():
    chunks = chunking_service.chunk_markdown(VALID_DOC, "crp.md")
    sections = [c.section for c in chunks]
    assert sections == ["Nedir?", "Neden ölçülür?"]
    assert chunks[0].content == "CRP bir iltihap belirtecidir."
    assert chunks[0].title == "CRP - Nedir?"


def test_chunk_id_is_deterministic_and_slugified():
    chunks = chunking_service.chunk_markdown(VALID_DOC, "crp.md")
    ids = [c.chunk_id for c in chunks]
    assert ids == ["crp-nedir", "crp-neden-olculur"]
    # Aynı girdi -> aynı id'ler
    again = [c.chunk_id for c in chunking_service.chunk_markdown(VALID_DOC, "crp.md")]
    assert again == ids


def test_slugify_handles_turkish_chars():
    assert chunking_service.slugify("Neden ölçülür?") == "neden-olculur"
    assert chunking_service.slugify("Yüksek ne anlama gelebilir?") == "yuksek-ne-anlama-gelebilir"


def test_missing_front_matter_raises():
    with pytest.raises(ValueError, match="front matter"):
        chunking_service.chunk_markdown("## Nedir?\nİçerik.", "bad.md")


def test_missing_required_metadata_raises():
    doc = """---
lab_test: CRP
source_title: Sana Seed Medical Notes
---

## Nedir?
İçerik var.
"""
    with pytest.raises(ValueError, match="source_url"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_empty_section_content_raises():
    doc = """---
lab_test: CRP
source_title: T
source_url: local://x
safety_level: general
---

## Nedir?

## Neden ölçülür?
Dolu içerik.
"""
    with pytest.raises(ValueError, match="içeriği boş"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_no_sections_raises():
    doc = """---
lab_test: CRP
source_title: T
source_url: local://x
safety_level: general
---

Sadece düz metin, başlık yok.
"""
    with pytest.raises(ValueError, match="section bulunamadı"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_duplicate_section_raises():
    doc = """---
lab_test: CRP
source_title: T
source_url: local://x
safety_level: general
---

## Nedir?
Birinci.

## Nedir?
İkinci.
"""
    with pytest.raises(ValueError, match="yinelenen"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_unclosed_front_matter_raises():
    # Kapanış '---' yok; kalan tüm satırlar geçerli key: value formatında.
    doc = """---
lab_test: CRP
source_title: T
source_url: local://x
safety_level: general
"""
    with pytest.raises(ValueError, match="kapatılmamış"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_invalid_front_matter_line_raises():
    doc = """---
lab_test: CRP
bu satırın iki noktası yok
---

## Nedir?
İçerik.
"""
    with pytest.raises(ValueError, match="geçersiz front matter"):
        chunking_service.chunk_markdown(doc, "bad.md")


def test_seed_docs_parse_and_align_with_store_schema():
    """Gerçek medical_docs dosyaları parse edilir ve şema alanlarını doldurur."""
    from pathlib import Path

    docs_dir = Path(__file__).resolve().parents[1] / "data" / "medical_docs"
    md_files = sorted(docs_dir.glob("*.md"))
    assert len(md_files) == len(LAB_VALUES)
    total = 0
    for md in md_files:
        chunks = chunking_service.chunk_file(md)
        assert chunks, f"{md.name} boş"
        for c in chunks:
            assert c.chunk_id and c.lab_test and c.section and c.content
            assert c.source_title and c.source_url and c.safety_level
        total += len(chunks)
    assert total == len(LAB_VALUES) * 6
