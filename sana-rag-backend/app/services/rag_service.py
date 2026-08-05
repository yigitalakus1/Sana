"""RAG orkestrasyonu: tüm katmanları birleştirip ExplainResponse üretir."""

import uuid
from collections import OrderedDict
from typing import Optional

from app.core import constants as C
from app.data import seed_documents
from app.models.schemas import ExplainResponse, QueryRequest
from app.services import (
    citation_service,
    confidence_service,
    intent_service,
    result_context_service,
    retrieval_service,
    safety_service,
)
from app.services.llm.source_content import combine_source_content
from app.services.llm_provider import get_llm_provider
from app.services.normalization_service import normalize
from app.utils import text_utils

KEYWORD_OVERLAP_MIN = 1  # en az 1 içerik kelimesi örtüşmesi


def new_request_id() -> str:
    return str(uuid.uuid4())



# Üretilen cevaplar için küçük, süreç içi önbellek.
#
# Aynı soru + aynı kaynak bağlamı her zaman aynı cevabı üretmelidir; kullanıcı
# bir terime ikinci kez baktığında yerel modeli tekrar çalıştırmak yalnızca
# bekletir. Yalnız bellekte tutulur, diske yazılmaz ve süreç kapanınca silinir.
_ANSWER_CACHE_LIMIT = 256
_answer_cache: "OrderedDict[tuple, str]" = OrderedDict()


def clear_answer_cache() -> None:
    """Testler ve içerik güncellemeleri için önbelleği boşaltır."""
    _answer_cache.clear()


def _generate_cached(provider, *, question, lab_test, intent, retrieved, result_context):
    key = (
        provider.name,
        normalize(question),
        lab_test,
        intent,
        tuple(item.chunk.chunk_id for item in retrieved),
        repr(result_context),
    )
    cached = _answer_cache.get(key)
    if cached is not None:
        _answer_cache.move_to_end(key)
        return cached

    answer = provider.generate(
        question=question,
        lab_test=lab_test,
        intent=intent,
        retrieved=retrieved,
        result_context=result_context,
    )
    _answer_cache[key] = answer
    if len(_answer_cache) > _ANSWER_CACHE_LIMIT:
        _answer_cache.popitem(last=False)
    return answer


def _with_definition(normalized: str, lab_test: str, primary):
    """Birincil bölümün ardına "Nedir?" parçasını ekler (varsa).

    Tanım her zaman ikinci sırada kalır; citation tekilleştirmesinde birincil
    bölümün seçilmesini korumak için skoru birincilin altında tutulur.
    """
    definition = retrieval_service.retrieve_for_query(
        normalized, lab_test, C.SECTION_WHAT, top_k=1
    )
    if not definition or definition[0].chunk.chunk_id == primary[0].chunk.chunk_id:
        return primary
    return primary + [
        retrieval_service.RetrievedChunk(
            chunk=definition[0].chunk,
            score=min(definition[0].score, primary[0].score - 0.01),
        )
    ]


def _retrieve_explanation_context(normalized: str, lab_test: str, section: str):
    """Genel açıklamayı kaynakta tutarak biraz daha kapsamlı hale getirir.

    Hedef bölüm her zaman ilk parçadır. Genel/definition sorularında testin ne
    olduğu kadar neden ölçüldüğü de yararlı olduğundan ikinci parça eklenir.
    Yüksek, düşük ve doktora danışma soruları tek özel bölümde kalır.
    """
    asks_definition = any(
        pattern in normalized for pattern in C.DEFINITION_PATTERNS
    )
    asks_what_and_why = section == C.SECTION_WHY and asks_definition
    primary_section = C.SECTION_WHAT if asks_what_and_why else section
    primary = retrieval_service.retrieve_for_query(
        normalized, lab_test, primary_section, top_k=1
    )
    if not primary:
        return primary

    if primary_section != C.SECTION_WHAT:
        # Rapor metninden gelen "yüksek/düşük" kelimeleri section tespitini
        # kaydırabilir (ör. referans sütunu "Düşük <132, Yüksek >173" veya
        # testin kendi adında "Düşük Yoğunluklu Lipoprotein" geçmesi). Kullanıcı
        # açıkça "nedir" diye sorduysa tanım her zaman eklenir; aksi halde cevap
        # terimi hiç açıklamadan yalnız yüksek/düşük yorumu döner.
        if asks_definition:
            return _with_definition(normalized, lab_test, primary)
        return primary

    secondary = retrieval_service.retrieve_for_query(
        normalized, lab_test, C.SECTION_WHY, top_k=1
    )
    if not secondary or secondary[0].chunk.chunk_id == primary[0].chunk.chunk_id:
        return primary

    # Citation tekilleştirmesinde birincil bölümün seçilmesini koru.
    secondary_score = min(secondary[0].score, primary[0].score - 0.01)
    return primary + [
        retrieval_service.RetrievedChunk(
            chunk=secondary[0].chunk,
            score=secondary_score,
        )
    ]


def _no_results(
    request_id: str, normalized_query: str, provider_name: str, emergency: bool = False
) -> ExplainResponse:
    # Acil bağlamda kaynak bulunamasa bile önce acil yönlendirme yapılır (S98).
    answer = (C.EMERGENCY_PREFIX + C.NO_RESULTS_MESSAGE) if emergency else C.NO_RESULTS_MESSAGE
    return ExplainResponse(
        request_id=request_id,
        response_type=C.RESPONSE_NO_RESULTS,
        lab_test=None,
        matched_term=None,
        answer=answer,
        confidence=0.0,
        confidence_label="low",
        result_context=None,
        citations=[],
        doctor_questions=list(C.NO_RESULTS_DOCTOR_QUESTIONS),
        disclaimer=C.DISCLAIMER,
        normalized_query=normalized_query,
        llm_provider=provider_name,
        safety_notes=[],
        retrieved_chunks=[],
    )


