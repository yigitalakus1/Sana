# Sana — LLM Provider Kurulumu

## Önerilen yerel kullanım (tek komut)

Ollama, `llama3.2:3b`, local SQLite RAG, backend ve Flutter web sürümünü birlikte
hazırlamak için proje kökünde çalıştır:

```powershell
cd C:\D_DİSKİ_2026\Sana
.\start_local.cmd
```

Script şu adımları otomatik yapar:

1. Ollama servisini ve `llama3.2:3b` modelini kontrol eder.
2. Kaynak dokümanları idempotent biçimde `data/sana_rag.db` içine işler.
3. Backend'i local RAG + Ollama ayarlarıyla `http://127.0.0.1:8000` üzerinde başlatır.
4. Gerekirse Flutter release web build'ini yeniler ve `http://127.0.0.1:57009` üzerinde sunar.
5. Uygulamayı tarayıcıda açar.

Yardımcı komutlar:

```powershell
.\status_local.cmd  # Ollama, backend, web ve model durumunu gösterir
.\stop_local.cmd    # start_local.cmd tarafından başlatılan süreçleri durdurur
.\evaluate_local.cmd # gerçek local model kalite/güvenlik raporu üretir
```

Farklı model kullanmak için `-Model` verilebilir. Model önceden Ollama'ya indirilmiş
olmalıdır; script kendiliğinden ağdan model indirmez.

```powershell
.\start_local.cmd -Model "llama3.2:3b" -RebuildWeb
```

`.cmd` sarmalayıcıları yalnızca proje içindeki imzalı olmayan yerel scripti o çalıştırma
için açar; Windows'un sistem genelindeki PowerShell execution policy ayarını değiştirmez.

### Küçük local model kalite korumaları

Varsayılan `llama3.2:3b` çalıştırmasında:

- Prompt'a yalnızca soruyla en alakalı tek kaynak bölümü verilir.
- Yanıt en fazla dört tamamlanmış cümleyle sınırlandırılır.
- Token sınırında yarım kalan son cümle kullanıcıya gösterilmez.
- Türkçe dışı model metni algılanırsa backend'in doğrulanmış kaynak metnine dönülür.
- Citation ve `retrieved_chunks` metadata'sı her durumda backend retrieval katmanından gelir.

Son doğrulama: backend `305 passed, 2 skipped`; Flutter `8 passed` ve `flutter analyze`
sonucu temiz. Otomatik testler gerçek Ollama veya ağ çağrısı yapmaz. Gerçek local model
10 kaynaklı bilgi senaryosu ve 5 güvenlik/no-results senaryosunda `15/15` başarılıdır.

Desteklenen tahliller: **CRP, Glukoz, Ferritin, B12, Hemoglobin, TSH, Kreatinin,
ALT, AST ve Trombosit**. Local ingestion 10 Markdown dosyasını 60 RAG chunk'ına işler.

Ayrıntılı local model değerlendirmesi:
[`sana-rag-backend/docs/OLLAMA_EVALUATION.md`](../sana-rag-backend/docs/OLLAMA_EVALUATION.md)

Sana backend'i varsayılan olarak **`dummy`** (deterministik, ağ gerektirmeyen)
sağlayıcıyla çalışır. Gerçek bir LLM istersen `ollama` veya `openai_compatible`
sağlayıcısını ortam değişkenleriyle etkinleştirebilirsin. **Backend'e veya public
API sözleşmesine dokunmadan** çalışır.

## Varsayılan: dummy

Hiçbir env vermeden çalıştır:

```powershell
cd C:\D_DİSKİ_2026\Sana\sana-rag-backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

- `LLM_PROVIDER` yoksa → `dummy`.
- `dummy` API key gerektirmez.
- Gerçek provider yapılandırılmamışsa backend dummy ile çalışmaya devam eder.

## Gerçek provider (openai_compatible)

OpenAI-compatible `/chat/completions` API'si sunan herhangi bir sağlayıcı kullanılabilir.

Ortam değişkenleri:

```text
LLM_PROVIDER=openai_compatible
LLM_MODEL=<model-adı>
LLM_API_KEY=<secret>
LLM_BASE_URL=<provider-base-url>     # örn. https://api.saglayici.com/v1
LLM_TIMEOUT_SECONDS=30
```

PowerShell (shell env) ile:

```powershell
$env:LLM_PROVIDER="openai_compatible"
$env:LLM_MODEL="<model-adı>"
$env:LLM_API_KEY="<secret>"
$env:LLM_BASE_URL="<provider-base-url>"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

