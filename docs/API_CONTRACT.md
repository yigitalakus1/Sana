# Sana RAG Backend — API Sözleşmesi (API_CONTRACT)

Bu belge `sana-rag-backend` servisinin public HTTP sözleşmesini özetler. Kaynak doğruluk
belgesi `DECISIONS.md`'dir; çelişki olursa DECISIONS.md geçerlidir.

## 1. Proje amacı
Sana, laboratuvar tahlil değerlerini **sade Türkçeyle**, **kaynak göstererek** ve
**güven skoruyla** açıklayan bir sağlık okuryazarlığı uygulamasıdır. Bu backend, açıklama
motorunu (RAG-lite) ve metin tabanlı rapor parser'ını sağlar.

## 2. Non-diagnostic ilke (pazarlık yok)
- **Tanı koymaz, tedavi/ilaç/doz önermez, doktor yerine geçmez.**
- "Yüksek / düşük / normal" gibi medikal yorum **üretilmez**; referans aralığına göre
  değerlendirme **yapılmaz**.
- Her yanıtta `disclaimer` döner. Kaynak yoksa kaynak uydurulmaz.
- Güvenlik ve kaynak gösterimi her özelliğin önündedir.

## 3. Endpoint listesi
| Method | Path | Amaç |
|---|---|---|
| `GET`  | `/health` | Sağlık kontrolü |
| `POST` | `/explain` | **Ana** açıklama endpoint'i (serbest soru / seçilen test) |
| `POST` | `/query` | **Deprecated** — `/explain` ile birebir aynı; geriye uyumluluk için |
| `POST` | `/chat` | Sana Asistan için kontrollü RAG + LLM sohbeti |
| `GET`  | `/terms` | Desteklenen lab testlerinin listesi |
| `GET`  | `/terms/{lab_test}` | Tek bir terimin detayı |
| `POST` | `/reports/parse` | Düz metin rapordan deterministik değer çıkarımı |

`response_type` ∈ { `answer`, `no_results`, `safety_block`, `error` }.
`no_results` ve `safety_block` **HTTP 200** döner; doğrulama/dil hataları **HTTP 400**.

## 4. Request/response örnekleri

### POST /explain — request
```json
{
  "question": "CRP 13.5 çıktı",
  "lab_test": "CRP",
  "options": { "language": "tr", "include_sources": true, "include_doctor_questions": true }
}
```

### POST /explain — response (answer)
```json
{
  "request_id": "uuid",
  "response_type": "answer",
  "lab_test": "CRP",
  "matched_term": "crp",
  "answer": "CRP, vücutta iltihaplanma olduğunda yükselebilen bir proteindir. Tek başına tanı koydurmaz.",
  "confidence": 0.8,
  "confidence_label": "high",
  "result_context": { "raw_value": "13.5", "value": 13.5, "unit": null, "reference_range": null, "interpretation": null },
  "citations": [
    { "source_title": "MedlinePlus", "source_url": "https://medlineplus.gov/...", "section": "Nedir?" }
  ],
  "doctor_questions": ["CRP yüksekliğim hangi durumlarla ilişkili olabilir?"],
  "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; ...",
  "normalized_query": "crp 13 5 çıktı",
  "llm_provider": "dummy",
  "safety_notes": [],
  "retrieved_chunks": [ { "lab_test": "CRP", "section": "Nedir?", "source_title": "MedlinePlus" } ]
}
```

### POST /chat — request
```json
{
  "messages": [
    { "role": "user", "content": "CRP 13.5 çıktı ne anlama gelir?" }
  ],
  "lab_test": "CRP",
  "include_sources": true
}
```

### POST /chat — response (answer)
```json
{
  "request_id": "uuid",
  "response_type": "answer",
  "answer": "CRP, vücutta iltihaplanma olduğunda yükselebilen bir proteindir. Tek başına tanı koydurmaz.",
  "lab_test": "CRP",
  "matched_term": "crp",
  "citations": [
    { "source_title": "MedlinePlus", "source_url": "https://medlineplus.gov/...", "section": "Nedir?" }
  ],
  "confidence": 0.8,
  "confidence_label": "high",
  "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; ...",
  "safety_notes": [],
  "retrieved_chunks": [ { "lab_test": "CRP", "section": "Nedir?", "source_title": "MedlinePlus" } ],
  "llm_provider": "dummy"
}
```

### POST /reports/parse — request
```json
{ "text": "CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nB12 350 pg/mL" }
```

### POST /reports/parse — response
```json
{
  "parser_status": "parsed",
  "results": [
    { "lab_test": "CRP", "matched_term": "crp", "raw_value": "13.5", "value": 13.5, "unit": "mg/L", "reference_range": null, "interpretation": null }
  ],
  "disclaimer": "Bu açıklama yalnızca bilgilendirme amaçlıdır; ..."
}
```

### GET /terms — response (özet liste)
```json
[ { "lab_test": "CRP", "title": "C-Reaktif Protein (CRP)", "sections": ["Nedir?", "Neden ölçülür?"] } ]
```

### GET /terms/{lab_test} — response (detay)
```json
{
  "lab_test": "CRP",
  "title": "C-Reaktif Protein (CRP)",
  "sections": ["Nedir?", "Neden ölçülür?"],
  "sources": [ { "source_title": "MedlinePlus", "source_url": "https://medlineplus.gov/...", "section": null } ]
}
```

