# Klinik Editoryal Inceleme Sureci

Bu süreç, otomatik kalite kontrolünü klinik uzman onayından ayırır. Kod ve
kaynak denetiminin geçmesi bir metni klinik olarak onaylanmış yapmaz.

## Mevcut durum

- 240 tahlil belgesi otomatik yapı, kaynak alanı, bölüm, alias ve güvenlik
  denetiminden geçmektedir.
- Klinik uzman imzası tamamlanan kayıt sayısı başlangıçta `0`dır.
- Tam kuyruk `reports/clinical_editorial_review_latest.json`, yüksek öncelikli
  özet ise `reports/clinical_editorial_review_latest.md` dosyasındadır.
- 45 nitel ve 57 panel sonucu, sayısal testlerden ayrı editoryal dil kullanır.
- Hizmet listeleme sayfasına dayanan kayıtlar daha doğrudan klinik kaynak
  bulunması için ayrıca işaretlenir.

## Resmi kaynakla doğrulanan temel kurallar

- Referans aralıkları laboratuvara ve yönteme göre değişebilir; uygulama yalnız
  kullanıcının raporunda yazılı aralığı kullanır:
  https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/
- Pozitif, negatif ve belirsiz sonuçlar sayısal yüksek/düşük diliyle aynı şey
  değildir; bazı sonuçlar doğrulama veya tekrar testi gerektirir.
- Reaktif/pozitif HIV tarama sonucu takip testi gerektirir:
  https://www.cdc.gov/hiv/testing/index.html
- Yenidoğan taramasında aralık dışı sonuç tanı değildir ve zamanında takip
  testi gerektirir:
  https://newbornscreening.hrsa.gov/newborn-screening-process/newborn-screening-results-and-follow
- Tümör belirteçleri tek başına kanser tanısı koydurmaz ve diğer testlerle
  birlikte değerlendirilir:
  https://www.cancer.gov/about-cancer/diagnosis-staging/diagnosis/tumor-markers-fact-sheet
- ABO/Rh tiplemesi kan grubu/antijen sınıfını bildirir; pozitif RhD tek başına
  hastalık değildir:
  https://medlineplus.gov/ency/article/003345.htm
- Crossmatch, verici ve alıcı arasındaki transfüzyon uyumluluğunu değerlendirir:
  https://www.fda.gov/regulatory-information/search-fda-guidance-documents/computer-crossmatch-computerized-analysis-compatibility-between-donors-cell-type-and-recipients

## Klinik uzman onayi

Uzman her kayıt için kaynak uygunluğunu, test tanımını, yüksek/düşük veya
pozitif/negatif dilini, takip-aciliyet metnini ve hasta dilindeki anlaşılırlığı
kontrol eder. Onay kaydı `data/clinical_editorial_signoffs.json` içine şu
alanlarla eklenir:

```json
{
  "lab_test": "CRP",
  "status": "approved",
  "reviewer_name": "Ad Soyad",
  "reviewer_credential": "Uzmanlık/unvan",
  "reviewed_at": "YYYY-MM-DD",
  "document_sha256": "rapordaki document_sha256"
}
```

İçerik değiştiğinde checksum değişir ve eski onay otomatik olarak
`stale_or_changes_requested` durumuna düşer. Yeni metin yeniden incelenmeden
klinik onaylı sayılmaz.

## Raporu yenileme

```powershell
cd "C:\d diski\Sana\sana-rag-backend"
.\.venv\Scripts\python.exe tools\clinical_editorial_review.py
```
