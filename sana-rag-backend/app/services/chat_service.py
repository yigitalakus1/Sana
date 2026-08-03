"""Kontrollü RAG + LLM destekli chat orkestrasyonu."""

import uuid
from typing import List, Optional, Tuple

from app.core import constants as C
from app.data.synonyms import LAB_VALUES
from app.models.schemas import ChatMessage, ChatRequest, ChatResponse
from app.services import (
    citation_service,
    confidence_service,
    intent_service,
    result_context_service,
    retrieval_service,
    safety_service,
)
from app.services.llm.prompts import CHAT_SYSTEM_PROMPT, build_chat_prompt
from app.services.llm_provider import get_llm_provider
from app.services.normalization_service import normalize
from app.utils import text_utils

KEYWORD_OVERLAP_MIN = 1
CHAT_BLOCK_INTENTS = {
    C.INTENT_DIAGNOSIS,
    C.INTENT_TREATMENT,
}


def new_request_id() -> str:
    return str(uuid.uuid4())


def _last_user_message(messages: List[ChatMessage]) -> Tuple[Optional[str], int]:
    for idx in range(len(messages) - 1, -1, -1):
        message = messages[idx]
        if message.role == "user" and message.content.strip():
            return message.content.strip(), idx
    return None, -1


def _history(messages: List[ChatMessage], last_user_index: int, limit: int = 6) -> str:
    items = messages[:last_user_index][-limit:]
    lines = []
    for message in items:
        content = " ".join(message.content.split())
        if not content:
            continue
        if len(content) > 300:
            content = content[:297] + "..."
        role = "Kullanıcı" if message.role == "user" else "Asistan"
        lines.append(f"{role}: {content}")
    return "\n".join(lines) if lines else "Yok"


def _format_chunks(retrieved) -> str:
    parts = []
    for rc in retrieved:
        c = rc.chunk
        parts.append(f"[{c.section}] {c.content}\n(Kaynak: {c.source_title})")
    return "\n\n".join(parts)


def _format_result_context(result_context: Optional[dict]) -> str:
    if not result_context:
        return "Belirtilmedi"
    raw = result_context.get("raw_value")
    if raw is None:
        return "Belirtilmedi"
    unit = result_context.get("unit")
    return f"{raw} {unit}".strip() if unit else str(raw)


def _no_results(
    request_id: str,
    provider_name: str,
    lab_test: Optional[str] = None,
    emergency: bool = False,
) -> ChatResponse:
    supported = ", ".join(LAB_VALUES)
    answer = (
        "Bu sohbet yalnız desteklenen tahlil sonuçlarını açıklamak içindir. "
        f"Lütfen bir tahlil adı veya sonucu yazın. Desteklenen tahliller: {supported}."
    )
    if emergency:
        # Acil bağlamda kaynak bulunamasa bile önce acil yönlendirme yapılır (S98).
        answer = C.EMERGENCY_PREFIX + answer
    return ChatResponse(
        request_id=request_id,
        response_type=C.RESPONSE_NO_RESULTS,
        answer=answer,
        lab_test=lab_test,
        matched_term=None,
        citations=[],
        confidence=0.0,
        confidence_label="low",
        disclaimer=C.DISCLAIMER,
        safety_notes=[],
        retrieved_chunks=[],
        llm_provider=provider_name,
    )


def _safety_block(
    request_id: str, intent: str, provider_name: str
) -> ChatResponse:
    if intent == C.INTENT_DIAGNOSIS:
        answer = (
            "Bu sonuç veya belirti üzerinden tanı koyamam. Sonuçlarınızı ve "
            "şikayetlerinizi doktorunuzla birlikte değerlendirmeniz gerekir."
        )
    else:
        answer = safety_service.block_message(intent)
    return ChatResponse(
        request_id=request_id,
        response_type=C.RESPONSE_SAFETY_BLOCK,
        answer=answer,
        lab_test=None,
        matched_term=None,
        citations=[],
        confidence=0.0,
        confidence_label="low",
        disclaimer=C.DISCLAIMER,
        safety_notes=[C.SAFETY_BLOCK_NOTE],
        retrieved_chunks=[],
        llm_provider=provider_name,
    )


