# Sana — RAG Backend Architecture v1

**Status:** Locked & implemented (Week 2 MVP built and tested) · **Scope:** 4-week MVP (summer school + portfolio) · **Guiding principle:** Health literacy, not diagnosis. Safety and citations come before features.

This document describes the backend that powers Sana's medical-term explanations. It produces Turkish, source-cited, confidence-scored, non-diagnostic explanations of lab values. It is intentionally small: the goal is a *working, trustworthy* demo in four weeks, not a complete medical AI system.

> **Implementation note:** The Week 2 MVP described here is implemented in `sana-rag-backend/` and passes its test suite. Sections marked *v1* are deferred to Week 3.

## 1. Project Vision

Sana is a Flutter health-literacy app that explains lab reports in plain Turkish. This backend replaces the app's mock dictionary service with a real explanation engine. Given a lab value or medical term, it retrieves information from trusted sources, explains it in plain Turkish without diagnosing, shows its sources, reports a confidence score, and refers the user to a doctor when appropriate. It is explicitly **not** a diagnostic system; its purpose is to help users ask their doctors better-informed questions.

## 2. MVP Scope

The current implementation covers ten lab values — **CRP, Glukoz, Ferritin, B12, Hemoglobin, TSH, Kreatinin, ALT, AST, Trombosit** — with Turkish seed content and a local SQLite RAG store. It includes query normalization, a synonym map, lexical retrieval, dummy/Ollama/OpenAI-compatible/Foundry Local providers, confidence scoring, citation building, and the safety layer. The public surface includes `/health`, `/explain`, backward-compatible `/query`, `/chat`, `/terms`, and `/reports/parse`.

## 3. Non-goals (explicitly out of scope)

OCR, PDF parsing, user accounts, Azure AI Search, full production monitoring, web scrapers, and any real diagnostic capability are out. Streaming responses and multilingual embedding are deferred to v1 (not in the first working demo). The `DummyLLMProvider` means no real LLM is required for the MVP to function.

## 4. System Architecture

```
┌─────────────────────────────────────────────┐
│   Sana Flutter App  →  MlDictionaryService   │
└───────────────────────┬─────────────────────┘
                        │  HTTPS · POST /query
                        ▼
┌─────────────────────────────────────────────┐
│               FastAPI Backend                │
│  API Layer        (validation, request_id)   │
│  Service Layer    (orchestration)            │
│  ── Retrieval ──┬── Confidence ──┬── Safety ──│
│  LLM Layer        (Dummy → Foundry Local)    │
│  Citation Builder                            │
│  Data Layer       (seed; SQLite-ready)       │
└───────────────────────┬─────────────────────┘
                        ▼
   JSON: answer · confidence · sources ·
         doctor_questions · disclaimer
```

The backend is a single FastAPI service over an in-code seed store (structured to move to SQLite later). Logical modules — API, Service, Retrieval, LLM, Safety, Confidence, Citation, Data, Evaluation — are separated in code for clarity and testability, but they all run in one process. No microservices, no orchestration layer.

## 5. RAG Pipeline

A request flows through these stages, in order:

1. **Validate** the request, attach a `request_id`.
2. **Normalize** the query (see §8).
3. **Detect intent** (definition / high_result / low_result / normal_range / doctor_questions / general / plus risky intents).
4. **Safety pre-check** — if the query matches a block-intent (medication/dosage, supplement, doctor-avoidance), short-circuit to a safe `safety_block` before retrieval.
5. **Retrieve** — exact `lab_value` match + keyword search over Turkish seed chunks (v0); hybrid retrieval in v1.
6. **No-results branch** — if zero chunks, return `no_results` with `confidence = 0.0` (never fabricate).
7. **Score confidence** from retrieval signals (§10).
8. **Generate answer** via the active LLM provider, grounded only on retrieved chunks.
9. **Safety post-filter** — frame/soften the generated answer for risky contexts (diagnosis, treatment, pediatric, emergency).
10. **Build citations** from retrieved sources only, deduplicated.
11. **Return JSON** with the disclaimer always attached.

