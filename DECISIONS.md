# Sana — Kilitlenmiş Mimari Kararları (DECISIONS)

**Durum: DONDURULDU.** Bu belge tüm mimari kararların tek kaynağıdır. Koda geçerken referans budur.
Yeni özellik/karar eklenmez, mevcut karar çıkarılmaz — kapsam değişikliği ayrı bir revizyon gerektirir.
Daha geniş anlatım için `Architecture.md`'ye, Claude Code yönlendirmesi için `CLAUDE.md`'ye bakılır.

---

## 0. Temel ilke
Sana, laboratuvar değerlerini **sade Türkçeyle** açıklayan bir sağlık okuryazarlığı uygulamasıdır.
**Tanı koymaz, tedavi/ilaç/doz önermez, doktor yerine geçmez.** Güvenlik ve kaynak gösterimi her özelliğin önündedir.

## 1. Kapsam — 5 değer (kilitli)
CRP · Glukoz · Ferritin · B12 · Hemoglobin. Başka değer MVP'ye eklenmez.

Her değer için 6 section: *Nedir? · Neden ölçülür? · Yüksek ne anlama gelebilir? · Düşük ne anlama gelebilir? · Ne zaman doktora danışılmalı? · Doktora sorulabilecek sorular.*

## 2. İki giriş yolu, tek açıklama motoru (kilitli)
- **PDF yolu:** kullanıcı tahlil PDF'i yükler → backend metni çıkarır → desteklenen değerler tespit edilir → Flutter'a tıklanabilir liste → değere tıklanınca açıklama.
- **Serbest soru yolu:** kullanıcı "kan şekeri nedir?" yazar → backend terimi eşler (lab_test zorunlu değil) → açıklama.
- **Kritik karar:** PDF, RAG çekirdeğinden **ayrıdır**. Serbest soru yolu PDF'ten bağımsız çalışır; PDF aksasa bile çekirdek RAG demosu ayakta kalır.

## 3. Backend yapısı (kilitli)
- **Stateless.** Kullanıcı verisi/rapor geçmişi DB'ye yazılmaz. Flutter, parse edilen context'i tutar ve `/explain`'e geri gönderir.
- **SQLite yalnızca** knowledge chunk + embedding deposu içindir. Başka veri tutmaz.
- **Temel:** mevcut `sana-rag-backend` (25 test geçiyor) genişletilir; yeniden yazılmaz. Üstüne eklenen: embedding katmanı + SQLite vektör deposu + PDF parser + provider seam + result_context + `/terms`.
- Akış sabit bir pipeline'dır, **autonomous agent yok**: `parse_pdf → detect_lab_values → retrieve_chunks → generate_explanation → safety_check`. Bu fonksiyonlar ileride agent tool'u olabilecek şekilde modüler yazılır ama MVP'de agent değildir.

## 4. RAG pipeline (kilitli — gerçek Local RAG)
1. Sorgu/context'ten retrieval sorgusu kur.
2. Foundry Local **embedding** ile query embedding üret.
3. SQLite'taki chunk embedding'leri arasında **brute-force cosine similarity**, **top-k = 2–3**.
4. Getirilen chunk'lar + result_context → Foundry Local **chat** modeline context olarak verilir.
5. LLM sade Türkçe, kaynaklı, tanı koymayan açıklama üretir.
6. Safety layer cevabı denetler.
7. Hata / güvenlik takılması / zayıf retrieval → **seed fallback** veya `no_results`.

## 5. Endpointler (kilitli)
- `GET /health` — sağlık kontrolü.
- `POST /reports/parse` — PDF al, metni çıkar, değerleri tespit et, liste JSON döndür.
- `POST /explain` — serbest soru veya seçilen lab_test + result_context al, açıklama döndür.
- `GET /terms` — desteklenen değerleri/terimleri listele.
- `GET /terms/{term_id}` — tek terim detayı.

## 6. Veri modelleri (kilitli)

