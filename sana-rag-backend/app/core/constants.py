"""Sabit değerler: mesajlar, eşikler, ağırlıklar, response tipleri ve pattern listeleri.

Tüm patternler NORMALIZE EDİLMİŞ metin (Türkçe küçük harf + noktalama temizliği)
üzerinde eşleştirilecek şekilde tanımlanmıştır. Hem Türkçe karakterli hem de
ASCII (çğıöşü -> cgiosu) yazımları kapsamak için iki varyant da eklenmiştir.
"""

# --- Genel ---
APP_VERSION = "v1"
SUPPORTED_LANGUAGES = {"tr"}

DISCLAIMER = (
    "Bu açıklama yalnızca bilgilendirme amaçlıdır; tanı, tedavi veya tıbbi karar "
    "önerisi değildir. Sonuçlarınızı doktorunuzla birlikte değerlendiriniz."
)

# --- Response tipleri ---
RESPONSE_ANSWER = "answer"
RESPONSE_NO_RESULTS = "no_results"
RESPONSE_SAFETY_BLOCK = "safety_block"
RESPONSE_ERROR = "error"

# --- Error kodları ---
ERR_VALIDATION = "VALIDATION_ERROR"
ERR_UNSUPPORTED_LANGUAGE = "UNSUPPORTED_LANGUAGE"
ERR_INTERNAL = "INTERNAL_ERROR"
ERR_TIMEOUT = "TIMEOUT"
ERR_SAFETY_BLOCKED = "SAFETY_BLOCKED"

# --- Standart mesajlar ---
NO_RESULTS_MESSAGE = (
    "Bu konuda yeterince güvenilir kaynak eşleşmesi bulunamadı. "
    "Sonucunuzu doktorunuzla değerlendirmeniz önerilir."
)
NO_RESULTS_DOCTOR_QUESTIONS = [
    "Bu sonucu hangi belirtilerimle birlikte değerlendirmeliyim?",
    "Bu testin tekrar edilmesi gerekir mi?",
    "Bu değer benim yaşım ve sağlık durumum için nasıl yorumlanmalı?",
]

MEDICATION_BLOCK_MESSAGE = (
    "İlaç, doz, takviye veya tedavi konusunda yönlendirme yapamam. "
    "Bu kararları doktorunuz veya eczacınızla değerlendirmeniz gerekir."
)
DOCTOR_AVOIDANCE_MESSAGE = (
    "Belirtileriniz veya değerleriniz için bir sağlık profesyoneline danışmanız önemlidir; "
    "bu adımı atlamanızı öneremem."
)

# safety_block yanıtında metadata olarak dönen kısa not (davranışı değiştirmez)
SAFETY_BLOCK_NOTE = (
    "Bu soru güvenlik gereği yanıtlanmadı; tıbbi yönlendirme için doktorunuza "
    "veya eczacınıza danışın."
)

# Cevap içine eklenen güvenlik çerçeveleri
EMERGENCY_PREFIX = (
    "Belirttiğiniz durum acil olabilir. Lütfen vakit kaybetmeden bir sağlık kuruluşuna "
    "veya acil servise başvurun. "
)
DIAGNOSIS_NOTE = "Bu sonuç tek başına bir hastalık tanısı koydurmaz. "
TREATMENT_NOTE = (
    "Tedavi yöntemleri konusunda yönlendirme yapamam; bunu doktorunuzla görüşmeniz gerekir. "
)
PEDIATRIC_SUFFIX = (
    " Çocuklarda değerler yaşa göre farklı yorumlanır; bu sonucu çocuk doktorunuzla "
    "değerlendirmeniz önemlidir."
)
GENERIC_CAVEAT = " Bu değer tek başına tanı koydurmaz."

