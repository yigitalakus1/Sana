# Sana Backend — Demo Script (S100)

Bu doküman, Sana backend'ini demo/teslim sırasında adım adım göstermek içindir.
Tüm komutlar Windows PowerShell uyumludur ve backend kökünde (`sana-rag-backend/`)
çalıştırılır.

> Demo iki şekilde yapılabilir:
> - **Hızlı demo (env'siz):** seed + dummy — kurulum sonrası anında çalışır, model gerekmez.
> - **Tam demo (local AI):** SQLite RAG + Foundry Local — gerçek local LLM cevabı.
>   Foundry kurulumu için: [FOUNDRY_LOCAL_SMOKE_TEST.md](FOUNDRY_LOCAL_SMOKE_TEST.md)
>
> Aşağıdaki istek/beklenti akışı iki modda da aynıdır; yalnız `answer` metninin
> üretim şekli değişir. **Hiçbir modda API key veya dış AI servisi kullanılmaz.**

## PowerShell'de Türkçe karakterler (ÖNEMLİ)

Backend yanıtları **UTF-8**'dir ve Türkçe karakterler doğrudur (backend testleriyle
sabit). Ancak PowerShell konsolu varsayılan kod sayfasında `değeri` → `deÄeri`,
`yüksek` → `yÃ¼ksek` gibi **görüntü** bozulması (mojibake) yapabilir. Bu terminal
kaynaklıdır, backend değil. Demodan önce konsolu UTF-8'e alın:

```powershell
chcp 65001
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

İstek gövdesinde de UTF-8 göndermek için `-ContentType "application/json; charset=utf-8"`
kullanın. (Doğrulama: `Invoke-RestMethod ... ` sonucundaki `answer` alanı Türkçe
karakterleri düzgün gösterir.)

## 0) Hazırlık

Ingestion (tam demo için; idempotent, tekrar çalıştırılabilir):

```powershell
python -m tools.ingest_docs --docs-dir data/medical_docs --db-path data/sana_rag.db
```

Tam demo env'leri (hızlı demo için bu adımı atlayın):

```powershell
$env:SANA_RAG_MODE="local"
$env:SANA_PROVIDER="foundry_local"
$env:SANA_FOUNDRY_MODEL="<model-adı>"
$env:SANA_RAG_DB_PATH="data/sana_rag.db"
$env:SANA_ENABLE_EXTERNAL_AI="false"
```

Backend'i başlat:

```powershell
uvicorn app.main:app --reload
```

## 1) Health kontrolü

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8000/health"
```

Beklenen: `status=ok, version=v1`. (Swagger UI: `http://127.0.0.1:8000/docs`)

## 2) /explain — answerable örnekler

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"CRP nedir?","lab_test":"CRP","options":{"language":"tr"}}'

Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"Ferritin neden ölçülür?","options":{"language":"tr"}}'
```

**Gösterilecekler:** `response_type="answer"`; Türkçe, sade, **tanı koymayan** cevap;
`citations` dolu ve hem local hem seed modunda doğrulanmış MedlinePlus URL'sine gider;
`doctor_questions` backend'den gelir (LLM uydurmaz); her yanıtta `disclaimer`.

## 3) /chat — answerable örnek

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/chat" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"messages":[{"role":"user","content":"B12 düşüklüğü ne anlama gelebilir?"}]}'
```

**Gösterilecekler:** kontrollü sohbet — aynı kaynak/güvenlik kuralları; cevap
"düşüklük şuna işaret edebilir, doktorla değerlendirin" çerçevesinde kalır.

## 4) no-results fallback

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"Miyoglobin nedir?","options":{"language":"tr"}}'
```

**Gösterilecekler:** desteklenmeyen tahlil (kapsam: CRP, Glukoz, Ferritin, B12,
Hemoglobin) → `response_type="no_results"`; **LLM hiç çağrılmaz**, kaynak uydurulmaz,
kullanıcı doktora yönlendirilir. Aynı davranış DB boş/yokken de geçerlidir (crash yok).

## 5) Safety — ilaç/doz bloğu

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/chat" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"messages":[{"role":"user","content":"B12 350 çıktı, ilaç alayım mı?"}]}'
```

**Gösterilecekler:** `response_type="safety_block"` — ilaç/doz sorusunda
**retrieval bile yapılmadan** güvenli blok; ilaç adı/doz asla verilmez;
doktora/eczacıya yönlendirme.

## 6) Emergency yönlendirmesi

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"Nefes darlığım var, ne yapayım?","options":{"language":"tr"}}'
```

**Gösterilecekler:** acil belirti + desteklenmeyen konu → `no_results` ama cevap
**acil sağlık hizmeti yönlendirmesiyle başlar**; LLM çağrılmaz.

Lab'lı acil örnek (cevap üretilir ama başına acil yönlendirme eklenir):

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/explain" `
  -ContentType "application/json; charset=utf-8" `
  -Body '{"question":"Bayılacak gibi oluyorum, hemoglobin düşük.","lab_test":"Hemoglobin","options":{"language":"tr"}}'
```

## Demo kapanış mesajları

- Her cevap **kaynaklıdır**; kaynak yoksa cevap uydurulmaz (`no_results`).
- Sistem **tanı koymaz, ilaç/doz önermez**; bu sorular güvenlik katmanında,
  LLM'e ulaşmadan kesilir.
- Acil bağlamda kullanıcı önce **acil sağlık hizmetine** yönlendirilir.
- Tüm AI **cihaz üzerinde** çalışır: API key yok, dış AI API yok, per-token ücret yok.
- Amaç teşhis değil; kullanıcıyı **doktoruna bilinçli soru sormaya** hazırlamak
  (`doctor_questions` alanı tam bunun için).
