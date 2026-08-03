"""Seed veri: 10 lab değeri için section-based içerik.

Yapı ileride SQLite'a taşınabilecek şekilde sadedir: dokümanlar burada tanımlı,
get_all_chunks() bunları düz chunk listesine çevirir.
"""

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from app.core import constants as C


@dataclass
class Chunk:
    chunk_id: str
    lab_test: str
    title: str
    section: str
    content: str
    source_title: str
    source_url: str
    # Güvenlik seviyesi: "general" (varsayılan) | ileride örn. "sensitive".
    # Seed içerik hekim onaylı genel bilgi olduğundan hepsi "general" başlar.
    safety_level: str = "general"
    # v1 (DECISIONS §6) vektör alanı: MVP'de boş başlar, embedding katmanı geldiğinde doldurulur.
    embedding: Optional[list[float]] = None


# Section sırası (chunk_id üretimi için sabit)
SECTION_ORDER = [
    C.SECTION_WHAT,
    C.SECTION_WHY,
    C.SECTION_HIGH,
    C.SECTION_LOW,
    C.SECTION_WHEN_DOCTOR,
    C.SECTION_DOCTOR_QUESTIONS,
]

SEED_DOCUMENTS = [
    {
        "lab_test": "CRP",
        "title": "C-Reaktif Protein (CRP)",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/c-reactive-protein-crp-test/",
        "sections": {
            C.SECTION_WHAT: "CRP, karaciğerde üretilen ve vücutta iltihaplanma olduğunda kanda yükselebilen bir proteindir. Genel bir iltihap belirtecidir; iltihabın nerede olduğunu tek başına göstermez. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Vücutta enfeksiyon, iltihaplanma veya doku hasarı olup olmadığını araştırmak için istenir. Bir sürecin zaman içindeki seyrini izlemek için de kullanılabilir.",
            C.SECTION_HIGH: "Yüksek CRP genellikle vücutta bir iltihaplanma ya da enfeksiyon olabileceğini düşündürür; ancak nedeni çok çeşitli olabilir. Yüksekliğin derecesi ve diğer bulgularla birlikte değerlendirilmesi gerekir.",
            C.SECTION_LOW: "Düşük veya normal CRP, çoğu durumda belirgin sistemik iltihaplanma bulgusu olmadığını düşündürebilir; ancak bazı durumlar yalnızca CRP ile dışlanamaz. Sonuç, şikâyetler ve diğer bulgularla birlikte değerlendirilmelidir.",
            C.SECTION_WHEN_DOCTOR: "Değeriniz referans aralığının dışındaysa veya ateş, ağrı gibi şikâyetlerle birlikteyse sonucu doktorunuzla değerlendirin. Çok yüksek değerler ya da şiddetli belirtiler varsa vakit kaybetmeden bir sağlık kuruluşuna başvurun.",
            C.SECTION_DOCTOR_QUESTIONS: "CRP yüksekliğim hangi durumlarla ilişkili olabilir? Bu sonucu diğer tahlillerimle birlikte nasıl değerlendirmeliyiz? Tekrar test gerekir mi?",
        },
        "doctor_questions": [
            "CRP yüksekliğim hangi durumlarla ilişkili olabilir?",
            "Bu sonucu diğer tahlillerimle birlikte nasıl değerlendirmeliyiz?",
            "Tekrar test gerekir mi?",
        ],
    },
    {
        "lab_test": "Glukoz",
        "title": "Kan Glukozu (Şeker)",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/blood-glucose-test/",
        "sections": {
            C.SECTION_WHAT: "Glukoz, vücudun temel enerji kaynağı olan bir şeker türüdür. Kandaki miktarı, vücudun şekeri nasıl kullandığı hakkında bilgi verir. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Kan şekeri dengesini değerlendirmek ve şeker metabolizmasıyla ilgili durumları araştırıp izlemek için istenir. Glukoz ölçümü açlık, tokluk veya farklı test protokolleriyle yapılabilir. Sonucun yorumu ölçümün hangi koşulda yapıldığına göre değişir.",
            C.SECTION_HIGH: "Yüksek glukoz, vücudun şekeri yeterince düzenleyemiyor olabileceğini düşündürebilir; ancak yemek, stres, bazı ilaçlar veya ölçüm koşulları da değeri etkiler. Tek bir yüksek sonuç tanı koydurmaz; genellikle tekrarlı ölçüm ve ek testlerle değerlendirilir.",
            C.SECTION_LOW: "Düşük glukoz baş dönmesi, terleme, titreme gibi belirtilere yol açabilir. Açlık veya başka durumlarla ilişkili olabilir; nedeni doktorla araştırılmalıdır.",
            C.SECTION_WHEN_DOCTOR: "Değeriniz referans aralığının dışındaysa doktorunuzla değerlendirin. Bayılma, aşırı terleme, bilinç bulanıklığı gibi belirtiler varsa acilen bir sağlık kuruluşuna başvurun.",
            C.SECTION_DOCTOR_QUESTIONS: "Benim için hedef glukoz aralığı ne olmalı? Tekrar veya ek bir test gerekir mi? Sonucu etkilemiş olabilecek bir durum var mı?",
        },
        "doctor_questions": [
            "Benim için hedef glukoz aralığı ne olmalı?",
            "Tekrar veya ek bir test gerekir mi?",
            "Sonucu etkilemiş olabilecek bir durum var mı?",
        ],
    },
    {
        "lab_test": "Ferritin",
        "title": "Ferritin",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/ferritin-blood-test/",
        "sections": {
            C.SECTION_WHAT: "Ferritin, vücutta demiri depolayan bir proteindir. Kandaki düzeyi, vücudun demir depolarının durumu hakkında fikir verir. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Vücuttaki demir depolarını değerlendirmek için istenir; demir eksikliği veya fazlalığı durumlarını araştırmada kullanılır. Genellikle hemoglobin gibi testlerle birlikte yorumlanır.",
            C.SECTION_HIGH: "Yüksek ferritin demir depolarının fazla olabileceğini düşündürebilir; ancak iltihaplanma ve bazı başka durumlarda da yükselebilir. Bu nedenle tek başına yorumlanmaz.",
            C.SECTION_LOW: "Düşük ferritin genellikle demir depolarının azaldığına işaret edebilir. Yorgunluk, halsizlik gibi belirtilerle birlikte olabilir; nedeni doktorla araştırılmalıdır.",
            C.SECTION_WHEN_DOCTOR: "Değeriniz referans aralığının dışındaysa, özellikle yorgunluk veya nefes darlığı gibi şikâyetler varsa doktorunuzla değerlendirin.",
            C.SECTION_DOCTOR_QUESTIONS: "Bu değer demir eksikliği/fazlalığı açısından ne ifade ediyor? Demir durumumu netleştirmek için ek test gerekir mi? Bunu hemoglobinimle birlikte nasıl yorumlamalıyız?",
        },
        "doctor_questions": [
            "Bu değer demir eksikliği/fazlalığı açısından ne ifade ediyor?",
            "Demir durumumu netleştirmek için ek test gerekir mi?",
            "Bunu hemoglobinimle birlikte nasıl yorumlamalıyız?",
        ],
    },
    {
        "lab_test": "B12",
        "title": "B12 Vitamini",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/vitamin-b-test/",
        "sections": {
            C.SECTION_WHAT: "B12, sinir sistemi ve kan hücrelerinin sağlıklı çalışması için gerekli bir vitamindir. Vücut B12'yi besinlerden alır; kandaki düzeyi vücudun B12 durumunu yansıtır. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "B12 düzeyini veya eksikliğini araştırmak için istenir; özellikle yorgunluk, uyuşma gibi belirtiler ya da beslenmeyle ilgili durumlar değerlendirilirken kullanılır.",
            C.SECTION_HIGH: "B12 sonucunun anlamı her zaman tek başına net değildir. Vücuttaki iltihaplanma, bazı ilaçlar ve laboratuvarlar arasındaki referans aralığı farkları sonucu etkileyebilir; sonuç belirtiler ve diğer bulgularla birlikte değerlendirilmelidir.",
            C.SECTION_LOW: "Düşük B12, vücutta B12'nin yetersiz olabileceğine işaret edebilir; yorgunluk, uyuşma, denge sorunları gibi belirtilerle ilişkili olabilir. Nedeni doktorla araştırılmalıdır.",
            C.SECTION_WHEN_DOCTOR: "Değeriniz referans aralığının dışındaysa, özellikle halsizlik, uyuşma, unutkanlık gibi şikâyetler varsa doktorunuzla değerlendirin.",
            C.SECTION_DOCTOR_QUESTIONS: "B12 düzeyim belirtilerimi açıklıyor olabilir mi? Beslenme veya emilimle ilgili araştırma gerekir mi? Takip için tekrar ölçüm gerekir mi?",
        },
        "doctor_questions": [
            "B12 düzeyim belirtilerimi açıklıyor olabilir mi?",
            "Beslenme veya emilimle ilgili araştırma gerekir mi?",
            "Takip için tekrar ölçüm gerekir mi?",
        ],
    },
    {
        "lab_test": "Hemoglobin",
        "title": "Hemoglobin",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/hemoglobin-test/",
        "sections": {
            C.SECTION_WHAT: "Hemoglobin, kırmızı kan hücrelerinde bulunan ve oksijeni vücuda taşıyan bir proteindir. Düzeyi, kanın oksijen taşıma kapasitesi hakkında bilgi verir. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Genel kan sağlığını değerlendirmek, kansızlık gibi durumları araştırmak ve izlemek için tam kan sayımının bir parçası olarak istenir.",
            C.SECTION_HIGH: "Yüksek hemoglobin; sıvı kaybı, yüksek rakımda yaşam veya bazı başka durumlarla ilişkili olabilir. Nedeni diğer bulgularla birlikte değerlendirilir.",
            C.SECTION_LOW: "Düşük hemoglobin, kansızlık/anemi açısından değerlendirme gerektirebilir; ancak nedenini anlamak için diğer kan değerleri ve klinik bulgularla birlikte yorumlanmalıdır.",
            C.SECTION_WHEN_DOCTOR: "Değeriniz referans aralığının dışındaysa doktorunuzla değerlendirin. Belirgin nefes darlığı, çarpıntı, baygınlık gibi belirtiler varsa vakit kaybetmeden bir sağlık kuruluşuna başvurun.",
            C.SECTION_DOCTOR_QUESTIONS: "Hemoglobin değerim anemi açısından ne ifade ediyor? Nedenini araştırmak için ek test gerekir mi? Bunu ferritinimle birlikte nasıl değerlendirmeliyiz?",
        },
        "doctor_questions": [
            "Hemoglobin değerim anemi açısından ne ifade ediyor?",
            "Nedenini araştırmak için ek test gerekir mi?",
            "Bunu ferritinimle birlikte nasıl değerlendirmeliyiz?",
        ],
    },
    {
        "lab_test": "TSH",
        "title": "TSH",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/tsh-thyroid-stimulating-hormone-test/",
        "sections": {
            C.SECTION_WHAT: "TSH, beynin tabanındaki hipofiz bezinin ürettiği ve tiroid bezine ne kadar hormon üretmesi gerektiğini bildiren bir hormondur. Kandaki TSH düzeyi, tiroid ile hipofiz arasındaki düzenleme hakkında bilgi verir. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Tiroid bezinin çalışmasını değerlendirmek, tiroidle ilişkili olabilecek belirtileri araştırmak ve bilinen bir tiroid sorununun takibini desteklemek için ölçülür. Sonuç genellikle T4, bazen T3 ve klinik bulgularla birlikte yorumlanır.",
            C.SECTION_HIGH: "Yüksek TSH, tiroid hormonu etkisinin yetersiz kaldığı durumlarda hipofizin tiroidi daha fazla uyarmasıyla görülebilir. Gebelik, yaş, bazı ilaçlar ve başka sağlık durumları sonucu etkileyebilir; tek bir sonuç nedeni göstermez.",
            C.SECTION_LOW: "Düşük TSH, tiroid hormonu etkisinin arttığı durumlarda hipofizin uyarıyı azaltmasıyla görülebilir. Gebelik, bazı ilaçlar ve başka sağlık durumları da değeri etkileyebilir; sonuç tek başına tanı değildir.",
            C.SECTION_WHEN_DOCTOR: "TSH sonucunuz laboratuvarın referans aralığı dışındaysa veya çarpıntı, belirgin kilo değişimi, aşırı yorgunluk ya da ısıya duyarlılık gibi şikayetleriniz varsa doktorunuzla değerlendirin. Gebelikte veya tiroid ilacı kullanırken sonucu kendi başınıza yorumlamayın ve ilacınızı doktorunuza danışmadan değiştirmeyin.",
            C.SECTION_DOCTOR_QUESTIONS: "TSH sonucumu T4 veya T3 ile birlikte nasıl değerlendirmeliyiz? Kullandığım ilaçlar ya da gebelik sonucu etkileyebilir mi? Takip için testi ne zaman tekrarlamak gerekir?",
        },
        "doctor_questions": [
            "TSH sonucumu T4 veya T3 ile birlikte nasıl değerlendirmeliyiz?",
            "Kullandığım ilaçlar ya da gebelik sonucu etkileyebilir mi?",
            "Takip için testi ne zaman tekrarlamak gerekir?",
        ],
    },
    {
        "lab_test": "Kreatinin",
        "title": "Kreatinin",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/creatinine-test/",
        "sections": {
            C.SECTION_WHAT: "Kreatinin, kasların normal çalışması sırasında oluşan ve çoğunlukla böbrekler tarafından kandan süzülen bir atık maddedir. Kan veya idrardaki düzeyi böbreklerin süzme işlevi hakkında bilgi verir; yaş, kas kütlesi ve başka etkenlerden de etkilenir. Tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Böbrek sağlığını ve süzme işlevini değerlendirmek, zaman içindeki değişimleri izlemek veya eGFR hesabına katkı sağlamak için ölçülür. Gerektiğinde idrar testleri, üre ve diğer bulgularla birlikte yorumlanır.",
            C.SECTION_HIGH: "Yüksek kreatinin böbreklerin süzme işlevinde azalma olabileceğini düşündürebilir. Sıvı kaybı, yoğun egzersiz, kas hasarı, beslenme ve bazı ilaçlar da sonucu etkileyebilir; tek bir değer nedeni göstermez.",
            C.SECTION_LOW: "Düşük kreatinin düşük kas kütlesi, yetersiz beslenme veya uzun süren bazı sağlık durumlarıyla ilişkili olabilir. Yaş ve vücut yapısı sonucu etkilediğinden tek başına yorumlanmamalıdır.",
            C.SECTION_WHEN_DOCTOR: "Sonucunuz referans aralığı dışındaysa veya önceki ölçümlere göre belirgin değiştiyse doktorunuzla değerlendirin. İdrar miktarında belirgin azalma, şişlik, nefes darlığı veya ciddi halsizlik varsa gecikmeden sağlık hizmeti alın.",
            C.SECTION_DOCTOR_QUESTIONS: "Kreatinin sonucum böbrek süzme işlevim açısından ne ifade ediyor? eGFR veya idrar testi gibi ek değerlendirme gerekir mi? Beslenme, egzersiz ya da kullandığım ilaçlar sonucu etkilemiş olabilir mi?",
        },
        "doctor_questions": [
            "Kreatinin sonucum böbrek süzme işlevim açısından ne ifade ediyor?",
            "eGFR veya idrar testi gibi ek değerlendirme gerekir mi?",
            "Beslenme, egzersiz ya da kullandığım ilaçlar sonucu etkilemiş olabilir mi?",
        ],
    },
    {
        "lab_test": "ALT",
        "title": "ALT",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/alt-blood-test/",
        "sections": {
            C.SECTION_WHAT: "ALT, çoğunlukla karaciğerde bulunan bir enzimdir. Karaciğer hücreleri etkilendiğinde kana geçebildiği için kandaki düzeyi karaciğer hücreleri hakkında bilgi verebilir. Tek başına tanı koydurmaz ve hasarın derecesini doğrudan göstermez.",
            C.SECTION_WHY: "Karaciğer sağlığını değerlendiren test panelinin bir parçası olarak, olası karaciğer sorunlarını araştırmak veya zaman içindeki değişimleri izlemek için ölçülür. AST, bilirubin ve diğer bulgularla birlikte yorumlanır.",
            C.SECTION_HIGH: "Yüksek ALT karaciğer hücrelerinin etkilendiğini düşündürebilir; ancak ilaçlar, yoğun egzersiz, metabolik durumlar ve farklı nedenler de sonucu değiştirebilir. Yüksekliğin miktarı nedeni veya hasarın şiddetini tek başına göstermez.",
            C.SECTION_LOW: "Düşük ALT sık görülmez; B6 vitamini eksikliği veya kronik böbrek hastalığı gibi durumlarla ilişkili olabilir. Tek başına tanı koydurmaz; sonuç diğer testler ve kişinin genel durumu ile birlikte değerlendirilmelidir.",
            C.SECTION_WHEN_DOCTOR: "ALT sonucunuz referans aralığı dışındaysa veya önceki ölçümlere göre yükselmişse doktorunuzla değerlendirin. Sarılık, koyu renkli idrar, şiddetli karın ağrısı veya belirgin bilinç değişikliği varsa gecikmeden sağlık hizmeti alın.",
            C.SECTION_DOCTOR_QUESTIONS: "ALT sonucumu AST ve diğer karaciğer testleriyle birlikte nasıl yorumlamalıyız? Kullandığım ilaçlar veya yakın zamandaki egzersiz sonucu etkileyebilir mi? Takip ya da ek test gerekir mi?",
        },
        "doctor_questions": [
            "ALT sonucumu AST ve diğer karaciğer testleriyle birlikte nasıl yorumlamalıyız?",
            "Kullandığım ilaçlar veya yakın zamandaki egzersiz sonucu etkileyebilir mi?",
            "Takip ya da ek test gerekir mi?",
        ],
    },
    {
        "lab_test": "AST",
        "title": "AST",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/ast-test/",
        "sections": {
            C.SECTION_WHAT: "AST; karaciğer, kalp, kaslar ve başka dokularda bulunan bir enzimdir. Bu dokulardaki hücreler etkilendiğinde AST kana geçebilir. Karaciğere özgü olmadığı için tek başına tanı koydurmaz.",
            C.SECTION_WHY: "Genellikle karaciğer test panelinin bir parçası olarak olası karaciğer sorunlarını araştırmak veya izlemek için ölçülür. Sonuç ALT ve diğer testlerle birlikte değerlendirilerek kaynağı hakkında daha fazla bilgi edinilir.",
            C.SECTION_HIGH: "Yüksek AST karaciğerin yanı sıra kas veya başka dokuların etkilenmesiyle de görülebilir. Yoğun egzersiz, bazı ilaçlar ve çeşitli sağlık durumları sonucu değiştirebilir; tek bir değer nedeni göstermez.",
            C.SECTION_LOW: "Düşük AST çoğu durumda tek başına sınırlı klinik anlam taşır. Laboratuvar aralığı, diğer testler ve kişinin genel durumu birlikte değerlendirilmelidir.",
            C.SECTION_WHEN_DOCTOR: "AST sonucunuz referans aralığı dışındaysa veya önceki ölçümlere göre belirgin değiştiyse doktorunuzla değerlendirin. Sarılık, koyu renkli idrar, şiddetli karın ağrısı ya da ciddi kas ağrısı gibi belirtiler varsa gecikmeden sağlık hizmeti alın.",
            C.SECTION_DOCTOR_QUESTIONS: "AST sonucumun kaynağını anlamak için ALT ve diğer testleri nasıl değerlendirmeliyiz? Egzersiz veya kullandığım ilaçlar sonucu etkilemiş olabilir mi? Takip ya da ek test gerekir mi?",
        },
        "doctor_questions": [
            "AST sonucumun kaynağını anlamak için ALT ve diğer testleri nasıl değerlendirmeliyiz?",
            "Egzersiz veya kullandığım ilaçlar sonucu etkilemiş olabilir mi?",
            "Takip ya da ek test gerekir mi?",
        ],
    },
    {
        "lab_test": "Trombosit",
        "title": "Trombosit",
        "source_title": "MedlinePlus",
        "source_url": "https://medlineplus.gov/lab-tests/platelet-tests/",
        "sections": {
            C.SECTION_WHAT: "Trombositler, kanamanın durmasına yardımcı olan küçük kan hücreleridir ve pıhtı oluşumunda görev alır. Trombosit sayımı kandaki trombosit miktarını ölçer; trombositlerin işlevini tek başına göstermez ve tanı koydurmaz.",
            C.SECTION_WHY: "Tam kan sayımının bir parçası olarak kanama veya pıhtılaşmayla ilişkili durumları değerlendirmek ve zaman içindeki değişimleri izlemek için ölçülür. Sonuç diğer kan değerleri ve klinik bulgularla birlikte yorumlanır.",
            C.SECTION_HIGH: "Yüksek trombosit sayısı geçici veya tepkisel değişikliklerle ve daha farklı durumlarla ilişkili olabilir. Bazı durumlarda pıhtılaşma riskiyle bağlantılı olsa da tek bir sayı nedeni ya da kişisel riski göstermez.",
            C.SECTION_LOW: "Düşük trombosit sayısı kanama eğilimini artırabilir ve çok farklı nedenlerle görülebilir. Değerin derecesi, belirtiler, diğer kan sonuçları ve zaman içindeki değişim birlikte değerlendirilmelidir.",
            C.SECTION_WHEN_DOCTOR: "Sonucunuz referans aralığı dışındaysa veya açıklanamayan morarma, ciltte noktasal kırmızı lekeler ya da uzayan kanama varsa doktorunuza danışın. Durmayan veya şiddetli kanama varsa acil sağlık hizmeti alın.",
            C.SECTION_DOCTOR_QUESTIONS: "Trombosit sonucumu diğer tam kan sayımı değerleriyle birlikte nasıl değerlendirmeliyiz? Sonucu etkileyebilecek geçici bir durum veya ilaç var mı? Testin tekrarı ya da ek inceleme gerekir mi?",
        },
        "doctor_questions": [
            "Trombosit sonucumu diğer tam kan sayımı değerleriyle birlikte nasıl değerlendirmeliyiz?",
            "Sonucu etkileyebilecek geçici bir durum veya ilaç var mı?",
            "Testin tekrarı ya da ek inceleme gerekir mi?",
        ],
    },
]


