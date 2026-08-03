# sana-rag-backend

**Sana** sağlık okuryazarlığı uygulamasının tıbbi açıklama backend'i.
Laboratuvar değerlerini **Türkçe, kaynak gösterimli, güven skorlu ve teşhis koymayan**
şekilde açıklar; ayrıca düz metin raporlardan deterministik olarak değer çıkarır.

> ⚠️ **Sana bir teşhis aracı DEĞİLDİR.** Amacı, kullanıcının sağlık okuryazarlığını
> artırmak ve doktoruna daha bilinçli sorular sormasına yardımcı olmaktır.

## Local-first mimari

Sana **ücretli dış AI API kullanmaz**: OpenAI, Azure OpenAI, Anthropic Claude ve
Google Gemini API'lerine bağımlılık yoktur, **API key gerekmez**, per-token ücret
oluşmaz. Model eğitimi/fine-tuning yapılmaz; **hazır bir local model + local RAG**
kullanılır. Sağlık bilgisi modelin genel bilgisinden değil, Sana'nın kendi kaynaklı
dokümanlarından (retrieval) gelir.

```
Flutter App
  → FastAPI Backend
    → Safety Guard (ilaç/doz/tanı/acil filtreleri)
    → Local RAG Retrieval (BM25-benzeri lexical)
    → SQLite (data/sana_rag.db)
    → Prompt Builder (kaynak parçaları + kurallar)
    → Ollama veya Foundry Local Provider (API key'siz, cihaz üstü)
    → Local LLM
  → Türkçe, sade, kaynaklı, tanı koymayan cevap
```

## Kurulum

Python **3.11+** gerekir.

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

Sunucu varsayılan olarak `http://127.0.0.1:8000`. Etkileşimli dokümantasyon: `/docs`.

## Çalışma modları

### Varsayılan (test/demo) modu — hiçbir env gerekmez

```
SANA_RAG_MODE=seed      # bellek-içi seed içerik (varsayılan)
SANA_PROVIDER=dummy     # deterministik, ağsız cevap üretici (varsayılan)
```

Env ayarlamadan çalıştırınca bu mod aktiftir; kurulum sonrası anında denenebilir.

### Local Foundry modu — gerçek local LLM + SQLite RAG

```powershell
# 1) Medical docs'u SQLite RAG store'a yaz (idempotent)
python -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db

# 2) Env
$env:SANA_RAG_MODE="local"
$env:SANA_PROVIDER="foundry_local"
$env:SANA_FOUNDRY_MODEL="<model-adı>"          # foundry model list'ten
$env:SANA_RAG_DB_PATH="data/sana_rag.db"
$env:SANA_ENABLE_EXTERNAL_AI="false"

# 3) Başlat
uvicorn app.main:app --reload
```

Adım adım gerçek runtime doğrulaması: **[docs/FOUNDRY_LOCAL_SMOKE_TEST.md](docs/FOUNDRY_LOCAL_SMOKE_TEST.md)**
Demo akışı ve örnek sorular: **[docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md)**

### Env değişkenleri

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `SANA_RAG_MODE` | `seed` | `local` → SQLite RAG store; bilinmeyen değer güvenle `seed`'e düşer |
| `SANA_PROVIDER` | `dummy` | `dummy` \| `ollama` \| `openai_compatible` \| `foundry_local` |
| `SANA_FOUNDRY_MODEL` | — | Foundry Local model adı |
| `SANA_FOUNDRY_BASE_URL` | — | Verilirse SDK gerekmez (örn. `http://127.0.0.1:5273/v1`) |
| `SANA_RAG_DB_PATH` | `data/sana_rag.db` | SQLite RAG store yolu |
| `SANA_ENABLE_EXTERNAL_AI` | (engel yok) | `false` → dış (OpenAI-uyumlu) sağlayıcı seçimi engellenir, dummy'ye düşer |
| `MEDLINEPLUS_TIMEOUT_SECONDS` | `20` | Manuel resmî kaynak sync zaman aşımı |
| `MEDLINEPLUS_CACHE_HOURS` | `24` | MedlinePlus Connect cache süresi (en az 12) |

