# Ek Resmi Laboratuvar Kaynaklari

MedlinePlus kataloguna ek olarak WHO, T.C. Saglik Bakanligi ve Turk Klinik
Biyokimya Dernegi kaynaklari kontrollu bir statik batch ile kullanilir.

## Kaynaklar

- WHO EDL 4: `https://www.who.int/publications/i/item/9789240081093`
- T.C. Saglik Bakanligi Akilci Laboratuvar Kullanimi:
  `https://ankarameslekdh.saglik.gov.tr/TR-367953/akilci-laboratuvar-kullanimi.html`
- Turk Klinik Biyokimya Dernegi Toplum Icin: `https://tkbd.org/toplum-icin`

WHO EDL 4'ten sodyum, potasyum ve fibrinojen; Bakanligin test listesinden on iki
eksik biyokimya testi; TKBD'nin toplum bilgilendirme sayfasindan oral glukoz
tolerans testi ve gestasyonel diyabet tarama testi eklenmistir.

Ikinci batch ile ulusal yenidogan programindan bes tarama kaydi, resmi Bakanlik
laboratuvar listelerinden on ozel hormon veya hormon metaboliti ve WHO ile
Bakanlik transfizyon kaynaklarindan dokuz immunohematoloji testi eklenmistir.

## Inceleme Kapisi

Kaynak kataloglari `data/source_batches/official_labs_01_rag.json` ve
`data/source_batches/official_labs_02_rag.json` dosyalarindadir.
Yayin icin su kosullar zorunludur:

- katalog `review_status=approved`, inceleyen ve inceleme tarihi tasir;
- kaynak URL'si WHO, `saglik.gov.tr` veya TKBD resmi alan adinda HTTPS olur;
- test adi, kaynak anahtari ve dosya slug'i benzersiz olur;
- tanim ve amac bos olamaz;
- sayisal referans araligi, tani veya tedavi onerisi uretilmez.

Yayin komutu:

```powershell
cd C:\D_DİSKİ_2026\Sana\sana-rag-backend
.\.venv\Scripts\python.exe tools\publish_curated_source_batch.py `
  data\source_batches\official_labs_01_rag.json `
  --seed-output data\source_batches\official_labs_01_seed.json
```

Arac altibolumlu Markdown belgelerini `data/medical_docs` altina, calisma zamani
seed verisini ise verilen `--seed-output` yoluna deterministik olarak yazar.
Ikinci batch ayni komutla `official_labs_02_rag.json` ve
`official_labs_02_seed.json` yollari kullanilarak yayinlanir.

## Ag Davranisi

Normal backend baslangici ve `pytest` bu kaynaklara ag cagrisi yapmaz. Resmi
kaynak arastirmasi ve insan incelemesi yayin oncesinde yapilir; uygulama yalniz
onaylanmis yerel batch ve citation metadatasini okur.