def _load_reviewed_seed_batch() -> None:
    directory = (
        Path(__file__).resolve().parents[2]
        / "data"
        / "source_batches"
    )
    known = {doc["lab_test"] for doc in SEED_DOCUMENTS}
    for path in sorted(directory.glob("*_seed.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for document in payload.get("documents", []):
            if document["lab_test"] not in known:
                SEED_DOCUMENTS.append(document)
                known.add(document["lab_test"])


_load_reviewed_seed_batch()


def get_all_chunks() -> List[Chunk]:
    """Seed dokümanları düz chunk listesine çevirir."""
    chunks: List[Chunk] = []
    for doc in SEED_DOCUMENTS:
        for idx, section in enumerate(SECTION_ORDER):
            text = doc["sections"].get(section)
            if not text:
                continue
            chunks.append(
                Chunk(
                    chunk_id=f"{doc['lab_test']}_{idx}",
                    lab_test=doc["lab_test"],
                    title=doc["title"],
                    section=section,
                    content=text,
                    source_title=doc["source_title"],
                    source_url=doc["source_url"],
                )
            )
    return chunks


def get_doctor_questions(lab_test: str) -> List[str]:
    for doc in SEED_DOCUMENTS:
        if doc["lab_test"] == lab_test:
            return list(doc["doctor_questions"])
    return []