def _safety_block(
    request_id: str, intent: str, normalized_query: str, provider_name: str
) -> ExplainResponse:
    return ExplainResponse(
        request_id=request_id,
        response_type=C.RESPONSE_SAFETY_BLOCK,
        lab_test=None,
        matched_term=None,
        answer=safety_service.block_message(intent),
        confidence=0.0,
        confidence_label="low",
        result_context=None,
        citations=[],
        doctor_questions=[],
        disclaimer=C.DISCLAIMER,
        normalized_query=normalized_query,
        llm_provider=provider_name,
        safety_notes=[C.SAFETY_BLOCK_NOTE],
        retrieved_chunks=[],
    )


def process(request: QueryRequest, request_id: Optional[str] = None) -> ExplainResponse:
    request_id = request_id or new_request_id()

    # Provider istek başına çözülür (env değişimi anında yansır). Örnekleme ağ
    # yapmaz; gerçek çağrı yalnız answer branch'inde generate() ile olur.
    provider = get_llm_provider()
    provider_name = provider.name

    age = request.profile.age if request.profile else None
    normalized = normalize(request.question)
    intent = intent_service.detect_intent(normalized, age)
    ctx = intent_service.detect_safety_context(normalized, age)

    # 1) Retrieval öncesi safety bloğu (provider ÇAĞRILMAZ)
    if safety_service.is_prompt_injection(normalized):
        return _safety_block(
            request_id, C.INTENT_PROMPT_INJECTION, normalized, provider_name
        )
    if safety_service.should_block_before_retrieval(intent):
        return _safety_block(request_id, intent, normalized, provider_name)

    # 2) Lab değeri çözümleme
    match = retrieval_service.resolve_lab_test(normalized, request.lab_test)
    if match.lab_test is None:
        return _no_results(request_id, normalized, provider_name, emergency=ctx.is_emergency)

    # 3) Section + retrieval (SANA_RAG_MODE'a göre seed veya local store)
    section = intent_service.detect_section(normalized)
    # Tek section bağlamı küçük local modelin kaynak dışına taşmasını azaltır.
    retrieved = _retrieve_explanation_context(normalized, match.lab_test, section)
    if not retrieved:
        return _no_results(request_id, normalized, provider_name, emergency=ctx.is_emergency)

    top = retrieved[0]
    source_exists = bool(top.chunk.source_url)
    section_match = top.chunk.section == section

    # keyword örtüşmesi
    q_tokens = text_utils.tokenize(normalized)
    chunk_tokens = text_utils.tokenize(
        normalize(top.chunk.section + " " + top.chunk.content)
    )
    keyword_ok = text_utils.overlap_count(q_tokens, chunk_tokens) >= KEYWORD_OVERLAP_MIN

    # 4) Confidence
    confidence, label = confidence_service.compute(
        exact_match=match.exact,
        synonym_match=match.synonym,
        keyword_overlap_ok=keyword_ok,
        source_exists=source_exists,
        section_match=section_match,
    )

    # 5) Değer bağlamı (generate'e verilir; yorum ÜRETİLMEZ)
    result_context = result_context_service.extract_result_context(request.question)

    # 6) Cevap üretimi (provider) + safety filtre
    #    Provider hatası (config/ağ) buradan yükselir; route güvenli generic
    #    error döndürür (secret/teknik detay sızmaz).
    #    Aynı soru + aynı bağlam için üretim tekrarlanmaz (bkz. _answer_cache).
    if request.options is not None and request.options.use_source_text:
        # Onaylı kaynak metni doğrudan sunulur: model çağrılmaz, bekleme olmaz
        # ve içerik kaynaktan sapamaz. Güvenlik filtreleri yine uygulanır.
        provider_name = C.PROVIDER_SOURCE
        raw_answer = combine_source_content(retrieved)
    else:
        raw_answer = _generate_cached(
            provider,
            question=request.question,
            lab_test=match.lab_test,
            intent=intent,
            retrieved=retrieved,
            result_context=result_context,
        )
    # Referans aralığı/yorum yokken sayısal değer sınıflandırmasını engelle.
    raw_answer = safety_service.strip_value_classification(
        raw_answer, match.lab_test, result_context
    )
    raw_answer = safety_service.add_missing_reference_range_note(
        raw_answer, result_context
    )
    answer = safety_service.apply_answer_filters(raw_answer, intent, ctx)

    # 7) Citation + doktor soruları (backend'den; LLM uydurmaz)
    citations = (
        citation_service.build(retrieved)
        if (request.options is None or request.options.include_sources)
        else []
    )
    if request.options is None or request.options.include_doctor_questions:
        doctor_questions = seed_documents.get_doctor_questions(match.lab_test)
    else:
        doctor_questions = []

    # 8) Hafif retrieved metadata (content/skor/chunk_id YOK — DECISIONS §6/§10/§11)
    retrieved_chunks = [
        {
            "lab_test": rc.chunk.lab_test,
            "section": rc.chunk.section,
            "source_title": rc.chunk.source_title,
        }
        for rc in retrieved
    ]

    return ExplainResponse(
        request_id=request_id,
        response_type=C.RESPONSE_ANSWER,
        lab_test=match.lab_test,
        matched_term=match.matched_term,
        answer=answer,
        confidence=confidence,
        confidence_label=label,
        result_context=result_context,
        citations=citations,
        doctor_questions=doctor_questions,
        disclaimer=C.DISCLAIMER,
        normalized_query=normalized,
        llm_provider=provider_name,
        safety_notes=[],
        retrieved_chunks=retrieved_chunks,
    )
