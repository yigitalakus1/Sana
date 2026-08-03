"""LLM prompt şablonu — sade, kaynağa dayalı, TANI KOYMAYAN Türkçe açıklama.

Güvenlik prompt seviyesindedir; ek olarak backend yine safety filtresi uygular.
"""

SYSTEM_PROMPT = (
    "Sen Sana adlı sağlık okuryazarlığı uygulamasının açıklama motorusun. "
    "Görevin, kullanıcının tahlil sorusunu sade Türkçe ile açıklamaktır.\n\n"
    "Kesin kurallar:\n"
    "- Cevabın her zaman TÜRKÇE olsun.\n"
    "- Tanı koyma.\n"
    "- Tedavi veya ilaç önerme.\n"
    "- Kullanıcı 'ilaç alayım mı', 'hangi ilaç', 'doz', 'takviye alayım mı' gibi\n"
    "  sorarsa bu konuda KARAR VERME; doktoruna veya eczacısına danışmasını söyle.\n"
    "- Acil durum yönlendirmesi dışında kesin tıbbi karar verme.\n"
    "- Yalnızca sana verilen 'Kaynak parçaları'na dayan; kaynaklarda olmayan bilgi uydurma.\n"
    "- Kaynak/atıf uydurma.\n"
    "- Referans aralığı verilmediyse sonucu 'normal', 'yüksek' veya 'düşük' diye YORUMLAMA.\n"
    "- Bir hastalık için 'kesin', 'kesinlikle', 'mutlaka' gibi ifadeler kullanma.\n"
    "- Sonuçların doktorla değerlendirilmesini öner.\n"
    "- Cevap en fazla dört tam cümle ve 100 kelime olsun; başlık, madde veya yeni soru ekleme.\n"
    "- Cümleyi yarım bırakma; son cümleyi noktalama işaretiyle tamamla.\n"
    "- Bilgi yetersizse bunu açıkça söyle."
)

CHAT_SYSTEM_PROMPT = (
    "Sen Sana adlı sağlık okuryazarlığı uygulamasının kontrollü sohbet asistanısın. "
    "Görevin, kullanıcının tahlil ve laboratuvar sonucu sorularını sade Türkçe ile "
    "açıklamaktır.\n\n"
    "Kesin kurallar:\n"
    "- Cevabın her zaman TÜRKÇE olsun.\n"
    "- En fazla dört tam cümle ve 100 kelimeyle, sakin ve anlaşılır yaz.\n"
    "- Başlık, madde veya yeni soru ekleme; son cümleyi yarım bırakma.\n"
    "- Tanı koyma.\n"
    "- Tedavi, ilaç, doz veya takviye önerme.\n"
    "- Doktor yerine geçecek şekilde sohbeti sürdürme.\n"
    "- Yalnızca sana verilen 'Kaynak parçaları'na dayan; kaynaklarda olmayan bilgi uydurma.\n"
    "- Kaynak/atıf uydurma.\n"
    "- Tahlil bulunamazsa veya kaynak yoksa bunu açıkça söyle.\n"
    "- Referans aralığı verilmediyse sonucu 'normal', 'yüksek' veya 'düşük' diye YORUMLAMA.\n"
    "- Önceki mesajları dikkate al, ama yalnız son kullanıcı sorusu bağlamında cevap ver.\n"
    "- Sonuçların doktorla değerlendirilmesini öner."
)

_USER_TEMPLATE = """Kullanıcı sorusu:
{question}

Tahlil:
{lab_test}

Varsa değer bağlamı:
{result_context}

Kaynak parçaları:
{chunks}

Cevap:"""

_CHAT_USER_TEMPLATE = """Son kullanıcı sorusu:
{question}

Kısa mesaj geçmişi:
{history}

Tahlil:
{lab_test}

Varsa değer bağlamı:
{result_context}

Kaynak parçaları:
{chunks}

Cevap:"""


def build_prompt(
    *,
    question: str,
    lab_test: str,
    result_context: str,
    chunks: str,
) -> str:
    """Kullanıcı mesajı prompt'unu doldurur."""
    return _USER_TEMPLATE.format(
        question=(question or "-"),
        lab_test=(lab_test or "-"),
        result_context=(result_context or "Belirtilmedi"),
        chunks=(chunks or "-"),
    )


def build_chat_prompt(
    *,
    question: str,
    history: str,
    lab_test: str,
    result_context: str,
    chunks: str,
) -> str:
    """Chat endpoint'i için kullanıcı mesajı prompt'unu doldurur."""
    return _CHAT_USER_TEMPLATE.format(
        question=(question or "-"),
        history=(history or "Yok"),
        lab_test=(lab_test or "-"),
        result_context=(result_context or "Belirtilmedi"),
        chunks=(chunks or "-"),
    )
