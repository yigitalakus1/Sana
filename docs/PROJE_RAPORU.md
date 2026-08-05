# Sana — Proje Raporu

**Tarih:** 27 Temmuz 2026
**Amaç:** Projede ne yapıldığını, hangi teknolojilerin neden seçildiğini ve
ölçülebilir sonuçları tek belgede toplamak. Sonunda 2 dakikalık video için
hazır bir anlatım akışı vardır.

---

## 1. Sana nedir?

Sana, **tıbbi tahlil raporlarını sade Türkçeyle açıklayan** bir sağlık
okuryazarlığı uygulamasıdır. Kullanıcı tahlil raporunu (PDF veya metin) verir;
uygulama değerleri tanır, her birinin ne olduğunu anlatır ve doktora
sorulabilecek soruları önerir.

**En kritik ilke:** Sana bir **teşhis aracı değildir**. Amacı hastanın yerine
karar vermek değil, hastayı doktoruyla daha iyi konuşabilecek hâle getirmektir.
Bu ilke tüm teknik kararların üstündedir.

### Çözülen gerçek problem
Türkiye'de insanlar tahlil sonucunu aldıklarında ilk iş arama motoruna
"CRP yüksekliği ne demek" yazıyor ve karşılarına forum yorumları, reklam içerikli
siteler ve korkutucu senaryolar çıkıyor. Sana bunun yerine **kaynağı belli,
temkinli ve Türkçe** bir açıklama veriyor.

---

## 2. Mimari

```
┌─────────────────────────┐        ┌──────────────────────────────────┐
│   sana-app (Flutter)    │  HTTP  │   sana-rag-backend (FastAPI)     │
│                         │ ─────► │                                  │
│  • Rapor tarama         │        │  normalization → intent →        │
│  • Tahlil sözlüğü       │        │  safety → retrieval →            │
│  • Rapor geçmişi/trend  │        │  confidence → cevap → safety     │
│  • Sağlık profili       │        │                                  │
└─────────────────────────┘        └───────────────┬──────────────────┘
                                                   │
                                   ┌───────────────┴───────────────┐
                                   │  SQLite RAG deposu            │
                                   │  240 belge / 1440 parça       │
                                   └───────────────┬───────────────┘
                                                   │
                                   ┌───────────────┴───────────────┐
                                   │  Ollama · llama3.2:3b (yerel) │
                                   └───────────────────────────────┘
```

Her şey **kullanıcının kendi cihazında/bilgisayarında** çalışır. Buluta veri
gitmez.

---

## 3. Kullanılan teknolojiler ve **neden** seçildiler

| Katman | Teknoloji | Seçilme nedeni |
|---|---|---|
| Mobil/Web arayüz | **Flutter (Dart)** | Tek kod tabanıyla Android, iOS ve web; hızlı arayüz geliştirme |
| Backend | **Python + FastAPI** | Hızlı geliştirme, otomatik API dokümantasyonu (`/docs`), tip doğrulama |
| Veri doğrulama | **Pydantic** | İstek/yanıt sözleşmesini kodda zorunlu kılar |
| Yerel LLM | **Ollama + llama3.2:3b** | İnternet ve API anahtarı gerekmez; sağlık verisi cihazdan çıkmaz |
| Bilgi tabanı | **SQLite + BM25 benzeri lexical retrieval** | Ek servis/bağımlılık yok; deterministik ve denetlenebilir |
| Yerel depolama | **shared_preferences** | Rapor geçmişi, profil ve ayarlar yalnız cihazda |
| Dosya işlemleri | **file_picker** | PDF seçme ve yedek dosyası kaydetme/yükleme |
| Test | **pytest** (backend) · **flutter_test** (uygulama) | 397 + 60 otomatik test |

### Bilinçli olarak KULLANILMAYANLAR (ve nedeni)