The branches that must never be skipped are the *no-results* branch (step 6) and the *safety pre-check / post-filter* (steps 4 and 9).

## 6. API Contract

**`GET /health`** → `{ "status": "ok", "version": "v1" }`

**`POST /query`** — request:
```json
{
  "question": "CRP yüksekliği ne anlama gelir?",
  "lab_value": "CRP",
  "profile": { "age": 25, "sex": "male", "conditions": [] },
  "options": { "language": "tr", "include_sources": true, "include_doctor_questions": true }
}
```

Every response carries `request_id` and `response_type` ∈ { `answer`, `no_results`, `safety_block`, `error` }.
`no_results` and `safety_block` return **HTTP 200** (they are not errors); only validation/language errors return HTTP 400.

Success (`answer`):
```json
{
  "request_id": "uuid",
  "response_type": "answer",
  "answer": "...",
  "confidence": 0.84,
  "confidence_label": "high",
  "sources": [
    { "title": "C-Reaktif Protein (CRP)", "url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/", "source": "MedlinePlus", "score": 0.91 }
  ],
  "doctor_questions": ["..."],
  "disclaimer": "Bu cevap teşhis amacı taşımaz. Sonuçlarınızı doktorunuzla değerlendirin."
}
```

No-results:
```json
{
  "request_id": "uuid",
  "response_type": "no_results",
  "answer": "Bu konuda yeterince güvenilir kaynak eşleşmesi bulunamadı. Sonucunuzu doktorunuzla değerlendirmeniz önerilir.",
  "confidence": 0.0,
  "confidence_label": "low",
  "sources": [],
  "doctor_questions": ["..."],
  "disclaimer": "..."
}
```

Safety-block:
```json
{
  "request_id": "uuid",
  "response_type": "safety_block",
  "answer": "İlaç veya doz değişikliği konusunda yönlendirme yapamam. Bu konuda doktorunuz veya eczacınızla görüşmeniz gerekir.",
  "confidence": 0.0,
  "confidence_label": "low",
  "sources": [],
  "doctor_questions": [],
  "disclaimer": "..."
}
```

Error (HTTP 400):
```json
{ "request_id": "uuid", "response_type": "error", "error": { "code": "VALIDATION_ERROR", "message": "Soru alanı boş olamaz.", "details": {} }, "disclaimer": "..." }
```

Error codes: `VALIDATION_ERROR`, `UNSUPPORTED_LANGUAGE`, `INTERNAL_ERROR`, `TIMEOUT`, `SAFETY_BLOCKED`.

## 7. Data Model

**MedicalDocument:** `id`, `lab_value`, `title`, `content`, `source_name`, `source_url`, `language`, `tags`, `last_updated`. Translation-ready fields are present from day one even though v0 is Turkish-only: `content_original`, `content_tr`, `language_original`, `translation_provider`, `translation_reviewed`.

**Chunk:** `chunk_id`, `document_id`, `lab_value`, `section_title`, `chunk_text`, `source_name`, `source_url`, `embedding` (nullable in v0), `metadata`. The `embedding` field exists from the start so v1 can add vectors without a schema migration.

## 8. Query Normalization & Synonym Strategy

Normalization runs before every retrieval: lowercase, strip punctuation, collapse extra whitespace, **preserve Turkish characters**, then apply the synonym map. One Turkish-specific pitfall handled explicitly: a naïve `.lower()` maps `I → i`, which is wrong in Turkish (`I → ı`, `İ → i`). A Turkish-aware fold is used so `"İLTİHAP"` normalizes to `"iltihap"`; otherwise synonym matching silently fails. A second pitfall: consonant softening in Turkish inflection (e.g. "antibiyotik" → "antibiyotiği", k→ğ) — patterns use stems ("antibiyot") rather than full words.

