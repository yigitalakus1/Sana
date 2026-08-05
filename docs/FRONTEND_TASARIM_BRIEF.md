# Sana — Mobil Uygulama Frontend Tasarım Brief'i

Bu belge bir tasarımcıya (veya tasarım üreten bir yapay zekâ aracına) olduğu
gibi verilebilir. Uygulamanın **ne olduğunu**, **bugün nelerin var olduğunu** ve
**neyin tasarlanması gerektiğini** anlatır.

---

## 1. Ürün özeti

**Sana**, tıbbi tahlil raporlarını **sade Türkçeyle** açıklayan bir sağlık
okuryazarlığı uygulamasıdır. Kullanıcı tahlil raporunu (PDF veya metin) verir;
uygulama değerleri tanır, her birinin ne olduğunu anlatır, kaynağını gösterir ve
doktora sorulabilecek soruları önerir.

### Pazarlık konusu olmayan ilke
> **Sana bir teşhis aracı DEĞİLDİR.**
> Amacı hastanın yerine karar vermek değil, hastayı doktoruyla daha iyi
> konuşabilecek hâle getirmektir.

Bu ilke tüm tasarım kararlarının üstündedir. Tasarım, kullanıcıyı "sonucu
öğrendim, tamam" hissine değil, **"doktoruma şunu soracağım"** hissine
götürmelidir.

### Ek özellik
Tüm yapay zekâ ve bilgi tabanı **kullanıcının kendi cihazında/bilgisayarında**
çalışır. Sağlık verisi buluta gitmez. Bu, tasarımda görünür bir **güven sinyali**
olarak kullanılmalıdır.

---

## 2. Kullanıcı ve duygusal bağlam (en kritik bölüm)

**Kullanıcı kim:** Tahlil sonucunu yeni almış, tıp eğitimi olmayan bir kişi.
Yaş aralığı geniş — 20'li yaşlardan 70'li yaşlara. Türkiye'de yaşıyor, Türkçe
kullanıyor. Bir kısmı yaşlı ebeveyni için kullanıyor.

**Hangi anda açıyor:** Elinde bir kâğıt/PDF var, içinde anlamadığı sayılar ve
bazılarının yanında "H", "L", "Yüksek", "Düşük" yazıyor. **Endişeli.** Alternatifi
arama motoruna yazmak ve korkutucu forum içerikleriyle karşılaşmak.

**Bu yüzden tasarımın işi:** Endişeyi büyütmeden bilgilendirmek.

| Yap | Yapma |
|---|---|
| Sakin, nefes alan yerleşim | Kırmızı alarm renkleri, ünlem ikonları |
| "Bu değer şu anlama gelebilir" dili | "DİKKAT! ANORMAL!" tonu |
| Kaynağı görünür kılmak | Kaynağı dipnota gömmek |
| Doktora soru önerilerini öne çıkarmak | Kullanıcıyı kendi kendine teşhise itmek |
| Referans dışı değeri sakin biçimde işaretlemek | Kızıl renk + titreşim + rozet yığını |

---

## 3. Bugün var olan yapı (yeniden tasarlanacak olan)

Uygulama **çalışır durumda**; bu bir sıfırdan tasarım değil, **görsel olarak
yeniden tasarım** işidir. Bilgi mimarisi büyük ölçüde oturmuş durumda.

### Alt navigasyon — 5 sekme
| Sekme | İşlevi |
|---|---|
| **Ana Sayfa** | Giriş, hızlı eylemler, kısa yönlendirme |
| **Açıkla** | Serbest soru sorma ("CRP nedir?") |
| **Sözlük** | 240 tahlilin alfabetik listesi + arama |
| **Rapor** | PDF/metin tarama → tanınan değerler |
| **Asistan** | Kontrollü sohbet |

