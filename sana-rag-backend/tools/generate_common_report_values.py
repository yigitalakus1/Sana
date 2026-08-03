"""Yaygın laboratuvar raporu alt değerleri için onaylı seed/RAG paketi üretir."""

import json
import re
from pathlib import Path


MEDLINEPLUS_RBC = "https://medlineplus.gov/lab-tests/red-blood-cell-rbc-indices/"
MEDLINEPLUS_DIFF = "https://medlineplus.gov/lab-tests/blood-differential/"
MEDLINEPLUS_IRON = "https://medlineplus.gov/lab-tests/iron-tests/"
MEDLINEPLUS_BILIRUBIN = "https://medlineplus.gov/lab-tests/bilirubin-blood-test/"
MEDLINEPLUS_T3 = "https://medlineplus.gov/lab-tests/triiodothyronine-t3-tests/"
MEDLINEPLUS_BUN = "https://medlineplus.gov/lab-tests/bun-blood-urea-nitrogen/"
NIH_CBC = "https://www.ncbi.nlm.nih.gov/books/NBK604207/"


VALUES = [
    {
        "lab_test": "MCH",
        "title": "MCH (Ortalama Eritrosit Hemoglobini)",
        "aliases": ["mch", "mean corpuscular hemoglobin", "ortalama eritrosit hemoglobini"],
        "definition": "MCH, bir kırmızı kan hücresindeki ortalama hemoglobin miktarını gösteren eritrosit indeksidir.",
        "purpose": "Kırmızı kan hücrelerinin özelliklerini değerlendirmek için tam kan sayımının bir parçası olarak ölçülür.",
        "source_title": "MedlinePlus - Red Blood Cell Indices",
        "source_url": MEDLINEPLUS_RBC,
    },
    {
        "lab_test": "MCHC",
        "title": "MCHC (Ortalama Eritrosit Hemoglobin Konsantrasyonu)",
        "aliases": ["mchc", "mean corpuscular hemoglobin concentration", "ortalama eritrosit hemoglobin konsantrasyonu"],
        "definition": "MCHC, kırmızı kan hücrelerindeki ortalama hemoglobin yoğunluğunu gösteren eritrosit indeksidir.",
        "purpose": "Kırmızı kan hücrelerinin hemoglobin içeriğini değerlendirmek için tam kan sayımının bir parçası olarak ölçülür.",
        "source_title": "MedlinePlus - Red Blood Cell Indices",
        "source_url": MEDLINEPLUS_RBC,
    },
    {
        "lab_test": "RDW",
        "title": "RDW (Eritrosit Dağılım Genişliği)",
        "aliases": ["rdw", "rdw cv", "rdw-cv", "rdw sd", "rdw-sd", "red cell distribution width", "eritrosit dağılım genişliği"],
        "definition": "RDW, kırmızı kan hücrelerinin boyutlarının birbirinden ne kadar farklı olduğunu gösteren eritrosit indeksidir.",
        "purpose": "Kırmızı kan hücresi boyut dağılımını değerlendirmek için tam kan sayımının bir parçası olarak ölçülür.",
        "source_title": "MedlinePlus - Red Blood Cell Indices",
        "source_url": MEDLINEPLUS_RBC,
    },
    {
        "lab_test": "Nötrofil",
        "title": "Nötrofil",
        "aliases": ["nötrofil", "notrofil", "neutrophil", "neu", "neut", "neutrofil"],
        "definition": "Nötrofiller, beyaz kan hücrelerinin bir türüdür ve vücudun mikroplara karşı savunmasında görev alır.",
        "purpose": "Beyaz kan hücresi dağılımını değerlendirmek için mutlak sayı veya yüzde olarak ölçülür.",
        "source_title": "MedlinePlus - Blood Differential",
        "source_url": MEDLINEPLUS_DIFF,
    },
    {
        "lab_test": "Lenfosit",
        "title": "Lenfosit",
        "aliases": ["lenfosit", "lymphocyte", "lym", "lymph"],
        "definition": "Lenfositler, bağışıklık yanıtında görev alan beyaz kan hücrelerinin bir türüdür.",
        "purpose": "Beyaz kan hücresi dağılımını değerlendirmek için mutlak sayı veya yüzde olarak ölçülür.",
        "source_title": "MedlinePlus - Blood Differential",
        "source_url": MEDLINEPLUS_DIFF,
    },
    {
        "lab_test": "Monosit",
        "title": "Monosit",
        "aliases": ["monosit", "monocyte", "mono", "mon"],
        "definition": "Monositler, mikropların ve hasarlı hücrelerin temizlenmesine katkı sağlayan beyaz kan hücrelerinin bir türüdür.",
        "purpose": "Beyaz kan hücresi dağılımını değerlendirmek için mutlak sayı veya yüzde olarak ölçülür.",
        "source_title": "MedlinePlus - Blood Differential",
        "source_url": MEDLINEPLUS_DIFF,
    },
    {
        "lab_test": "Eozinofil",
        "title": "Eozinofil",
        "aliases": ["eozinofil", "eosinophil", "eos"],
        "definition": "Eozinofiller, parazitlere karşı savunma, alerjik yanıt ve iltihap süreçlerinde rol alan beyaz kan hücreleridir.",
        "purpose": "Beyaz kan hücresi dağılımını değerlendirmek için mutlak sayı veya yüzde olarak ölçülür.",
        "source_title": "MedlinePlus - Blood Differential",
        "source_url": MEDLINEPLUS_DIFF,
    },
    {
        "lab_test": "Bazofil",
        "title": "Bazofil",
        "aliases": ["bazofil", "basophil", "baso"],
        "definition": "Bazofiller, alerjik yanıtlar ve bağışıklık süreçlerinde rol alan beyaz kan hücrelerinin bir türüdür.",
        "purpose": "Beyaz kan hücresi dağılımını değerlendirmek için mutlak sayı veya yüzde olarak ölçülür.",
        "source_title": "MedlinePlus - Blood Differential",
        "source_url": MEDLINEPLUS_DIFF,
    },
    {
        "lab_test": "PDW",
        "title": "PDW (Trombosit Dağılım Genişliği)",
        "aliases": ["pdw", "platelet distribution width", "trombosit dağılım genişliği"],
        "definition": "PDW, trombositlerin boyutlarının birbirinden ne kadar farklı olduğunu gösteren otomatik kan sayımı indeksidir.",
        "purpose": "Trombositlerle ilgili diğer ölçümleri tamamlayan bir dağılım göstergesi olarak raporlanabilir.",
        "source_title": "NIH NCBI Bookshelf - Complete Blood Count",
        "source_url": NIH_CBC,
    },
    {
        "lab_test": "Plateletkrit",
        "title": "Plateletkrit (PCT)",
        "aliases": ["plateletkrit", "plateletcrit", "trombositkrit", "pct hemogram"],
        "definition": "Plateletkrit, trombositlerin kan hacmi içindeki toplam hacim oranını gösteren otomatik kan sayımı indeksidir.",
        "purpose": "Trombosit sayısı ve hacim göstergeleriyle birlikte değerlendirilebilen bir trombosit indeksi olarak raporlanabilir.",
        "source_title": "NIH NCBI Bookshelf - Complete Blood Count",
        "source_url": NIH_CBC,
    },
    {
        "lab_test": "Total Demir Bağlama Kapasitesi",
        "title": "Total Demir Bağlama Kapasitesi (TDBK/TIBC)",
        "aliases": ["total demir bağlama kapasitesi", "tdbk", "tibc", "tıbc", "total iron binding capacity"],
        "definition": "Total demir bağlama kapasitesi, demirin transferrin ve diğer proteinlere bağlanabilme kapasitesini değerlendiren demir testidir.",
        "purpose": "Vücudun demir durumunu diğer demir testleriyle birlikte değerlendirmeye yardımcı olmak için ölçülür.",
        "source_title": "MedlinePlus - Iron Tests",
        "source_url": MEDLINEPLUS_IRON,
    },
    {
        "lab_test": "Doymamış Demir Bağlama Kapasitesi",
        "title": "Doymamış Demir Bağlama Kapasitesi (UIBC)",
        "aliases": ["doymamış demir bağlama kapasitesi", "uibc", "uıbc", "unsaturated iron binding capacity"],
        "definition": "Doymamış demir bağlama kapasitesi, kandaki demir taşıma proteinlerinin henüz demirle dolmamış bağlama kapasitesini değerlendiren demir testidir.",
        "purpose": "Demir durumunu serum demiri ve diğer demir testleriyle birlikte değerlendirmeye yardımcı olmak için ölçülür.",
        "source_title": "MedlinePlus - Iron Tests",
        "source_url": MEDLINEPLUS_IRON,
    },
    {
        "lab_test": "Transferrin",
        "title": "Transferrin",
        "aliases": ["transferrin", "transferrin düzeyi", "transferrin level"],
        "definition": "Transferrin, demiri kanda taşıyan bir proteindir; transferrin testi bu proteinin miktarını değerlendirir.",
        "purpose": "Vücudun demir taşıma durumunu diğer demir testleriyle birlikte değerlendirmeye yardımcı olmak için ölçülür.",
        "source_title": "MedlinePlus - Iron Tests",
        "source_url": MEDLINEPLUS_IRON,
    },
    {
        "lab_test": "Transferrin Saturasyonu",
        "title": "Transferrin Saturasyonu",
        "aliases": ["transferrin saturasyonu", "transferrin saturation", "tsat", "t sat", "demir saturasyonu"],
        "definition": "Transferrin saturasyonu, demir taşıyan transferrinin ne kadarının demirle bağlı olduğunu ifade eden hesaplanmış bir demir göstergesidir.",
        "purpose": "Demir durumunu serum demiri, transferrin ve bağlama kapasitesiyle birlikte değerlendirmeye yardımcı olmak için kullanılır.",
        "source_title": "MedlinePlus - Iron Tests",
        "source_url": MEDLINEPLUS_IRON,
    },
    {
        "lab_test": "Direkt Bilirubin",
        "title": "Direkt Bilirubin",
        "aliases": ["direkt bilirubin", "direct bilirubin", "konjuge bilirubin", "dbil", "d bil"],
        "definition": "Direkt bilirubin, karaciğerde işlenmiş ve suda çözünebilir hale gelmiş bilirubin bölümünü ölçer.",
        "purpose": "Bilirubin düzeylerini ve karaciğer-safra sistemiyle ilişkili değerlendirmeyi diğer testlerle birlikte desteklemek için ölçülür.",
        "source_title": "MedlinePlus - Bilirubin Blood Test",
        "source_url": MEDLINEPLUS_BILIRUBIN,
    },
    {
        "lab_test": "İndirekt Bilirubin",
        "title": "İndirekt Bilirubin",
        "aliases": ["indirekt bilirubin", "indirect bilirubin", "unkonjuge bilirubin", "ibil", "i bil"],
        "definition": "İndirekt bilirubin, henüz karaciğerde işlenmemiş bilirubin bölümünü ifade eder ve bazı raporlarda hesaplanmış olarak verilir.",
        "purpose": "Bilirubin düzeylerini diğer karaciğer ve kan testleriyle birlikte değerlendirmeyi desteklemek için kullanılır.",
        "source_title": "MedlinePlus - Bilirubin Blood Test",
        "source_url": MEDLINEPLUS_BILIRUBIN,
    },
    {
        "lab_test": "Serbest T3",
        "title": "Serbest T3 (FT3)",
        "aliases": ["serbest t3", "free t3", "ft3", "f t3", "free triiodothyronine"],
        "definition": "Serbest T3, kandaki proteinlere bağlı olmayan ve dokulara girebilen T3 hormonunu ölçer.",
        "purpose": "Tiroid işlevini TSH, T4 ve klinik bilgilerle birlikte değerlendirmeye yardımcı olmak için ölçülür.",
        "source_title": "MedlinePlus - Triiodothyronine T3 Tests",
        "source_url": MEDLINEPLUS_T3,
    },
    {
        "lab_test": "Üre",
        "title": "Üre",
        "aliases": ["üre", "urea", "serum üre", "kan üre"],
        "definition": "Üre, proteinlerin parçalanması sırasında oluşan ve büyük ölçüde böbrekler tarafından vücuttan uzaklaştırılan bir atık maddedir.",
        "purpose": "Böbrek işlevi ve protein yıkımıyla ilişkili değerlendirmeyi diğer testlerle birlikte desteklemek için ölçülür.",
        "source_title": "MedlinePlus - BUN Blood Urea Nitrogen",
        "source_url": MEDLINEPLUS_BUN,
    },
]