- **Ücretli AI API'leri (OpenAI/Azure/Anthropic/Gemini):** Sağlık verisinin üçüncü
  tarafa gitmemesi ve maliyet bağımsızlığı için yasaklandı. Kod içinde bir
  "kill-switch" ile dış AI seçimi engellenebiliyor.
- **Model eğitimi / fine-tuning:** Hazır yerel model + kendi bilgi tabanımız
  (RAG) yeterli; eğitim hem gereksiz hem doğrulanamaz.
- **Kullanıcı hesabı / bulut veritabanı:** Gizlilik avantajını yok eder, KVKK
  yükünü ağırlaştırır ve kullanıcıyı değer görmeden kaydolmaya zorlar.
- **Web scraping:** Kaynaklar yalnız izinli ve resmî kanallardan alınır.

---

## 4. Nasıl çalışıyor? (RAG hattı)

Kullanıcı bir soru sorduğunda cevabı model "uydurmaz"; **onaylı bilgi
tabanından** getirilen metne dayanır:

1. **Normalizasyon** — Türkçe'ye özgü küçük harf dönüşümü (`I→ı`, `İ→i`;
   standart `lower()` Türkçede yanlış sonuç verir)
2. **Niyet tespiti** — soru bir tanım mı, yüksek/düşük yorumu mu, doktor sorusu mu?
3. **Güvenlik ön kontrolü** — ilaç/doz/tedavi isteği ise **retrieval bile
   yapılmadan** bloklanır, model hiç çağrılmaz
4. **Getirme (retrieval)** — SQLite deposundan ilgili belge parçaları
5. **Güven puanı** — eşleşme kalitesi hesaplanır
6. **Cevap** — kaynak metne dayalı üretim
7. **Güvenlik filtresi + kaynak + uyarı** — her cevapta kaynak linki ve
   "teşhis değildir" uyarısı

### Bilgi tabanı
- **240 tahlil belgesi**, her biri 6 bölümlü (Nedir? / Neden ölçülür? / Yüksek /
  Düşük / Ne zaman doktora / Doktora sorulabilecek sorular)
- Kaynaklar: **MedlinePlus** (ABD Ulusal Tıp Kütüphanesi), **WHO Temel İn Vitro
  Tanı Listesi**, **T.C. Sağlık Bakanlığı**, **Türk Klinik Biyokimya Derneği**
- İçerik kopyalanmaz; kaynağa dayanarak Türkçe yazılır ve **yayın öncesi insan
  incelemesinden** geçer (onaylayan adı + tarih zorunlu)

---

## 5. Güvenlik tasarımı (pazarlık konusu değil)

| Kural | Uygulanışı |
|---|---|
| Teşhis konmaz | Tüm içerik temkinli yazılır, her cevapta uyarı |
| İlaç/doz/tedavi önerilmez | `safety_block` — **model çağrılmadan** reddedilir |
| Kaynak uydurulmaz | Cevap yalnız bilgi tabanındaki metne dayanır |
| Pediatrik/acil bağlam | Çocuk doktoruna / acil servise yönlendirme |
| Sonuç sınıflandırması | Referans aralığı yoksa "yüksek/düşük" demez |
| Gizlilik | Uygulamada hiç log yok; sağlık verisi log'a düşmez |

Bu davranışların **hepsi otomatik testlerle sabitlenmiştir** — biri bozulursa
test kırılır.

---

## 6. Bu dönemde yapılan işler

### A. Ürün özellikleri
1. **Rapor etiketi/notu** — Kullanıcı her rapora kendi adını verebiliyor
   ("Mart kontrolü"), dosya adı alt satırda korunuyor.
2. **Rapor tarihini içerikten çıkarma** — Rapor metnindeki *etiketli* tarih
   okunuyor (`Rapor Tarihi: 03.02.2026`). Güvenli kurallar: doğum tarihi
   satırları atlanır, geçersiz/gelecek tarihler reddedilir, etiketsiz sayı
   dizileri tarih sayılmaz. Bulunamazsa dosya adı → kayıt zamanı yedeği.