Synonym map (MVP):
- **CRP:** crp, c-reaktif protein, c reaktif protein, c reaktif, creaktif protein, c-reactive protein, c reactive protein, crp değeri, iltihap değeri, hs-crp, hs crp
- **Glukoz:** glukoz, glikoz, glucose, kan şekeri, kan sekeri, açlık şekeri, aclik sekeri, açlık kan şekeri, açlık glukoz, kan glukozu, şeker
- **Ferritin:** ferritin, ferritin değeri, serum ferritin, demir deposu, demir deposu değeri, depo demir, demir depo proteini
- **B12:** b12, b 12, b-12, vitamin b12, vit b12, b12 vitamini, b12 değeri, kobalamin, cobalamin
- **Hemoglobin:** hemoglobin, hgb, hb, hgb değeri, hb değeri, hemoglobin değeri, hemoglobin düzeyi

## 9. Retrieval Strategy

**v0 (MVP):** `lab_value` exact match + keyword search over the Turkish seed corpus. Simple and reliable for short technical queries like "CRP nedir?".

**v1:** add BM25 or TF-IDF, a multilingual embedding model, and hybrid retrieval combined via Reciprocal Rank Fusion or a weighted score. Rationale: keyword search wins on short technical queries, semantic search wins on natural-language ones like "iltihap değerim yüksek çıktı." Keeping the data Turkish-first in the MVP sidesteps the Turkish-query / English-chunk mismatch entirely; multilingual embedding only becomes relevant once non-Turkish sources are added.

## 10. Confidence Scoring

Confidence is a separate module. MVP score components:

| Signal | Weight |
|---|---|
| lab_value exact match | +0.35 |
| synonym match | +0.20 |
| keyword overlap | +0.20 |
| source exists | +0.15 |
| intent–section match | +0.10 |

Labels: **0.71–1.00 high · 0.41–0.70 medium · 0.00–0.40 low.**

Hard rules (override the formula): if retrieval returns zero chunks, `confidence = 0.0`; if there is no source, the answer can never be labelled `high`; a `safety_block` is always `0.0` / `low`. Source-freshness scoring is deferred to v1.

## 11. Citation Policy

Only sources that actually came from retrieval may appear in the response — the model can never invent a citation. Sources are deduplicated by URL so multiple chunks from one page show as a single source. `chunk_id` is never exposed in the public response but is kept in backend logs for debugging. Source URLs should be sanity-checked periodically so the app never surfaces a dead link.

## 12. Safety & Medical Guardrails

This is the most critical layer and runs in **two stages**: a safe block decision before generation, and a filter applied to the generated answer afterward.

Prohibited outputs: making a diagnosis; recommending treatment, medication, or dosage; advising to start/stop/increase/decrease a drug or supplement; implying a doctor visit is unnecessary; asserting certainty; or showing a source when none exists.

Risky intents the system catches: `diagnosis_request`, `treatment_request`, `medication_or_dosage_advice`, `medication_or_supplement_advice`, `emergency_or_panic_value`, `pediatric_context`, `doctor_avoidance`, `no_retrieval_results`. Concretely: medication/dosage, supplement, and doctor-avoidance questions get a `safety_block` **without retrieval**; panic/emergency signals (per-lab critical thresholds and symptom cues) prepend an urgent referral; diagnosis/treatment answers are reframed with non-diagnostic notes; if pediatric context (age < 14 or "çocuk/bebek") attach a pediatric caution and give no age-specific ranges; and every answer carries the disclaimer.

## 13. LLM Provider Strategy

An `LLMProvider` abstraction sits behind the service layer. The MVP ships `DummyLLMProvider`, which composes a controlled Turkish answer from the retrieved chunks (deterministic, testable, no model needed). `FoundryLocalProvider` is added in Week 3; if Foundry Local fails to run on the demo machine (RAM/GPU limits), the system falls back to `DummyLLMProvider` so the demo never breaks. Because Foundry Local exposes an OpenAI-compatible API, swapping in Azure OpenAI later is a config change, not a rewrite.

## 14. Chunking Strategy

Primary strategy is **section-based** chunking, one chunk per section: *Nedir? · Neden ölçülür? · Yüksek ne anlama gelebilir? · Düşük ne anlama gelebilir? · Ne zaman doktora danışılmalı? · Doktora sorulabilecek sorular.* These natural boundaries double as clean retrieval units and map directly onto the intent types. Fallbacks: split any section longer than ~300–400 words; keep overlap at 0–20 words (boundaries are already semantic); merge any section under ~50 words into the next.

