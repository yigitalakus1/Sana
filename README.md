# Sana

Sana tamamen ücretsizdir; hesap, profil veya abonelik gerektirmez. Rapor
geçmişi ve karşılaştırma dahil tüm uygulama özellikleri herkese açıktır.

**Sana**, Flutter istemcisi ve FastAPI tıbbi açıklama backend'inden oluşan bir
sağlık okuryazarlığı uygulamasıdır.
Tahlil değerleri hakkında **Türkçe, kaynak gösterimli, güven skorlu ve teşhis koymayan**
açıklamalar üretir.

> ⚠️ Bu sistem bir teşhis aracı değildir. Amacı, kullanıcının sağlık okuryazarlığını
> artırmak ve doktoruna daha bilinçli sorular sormasına yardımcı olmaktır.

## Özellikler
- 240 tahlil değeri için Türkçe seed içerik ve güvenilir kaynak bağlantıları
- Sorgu normalizasyonu (Türkçe karakter duyarlı), eş anlamlı (synonym) haritası
- Keyword + exact-match retrieval (embedding yok)
- Provider seam: varsayılan `DummyLLMProvider`, opsiyonel `ollama` ve `openai_compatible`
- Güven skoru (confidence) + etiket (high/medium/low)
- Citation (yalnızca retrieval'dan, URL dedup)
- Safety katmanı (ilaç/doz, teşhis, tedavi, pediatrik, acil, doktordan kaçınma)
- `GET /health`, `POST /explain`, `POST /query` (deprecated), `POST /chat`, `GET /terms`, `POST /reports/parse`
- Pytest regresyon testleri

## Hızlı başlangıç (Windows)

Tüm sistemi (Ollama + backend + web arayüzü) tek tıkla çalıştırmak için:

```bat
Kisayol Olustur.cmd
```

Bu, masaüstünde **Sana** kısayolu oluşturur. Kısayola çift tıklayınca servisler
başlar ve tarayıcı açılır; pencerede bir tuşa basınca hepsi düzgünce durur.

Kısayol istemiyorsan doğrudan da çalıştırabilirsin:

```bat
Sana Baslat.cmd     :: başlat (tarayıcıyı da açar)
status_local.cmd    :: durum
stop_local.cmd      :: durdur
```

> Kısayol dosyasının kendisi (`.lnk`) mutlak yol içerdiği için depoda
> tutulmaz; her bilgisayarda `Kisayol Olustur.cmd` ile üretilir.

## Kurulum
```bash
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install -r requirements.txt
```

## Çalıştırma
```bash
uvicorn app.main:app --reload
```
Sunucu varsayılan olarak `http://127.0.0.1:8000` adresinde açılır.
Etkileşimli dokümantasyon: `http://127.0.0.1:8000/docs`

## Test
```bash
pytest
```

## Örnek curl

Sağlık kontrolü:
```bash
curl http://127.0.0.1:8000/health
```

Açıklama sorusu:
```bash
curl -X POST http://127.0.0.1:8000/explain \
  -H "Content-Type: application/json" \
  -d '{"question":"CRP nedir?","lab_test":"CRP","options":{"language":"tr"}}'
```

Eş anlamlı (synonym) eşleşmesi — "iltihap değeri" → CRP:
```bash
curl -X POST http://127.0.0.1:8000/query \
  -H "Content-Type: application/json" \
  -d '{"question":"İltihap değerim yüksek çıkmış, ne demek?","options":{"language":"tr"}}'
```

İlaç sorusu (safety_block):
```bash
curl -X POST http://127.0.0.1:8000/query \
  -H "Content-Type: application/json" \
  -d '{"question":"CRP yüksekse hangi antibiyotiği almalıyım?","options":{"language":"tr"}}'
```

Kontrollü sohbet (`/chat`):
```bash
curl -X POST http://127.0.0.1:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"CRP 13.5 çıktı ne anlama gelir?"}],"lab_test":"CRP"}'
```

`/chat`, Sana Asistan için RAG + LLM destekli ama sınırlı bir sohbet endpoint'idir:
genel tıbbi sohbet yapmaz, desteklenen tahlil bulunamazsa güvenli `no_results` döner.
Local/offline kullanım için `LLM_PROVIDER=ollama` ile çalışabilir; kaynaklar yine backend
seed retrieval sonucundan gelir.

## API yanıt tipleri

`response_type` alanı yanıtın türünü belirtir: `answer` · `no_results` · `safety_block` · `error`.
No-results ve safety_block **HTTP 200** döner (hata değildir); yalnızca doğrulama/dil hataları HTTP 400 döner.

**answer:**
```json
{
  "request_id": "uuid",
  "response_type": "answer",
  "answer": "CRP, karaciğerde üretilen ... Tek başına tanı koydurmaz.",
  "confidence": 0.8,
  "confidence_label": "high",
  "sources": [
    { "title": "C-Reaktif Protein (CRP)", "url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/", "source": "MedlinePlus", "score": 1.0 }
  ],
  "doctor_questions": ["CRP yüksekliğim hangi durumlarla ilişkili olabilir?", "..."],
  "disclaimer": "Bu cevap teşhis amacı taşımaz. Sonuçlarınızı doktorunuzla değerlendirin."
}
```

**no_results** (kaynak eşleşmesi yok → confidence 0.0, kaynak uydurulmaz):
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

**safety_block** (ör. ilaç/doz sorusu — retrieval yapılmaz):
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

**error** (HTTP 400):
```json
{
  "request_id": "uuid",
  "response_type": "error",
  "error": { "code": "VALIDATION_ERROR", "message": "Soru alanı boş olamaz.", "details": {} },
  "disclaimer": "..."
}
```
Error kodları: `VALIDATION_ERROR`, `UNSUPPORTED_LANGUAGE`, `INTERNAL_ERROR`, `TIMEOUT`, `SAFETY_BLOCKED`.

## Güven skoru (confidence)
| Bileşen | Ağırlık |
|---|---|
| lab_value tam eşleşme | +0.35 |
| eş anlamlı eşleşme | +0.20 |
| keyword örtüşmesi | +0.20 |
| kaynak var | +0.15 |
| intent–section eşleşmesi | +0.10 |

Eşikler: **0.71–1.00 high · 0.41–0.70 medium · 0.00–0.40 low.**
Sert kurallar: retrieval yoksa skor 0.0; kaynak yoksa "high" olamaz; safety_block → 0.0/low.

## Güvenlik ilkeleri
- Teşhis koyma, tedavi/ilaç/doz önerme yok.
- İlaç-doz, takviye ve "doktora gerek yok" türü sorular **retrieval yapılmadan** güvenli şekilde reddedilir.
- Teşhis, tedavi, pediatrik ve acil bağlamlarda cevap **güvenlik filtresinden** geçer (uyarı eklenir).
- Pediatrik (yaş < 14 veya "çocuk/bebek" bağlamı) → çocuk doktoruna yönlendirme, yaşa özel aralık verilmez.
- Acil/panik bağlamı → önce acil sağlık hizmetine yönlendirme.
- Her cevapta disclaimer döner. Kaynak yoksa kaynak uydurulmaz.

## Proje yapısı
```
app/
  main.py                  # FastAPI girişi
  api/                     # routes_health, routes_query, routes_chat, routes_terms, routes_reports
  core/                    # constants, config
  models/                  # Pydantic şemaları
  data/                    # seed_documents, synonyms
  services/                # normalization, intent, retrieval,
                           # confidence, citation, safety, llm_provider, rag_service, chat_service
  utils/                   # text_utils
tests/                     # 305 geçen pytest testi + 2 opsiyonel Foundry smoke testi
```

## Week 3 planı
- **Retrieval v1:** BM25 / TF-IDF + (opsiyonel) çok dilli embedding + hybrid retrieval (RRF veya ağırlıklı skor)
- **Flutter entegrasyonu:** `MlDictionaryService` → `POST /explain` bağlantısı, Asistan sekmesi için `/chat`
- **LLM:** local `ollama` veya OpenAI-compatible provider; çalışmazsa demo için `DummyLLMProvider`
- **Değerlendirme:** 20 soruluk test seti üzerinde precision@3 ölçümü

## Not
Tüm tıbbi seed içerik kasıtlı olarak genel ve temkinlidir; üretime alınmadan önce bir hekim
tarafından gözden geçirilmesi önerilir. MedlinePlus URL'leri doğrulanmalıdır.
