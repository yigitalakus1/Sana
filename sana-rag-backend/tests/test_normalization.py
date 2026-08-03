from app.services.normalization_service import turkish_lower, normalize


def test_turkish_lower_dotted_i():
    assert turkish_lower("İLTİHAP") == "iltihap"


def test_turkish_lower_dotless_i():
    assert turkish_lower("ISI") == "ısı"


def test_turkish_lower_mixed():
    assert turkish_lower("Iğdır İstanbul") == "ığdır istanbul"


def test_normalize_strips_punctuation_and_spaces():
    assert normalize("CRP,   yüksek!!!") == "crp yüksek"


def test_normalize_preserves_turkish_letters():
    assert normalize("Şeker Değeri") == "şeker değeri"
