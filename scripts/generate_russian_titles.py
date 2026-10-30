#!/usr/bin/env python3
"""Генерирует Packages/AnivibeCore/Sources/AnivibeCore/Catalog/RussianTitleDictionary+Data.swift.

Источники: публичный API Shikimori (топ по популярности: TV + фильмы, официальные русские
названия и синонимы) и ручной список разговорных вариантов из russian_title_aliases.py.
Сеть нужна только при генерации; приложение читает готовый файл офлайн.

    python3 scripts/generate_russian_titles.py            # обновить словарь
    python3 scripts/generate_russian_titles.py --check    # только проверить ручной список
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from russian_title_aliases import CURATED  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Packages/AnivibeCore/Sources/AnivibeCore/Catalog/RussianTitleDictionary+Data.swift"
CACHE = ROOT / "build/shikimori_titles.json"
API = "https://shikimori.io/api"
HEADERS = {"User-Agent": "Anivibe-dev (russian title dictionary generator)"}
FIELDS = ["id", "name", "russian", "synonyms", "english", "japanese", "kind", "aired_on", "franchise", "score"]
TOP_PAGES = 8
MOVIE_PAGES = 2


def get(url):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=20) as response:
                return json.load(response)
        except Exception as error:  # noqa: BLE001 — сеть, повторяем
            print("retry", url, error, file=sys.stderr)
            time.sleep(3 + attempt * 3)
    return None


def popular_ids():
    ids = []
    for page in range(1, TOP_PAGES + 1):
        ids += [a["id"] for a in get(f"{API}/animes?order=popularity&limit=50&page={page}&censored=true") or []]
        time.sleep(0.4)
    for page in range(1, MOVIE_PAGES + 1):
        ids += [a["id"] for a in get(f"{API}/animes?order=popularity&limit=50&page={page}&kind=movie&censored=true") or []]
        time.sleep(0.4)
    return list(dict.fromkeys(ids))


def fetch(ids, cache):
    for n, anime_id in enumerate(ids):
        if anime_id in cache:
            continue
        data = get(f"{API}/animes/{anime_id}")
        if data:
            cache[anime_id] = {k: data.get(k) for k in FIELDS}
        time.sleep(0.35)
        if n % 50 == 0:
            print(n, "/", len(ids), file=sys.stderr)
    return cache


def validate(cache):
    bad = []
    for anime_id, (fragment, _) in CURATED.items():
        name = (cache.get(anime_id) or {}).get("name") or ""
        if fragment.lower() not in name.lower():
            bad.append((anime_id, fragment, name, (cache.get(anime_id) or {}).get("russian")))
    for item in bad:
        print("MISMATCH", item, file=sys.stderr)
    return not bad


def clean(text):
    return text.replace("\t", " ").replace("|", "/").replace("\\", "/").strip()


def render(cache):
    lines = []
    for anime_id, anime in sorted(cache.items()):
        russian = clean(anime.get("russian") or "")
        name = clean(anime.get("name") or "")
        english = [clean(e) for e in (anime.get("english") or []) if e]
        aliases = []
        for alias in (anime.get("synonyms") or []) + CURATED.get(anime_id, ("", []))[1]:
            alias = clean(alias)
            if alias and alias not in aliases and alias != russian and alias != name and alias not in english:
                aliases.append(alias)
        if not russian and not aliases:
            continue
        lines.append("\t".join([str(anime_id), russian, name, "|".join(english), "|".join(aliases)]))
    header = '''import Foundation

// Сгенерировано scripts/generate_russian_titles.py по публичным данным Shikimori (топ по популярности)
// и ручному списку разговорных названий. Формат строки: malID<TAB>русское<TAB>ромадзи<TAB>english|…<TAB>алиас|…
// Запрещённые в данных символы: табуляция и вертикальная черта заменяются при генерации.
extension RussianTitleDictionary {
    static let rawData = """
'''
    return header + "\n".join(lines) + '\n"""\n}\n', len(lines)


def main():
    cache = {}
    if CACHE.exists():
        cache = {a["id"]: a for a in json.loads(CACHE.read_text())}
    if "--check" not in sys.argv:
        ids = popular_ids() + [i for i in CURATED if i not in cache]
        fetch(ids, cache)
        CACHE.parent.mkdir(exist_ok=True)
        CACHE.write_text(json.dumps(list(cache.values()), ensure_ascii=False, indent=0))
    ok = validate(cache)
    if "--check" in sys.argv:
        sys.exit(0 if ok else 1)
    swift, count = render(cache)
    OUTPUT.write_text(swift)
    print("entries", count, "->", OUTPUT.relative_to(ROOT), file=sys.stderr)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