3. **Birim tutarlılığı uyarısı** — Farklı birimdeki ölçümler **dönüştürülmez**
   (tıbbi dönüşüm tahmin edilmez) ve artık *sessizce atlanmak yerine* kullanıcıya
   açıkça bildirilir.
4. **Rapor geçmişi yedekleme** — JSON olarak dışa aktarma ve geri yükleme.
   Dosya anlık üretilir, uygulama kopya tutmaz, geçici dosyalar temizlenir.
   Geri yükleme **birleştirir**, hiçbir kaydı silmez.
5. **Release öncesi kontroller** — Büyük yazı (2×) ve koyu temada tüm ekranlar
   dar telefonda taşmasız; grafiğe ekran okuyucu desteği eklendi.

### B. Bulunan ve düzeltilen gerçek hatalar

Bunlar tahminle değil, **ölçümle** bulundu:

| # | Hata | Etkisi | Çözüm |
|---|---|---|---|
| 1 | Açıklamada tahlilin tanımı kaybolması | Kullanıcı "bu değer nedir" sorusunun cevabını hiç göremiyordu | Raporun `Yüksek/Düşük` bayrakları soru metnine sızıp bölüm seçimini kaçırıyordu. İki katmanlı düzeltildi |
| 2 | Rapor kimliği çakışması | Arka arkaya eklenen iki rapordan biri **sessizce siliniyordu** | Kimlik üretimi monotonik hâle getirildi |
| 3 | Pencere kapanırken çökme | Rapor adı düzenlenirken uygulama çöküyordu | Controller yaşam döngüsü doğru desene taşındı |
| 4 | Testler arası önbellek sızıntısı | Testler **yanlış yeşil** verebilirdi | Her testten önce önbellek temizleniyor |
| 5 | Ekran taşması | Dar ekranda başlık taşıyordu | Esnek yerleşim |

**1 numaralı hatanın hikâyesi (videoda anlatmaya değer):**
Kullanıcı "bazı değerlerde açıklama gelmiyor" dedi. Önce belgelerden şüphelendim —
240 belgeyi taradım, hepsi sağlamdı. Sonra retrieval'den şüphelendim — 240
tahlili iki ayrı modda taradım, 240/240 doğruydu. Suçlu şuydu: Türk tahlil
raporlarında değer sütununda sık sık **"Yüksek"/"Düşük"** yazar. Uygulama bu ham
metni soruya gömüyordu; backend de bu kelimeleri gördüğü için soruyu "yüksek
yorumu" sanıyor ve tanım bölümünü hiç getirmiyordu.

### C. Performans

Ölçüm yapılmadan iyileştirme yapılmadı.

| Senaryo | Önce | Sonra | Kazanç |
|---|---|---|---|
| Sözlükte bölüm açıklaması | 3454 ms | **157 ms** | **22×** |
| Aynı soruya tekrar bakış | 5164 ms | **149 ms** | **28×** |
| İlk model cevabı | 5164 ms | **4190 ms** | %19 |

Üç değişiklik:
1. **Kaynak metin modu** — Sözlükteki bölüm açıklamaları zaten hazır ve
   onaylı içerik. Modeli çalıştırıp beklemek yerine kaynak metni doğrudan
   sunuluyor. Yan fayda: modelin metinden sapma riski de ortadan kalkıyor.
2. **Cevap önbelleği** — Aynı soru + aynı kaynak için model tekrar çalışmıyor.
   Yalnız bellekte, diske yazılmıyor.
3. **Üretim uzunluğu sınırı** — Cevaplar 2-4 cümle; üst sınır 256→160 token.

---

## 7. Doğrulama (sayılarla)

| Kontrol | Sonuç |
|---|---|
| Backend testleri (pytest) | **397 passed, 2 skipped** |
| Uygulama testleri (flutter test) | **60 passed** |
| Statik analiz (flutter analyze) | **0 sorun** |
| Gerçek yerel model değerlendirmesi | **15/15 başarılı** |
| Web derlemesi | başarılı |