Ayrıca: **Rapor Geçmişi**, **Sağlık Profili**, **Ayarlar**, **Güvenlik onayı**
(ilk açılış) ekranları var. Geniş ekranda alt bar yerine yan **NavigationRail**
kullanılıyor (uygulama web'de de çalışıyor).

### Mevcut renk paleti (kodda gerçekte kullanılan)
```
Birincil (teal)        #0B8F83     Birincil yumuşak   #E7F4F2
Birincil koyu          #08665F
Vurgu mavi             #2F6FED     Mavi yumuşak       #EAF0FF
Arka plan              #F6F7F9     Yüzey              #FFFFFF
Metin birincil         #182230     Metin ikincil      #667085
Kenarlık               #D9DEE7     Sessiz yüzey       #F2F4F7
Uyarı zemin            #FFF4E5     Uyarı metin        #8A4B08
```
**Koyu tema mevcut** (arka plan `#101418`, yüzey `#181D23`, birincil `#58C9BC`).

### Durum renkleri (tahlil sonucu göstergesi)
```
Normal  yeşil    #12B76A
Yüksek  kehribar #F79009      ← kırmızı DEĞİL, bilinçli tercih
Düşük   mavi     #2E90FA
```

### Mevcut ölçüler
- Boşluk skalası: 4 · 8 · 12 · 16 · 24 · 32
- Köşe yarıçapı: **8** (küçük/keskin), maks. içerik genişliği 960

### Mevcut bileşenler
`SanaCard`, `StatusChip`, `SectionHeader`, `DisclaimerBox` (uyarı kutusu),
`ErrorBox`, `ResponsiveCenter`, birincil buton.

---

## 4. Tasarlanması istenen ekranlar

Her ekran için **normal / boş / yükleniyor / hata** durumları istenir.

### 4.1 Güvenlik onayı (ilk açılış)
Kullanıcı uygulamayı ilk açtığında "bu bir teşhis aracı değildir" onayı.
Korkutucu bir yasal metin duvarı değil, **güven veren bir karşılama** olmalı.

### 4.2 Ana Sayfa
Kullanıcı ne yapabileceğini 3 saniyede anlamalı. Öne çıkması gerekenler:
"Raporumu tara", "Bir tahlil terimi ara", "Soru sor". Yerel çalışma rozeti.

### 4.3 Rapor Tara — **en önemli akış**
1. Giriş: PDF seç **veya** metin yapıştır (iki mod arası geçiş)
2. Tarama sırasında bekleme durumu
3. **Sonuç listesi:** tanınan tahliller — her satırda ad, ölçülen değer, birim,
   raporun kendi referans aralığı, aralığa göre durum
4. **Satır açılınca:** açıklama metni + **kaynak linki (ör. MedlinePlus)** +
   "teşhis değildir" uyarısı + "Ayrıntılı açıklamayı aç" + "Diğer raporlarla
   karşılaştır"

> ⚠️ Şu an bu ekranda bilgi biraz "form/tablo" gibi duruyor. Asıl tasarım
> zorluğu burada: **sayıları korkutmadan, okunur ve güven veren biçimde**
> sunmak.

### 4.4 Tahlil Sözlüğü + Terim detayı
- Liste: 240 terim, arama çubuğu, alfabetik gruplama
- Detay: **6 bölüm** — Nedir? / Neden ölçülür? / Yüksek ne anlama gelebilir? /
  Düşük ne anlama gelebilir? / Ne zaman doktora danışılmalı? / Doktora
  sorulabilecek sorular
- Bölümler açılır-kapanır; içerik **anında** geliyor (~150 ms), bu hız
  hissedilmeli

### 4.5 Sonuç Açıkla (serbest soru)
Soru girişi + cevap kartı. Cevapta: metin, **kaynak**, güven düzeyi, uyarı.

### 4.6 Asistan (sohbet)
Kontrollü sohbet. Cevap ~3-4 saniye sürebilir → **iyi bir bekleme durumu**
gerekiyor. **Güvenlik reddi durumu ayrıca tasarlanmalı:** kullanıcı ilaç/doz
sorduğunda uygulama cevap vermez. Bu ret ekranı **kullanıcıyı azarlamamalı**;
"bunu söyleyemem ama doktorunuza şunu sorabilirsiniz" tonunda olmalı.

### 4.7 Rapor Geçmişi + Karşılaştırma
- Kayıtlı raporlar listesi (kullanıcı her rapora **kendi adını** verebiliyor —
  ör. "Mart kontrolü"; dosya adı alt satırda korunuyor)
- Raporları seçip **zaman içindeki değişim grafiği**
- Farklı birimdeki ölçümler **birleştirilmez**; bunun kullanıcıya sakin bir
  bilgi notuyla söylenmesi gerekiyor
- Silme onayı, tüm geçmişi temizleme

### 4.8 Sağlık Profili
İsteğe bağlı yaş + biyolojik cinsiyet. **"Bu bilgiler yalnızca bu cihazda
kalır"** mesajı görünür olmalı.

### 4.9 Ayarlar
Koyu tema, büyük yazı, **rapor geçmişi yedeği (dışa aktar / geri yükle)**,
gizlilik bilgileri.

---

## 5. Zorunlu tasarım kısıtları

1. **Her sonuç/açıklama ekranında "teşhis değildir" uyarısı görünür olmalı.**
   Tasarım zorluğu: tekrar ede ede görünmez hâle gelmemeli ama korkutmamalı da.
2. **Kaynak her zaman görünür.** (MedlinePlus, WHO, Sağlık Bakanlığı, TKBD)
   Bu, ürünün forum içeriğinden farkını gösteren ana güven sinyali.
3. **Büyük yazı desteği zorunlu.** Ekranlar 2× yazı ölçeğinde taşmadan
   çalışmalı — yaşlı kullanıcı gerçek bir kitle.
4. **Koyu tema zorunlu.**
5. **Türkçe metin İngilizceden ~%20 uzundur.** Sabit genişlikli etiketler ve
   dar butonlar tasarlamayın; "Ne zaman doktora danışılmalı?" gibi uzun başlıklar
   var.
6. **Erişilebilirlik:** WCAG AA kontrast; grafik gibi görsel öğelerin metin
   karşılığı olmalı.
7. **Sayısal referans aralığı üretilmez.** Tasarım, olmayan bir "normal aralık
   çubuğu" varsayamaz — rapor kendi aralığını vermediyse gösterilecek aralık
   yoktur.
8. **Kırmızı kullanmayın.** Yüksek değer kehribar, düşük değer mavidir.

---

## 6. Karar bekleyen konular (tasarımcı öneri getirsin)

1. **Yazı tipi:** Uygulama şu an sistem yazı tipini kullanıyor. Bir marka yazı
   tipi (ör. Plus Jakarta Sans / Inter) önerilmesi bekleniyor — **tam Türkçe
   karakter desteği zorunlu** (ğ, ü, ş, İ, ı, ö, ç).
2. **Köşe yarıçapı:** Şu an 8 (keskin/kurumsal). Daha yumuşak (12–16) bir dil
   ürünün "sakin" tonuna daha uygun olabilir — öneri bekleniyor.
3. **Marka kimliği:** Logo/ikon yok. Sağlık + güven + sadelik.
4. **Boş durum görselleri:** İllüstrasyon mu, ikon mu?
5. **Değer gösterimi:** Sayıyı öne çıkaran kart mı, satır listesi mi?

---

## 7. Beklenen çıktılar

1. Tasarım sistemi: renk (açık + koyu), tipografi skalası, boşluk, yarıçap,
   gölge, ikon dili
2. Bileşen kütüphanesi: kart, buton, giriş alanı, çip/rozet, uyarı kutusu,
   liste öğesi, sekme barı, boş/hata/yükleniyor durumları
3. Yukarıdaki 9 ekranın **açık ve koyu** tasarımı
4. En az bir ekranın **2× büyük yazı** hâli
5. Akış prototipi: PDF tara → sonuç → değer detayı → sözlük terimi
6. Geliştiriciye teslim: renk kodları, ölçüler, durum listeleri
   (uygulama **Flutter / Material 3** ile yazılıyor — Material bileşenleriyle
   uyumlu, hayata geçirilebilir tasarım isteniyor)

---

## 8. Tek cümlelik yönlendirme

> Tahlil sonucunu eline almış endişeli bir insanın, sayıların ne olduğunu sakin
> biçimde anlayıp **doktoruna soracağı soruyla** uygulamadan çıkmasını sağlayan;
> kaynağını her zaman gösteren, kırmızıya kaçmayan, büyük yazıda da çalışan bir
> arayüz tasarla.