## 5. `/explain` response alanları
| Alan | Tip | Açıklama |
|---|---|---|
| `request_id` | string | İstek izleme kimliği |
| `response_type` | string | `answer` / `no_results` / `safety_block` / `error` |
| `lab_test` | string \| null | Kanonik test adı (resolve edilemezse null) |
| `matched_term` | string \| null | Girdideki eşleşen terim |
| `answer` | string | Sade Türkçe açıklama (tanı içermez) |
| `confidence` | float | 0.0–1.0 |
| `confidence_label` | string | `low` / `medium` / `high` |
| `result_context` | object \| null | Sorudaki sayısal değer bağlamı (yorum yok) |
| `citations` | array | Yalnız retrieval'dan gelen kaynaklar (URL dedup) |
| `doctor_questions` | array | Doktora sorulabilecek sorular |
| `disclaimer` | string | Her yanıtta bulunur |
| `normalized_query` | string \| null | Sorgunun normalize hali |
| `llm_provider` | string \| null | Aktif sağlayıcı (`dummy`) |
| `safety_notes` | array | safety_block'ta kısa not; aksi halde boş |
| `retrieved_chunks` | array | Kullanılan parçaların hafif metadata'sı |

`result_context` / `ResultContext`: `raw_value`, `value`, `unit`, `reference_range`, `interpretation`.
`reference_range` ve `interpretation` **şimdilik her zaman null** (yorum/aralık üretilmez).

## 6. `/chat` endpointinin amacı ve response alanları
`POST /chat`, ileride Flutter Asistan sekmesinin kullanacağı kontrollü sohbet endpoint'idir.
Serbest genel tıbbi sohbet değildir; son kullanıcı mesajından veya `lab_test` alanından
desteklenen bir tahlil eşleşmesi bulamazsa güvenli `no_results` döner ve kullanıcıdan
tahlil adı/sonuç yazmasını ister. İlaç/doz/takviye/tedavi ve teşhis isteklerinde provider
çağrılmadan güvenli blok uygulanır.

| Alan | Tip | Açıklama |
|---|---|---|
| `request_id` | string | İstek izleme kimliği |
| `response_type` | string | `answer` / `no_results` / `safety_block` / `error` |
| `answer` | string | Sade Türkçe, tanı/tedavi içermeyen yanıt |
| `lab_test` | string \| null | Kanonik test adı |
| `matched_term` | string \| null | Son kullanıcı mesajındaki eşleşen terim |
| `citations` | array | Yalnız retrieval'dan gelen kaynaklar |
| `confidence` | float | 0.0–1.0 |
| `confidence_label` | string | `low` / `medium` / `high` |
| `disclaimer` | string | Her yanıtta bulunur |
| `safety_notes` | array | safety_block'ta kısa not; aksi halde boş |
| `retrieved_chunks` | array | Public-safe metadata; `content`, `chunk_id`, `score` içermez |
| `llm_provider` | string | Aktif sağlayıcı (`dummy`, `ollama`, `openai_compatible`) |

`/chat` de `/explain` gibi kaynak uydurmaz; cevap modelden gelse bile kaynaklar backend seed
retrieval sonucundan üretilir. Local/offline kullanım için `LLM_PROVIDER=ollama` ile aynı
endpoint çalışır.

## 7. `/reports/parse` response alanları
| Alan | Tip | Açıklama |
|---|---|---|
| `parser_status` | string | `parsed` / `no_results` |
| `results` | array | Bulunan `ParsedLabResult` öğeleri |
| `disclaimer` | string | `C.DISCLAIMER` |

`ParsedLabResult`: `lab_test`, `matched_term`, `raw_value`, `value`, `unit`,
`reference_range` (her zaman null), `interpretation` (her zaman null). Değer alanları
`/explain` içindeki `ResultContext` ile **aynı isimlidir** (uyumluluk).
Boş `text` → **400**. Desteklenen test bulunamazsa → **200 + `no_results` + `results: []`**.

## 8. `/terms` endpointlerinin amacı
Flutter "lab sözlüğü" ekranı için desteklenen testleri ve detaylarını okumak.
`GET /terms` özet liste; `GET /terms/{lab_test}` tek terim detayı (path değeri
`resolve_lab_test` ile kanonik ada bağlanır — `CRP`, `crp`, `C reaktif protein` hepsi
`CRP`'ye çözülür; bulunamazsa **404**).

## 9. Deprecated `/query` notu
`POST /query`, `/explain` ile **birebir aynı** akışı ve `ExplainResponse` modelini kullanır.
OpenAPI'de `deprecated=True` işaretlidir. **Yeni istemciler `/explain` kullanmalıdır;**
`/query` yalnız geriye uyumluluk içindir ve ileride kaldırılabilir.

## 10. Public yanıtta ASLA dönmeyen internal alanlar
Aşağıdaki alanlar yalnız internal/log tarafında kalır, hiçbir public yanıta çıkmaz
(DECISIONS §6/§10/§11):
- `chunk_id`
- `content`
- `score`

## 11. Şu an bilinçli olarak OLMAYAN şeyler
- OCR
- PDF binary parsing / dosya upload
- database
- auth
- embedding / vektör arama
- tanı / tedavi önerisi
- "yüksek / düşük / normal" yorumu veya referans aralığı değerlendirmesi
- Flutter Asistan sekmesi (sonraki sprint)
