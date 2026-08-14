# Sana

Sana tamamen ücretsizdir; hesap, profil veya abonelik gerektirmez. Rapor
geçmişi ve karşılaştırma dahil tüm uygulama özellikleri herkese açıktır.

**Sana**, Flutter istemcisi ve FastAPI tıbbi açıklama backend'inden oluşan bir
sağlık okuryazarlığı uygulamasıdır.
Tahlil değerleri hakkında **Türkçe, kaynak gösterimli, güven skorlu ve teşhis koymayan**
açıklamalar üretir.

> ⚠️ Bu sistem bir teşhis aracı değildir. Amacı, kullanıcının sağlık okuryazarlığını
> artırmak ve doktoruna daha bilinçli sorular sormasına yardımcı olmaktır.

## Tanıtım videosu hakkında

Tanıtım videosu projenin **daha erken bir sürümünü** anlatır. Videodan sonra
rapor okuma tamamen cihaza taşındı; anlatılan temel ilkeler (teşhis koymama,
kaynak gösterme, ücretli dış AI kullanmama, 240 tahlilin çevrimdışı çalışması)
değişmedi.

| Videodaki sürüm | Bugünkü depo |
|---|---|
| PDF metni backend'de çıkarılıyordu | **Cihazda** çıkarılıyor, backend çağrılmıyor |
| Kamera/OCR yoktu | Kamera ve galeriden **cihaz üzerinde OCR** (ML Kit, model uygulamaya gömülü) |
| Ayrıştırılan değerler doğrudan kaydediliyordu | Önce **düzeltme/onay ekranı**; kullanıcı onaylamadan kayıt yok |
| Sürekli entegrasyon yoktu | Her push'ta backend + uygulama testleri otomatik koşuyor |