def _slugify(value):
    table = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
    return re.sub(r"[^a-z0-9]+", "-", value.translate(table).lower()).strip("-")


def _seed_document(item):
    name = item["lab_test"]
    return {
        "lab_test": name,
        "title": item["title"],
        "source_title": item["source_title"],
        "source_url": item["source_url"],
        "sections": {
            "Nedir?": f'{item["definition"]} Tek başına tanı koydurmaz.',
            "Neden ölçülür?": item["purpose"],
            "Yüksek ne anlama gelebilir?": f"Yüksek {name} sonucu, ölçümün laboratuvarın ilgili referans aralığının üzerinde olduğunu gösterir. Nedenini tek başına açıklamaz; diğer sonuçlar ve sağlık bilgileriyle birlikte değerlendirilir.",
            "Düşük ne anlama gelebilir?": f"Düşük {name} sonucu, ölçümün laboratuvarın ilgili referans aralığının altında olduğunu gösterir. Anlamı diğer sonuçlar ve sağlık bilgileriyle birlikte değerlendirilir.",
            "Ne zaman doktora danışılmalı?": f"{name} sonucunuz referans aralığı dışındaysa veya önceki ölçümlere göre belirgin değiştiyse doktorunuzla değerlendirin. Şiddetli veya hızla kötüleşen belirtiler varsa gecikmeden sağlık hizmeti alın.",
            "Doktora sorulabilecek sorular": f"{name} sonucumu diğer tahlillerimle birlikte nasıl değerlendirmeliyiz? Sonucu etkilemiş olabilecek geçici bir durum var mı? Takip veya ek test gerekir mi?",
        },
        "doctor_questions": [
            f"{name} sonucumu diğer tahlillerimle birlikte nasıl değerlendirmeliyiz?",
            "Sonucu etkilemiş olabilecek geçici bir durum var mı?",
            "Takip veya ek test gerekir mi?",
        ],
    }


def main():
    output_dir = Path(__file__).resolve().parents[1] / "data" / "source_batches"
    common = {
        "batch_id": "common_report_values_03",
        "review_status": "approved",
        "reviewed_by": "Sana official source review",
        "reviewed_at": "2026-07-21",
        "review_notes": "MedlinePlus ve NIH sayfalarıyla karşılaştırıldı; referans aralığı, tanı ve tedavi önerisi eklenmedi.",
    }
    rag = {
        **common,
        "items": [
            {
                "source_key": f'common-report:{item["lab_test"].casefold()}',
                "source_title": item["source_title"],
                "source_url": item["source_url"],
                "lab_test": item["lab_test"],
                "slug": _slugify(item["lab_test"]),
                "title": item["title"],
                "aliases": item["aliases"],
                "definition": f'{item["definition"]} Tek başına tanı koydurmaz.',
                "purpose": item["purpose"],
                "result_kind": "scalar",
            }
            for item in VALUES
        ],
    }
    seed = {**common, "documents": [_seed_document(item) for item in VALUES]}
    for suffix, payload in (("rag", rag), ("seed", seed)):
        path = output_dir / f"common_report_values_03_{suffix}.json"
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(path)


if __name__ == "__main__":
    main()
