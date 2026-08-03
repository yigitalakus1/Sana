"""Retrieved kaynak parçalarından güvenli ve açıklayıcı fallback metni üretir."""

import re


def combine_source_content(retrieved, max_sentences: int = 4) -> str:
    """İlk kaynak parçalarını tekrar etmeden, tam cümlelerle birleştirir.

    Yeni tıbbi bilgi üretmez; yalnız backend'de onaylı içerikleri kullanır.
    """
    sentences: list[str] = []
    seen: set[str] = set()
    for item in retrieved:
        content = item.chunk.content.strip()
        if not content:
            continue
        for sentence in re.split(r"(?<=[.!?])\s+", content):
            value = sentence.strip()
            key = value.casefold()
            if not value or key in seen:
                continue
            seen.add(key)
            sentences.append(value)
            if len(sentences) >= max_sentences:
                return " ".join(sentences)
    return " ".join(sentences)