# Referans aralığı/yorum yokken LLM sayıyı normal/yüksek/düşük diye sınıflandırırsa
# cevabın tamamı bu güvenli metinle değiştirilir (S: değer sınıflandırma filtresi).
VALUE_CLASSIFICATION_SAFE_TEXT = (
    "{lab_test}, verilen sayı üzerinden tek başına normal, yüksek veya düşük "
    "olarak sınıflandırılamaz; referans aralığı, laboratuvar yöntemi ve klinik "
    "durumla birlikte doktorunuz tarafından değerlendirilmelidir."
)
VALUE_CONTEXT_MISSING_RANGE_NOTE = (
    "Rapordaki laboratuvar referans aralığı verilmediği için bu sayı tek başına "
    "normal, yüksek veya düşük olarak sınıflandırılamaz."
)

# --- Confidence ---
W_LAB_EXACT = 0.35
W_SYNONYM = 0.20
W_KEYWORD = 0.20
W_SOURCE = 0.15
W_INTENT_SECTION = 0.10

THRESHOLD_HIGH = 0.71
THRESHOLD_MEDIUM = 0.41

# --- Section adları ---
SECTION_WHAT = "Nedir?"
SECTION_WHY = "Neden ölçülür?"
SECTION_HIGH = "Yüksek ne anlama gelebilir?"
SECTION_LOW = "Düşük ne anlama gelebilir?"
SECTION_WHEN_DOCTOR = "Ne zaman doktora danışılmalı?"
SECTION_DOCTOR_QUESTIONS = "Doktora sorulabilecek sorular"

# --- Intentler ---
INTENT_DEFINITION = "definition"
INTENT_HIGH = "high_result_explanation"
INTENT_LOW = "low_result_explanation"
INTENT_NORMAL_RANGE = "normal_range"
INTENT_DOCTOR_QUESTIONS = "doctor_questions"
INTENT_GENERAL = "general_explanation"
INTENT_DIAGNOSIS = "diagnosis_request"
INTENT_TREATMENT = "treatment_request"
INTENT_MED_DOSAGE = "medication_or_dosage_advice"
INTENT_MED_SUPPLEMENT = "medication_or_supplement_advice"
INTENT_EMERGENCY = "emergency_or_panic_value"
INTENT_PEDIATRIC = "pediatric_context"
INTENT_DOCTOR_AVOIDANCE = "doctor_avoidance"
INTENT_PROMPT_INJECTION = "prompt_injection"
INTENT_NO_RESULTS = "no_retrieval_results"

# Retrieval yapmadan doğrudan safety_block dönülecek intentler
BLOCK_BEFORE_RETRIEVAL = {INTENT_MED_DOSAGE, INTENT_MED_SUPPLEMENT, INTENT_DOCTOR_AVOIDANCE}

PROMPT_INJECTION_BLOCK_MESSAGE = (
    "Sistem talimatları, teknik yapılandırma veya gizli çalışma ayrıntıları "
    "paylaşılmaz. Desteklenen bir tahlil hakkında açıklama sorabilirsiniz."
)

# Pediatrik yaş eşiği
PEDIATRIC_AGE_LIMIT = 14

# --- Pattern listeleri (normalize edilmiş metin üzerinde aranır) ---
EMERGENCY_PATTERNS = [
    "çok yüksek", "cok yuksek", "çok düşük", "cok dusuk",
    "350", "450",
    "kendimi çok kötü", "kendimi cok kotu",
    "bayılma", "bayilma", "bayıl", "bayil",
    "bilinç bulanıklığı", "bilinc bulanikligi",
    "nefes darlığı", "nefes darligi",
    # Kök desen: "göğüs ağrısı" / "göğüs ağrım" / "göğüs ağrısı olan" hepsini kapsar
    "göğüs ağrı", "gogus agri",
    "şiddetli", "siddetli",
]

PEDIATRIC_PATTERNS = [
    "çocuk", "cocuk", "çocuğum", "cocugum", "çocuğun", "cocugun",
    "bebek", "bebeğim", "bebegim", "bebeğin", "bebegin",
    "yaşındaki", "yasindaki",
]