def should_block_chat_before_retrieval(intent: str) -> bool:
    return safety_service.should_block_before_retrieval(intent) or intent in CHAT_BLOCK_INTENTS


def process(request: ChatRequest, request_id: Optional[str] = None) -> ChatResponse:
    request_id = request_id or new_request_id()
    provider = get_llm_provider()
    provider_name = provider.name

    question, last_user_index = _last_user_message(request.messages)
    if question is None:
        return ChatResponse(
            request_id=request_id,
            response_type=C.RESPONSE_ERROR,
            answer="Son kullanıcı mesajı bulunamadı.",
            lab_test=None,
            matched_term=None,
            citations=[],
            confidence=0.0,
            confidence_label="low",
            disclaimer=C.DISCLAIMER,
            safety_notes=[],
            retrieved_chunks=[],
            llm_provider=provider_name,
        )

    normalized = normalize(question)
    intent = intent_service.detect_intent(normalized)
    ctx = intent_service.detect_safety_context(normalized)

    if safety_service.is_prompt_injection(normalized):
        return _safety_block(request_id, C.INTENT_PROMPT_INJECTION, provider_name)
    if should_block_chat_before_retrieval(intent):
        return _safety_block(request_id, intent, provider_name)

    match = retrieval_service.resolve_lab_test(normalized, request.lab_test)
    if match.lab_test is None:
        return _no_results(request_id, provider_name, emergency=ctx.is_emergency)

    section = intent_service.detect_section(normalized)
    # Küçük local modellerde ilgisiz bölümlerin cevaba karışmasını önlemek için
    # prompt ve public metadata yalnızca en alakalı section chunk'ını kullanır.
    retrieved = retrieval_service.retrieve_for_query(
        normalized, match.lab_test, section, top_k=1
    )
    if not retrieved:
        return _no_results(
            request_id, provider_name, lab_test=match.lab_test, emergency=ctx.is_emergency
        )

    top = retrieved[0]
    source_exists = bool(top.chunk.source_url)
    section_match = top.chunk.section == section
    q_tokens = text_utils.tokenize(normalized)
    chunk_tokens = text_utils.tokenize(
        normalize(top.chunk.section + " " + top.chunk.content)
    )
    keyword_ok = text_utils.overlap_count(q_tokens, chunk_tokens) >= KEYWORD_OVERLAP_MIN

    confidence, label = confidence_service.compute(
        exact_match=match.exact,
        synonym_match=match.synonym,
        keyword_overlap_ok=keyword_ok,
        source_exists=source_exists,
        section_match=section_match,
    )

    result_context = result_context_service.extract_result_context(question)
    chat_prompt = build_chat_prompt(
        question=question,
        history=_history(request.messages, last_user_index),
        lab_test=match.lab_test,
        result_context=_format_result_context(result_context),
        chunks=_format_chunks(retrieved),
    )

    raw_answer = provider.generate(
        question=question,
        lab_test=match.lab_test,
        intent=intent,
        retrieved=retrieved,
        result_context=result_context,
        system_prompt=CHAT_SYSTEM_PROMPT,
        user_prompt=chat_prompt,
    )
    # Referans aralığı/yorum yokken sayısal değer sınıflandırmasını engelle.
    raw_answer = safety_service.strip_value_classification(
        raw_answer, match.lab_test, result_context
    )
    raw_answer = safety_service.add_missing_reference_range_note(
        raw_answer, result_context
    )
    answer = safety_service.apply_answer_filters(raw_answer, intent, ctx)
    citations = citation_service.build(retrieved) if request.include_sources else []
    retrieved_chunks = [
        {
            "lab_test": rc.chunk.lab_test,
            "section": rc.chunk.section,
            "source_title": rc.chunk.source_title,
        }
        for rc in retrieved
    ]

    return ChatResponse(
        request_id=request_id,
        response_type=C.RESPONSE_ANSWER,
        answer=answer,
        lab_test=match.lab_test,
        matched_term=match.matched_term,
        citations=citations,
        confidence=confidence,
        confidence_label=label,
        disclaimer=C.DISCLAIMER,
        safety_notes=[],
        retrieved_chunks=retrieved_chunks,
        llm_provider=provider_name,
    )