## 15. Data Source Strategy

**Phase 1 (MVP):** hand-written Turkish seed content for the 5 values, each carrying its MedlinePlus source link. **Phase 2:** a MedlinePlus pipeline (preserve source URL, clean text, translate as needed). **Phase 3:** NHS UK and other vetted sources, added only after checking licence terms (NHS content is Open Government Licence v3.0 — usable with attribution). **LabTestsOnline / Testing.com are excluded** — their terms disallow scraping, so they carry legal risk and stay out. Sources are limited to official/clinical bodies; no forums or user-generated content.

## 16. Flutter Integration Strategy

`MlDictionaryService` calls `POST /query` and maps the response directly to the existing result UI. Because the app already abstracts the dictionary service, switching from `StaticDictionaryService` to `MlDictionaryService` changes one wiring point and nothing else. The client must: branch on `response_type` first, then trust `confidence_label` (it does not compute thresholds itself); send and log `request_id`; tolerate a 3–8s first response from Foundry Local with a clear loading state; and map error codes to friendly Turkish messages. Streaming (SSE) is a v1 enhancement that will most improve perceived latency via a "typing" effect.

## 17. Evaluation Plan

A 20-question evaluation set (a mix of definition, high/low-result, natural-language, safety, pediatric, and no-results phrasings across the 5 values, each annotated with `expected_lab_value`, `expected_intent`, and `expected_section`) drives a reported **precision@3** and retrieval hit-rate. A separate set of safety test cases exercises every risky intent to confirm the guardrails fire. Both results go in the README — the precision number is a concrete metric to bring into a technical interview.

## 18. 4-Week Roadmap

**Week 1 — design freeze.** Architecture v1, API contract, safety rules, confidence rules, seed-data schema, synonym map, content outline for the 5 values, draft of the 20-question eval set. *(Done.)*

**Week 2 — working backend.** FastAPI MVP: `GET /health`, `POST /query`, manual seed data, query normalization, synonym map, keyword retrieval, `DummyLLMProvider`, confidence, citation, safety, and pytest coverage. *(Done — 25 tests passing.)*

**Week 3 — retrieval + integration.** BM25/TF-IDF (optional multilingual embedding), `MlDictionaryService` connection, AI-backed explanations live in the Flutter app, `FoundryLocalProvider` trial with Dummy fallback.

**Week 4 — package & present.** README, architecture diagram, demo video, 5-minute presentation, Responsible AI document, the 20-question test result, and a clean GitHub repo.

## 19. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Architecture-astronaut: design eats the timeline | Strict roadmap; no scope creep |
| Turkish query / English chunk mismatch | Turkish-first seed data in MVP; multilingual embedding deferred to v1 |
| Foundry Local won't run on demo machine | `DummyLLMProvider` fallback; demo never depends on the model |
| Turkish lowercase (`I/İ`) and inflection (k→ğ) break matching | Turkish-aware normalization + stem patterns (§8) |
| Hallucinated or dead sources | Citations only from retrieval; periodic URL checks |
| Legal/scraping exposure | Manual seed + MedlinePlus/NHS only; LabTestsOnline excluded |
| Perceived latency on first answer | Clear loading state now; SSE streaming in v1 |
| Unsafe medical output | Two-stage safety layer, panic-value referral, always-on disclaimer |

## 20. Decisions Locked Before Coding

The ten supported values and Turkish-first seed data are fixed for the current demo. The API response schema — including the `response_type` envelope, error shape, and error codes — remains frozen. Section-based chunking is the chunking method. Confidence components, thresholds, and hard rules are set. Citations come only from retrieval. `DummyLLMProvider` remains the default, with local Ollama and Foundry paths plus an optional OpenAI-compatible provider. The safety layer is mandatory. LabTestsOnline is out. Streaming and multilingual embedding remain deferred.
