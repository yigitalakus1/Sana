# MedlinePlus Resmi Kaynak Senkronizasyonu

Sana, desteklenen laboratuvar testlerini LOINC kodlariyla MedlinePlus Connect'e
esler. Senkronizasyon kullanici istegi sirasinda yapilmaz; resmi kayitlar once
SQLite staging tablosuna alinir ve acik inceleme olmadan RAG icerigini degistirmez.

## Kaynak ve kullanim sinirlari

- Endpoint: `https://connect.medlineplus.gov/service`
- Kod sistemi: LOINC (`2.16.840.1.113883.6.1`)
- Format: JSON, dil: Ingilizce
- Yeni paket yoktur; istemci Python `urllib` kullanir.
- NLM siniri 100 istek/dakika/IP'dir ve 12-24 saat cache onerir.
- Sana varsayilan olarak 24 saat cache uygular.
- Connect tek istekte tek LOINC kodu kabul eder; tum testleri listeleyen bir
  endpoint saglamaz.
- Toplu senkronizasyonda istekler arasinda varsayilan `0.65` saniye beklenir.
- MedlinePlus sayfalari kazinmaz; yalniz resmi Connect yaniti saklanir.
- Takip parametreleri temizlenir ve yalniz resmi HTTPS MedlinePlus URL'leri kabul edilir.

## Senkronizasyon

```powershell
cd C:\D_DİSKİ_2026\Sana
.\sync_sources.cmd

# Tek tahlil veya cache'i yok sayan kontrollu yenileme
.\sync_sources.cmd --lab-test CRP
.\sync_sources.cmd --force
```

## On test sinirini kaldiran LOINC katalogu

Yerlesik 10 test geriye donuk uyumluluk icin korunur. `--catalog-csv` ile
istenen sayida ek LOINC kaydi staging akimina verilebilir. Bu islem public API'yi
veya RAG icerigini otomatik degistirmez.

Arac iki CSV bicimini dogrudan kabul eder:

1. Resmi LOINC dagitimindaki `Loinc.csv` (`LOINC_NUM`, `LONG_COMMON_NAME`,
   `STATUS`, `COMMON_TEST_RANK` sutunlari).
2. Sana katalogu (`lab_test`, `loinc_code`, `loinc_name`, istege bagli
   `medlineplus_url` sutunlari).

Resmi LOINC dosyasi ucretsiz LOINC hesabi ve lisans kosullarinin kabulunu
gerektirir. Dosya indirildikten sonra ilk 2.000 yaygin kodu 100'er kayitlik
partilerle taramak icin:

```powershell
cd C:\D_DİSKİ_2026\Sana

.\sync_sources.cmd `
  --catalog-csv "C:\path\to\Loinc.csv" `
  --max-common-rank 2000 `
  --offset 0 `
  --limit 100

# Sonraki parti
.\sync_sources.cmd `
  --catalog-csv "C:\path\to\Loinc.csv" `
  --max-common-rank 2000 `
  --offset 100 `
  --limit 100
```

Yalniz harici katalogu kullanmak icin `--catalog-only` verilebilir. Varsayilan
`0.65` saniyelik aralik NLM'nin 100 istek/dakika/IP ust sinirinin altinda kalir.
Connect'in eslestirmedigi kodlar `no_match` sayilir; hata veya uydurma kaynak
olarak kaydedilmez. Eslesen her yeni kaynak `pending` olur ve insan onayi olmadan
yayinlanamaz.

Farkli LOINC kodlari ayni MedlinePlus sayfasina cikabilir. Kodlar
`source_mappings` tablosunda ayri ayri korunur; inceleme kaynaklari ise resmi URL
bazinda tekillestirilir. Boylece bir sayfa onlarca kez onay kuyruguna girmez.
Onaylanmis kaynaklar veya taslagi bulunan kayitlar otomatik birlestirilmez.

Mevcut kod eslemelerinin LOINC adi ve yayginlik sirasini aga cikmadan yenilemek
icin:

```powershell
.\sync_sources.cmd `
  --catalog-csv "C:\path\to\Loinc.csv" `
  --max-common-rank 2000 `
  --metadata-only
