# Sana — Flutter

Sana, laboratuvar sonuçlarını **sade Türkçe** ile açıklayan bir sağlık okuryazarlığı
uygulamasıdır. Bu Flutter istemcisi, `sana-rag-backend` FastAPI servisine bağlanır.

> Bilgilendirme amaçlıdır. **Tanı koymaz, tedavi önermez, "yüksek/düşük/normal" yorumu yapmaz.**

## Backend gereksinimi

Uygulama bir backend'e ihtiyaç duyar. Backend çalışıyor olmalı:

```powershell
cd "C:\d diski\Sana\sana-rag-backend"
.\.venv\Scripts\activate
uvicorn app.main:app --reload
```

Backend varsayılan olarak `http://127.0.0.1:8000` adresinde açılır.

## Flutter çalıştırma

```powershell
cd "C:\d diski\Sana\sana-app"
flutter pub get
flutter analyze
flutter test
flutter run -d chrome     # web
flutter run -d windows    # Windows desktop
```

### Android emulator için base URL

Android emülatörde `localhost`, ana makineyi göstermez; `10.0.2.2` kullanılır:

```powershell
flutter run --dart-define=SANA_API_BASE_URL=http://10.0.2.2:8000
```

Base URL tek yerden yönetilir: `lib/core/config/api_config.dart`
(`SANA_API_BASE_URL`, varsayılan `http://localhost:8000`).

## Kullanılan endpointler

- `GET /health` — sunucu durumu
- `POST /explain` — **ana** açıklama endpoint'i
- `GET /terms` — desteklenen testler
- `GET /terms/{lab_test}` — terim detayı
- `POST /reports/parse` — düz metin rapordan değer çıkarımı

**Kullanılmayan:** `POST /query` (deprecated) — uygulama bunu çağırmaz.

## Medikal sınırlar

- Tanı koymaz.
- Tedavi/ilaç/doz önermez.
- Değerleri "yüksek/düşük/normal" diye yorumlamaz; `interpretation` UI'da gösterilmez.
- Yalnızca bilgilendirme amaçlıdır; her sonuçta disclaimer gösterilir.

## Smoke test (manuel)

Gerçek istemci kodunu canlı backend'e karşı doğrular:

```powershell
dart run tool/smoke_test.dart
```

- Backend **açıkken** beklenen çıktı: `SMOKE_OK`
- Backend **kapalıyken**: dostça bağlantı hatası (`SMOKE_FAIL (friendly): ...`) — uygulama çökmez.

## Proje yapısı

```
lib/
  main.dart
  core/
    config/api_config.dart        # base URL (tek kaynak)
    network/sana_api_client.dart  # http istemci, timeout, hata sarma
  features/ml_dictionary/
    models/                       # explain_response, term_models, report_parse_models
    services/ml_dictionary_service.dart
    widgets/common_widgets.dart   # DisclaimerBox, ErrorBox
    screens/                      # home, explain, terms, term_detail, report_parse
test/widget_test.dart             # model parse testleri
tool/smoke_test.dart              # manuel backend doğrulama (suite dışı)
```

## Bağımlılıklar

- `http`: backend iletişimi
- `file_picker`: rapor dosyası seçimi
- `shared_preferences`: cihaz içi ayarlar, profil ve rapor geçmişi
