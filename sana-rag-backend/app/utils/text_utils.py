"""Metin yardımcıları: tokenizasyon ve kelime örtüşmesi."""

from typing import List, Set

# Anahtar kelime örtüşmesini bozan yaygın Türkçe soru/dolgu kelimeleri
STOPWORDS: Set[str] = {
    "ne", "mi", "mı", "mu", "mü", "için", "icin", "bir", "ve", "bu", "şu", "su",
    "da", "de", "ki", "ile", "gibi", "çok", "cok", "daha", "en", "ya", "yani",
    "ama", "veya", "olan", "olarak", "göre", "gore", "kadar", "sonra", "önce",
    "var", "yok", "nasıl", "nasil", "neden", "nedir", "anlama", "gelir",
    "gelebilir", "demek", "çıktı", "cikti", "çıkmış", "cikmis", "biraz",
    "benim", "bana", "beni", "mıyım", "miyim", "muyum", "müyüm",
}


def tokenize(normalized_text: str) -> List[str]:
    """Normalize edilmiş metni içerik kelimelerine ayırır (stopword'ler hariç)."""
    return [
        tok
        for tok in normalized_text.split()
        if len(tok) > 1 and tok not in STOPWORDS
    ]


def overlap_count(query_tokens: List[str], chunk_tokens: List[str]) -> int:
    return len(set(query_tokens) & set(chunk_tokens))


def overlap_ratio(query_tokens: List[str], chunk_tokens: List[str]) -> float:
    if not query_tokens:
        return 0.0
    return overlap_count(query_tokens, chunk_tokens) / len(set(query_tokens))