İstek son URL'i: `LLM_BASE_URL` + `/chat/completions`.

## Yerel/offline provider (ollama)

Ollama yerelde çalışıyorsa `LLM_PROVIDER=ollama` ile Sana açıklamalarını local modelden
üretebilir. Backend import sırasında Ollama'ya bağlanmaz; bağlantı yalnız açıklama
üretilirken denenir.

Ortam değişkenleri:

```text
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=<local-model-name>
OLLAMA_TIMEOUT_SECONDS=60
```

PowerShell (shell env) ile:

```powershell
$env:LLM_PROVIDER="ollama"
$env:OLLAMA_BASE_URL="http://127.0.0.1:11434"
$env:OLLAMA_MODEL="<local-model-name>"
$env:OLLAMA_TIMEOUT_SECONDS="60"
cd C:\D_DİSKİ_2026\Sana\sana-rag-backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Test isteği:

```json
{
  "question": "CRP 13.5 mg/L çıktı",
  "lab_test": "CRP"
}
```

Chat test isteği:

```json
{
  "messages": [
    { "role": "user", "content": "CRP 13.5 mg/L çıktı ne anlama gelir?" }
  ],
  "lab_test": "CRP"
}
```

Beklenen davranış:

- `llm_provider` alanı `ollama` döner.
- `answer` yerel modelden gelir.
- `citations` backend'in seed kaynaklarından gelir; model kaynak uydurmaz.
- `disclaimer` korunur.
- Tanı, tedavi, ilaç veya doz önerisi verilmez.

İstek son URL'i: `OLLAMA_BASE_URL` + `/api/chat`.
`OLLAMA_BASE_URL` verilmezse varsayılan `http://127.0.0.1:11434` kullanılır.
`LLM_PROVIDER=ollama` seçiliyken `OLLAMA_MODEL` zorunludur; eksikse hata açıklama
üretilirken kontrollü şekilde döner.

## API key güvenliği

- API key **repoya commit edilmez** — `.env` dosyası ya da shell env olarak verilir
  (`.env` `.gitignore`'da olmalıdır).
- Key eksik/yanlışsa backend **import sırasında patlamaz**; hata yalnız açıklama
  üretilirken kontrollü şekilde oluşur.
- Kullanıcıya **hiçbir zaman** teknik hata / secret / `Authorization` başlığı sızmaz;
  yapılandırma/ağ hatası genel bir hata yanıtına (`response_type="error"`) çevrilir.

## Davranış özeti

- `/explain` yanıt şekli **değişmez** (aynı `ExplainResponse`).
- `/chat`, Flutter'daki Sana Asistan sekmesi için aynı RAG + provider seam'ini kullanır.
- `answer` gerçek sağlayıcıdan gelir; `llm_provider` alanı seçilen provider adını
  (`ollama` veya `openai_compatible`) döner.
- `citations` **her zaman backend'in seed kaynaklarından** gelir — model kaynak
  uydurmaz.
- `safety_block` ve `no_results` durumlarında sağlayıcı **çağrılmaz** (ağ isteği yok).
- `/chat` genel tıbbi sohbet değildir; desteklenen tahlil bulunamazsa güvenli
  `no_results` döner.
- `/query` deprecated kalır; Flutter yalnız `/explain` kullanır.

## Güvenlik notu

Sana bir **tanı/tedavi sistemi değildir**. Prompt ve backend safety katmanı, modelin
tanı koymasını, tedavi/ilaç önermesini ve (referans aralığı verilmediyse) sonucu
"yüksek/düşük/normal" diye yorumlamasını engeller. Her yanıtta disclaimer döner.