Hiçbir modda `OPENAI_API_KEY` / `AZURE_OPENAI_API_KEY` / `ANTHROPIC_API_KEY` /
`GEMINI_API_KEY` okunmaz; ayarlansalar bile kullanılmaz ve isteklere `Authorization`
başlığı gönderilmez (testle sabitlenmiştir).

## Test

```bash
pytest          # 305 passed, 2 skipped; ağ/API key GEREKMEZ (fake provider + geçici DB)
```

Opsiyonel gerçek Foundry smoke testi (Foundry kurulu + model yüklüyse):

```powershell
$env:SANA_RUN_FOUNDRY_SMOKE="1"
$env:SANA_FOUNDRY_MODEL="<model-adı>"
python -m pytest tests/test_foundry_runtime_smoke.py -v
```

Bu env'ler yokken smoke testler otomatik **skip** edilir; normal paket etkilenmez.

## Endpoint özeti

| Method | Path | Açıklama |
|---|---|---|
| `GET`  | `/health` | Sağlık kontrolü |
| `POST` | `/explain` | **Ana** açıklama endpoint'i (serbest soru / seçilen test) |
| `POST` | `/query` | **Deprecated** — `/explain` ile birebir aynı; geriye uyumluluk için |
| `POST` | `/chat` | Sana Asistan için kontrollü RAG + LLM sohbeti |
| `GET`  | `/terms` | Desteklenen lab testlerinin listesi |
| `GET`  | `/terms/{lab_test}` | Tek terim detayı |
| `POST` | `/reports/parse` | Düz metin rapordan deterministik değer çıkarımı |

`response_type` ∈ { `answer`, `no_results`, `safety_block`, `error` }.
`no_results` ve `safety_block` **HTTP 200** döner; doğrulama/dil hataları **HTTP 400**.

Desteklenen 10 değer: **CRP, Glukoz, Ferritin, B12, Hemoglobin, TSH, Kreatinin,
ALT, AST, Trombosit**.

## Örnek istekler

> `/explain` gövdesinde alan adı **`question`**'dır (`query` değil).

Açıklama (`/explain`):
```bash
curl -X POST http://127.0.0.1:8000/explain \
  -H "Content-Type: application/json" \
  -d '{"question":"CRP nedir?","lab_test":"CRP","options":{"language":"tr"}}'
```

Kontrollü sohbet (`/chat`):
```bash
curl -X POST http://127.0.0.1:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"CRP 13.5 çıktı ne anlama gelir?"}],"lab_test":"CRP","include_sources":true}'
```

Rapor metni parse (`/reports/parse`):
```bash
curl -X POST http://127.0.0.1:8000/reports/parse \
  -H "Content-Type: application/json" \
  -d '{"text":"CRP: 13.5 mg/L\nGlukoz 92 mg/dL\nB12 350 pg/mL"}'
```

Desteklenen testler (`/terms`):
```bash
curl http://127.0.0.1:8000/terms
```

## Güvenlik / medikal sınırlar

- **Tanı koymaz.**
- **Tedavi / ilaç / doz önermez.**
- İlaç/doz, takviye, "doktora gerek yok" soruları → `safety_block`
  (**retrieval ve LLM hiç çağrılmadan**).
- Tanı/tedavi/pediatrik/acil bağlamlarında cevap güvenlik filtresinden geçer;
  acil bağlamda cevap acil yönlendirmeyle başlar (kaynak bulunamasa bile).
- `/chat` genel tıbbi sohbet değildir; desteklenen tahlil bulunamazsa güvenli
  `no_results` döner ve kullanıcıdan tahlil adı/sonuç yazmasını ister.
- **"Yüksek / düşük / normal" yorumu yapmaz**; referans aralığına göre değerlendirme
  yapmaz (`interpretation` ve `reference_range` her zaman `null`).
- **Her yanıtta `disclaimer` döner.** Kaynak yoksa kaynak uydurulmaz; `no_results` /
  `safety_block` durumlarında LLM provider **çağrılmaz**.

