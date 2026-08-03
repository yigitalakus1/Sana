"""Onayli Turkce taslak batch'ini Markdown ve seed verisine donusturur."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import constants as C  # noqa: E402
from app.services.source_sync_store import SourceSyncStore  # noqa: E402


SECTIONS = (
    C.SECTION_WHAT,
    C.SECTION_WHY,
    C.SECTION_HIGH,
    C.SECTION_LOW,
    C.SECTION_WHEN_DOCTOR,
    C.SECTION_DOCTOR_QUESTIONS,
)


def _sections(item: Dict[str, Any], draft_content: str) -> Dict[str, str]:
    lab = item["lab_test"]
    result_kind = item["result_kind"]
    if result_kind == "panel":
        high = (
            "Bu panel birden fazla ölçüm içerdiğinden tek bir yüksek sonuçtan söz "
            "edilmez. Her bileşen kendi laboratuvar referans aralığına, diğer "
            "sonuçlara ve kişinin sağlık bilgilerine göre değerlendirilir."
        )
        low = (
            "Bu panel birden fazla ölçüm içerdiğinden tek bir düşük sonuçtan söz "
            "edilmez. Hangi bileşenin düşük olduğu ve diğer bileşenlerle ilişkisi "
            "birlikte değerlendirilir."
        )
    elif result_kind == "qualitative":
        high = (
            "Bu test çoğunlukla bir bulgunun varlığını veya yokluğunu bildirir; "
            "bu nedenle sonuç için yüksek ifadesi uygun olmayabilir. Pozitif veya "
            "saptandı biçimindeki sonuç diğer bulgularla birlikte değerlendirilir."
        )
        low = (
            "Bu test çoğunlukla bir bulgunun varlığını veya yokluğunu bildirir; "
            "bu nedenle sonuç için düşük ifadesi uygun olmayabilir. Negatif veya "
            "saptanmadı sonucu ilgili durumu her zaman tek başına dışlamaz."
        )
    else:
        high = (
            f"Yüksek {lab} sonucu, ölçümün laboratuvarın ilgili referans "
            "aralığının üzerinde olduğunu gösterir. Bunun farklı nedenleri "
            "olabilir; sonuç tek başına tanı koydurmaz ve diğer bulgularla "
            "birlikte değerlendirilir."
        )
        low = (
            f"Düşük {lab} sonucu, ölçümün laboratuvarın ilgili referans "
            "aralığının altında olduğunu gösterir. Bunun anlamı testin türüne ve "
            "kişinin sağlık bilgilerine göre değişir; tek başına tanı koydurmaz."
        )

    urgent = item.get(
        "urgent",
        "Şiddetli veya hızla kötüleşen belirtiler varsa gecikmeden sağlık hizmeti alın.",
    )
    if result_kind == "qualitative":
        consult = (
            f"{lab} sonucu pozitif, reaktif, saptandı, uyumsuz veya belirsiz "
            "olarak raporlandıysa sonucunuzun doğrulama ya da tekrar gerektirip "
            f"gerektirmediğini sağlık uzmanıyla değerlendirin. {urgent}"
        )
        questions = (
            f"{lab} sonucundaki ifade tam olarak ne anlama geliyor? "
            "Doğrulama veya tekrar testi gerekiyor mu? Örnek zamanı ya da test "
            "yöntemi sonucu etkileyebilir mi?"
        )
    elif result_kind == "panel":
        consult = (
            f"{lab} içindeki bir bileşen referans aralığı dışında, pozitif, "
            "reaktif veya belirsiz raporlandıysa paneli tek tek bileşenleriyle "
            f"birlikte doktorunuzla değerlendirin. {urgent}"
        )
        questions = (
            f"{lab} içindeki hangi bileşenler değerlendirme gerektiriyor? "
            "Bileşenler birlikte ne ifade ediyor? Takip veya ek test gerekiyor mu?"
        )
    else:
        consult = (
            f"{lab} sonucunuz referans aralığı dışındaysa, önceki sonuçlara göre "
            "belirgin değiştiyse veya yeni şikayetlerle birlikteyse doktorunuzla "
            f"değerlendirin. {urgent}"
        )
        questions = (
            f"{lab} sonucumu diğer tahlillerimle birlikte nasıl değerlendirmeliyiz? "
            "Sonucu etkilemiş olabilecek geçici bir durum var mı? Takip veya ek test gerekir mi?"
        )
    sections = {
        C.SECTION_WHAT: draft_content,
        C.SECTION_WHY: item["purpose"],
        C.SECTION_HIGH: high,
        C.SECTION_LOW: low,
        C.SECTION_WHEN_DOCTOR: consult,
        C.SECTION_DOCTOR_QUESTIONS: questions,
    }
    overrides = item.get("section_overrides", {})
    if not isinstance(overrides, dict):
        raise ValueError(f"section_overrides nesne olmalidir: {lab}")
    unknown = set(overrides).difference(SECTIONS)
    if unknown:
        raise ValueError(f"Bilinmeyen aciklama bolumu ({lab}): {', '.join(sorted(unknown))}")
    for heading, content in overrides.items():
        value = str(content).strip()
        if not value:
            raise ValueError(f"Bos aciklama bolumu ({lab}): {heading}")
        sections[heading] = value
    return sections


def _markdown(item: Dict[str, Any], source_url: str, sections: Dict[str, str]) -> str:
    lines = [
        "---",
        f"lab_test: {item['lab_test']}",
        "source_title: MedlinePlus",
        f"source_url: {source_url}",
        "safety_level: general",
        "---",
        "",
    ]
    for heading in SECTIONS:
        lines.extend((f"## {heading}", sections[heading], ""))
    return "\n".join(lines)


def publish_batch(catalog_path: Path, docs_dir: Path, seed_output: Path, store: SourceSyncStore) -> int:
    payload = json.loads(catalog_path.read_text(encoding="utf-8"))
    items = payload.get("items")
    if not isinstance(items, list) or not items:
        raise ValueError("RAG batch items listesi icermelidir.")

    prepared = []
    seen_labs = set()
    seen_slugs = set()
    for item in items:
        lab = str(item.get("lab_test", "")).strip()
        slug = str(item.get("slug", "")).strip()
        if not lab or lab in seen_labs or not slug or slug in seen_slugs:
            raise ValueError(f"Gecersiz veya yinelenen RAG kaydi: {lab}")
        seen_labs.add(lab)
        seen_slugs.add(slug)
        if item.get("result_kind") not in {"scalar", "panel", "qualitative"}:
            raise ValueError(f"Gecersiz result_kind: {lab}")
        if not item.get("purpose") or not item.get("aliases"):
            raise ValueError(f"Eksik RAG metadata: {lab}")

        source = store.get(item["source_key"])
        draft = store.get_current_draft(item["source_key"])
        if source is None or source.review_status != "approved":
            raise ValueError(f"Kaynak onayli degil: {item['source_key']}")
        if draft is None or draft.review_status != "approved":
            raise ValueError(f"Turkce taslak onayli degil: {item['source_key']}")
        sections = _sections(item, draft.content)
        prepared.append((item, source, sections))

    docs_dir.mkdir(parents=True, exist_ok=True)
    seed_documents = []
    for item, source, sections in prepared:
        (docs_dir / f"{item['slug']}.md").write_text(
            _markdown(item, source.source_url, sections), encoding="utf-8"
        )
        seed_documents.append(
            {
                "lab_test": item["lab_test"],
                "title": item["title"],
                "source_title": "MedlinePlus",
                "source_url": source.source_url,
                "sections": sections,
                "doctor_questions": [part.strip() + "?" for part in sections[C.SECTION_DOCTOR_QUESTIONS].split("?") if part.strip()],
            }
        )

    seed_output.write_text(
        json.dumps({"batch_id": payload["batch_id"], "documents": seed_documents}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    for item, _, _ in prepared:
        store.mark_draft_published(item["source_key"])
    return len(prepared)


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Onayli source batch'ini RAG'e yayinlar.")
    parser.add_argument("catalog_path", type=Path)
    parser.add_argument("--db-path", default="data/sana_rag.db")
    parser.add_argument("--docs-dir", type=Path, default=Path("data/medical_docs"))
    parser.add_argument("--seed-output", type=Path, default=Path("data/source_batches/medlineplus_common_01_seed.json"))
    args = parser.parse_args(argv)
    try:
        count = publish_batch(args.catalog_path, args.docs_dir, args.seed_output, SourceSyncStore(args.db_path))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Batch yayinlanamadi: {exc}")
        return 1
    print(f"Yayinlanan RAG belgesi: {count}")
    print(f"Durum: approved + published")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
