from app.core import constants as C
from app.services.llm.source_content import combine_source_content
from app.services.normalization_service import normalize
from app.services.retrieval_service import retrieve


def test_combined_source_content_is_grounded_complete_and_limited():
    retrieved = retrieve(normalize("ALT nedir?"), "ALT", C.SECTION_WHAT, top_k=6)

    answer = combine_source_content(retrieved)

    assert "karaciğer" in answer.casefold()
    assert answer.endswith((".", "!", "?"))
    assert len([part for part in answer.split(".") if part.strip()]) <= 4
