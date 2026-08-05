"""Testler arasında paylaşılan durum sıfırlanır.

`rag_service` üretilen cevapları süreç içi bir önbellekte tutar. Testler sahte
sağlayıcılarla aynı soruyu farklı cevaplarla kurguladığı için önbellek testler
arasında sızarsa yanlış sonuç verir; her testten önce boşaltılır.
"""

import pytest

from app.services import rag_service


@pytest.fixture(autouse=True)
def _clear_answer_cache():
    rag_service.clear_answer_cache()
    yield
    rag_service.clear_answer_cache()