Yerel model değerlendirmesi güvenlik dallarını da kapsıyor: ilaç/doz isteği,
takviye isteği, tanı isteği ve sistem promptu sızıntısı denemelerinin **hepsi
bloklanıyor** ve bu dallarda model hiç çağrılmıyor.

---

## 8. İki dakikalık video için anlatım akışı

**0:00–0:20 — Problem**
> "Tahlil sonucunu alan insan onu anlamıyor ve internette korkutucu içeriklerle
> karşılaşıyor. Sana, tahlil raporunu sade Türkçeyle açıklayan bir uygulama.
> Teşhis koymuyor — amacı kullanıcıyı doktoruyla daha iyi konuşabilir hâle
> getirmek."

**0:20–0:45 — Ne yaptım**
> "Flutter ile mobil uygulamayı, Python FastAPI ile backend'i yazdım.
> Arkasında 240 tahlil belgelik bir bilgi tabanı ve tamamen **yerelde çalışan**
> bir yapay zekâ modeli var — Ollama üzerinde llama3.2. Hiçbir sağlık verisi
> buluta gitmiyor, hiçbir ücretli API kullanılmıyor."

**0:45–1:10 — Nasıl çalışıyor (ekran kaydı: PDF tara → sonuç → sözlük)**
> "Kullanıcı raporunu veriyor, uygulama değerleri tanıyor. Cevaplar modelin
> hayal gücünden değil, kaynağı belli bir bilgi tabanından geliyor —
> MedlinePlus, Dünya Sağlık Örgütü ve Sağlık Bakanlığı kaynakları. Her cevapta
> kaynak linki ve 'teşhis değildir' uyarısı var."

**1:10–1:35 — Güvenlik (ekran: ilaç sorusu sor → bloklanıyor)**
> "En çok üzerinde durduğum kısım güvenlik. İlaç, doz veya tedavi sorulduğunda
> sistem yapay zekâyı **hiç çalıştırmadan** reddediyor. Bu davranışların hepsi
> otomatik testlerle kilitli: toplam 457 test var."

**1:35–2:00 — Ölçüm ve sonuç**
> "Geliştirirken tahminle değil ölçümle ilerledim. Bekleme süresini ölçtüm,
> 3.5 saniyeydi; hazır ve onaylı içerikte modeli hiç çağırmayarak bunu
> **157 milisaniyeye** indirdim — 22 kat hızlanma. Ayrıca ölçüm sırasında
> iki rapor arka arkaya eklendiğinde birinin sessizce silindiği gerçek bir veri
> kaybı hatası buldum ve düzelttim."

### Videoda vurgulanması gereken 3 cümle
1. **"Tamamen yerel çalışıyor — sağlık verisi cihazdan çıkmıyor."**
2. **"Model uydurmuyor; kaynağı belli bir bilgi tabanından cevap veriyor."**
3. **"İlaç/doz sorularında yapay zekâ hiç çalıştırılmıyor."**

### Ekran kaydı çekim listesi
1. Ana ekran → **Rapor Tara** → PDF/metin ver → tanınan değerler listesi
2. Bir değere dokun → açıklama + **MedlinePlus kaynak linki** + uyarı kutusu
3. **Tahlil Sözlüğü** → bir terim → bölümler anında açılıyor (hız göstergesi)
4. **Asistan** → "hangi ilacı kullanmalıyım?" → güvenlik reddi
5. **Rapor Geçmişi** → iki raporu seç → karşılaştırma grafiği
6. Terminal → `pytest` çıktısı (397 passed) — teknik ciddiyet göstergesi

---

## 9. Sıradaki işler

- Gerçek Android cihazda uçtan uca duman testi (fiziksel cihaz gerekiyor)
- Bilgi tabanını genişletme (öncelik: yaygın panellerdeki eksik testler)
- Premium/abonelik katmanı (bilinçli olarak en sona bırakıldı)
- Sözlüğün herkese açık web sürümü (organik erişim için en yüksek kaldıraç)
