# Foundry Local — Gerçek Runtime Smoke Test (S99)

## Amaç

Sana backend'ini **gerçek** Foundry Local runtime ve küçük bir local model ile
uçtan uca doğrulamak: local RAG (SQLite) → prompt → Foundry Local → Türkçe,
kaynaklı, tanı koymayan cevap.

Otomatik testlerin tamamı (225+) Foundry olmadan, fake provider ile çalışır.
Bu doküman yalnız gerçek runtime'ı elle doğrulamak içindir. Opsiyonel otomatik
smoke testi için en alttaki [pytest bölümüne](#opsiyonel-pytest-smoke-testi) bakın.

## Gereksinimler

- Windows 10/11 (veya macOS), Python 3.11+, bu repo kurulu (`pip install -r requirements.txt`)
- Microsoft Foundry Local ([kurulum](https://learn.microsoft.com/azure/ai-foundry/foundry-local/get-started))
- **API key GEREKMEZ. Dış AI servisi KULLANILMAZ.** Tüm inference cihaz üzerindedir;
  per-token ücret yoktur.

## 1) Foundry Local kurulumu

```powershell
winget install Microsoft.FoundryLocal
```

Kullanılabilir modelleri listeleyin ve küçük bir model indirin/çalıştırın
(model adları donanıma göre değişir; `foundry model list` çıktısından seçin):

```powershell
foundry model list
foundry model run phi-3.5-mini        # <model-adı> örneği; kendi seçiminizle değiştirin
foundry service status                 # servis ve endpoint portunu gösterir
```

## 2) Medical docs ingestion

Backend kökünde (`sana-rag-backend/`):

```powershell
python -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db
```

Beklenen özet: `Okunan dosya: 5`, `Parse edilen chunk: 30`, store toplamı 30.
Komut idempotenttir; tekrar çalıştırmak güvenlidir.

## 3) Env ayarları

```powershell
$env:SANA_RAG_MODE="local"
$env:SANA_PROVIDER="foundry_local"
$env:SANA_FOUNDRY_MODEL="phi-3.5-mini"          # <model-adı>: foundry model list'ten
$env:SANA_RAG_DB_PATH="data/sana_rag.db"
$env:SANA_ENABLE_EXTERNAL_AI="false"
```

İsteğe bağlı — SDK kurulu değilse endpoint'i elle verin (`foundry service status`
çıktısındaki port ile; SDK hiç gerekmez):

```powershell
$env:SANA_FOUNDRY_BASE_URL="http://127.0.0.1:5273/v1"
```

`SANA_FOUNDRY_BASE_URL` verilmezse backend, opsiyonel `foundry-local-sdk`
paketiyle endpoint'i kendisi keşfetmeye çalışır:

```powershell
pip install foundry-local-sdk
```

## 4) Backend'i başlat

```powershell
uvicorn app.main:app --reload
```

## 5) Health kontrolü

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8000/health"
# beklenen: status=ok, version=v1
```

## 6) /explain smoke

> İstek gövdesinde alan adı `question`'dır (contract: `QueryRequest`).

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"CRP nedir?","lab_test":"CRP","options":{"language":"tr"}}'
```

**Beklenen başarılı davranış:**
- `response_type = "answer"`
- `llm_provider = "foundry_local"`
- `answer`: Türkçe, sade, tanı koymayan açıklama
- `citations`: boş DEĞİL; `source_url` değerleri `https://medlineplus.gov/...`
- `disclaimer` dolu

## 7) /chat smoke

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/chat" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"messages":[{"role":"user","content":"Ferritin neden ölçülür?"}]}'
```

Beklenen: `response_type="answer"`, Türkçe cevap, local kaynaklı `citations`.

## 8) Fallback / no-results smoke

Desteklenmeyen tahlil (local docs yalnız CRP, Glukoz, Ferritin, B12,
Hemoglobin içerir):

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"Miyoglobin nedir?","options":{"language":"tr"}}'
```

Beklenen: `response_type="no_results"`, **model hiç çağrılmaz**, kaynak uydurulmaz.
Aynı davranış DB dosyası yoksa/boşsa da geçerlidir (crash olmaz).

## 9) Safety smoke

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/chat" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"messages":[{"role":"user","content":"B12 350 çıktı, ilaç alayım mı?"}]}'
```

Beklenen: `response_type="safety_block"`, doktora/eczacıya yönlendirme,
**Foundry Local hiç çağrılmaz** (ilaç/doz sorularında retrieval bile yapılmaz).

## Troubleshooting

| Belirti | Muhtemel neden / çözüm |
|---|---|
| `answer` alanında "Foundry Local sağlayıcısı kullanılamıyor" tarzı hata | SDK kurulu değil ve `SANA_FOUNDRY_BASE_URL` verilmemiş. `pip install foundry-local-sdk` veya base URL verin. |
| "Yerel açıklama servisi (Foundry Local) şu anda hazır değil" | `foundry service status` ile servisi kontrol edin; `foundry model run <model>` ile modeli yükleyin. Port değiştiyse `SANA_FOUNDRY_BASE_URL`'i güncelleyin. |
| "Foundry Local model adı eksik" | `SANA_FOUNDRY_MODEL` env'ini ayarlayın. |
| Her sorguda `no_results` | Ingestion yapılmamış ya da `SANA_RAG_DB_PATH` yanlış. Adım 2'yi ve yolun backend köküne göre doğru olduğunu kontrol edin. |
| Cevap İngilizce/karışık | Küçük modellerde olabilir; daha yetenekli bir model deneyin. Sistem promptu Türkçe'yi zorunlu kılar ama model kalitesi belirleyicidir. |
| İlk cevap çok yavaş | Model ilk istekte belleğe yüklenir; `SANA_FOUNDRY_TIMEOUT_SECONDS` (varsayılan 120) artırılabilir. |

Notlar:
- Hiçbir adımda `OPENAI_API_KEY` / `AZURE_OPENAI_API_KEY` / `ANTHROPIC_API_KEY` /
  `GEMINI_API_KEY` gerekmez; ayarlansalar bile local hat bunları kullanmaz ve
  isteklere `Authorization` başlığı gönderilmez (testle sabitlenmiştir).
- `SANA_ENABLE_EXTERNAL_AI="false"` dış (OpenAI-uyumlu) sağlayıcı seçimini de engeller.

## Opsiyonel pytest smoke testi

Foundry Local gerçekten kurulu ve model yüklüyse:

```powershell
$env:SANA_RUN_FOUNDRY_SMOKE="1"
$env:SANA_FOUNDRY_MODEL="phi-3.5-mini"   # ve gerekirse SANA_FOUNDRY_BASE_URL
python -m pytest tests/test_foundry_runtime_smoke.py -v
```

Bu env'ler yokken test paketi bu dosyayı otomatik **skip** eder; CI'da hiçbir
şey kırılmaz.