MED_DOSAGE_PATTERNS = [
    # Not: Türkçe ünsüz yumuşaması nedeniyle kök desen kullanılır
    # ("antibiyotik" -> "antibiyotiği" için "antibiyot"; "ilaç" -> "ilacı" için "ilacı").
    "hangi ilaç", "hangi ilac", "hangi ilacı", "hangi ilaci", "antibiyot",
    "doz", "dozunu", "dozaj", "ilaç dozu", "ilac dozu",
    # İlaç alma/kullanma/değiştirme (çekimleri kapsayan kök desenler)
    "ilaç al", "ilac al", "ilaç kullan", "ilac kullan",
    "ilaç başla", "ilac basla", "ilaç bırak", "ilac birak",
    "ilaç artır", "ilac artir", "ilaç azalt", "ilac azalt",
    "ilaç öner", "ilac oner",
    "ilacı al", "ilaci al", "ilacı kullan", "ilaci kullan",
    "ilacı artır", "ilaci artir", "ilacı azalt", "ilaci azalt",
    "ilacı bırak", "ilaci birak",
    # Tedavi isteği (retrieval öncesi blok)
    "nasıl tedavi", "nasil tedavi", "tedavi edil",
    "evde tedavi", "tedavi ne olmalı", "tedavi ne olmali",
    "tedavi öner", "tedavi oner",
]

MED_SUPPLEMENT_PATTERNS = [
    "ilacına başla", "ilacina basla", "ilaca başla", "ilaca basla",
    "demir ilacı", "demir ilaci", "demir hapı", "demir hapi",
    "takviye", "vitamin alay", "vitamin alsam", "hap alay",
    "vitamin al", "vitamini al", "vitamin kullan", "vitamini kullan",
    "başlayayım mı", "baslayayim mi", "başlasam mı", "baslasam mi",
    "kullanmaya başla", "kullanmaya basla",
]

DOCTOR_AVOIDANCE_PATTERNS = [
    "doktora gitmeme gerek", "doktora gitmesem", "doktora gerek var mı",
    "doktora gerek var mi", "doktora gerek yok", "doktora gitmeye gerek",
    "geçer mi", "gecer mi", "kendi kendine geçer", "kendi kendine gecer",
]

DIAGNOSIS_PATTERNS = [
    "hasta mıyım", "hasta miyim", "hastayım", "hastayim", "hasta mı", "hasta mi",
    "şeker hastası", "seker hastasi", "kanser mi", "kanser miyim",
    "kesin hasta", "hangi hastalık", "hangi hastalik", "teşhis", "teshis",
    # "enfeksiyon muyum / mu var" ve "hastalık var mı" tarzı tanı istekleri
    "enfeksiyon mu", "hastalık var", "hastalik var",
]

TREATMENT_PATTERNS = [
    "nasıl tedavi", "nasil tedavi", "tedavi edilir",
    "nasıl geçer", "nasil gecer", "nasıl düzelir", "nasil duzelir",
    "nasıl yükselt", "nasil yukselt", "nasıl düşür", "nasil dusur",
    "nasıl iyileş", "nasil iyiles", "nasıl artır", "nasil artir",
]

NORMAL_RANGE_PATTERNS = [
    "normal mi", "normal değer", "normal deger", "referans aralığı",
    "referans araligi", "kaç olmalı", "kac olmali", "normal aralık", "normal aralik",
]

DOCTOR_QUESTION_PATTERNS = [
    "doktora ne sor", "hangi soruları", "hangi sorulari",
    "neyi sormalı", "neyi sormali", "doktora hangi",
]

WHEN_DOCTOR_PATTERNS = [
    "ne zaman doktora", "ne zaman hekime", "ne zaman başvur",
    "ne zaman basvur", "doktora ne zaman", "hekime ne zaman",
]

HIGH_PATTERNS = ["yüksek", "yuksek", "fazla", "yukarı", "yukari"]
LOW_PATTERNS = ["düşük", "dusuk", "aşağı", "asagi"]

DEFINITION_PATTERNS = [
    "nedir", "ne demek", "neyi gösterir", "neyi gosterir",
    "ne işe yarar", "ne ise yarar", "ne için", "ne icin", "ne için ölç", "ne icin olc",
]

WHY_PATTERNS = [
    "ne işe yarar", "ne ise yarar", "neden ölç", "neden olc",
    "ne için ölç", "ne icin olc", "niçin ölç", "nicin olc",
]
