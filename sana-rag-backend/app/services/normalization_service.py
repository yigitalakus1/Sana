"""Sorgu normalizasyonu (Türkçe karakter duyarlı)."""

import re


def turkish_lower(text: str) -> str:
    """Türkçe duyarlı küçük harf: I -> ı, İ -> i.

    Standart str.lower() Türkçede yanlış sonuç verir ('I' -> 'i'),
    bu yüzden dönüşümü lower()'dan önce elle yapıyoruz.
    """
    text = text.replace("I", "ı").replace("İ", "i")
    return text.lower()


def normalize(text: str) -> str:
    """Küçük harfe çevirir, noktalamayı temizler, fazla boşlukları sadeleştirir.

    Türkçe harfler (çğıöşü) ve rakamlar korunur.
    """
    text = turkish_lower(text)
    text = re.sub(r"[^\w\s]", " ", text, flags=re.UNICODE)
    text = re.sub(r"\s+", " ", text).strip()
    return text