Videodaki sürüm **[`video-demo`](https://github.com/yigitalakus1/Sana/tree/video-demo)**
etiketiyle işaretlidir (`751e036`, 5 Ağustos 2026); yukarıdaki değişikliklerin
hepsi bu noktadan sonra geldi. Tam o hâli görmek için:
`git checkout video-demo`.

## Neden farklı: her şey cihazda çalışır

Sağlık verisi hassastır, bu yüzden **ücretli dış AI API'si kullanılmaz** (OpenAI,
Azure OpenAI, Anthropic, Gemini) ve API anahtarı gerekmez. Metin üretimi
[Microsoft Foundry Local](https://learn.microsoft.com/azure/ai-foundry/foundry-local/)
veya Ollama ile **cihaz üzerinde** yapılır.

Foundry Local OpenAI-uyumlu bir uç nokta sunduğu için, ileride Azure OpenAI'a
geçiş bir yapılandırma değişikliğidir; yeniden yazım değil.

Mobil uygulamada raporun telefondan hiç çıkmaz:

| İşlem | Nerede |
|---|---|
| 240 tahlil sözlüğü ve bölüm açıklamaları | cihazda (uygulamayla paketli) |
| PDF metin çıkarma | cihazda |
| Kamera/galeri OCR (ML Kit, Latin modeli APK'da gömülü) | cihazda |
| Tahlil eşleştirme, birim ve referans aralığı ayrıştırma | cihazda |
| Rapor geçmişi, trend grafiği, PDF özeti, ilaç hatırlatıcı | cihazda |
| Sana Asistan (kontrollü sohbet) | **tek internet gerektiren özellik** |

Uçak modunda Asistan dışındaki her şey çalışır; bu bir iddia değil,
`sana-app/test/offline_privacy_test.dart` içinde her ağ çağrısında fırlatan
sahte istemciyle doğrulanmış bir davranıştır.

## Mobil uygulama (sana-app)
- PDF yükle, kamerayla tara, galeriden seç veya metin yapıştır
- Ayrıştırılan değerler **kaydedilmeden önce** düzeltme/onay ekranından geçer
- Tanınmayan satırlar sessizce atlanmaz, kullanıcıya listelenir
- Rapor geçmişi, aynı tahlil için trend grafiği ve karşılaştırma
- Doktora gösterilebilecek PDF rapor özeti
- İlaç/ölçüm hatırlatıcısı (günlük veya N saatte bir yerel bildirim)
- Açık/koyu tema, Türkçe arayüz, 24 saat gösterim

## Backend (sana-rag-backend)
- 240 tahlil değeri için Türkçe seed içerik ve kaynak bağlantıları
- Sorgu normalizasyonu (Türkçe `I`/`İ` duyarlı), eş anlamlı haritası
- Keyword + exact-match retrieval; `SANA_RAG_MODE=local` ile SQLite + BM25-benzeri
- Provider seam: `dummy` (varsayılan) · `foundry_local` · `ollama` · `openai_compatible`
- Güven skoru (confidence) + etiket, yalnız retrieval'dan gelen citation
- Safety katmanı: ilaç/doz, teşhis, tedavi, pediatrik, acil, doktordan kaçınma
- `GET /health`, `POST /explain`, `POST /query` (deprecated), `POST /chat`, `GET /terms`, `POST /reports/parse`

## Güvenlik yaklaşımı (Responsible AI)

| İlke | Uygulaması |
|---|---|
| Güvenilirlik | İlaç/doz sorusunda **retrieval bile yapılmaz**, LLM hiç çağrılmaz |
| Şeffaflık | Her cevapta kaynak, güven skoru ve sorumluluk reddi |
| Gizlilik | Sağlık verisi cihazda işlenir, API anahtarı yoktur |
| Hesap verebilirlik | Kaynak yoksa kaynak uydurulmaz; referans aralığı yoksa sınıflandırma yapılmaz |

`safety_block` ve `no_results` durumlarında sağlayıcının çağrılmadığı testle
sabittir (`test_safety_block_does_not_call_provider`).

## Hızlı başlangıç (Windows)

Ön koşullar: Python 3.11+, Flutter ve Ollama bilgisayarda kurulu olmalıdır.
Depoyu GitHub'dan ilk kez indirdikten sonra şunu çalıştırın:

```bat
Kurulum.cmd
```

Kurulum betiği backend sanal ortamını ve Flutter paketlerini hazırlar, yerel
`llama3.2:3b` modelini gerekirse indirir, RAG veritabanını oluşturur ve
masaüstünde **Sana** kısayolunu hazırlar. Model ve paketlerin ilk kurulumu için
internet bağlantısı gerekir.

Sonraki kullanımlarda masaüstündeki **Sana** kısayoluna çift tıklayın. Servisler
başlar ve tarayıcı açılır; pencerede bir tuşa basınca hepsi düzgünce durur.

Kısayol istemiyorsan doğrudan da çalıştırabilirsin:

```bat
Sana Baslat.cmd     :: başlat (tarayıcıyı da açar)
status_local.cmd    :: durum
stop_local.cmd      :: durdur
```

> Kısayol dosyasının kendisi (`.lnk`) mutlak yol içerdiği için depoda
> tutulmaz; her bilgisayarda `Kisayol Olustur.cmd` ile üretilir.

## Manuel backend kurulumu
```bash
cd sana-rag-backend
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

Backend (`sana-rag-backend/`):
```bash
pytest
```

Mobil uygulama (`sana-app/`):
```bash
flutter analyze && flutter test
```

Toplam **571 test**: 398 backend (+2 opsiyonel Foundry smoke) ve 173 Flutter.
Hiçbir test gerçek ağa, Ollama'ya veya harici OCR servisine çıkmaz.

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
tests/                     # 398 geçen pytest testi + 2 opsiyonel Foundry smoke testi
```

## Sıradaki işler
- Fiziksel Android cihazda uçtan uca doğrulama (PDF seçme, kamera, bildirimler)
- Tanınmayan satırlar için satır bazında güven işaretlemesi
- Release APK'da `--split-per-abi` (ML Kit native kütüphaneleri boyutu büyütüyor)
- Hekim gözden geçirmesi ve MedlinePlus bağlantılarının doğrulanması

## Not
Tüm tıbbi seed içerik kasıtlı olarak genel ve temkinlidir; üretime alınmadan önce bir hekim
tarafından gözden geçirilmesi önerilir. MedlinePlus URL'leri doğrulanmalıdır.
