# Sana — Flutter Entegrasyon Sözleşmesi

Bu belge, Flutter uygulamasının `sana-rag-backend` ile nasıl konuşacağını tanımlar.
Tam HTTP sözleşmesi için `API_CONTRACT.md`'ye bakın. Bu belge yalnız **sözleşme/akış**
tanımıdır; Flutter kodu içermez.

## Ana ilkeler
- **Ana açıklama endpoint'i `POST /explain`'dir.** Flutter `MlDictionaryService` bunu çağırır.
- **`POST /query` deprecated'dir** — `/explain` ile birebir aynıdır, yalnız geriye
  uyumluluk için durur. Yeni Flutter kodu `/query` kullanmamalıdır.
- İstemci önce `response_type`'a göre dallanmalı, sonra `confidence_label`'a güvenmeli
  (eşik hesaplamamalı). `disclaimer` her ekranda gösterilmelidir.

## Endpoint kullanımı
| Ekran / İhtiyaç | Endpoint |
|---|---|
| Açıklama (serbest soru veya seçilen test) | `POST /explain` |
| Lab sözlüğü — desteklenen testler listesi | `GET /terms` |
| Lab sözlüğü — tek terim detayı | `GET /terms/{lab_test}` |
| Rapor metnini değerlere ayırma | `POST /reports/parse` |
| Sağlık kontrolü | `GET /health` |

## Önerilen "rapor → açıklama" akışı
1. Kullanıcı rapor metnini girer (ileride OCR'dan gelen metin de aynı yere beslenebilir;
   **OCR şu an backend'de yok**, metni Flutter sağlar).
2. Flutter `POST /reports/parse` çağırır → `{ parser_status, results[], disclaimer }`.
3. Kullanıcı dönen `results` içinden bir testi seçer (örn. CRP 13.5 mg/L).
4. Flutter `POST /explain` çağırır. Seçilen testin değerleri soruya/alanlara taşınabilir
   (örn. `question: "CRP 13.5 çıktı"`, `lab_test: "CRP"`).
5. UI'da şunlar gösterilir:
   - `answer` (sade açıklama)
   - `result_context` (girilen değer bağlamı; **yorum yok**)
   - `citations` (kaynaklar: `source_title` + `source_url`)
   - `doctor_questions` (doktora sorulabilecek sorular)
   - `disclaimer` (her zaman)

> Not: Bu sürümde `/reports/parse` sonucu **otomatik `/explain` çağırmaz**; iki adım
> ayrıdır. Test seçimi kullanıcıdadır.

## Lab sözlüğü akışı
1. `GET /terms` → kart listesi (`lab_test`, `title`, `sections`).
2. Karta tıklanınca `GET /terms/{lab_test}` → detay (`sections`, `sources`).
3. Path değeri kullanıcı dostu olabilir: `CRP`, `crp`, `C reaktif protein` hepsi `CRP`'ye
   çözülür. Bilinmeyen değer → **404** (Flutter "bulunamadı" durumu göstermeli).

## Hata ve durum yönetimi
- `response_type == "safety_block"` → açıklama yerine güvenli yönlendirme mesajı gösterilir.
- `response_type == "no_results"` → kaynak bulunamadı mesajı; `citations` boş olur.
- HTTP 400 (boş soru / desteklenmeyen dil / boş rapor metni) → Flutter doğrulama mesajı.
- HTTP 404 (`/terms/{lab_test}`) → desteklenmeyen test.

## İstemcinin GÜVENMEMESİ gereken alanlar
Public yanıtlarda `chunk_id`, `content`, `score` **yer almaz**; Flutter bu alanlara
bağımlı kod yazmamalıdır.

## Şu an backend'de OLMAYAN (Flutter buna göre planlamalı)
OCR, PDF binary/dosya upload, gerçek LLM, database, auth, embedding, tanı/tedavi önerisi,
"yüksek/düşük/normal" yorumu. Bunlar gelecekte eklenirse sözleşme genişletilir; mevcut
alanlar korunur.