**PDF parse çıktısı (her değer):**
```json
{
  "raw_name": "C-Reaktif Protein",
  "lab_test": "CRP",
  "result_value": 13.5,
  "unit": "mg/L",
  "reference_range": "0-5",
  "status": "high",
  "explainable": true,
  "extraction_confidence": 0.9,
  "raw_line": "C-Reaktif Protein 13.5 mg/L Referans: 0-5"
}
```
İsimlendirme: `lab_test` = hangi test · `result_value` = sonuç · `unit` = birim · `reference_range` = referans aralığı · `status` ∈ {low, normal, high, unknown} · `extraction_confidence` = PDF çıkarım güveni. ("lab_value" kullanılmaz — value sayısal sonucu çağrıştırır.)

**Knowledge chunk (SQLite):**
```json
{ "chunk_id": "...", "lab_test": "CRP", "section": "Nedir?", "content": "...", "source_title": "MedlinePlus", "source_url": "...", "embedding": [] }
```

**/explain isteği:**
```json
{
  "question": "Bu laboratuvar değeri ne işe yarar?",
  "lab_test": "CRP",
  "result_value": 13.5, "unit": "mg/L", "reference_range": "0-5", "status": "high",
  "options": { "language": "tr", "include_sources": true, "include_doctor_questions": true }
}
```

**/explain yanıtı:**
```json
{
  "response_type": "answer",
  "matched_term": "CRP",
  "normalized_query": "CRP",
  "answer": "...",
  "confidence": 0.88,
  "citations": [],
  "safety_notes": [],
  "doctor_questions": [],
  "disclaimer": "Bu açıklama tanı veya tedavi önerisi değildir.",
  "result_context": { "result_value": 13.5, "unit": "mg/L", "reference_range": "0-5", "status": "high" },
  "retrieved_chunks": [ { "section": "Nedir?", "source_title": "MedlinePlus", "score": 0.91 } ],
  "llm_provider": "foundry_local"
}
```
`response_type` ∈ { `answer`, `no_results`, `safety_block`, `error` } — korunur. `no_results` ve `safety_block` HTTP 200; doğrulama/dil hataları HTTP 400. `retrieved_chunks` chunk_id içermez, top-k ile sınırlıdır.

## 7. LLM provider stratejisi (kilitli)
- Birincil: **`foundry_local`** (offline, on-device) — yaz okulu yıldızı.
- Güvenlik ağı: **`seed_fallback`** (deterministik, önceden onaylı seed metni) — LLM düşerse/yavaşsa/filtreden geçemezse devreye girer.
- **`azure_openai` ertelendi:** MVP'de kurulmaz; "aynı interface ile buluta ölçeklenir" diye gelecek genişleme olarak anlatılır. Offline hikâyesi öne çıkarılır.
- Provider seam dar: `explain(term, context, result_context) -> str`. Safety ve grounding provider'ın dışındadır, her provider'a uygulanır. Her çağrı timeout + try/except ile sarılır; hata → seed fallback. `llm_provider` alanı kimin cevapladığını döndürür.
- **Foundry modelleri:** embedding `qwen3-embedding-0.6b`, chat `Phi-3.5 Mini`. **Türkçe kalitesi erken test edilir**; zayıfsa seed_fallback devrede kalır.

## 8. PDF parser (kilitli)
- Yalnızca **metin tabanlı PDF**. Taranmış PDF / fotoğraf / kamera OCR sonraki faz.
- **Demo PDF formatı sabitlenir**, parser ona göre kısıtlanır.
- Parser emin değilse **tahmin etmez**: `explainable=false` veya `status="unknown"` döndürür, "PDF okunamadı" ekranına nazikçe düşer.
- `status` **parser tarafından deterministik** hesaplanır (result_value ↔ reference_range). LLM asla status hesaplamaz. reference_range ayrıştırılamazsa `status="unknown"`.
- MVP'de test başına **tek birim** varsayılır.
- Bu, projenin en büyük riski olarak ele alınır; çekirdek RAG buna bağımlı değildir.

## 9. Confidence (kilitli)
Bileşenler: lab_test exact +0.35 · synonym +0.20 · keyword overlap +0.20 · source exists +0.15 · intent–section +0.10.
Eşikler: **0.71–1.00 high · 0.41–0.70 medium · 0.00–0.40 low.**
Sert kurallar: retrieval yoksa 0.0 · kaynak yoksa high olamaz · safety_block → 0.0/low.