```

## Inceleme kuyrugu

Yeni veya degisen her kayit `pending` olur. Icerik ayniysa mevcut onay durumu
korunur; checksum degisirse onceki onay ve yayin isareti otomatik sifirlanir.

```powershell
cd C:\D_DİSKİ_2026\Sana
.\review_sources.cmd list --status pending
.\review_sources.cmd approve medlineplus:1988-5:en --reviewer "reviewer-name"
.\review_sources.cmd reject medlineplus:1988-5:en --reviewer "reviewer-name"
.\review_sources.cmd publish medlineplus:1988-5:en
```

`publish` yalniz onayli kayda yayin isareti koyar. Ham Ingilizce ozeti otomatik
olarak Turkceye cevirmez veya RAG chunk'larina kopyalamaz. Turkce tibbi icerik
ayri inceleme ve yazarlik asamasindan sonra guncellenmelidir.

## Karsilastirma raporu

MedlinePlus ozeti, dogrudan medical-test URL'si, Connect eslesmesi, mevcut
Turkce RAG bolumleri ve varsa Turkce taslak tek raporda gorulebilir:

```powershell
cd C:\D_DİSKİ_2026\Sana
.\source_review_report.cmd
```

Raporlar:

```text
C:\D_DİSKİ_2026\Sana\sana-rag-backend\reports\source_review_latest.json
C:\D_DİSKİ_2026\Sana\sana-rag-backend\reports\source_review_latest.md
```

`broader_topic`, LOINC Connect sonucunun dogrudan tahlil sayfasi yerine daha
genis bir MedlinePlus konu sayfasina gittigini belirtir. Bu kayitlar daha dikkatli
incelenmelidir.

## Kontrollu Turkce taslak

Taslak yalniz kaynak kaydi `approved` olduktan sonra local Ollama ile uretilir:

```powershell
.\generate_source_draft.cmd medlineplus:1988-5:en
.\review_sources.cmd draft-list --status pending
.\review_sources.cmd draft-approve medlineplus:1988-5:en --reviewer "reviewer-name"
.\review_sources.cmd draft-reject medlineplus:1988-5:en --reviewer "reviewer-name"
.\review_sources.cmd draft-publish medlineplus:1988-5:en
```

Taslak katmani kaynakta olmayan sayilari, referans araliklarini, Ingilizce veya
prompt sizintisini ve dogrudan ilac/doz yonlendirmesini reddeder. Taslak en fazla
dort tamamlanmis cumledir. Kaynak checksum'u degisirse onceki taslak `stale` olur.
Taslak yayin isareti de RAG dosyalarini otomatik degistirmez; son tibbi yazarlik
ve section bazli yayin adimi ayridir.

Yerel model kalite kapisini gecemeyen bir cikti urettiginde, resmi kaynak metnine
dayali ve kod incelemesinden gecen kontrollu batch taslaklari da ayni `pending`
kuyruguna eklenebilir:

```powershell
cd C:\D_DİSKİ_2026\Sana\sana-rag-backend
.\.venv\Scripts\python.exe tools\stage_source_batch.py `
  data\source_batches\medlineplus_common_01_drafts.json `
  --db-path data\sana_rag.db
```

Arac once batch'in tamamini dogrular; onaysiz kaynak, dogrudan MedlinePlus test
sayfasi olmayan URL, yinelenen anahtar veya kalite ihlali varsa hicbir taslagi
yazmaz. Basarili kayitlar yine yalniz `pending` olur; otomatik onaylanmaz,
yayinlanmaz ve kullaniciya sunulan RAG dosyalarini degistirmez.

Ikinci incelemesi tamamlanan batch, alti bolumlu Markdown belgelerine ve seed
paketine kontrollu olarak yayinlanir:

```powershell
.\.venv\Scripts\python.exe tools\publish_source_batch.py `
  data\source_batches\medlineplus_common_01_rag.json `
  --db-path data\sana_rag.db
.\.venv\Scripts\python.exe -m tools.ingest_docs `
  --docs-dir data\medical_docs `
  --db-path data\sana_rag.db
```

Yayin araci yalniz hem kaynagi hem Turkce taslagi onayli kayitlari kabul eder.
Incelenen MedlinePlus kaynaklarindan yuz seksen bir benzersiz test yayinlanmistir.
WHO, T.C. Saglik Bakanligi ve Turk Klinik Biyokimya Dernegi resmi kaynaklarindan
eklenen kirk bir testle toplam katalog iki yuz yirmi iki teste ve bin uc yuz otuz iki
RAG chunk'ina cikmistir. Seed ve local retrieval ayni onayli citation
metadata'sini kullanir. Yeni `medlineplus_common_*` batch dosyalari loader
tarafindan otomatik bulunur; her paket yine ayri kaynak ve taslak incelemesinden
gecmelidir.

## Yapilandirma

| Degisken | Varsayilan | Aciklama |
|---|---|---|
| `MEDLINEPLUS_BASE_URL` | `https://connect.medlineplus.gov/service` | Connect endpoint'i |
| `MEDLINEPLUS_TIMEOUT_SECONDS` | `20` | Istek zaman asimi |
| `MEDLINEPLUS_CACHE_HOURS` | `24` | En az 12 saatlik yerel cache |

Uygulama import edilirken veya `/chat`/`/explain` cagrilirken MedlinePlus agina
cikilmaz. Servis erisilemezse senkronizasyon kontrollu hata verir; backend ve son
onayli yerel RAG icerigi calismaya devam eder.

## Otomatik testler

`tests/test_medlineplus_source_sync.py` ve `tests/test_source_review_and_drafts.py`
istemci, URL dogrulama, HTML temizleme, checksum, cache, staging, rapor ve iki
asamali review/publish kurallarini fake transport ve gecici SQLite ile test eder.
Normal `pytest` gercek MedlinePlus, Ollama veya ag cagrisi yapmaz.