## Flutter bağlantısı

- Flutter tarafında `MlDictionaryService` → `SanaApiClient` şu endpoint'leri kullanır:
  `/health`, `/explain` (**`/query` kullanılmaz**), `/chat`, `/terms`,
  `/terms/{lab_test}`, `/reports/parse`.
- Base URL `sana-app/lib/core/config/api_config.dart` içindeki `ApiConfig.baseUrl`'den
  gelir; derlerken değiştirmek için:
  `flutter run --dart-define=SANA_API_BASE_URL=http://127.0.0.1:8000`
  (varsayılan `http://localhost:8000`; Android emülatöründe `http://10.0.2.2:8000` kullanın).
- `/explain` ve `/chat` contract'ları S93–S99 boyunca korunmuştur; Flutter tarafında
  değişiklik gerekmez.
- **Flutter tarafında hiçbir AI API key'i gerekmez** — uygulama yalnız local FastAPI
  backend'ine istek atar; AI/inference tamamen backend arkasındadır.

## Sınırlılıklar / bilinen riskler

- Tıbbi seed içerik kasıtlı olarak genel ve temkinlidir; **üretim öncesi hekim
  incelemesi gerekir**. MedlinePlus URL'leri doğrulanmalıdır.
- Gerçek local model çıktısı `evaluate_local.cmd` ile Türkçe, grounding, prompt sızıntısı,
  safety, contract ve gecikme açısından ölçülür; üretim öncesi **insan/hekim incelemesi
  yine gereklidir**.
- Küçük local modeller Türkçe'de zayıf kalabilir (dil karışması, devrik anlatım);
  model seçimi donanıma ve kaliteye göre yapılmalıdır.
- Acil/tanı/ilaç güvenliği **pattern tabanlıdır ve sınırlıdır**; dolaylı ifadeler
  ağdan kaçabilir. Prompt kuralları + cevap sonrası güvenlik filtresi ikinci savunma
  hattıdır ama garanti değildir.

## Şu an olmayanlar (bilinçli)

OCR · PDF binary parsing / dosya upload · auth · embedding / vektör arama ·
model eğitimi / fine-tuning.

## Dokümanlar

- [docs/FOUNDRY_LOCAL_SMOKE_TEST.md](docs/FOUNDRY_LOCAL_SMOKE_TEST.md) — gerçek Foundry Local runtime smoke testi
- [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) — demo akışı ve örnek sorular
- [docs/OLLAMA_EVALUATION.md](docs/OLLAMA_EVALUATION.md) — gerçek Ollama kalite/güvenlik değerlendirmesi
- [docs/MEDLINEPLUS_SOURCE_SYNC.md](docs/MEDLINEPLUS_SOURCE_SYNC.md) — LOINC tabanlı resmî kaynak staging ve inceleme akışı
- [docs/API_CONTRACT.md](../docs/API_CONTRACT.md) — public API sözleşmesi
- [docs/FLUTTER_INTEGRATION.md](../docs/FLUTTER_INTEGRATION.md) — Flutter entegrasyon akışı

## Proje yapısı

```
app/
  main.py                  # FastAPI girişi (router include)
  api/                     # routes_health, routes_query, routes_chat, routes_terms, routes_reports
  core/                    # constants, config (env: SANA_RAG_MODE, SANA_PROVIDER, ...)
  models/                  # Pydantic şemaları
  data/                    # seed_documents, synonyms
  services/                # normalization, intent, retrieval, local_retrieval, rag_store,
                           # chunking, confidence, citation, safety, llm_provider,
                           # result_context, terms, report_parse, rag_service, chat_service
    llm/                   # prompts + dummy/ollama/openai_compatible/foundry_local sağlayıcıları
data/
  medical_docs/            # kaynaklı Türkçe markdown içerik (ingestion girdisi)
  sana_rag.db              # SQLite RAG store (ingestion çıktısı; commit edilmez)
tools/
  ingest_docs.py           # medical_docs -> SQLite ingestion (idempotent)
tests/                     # pytest (305 passed; 2 Foundry smoke testi skip-korumalı)
```