## 10. Citation (kilitli)
Yalnızca retrieval'dan gelen kaynaklar gösterilir; model kaynak uyduramaz. Aynı URL dedup edilir. `chunk_id` public yanıtta yer almaz (yalnız log). Kaynak alanları: title/source_title, url, source, score.

## 11. Safety (kilitli — pazarlık yok)
İki aşamalı: (a) üretim öncesi blok — ilaç/doz, takviye, doktordan kaçınma, teşhis isteği → **retrieval yapmadan** güvenli cevap (`safety_block`); (b) üretim sonrası filtre — çıktıda teşhis iddiası, ilaç/doz, "doktora gerek yok", kesinlik taranır.
Ek kurallar: `status`'u parser hesaplar (LLM değil) · **panik/kritik değer** kontrolü deterministik (parse edilen sayı test-bazlı eşiği aşarsa acil yönlendirme öne eklenir, LLM'e bağlı değil) · grounding prompt sayıyı teşhis olarak yorumlamayı yasaklar ("referans aralığının üstünde görünüyor" + "tek başına tanı koydurmaz") · post-filter tetiklenirse LLM metni gösterilmez, **seed'e düşülür** · pediatrik (yaş < 14 veya çocuk/bebek) → çocuk doktoruna yönlendir, yaşa özel aralık verme · her cevapta disclaimer · kaynak yoksa uydurma. **Emin değilsen her zaman önceden-onaylı seed'e dön.**

## 12. Türkçe teknik kurallar (kilitli)
- Küçük harf: `I → ı`, `İ → i` (standart `.lower()` yanlış yapar).
- Pattern yazarken ünsüz yumuşaması: kök desen kullan ("antibiyotik" → "antibiyotiği" için "antibiyot").

## 13. Veri kaynağı (kilitli)
Manuel Türkçe seed + MedlinePlus kaynak linkleri (MVP). NHS UK sonraki faz (OGL v3.0, atıfla). **LabTestsOnline/Testing.com hariç** (scraping yasak). Forum/kullanıcı içeriği yok. Tüm seed kasıtlı genel/temkinli; üretim öncesi hekim gözden geçirir; URL'ler doğrulanır.

## 14. MVP'de olacaklar
Flutter uygulaması · PDF yükleme + metin tabanlı okuma · 5 değer tespiti · tıklanabilir liste · Foundry Local embeddings · SQLite vektör deposu · top-k retrieval · Foundry Local chat ile açıklama · RAG-lite/controlled grounding · citation metadata · safety layer · seed fallback · serbest soru yolu · demo PDF ile uçtan uca stabil akış.

## 15. MVP'de olmayacaklar
Auth/hesap · rapor geçmişi · kullanıcı verisi DB · admin/doktor paneli · tüm lab değerleri · fotoğraf/kamera OCR · taranmış PDF · ilaç önerisi · tanı/hastalık tahmini · fine-tuning · sıfırdan model eğitimi · autonomous agent · canlı kaynak scraping · Azure (MVP'de; gelecek genişleme).

## 16. 4 haftalık plan (yaz okulu fazlarıyla hizalı)
- **Hafta 1:** Foundry Local kurulum + Türkçe model testi · SQLite şema · seed chunk'ları + embedding üretimi.
- **Hafta 2:** retrieval pipeline (embed → top-k cosine) · `/explain` serbest soru yolu · safety + confidence + citation (mevcut backend üstüne).
- **Hafta 3:** PDF parser (metin) + `/reports/parse` · Flutter entegrasyonu · uçtan uca akış.
- **Hafta 4:** demo PDF sabitleme + 5 kez hatasız test · README · mimari diyagram · Responsible AI · 5 dk sunum · GitHub.

---

**Kilit özeti:** 5 değer · iki giriş/tek motor · stateless · SQLite sadece bilgi tabanı · Foundry Local (primary) + seed_fallback · Azure ertelendi · gerçek RAG (embedding + top-k) · PDF çekirdekten ayrı + parser status'u hesaplar · iki aşamalı safety + seed fallback · response_type zarfı · agent yok · mevcut backend genişletilir.
