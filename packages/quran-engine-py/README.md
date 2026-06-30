# quran-engine (Python)

Python port of the [Quran Tajweed Engine](../../README.md). Pure standard library — no dependencies. Reads the canonical JSON in [`../../data`](../../data) and follows the shared [porting contract](../../docs/PORTING.md).

## Install / use

No build needed to use it from the repo — the loader finds `/data` automatically:

```python
from quran_engine import Engine

engine = Engine.load()                                  # core data (quran, juz, reciters, tajweed, rules)
# opt-in heavier data:
# engine = Engine.load(load_qiraat=True, load_surah_info=True)

# Quran
engine.quran.surah(2).name_english                       # "The Cow"
engine.quran.ayah(2, 255).text_arabic                    # Ayat al-Kursi
engine.quran.global_ayah_number(2, 1)                    # 8

# Tajweed (colored spans from the pre-computed corpus)
for sp in engine.tajweed(1, 1):
    print(sp.rule, sp.color, repr(sp.text))

# Juz / Page
engine.juz_page.first_ayah_of_juz(30)                    # (Surah, Ayah)

# Recitations
from quran_engine import surah_audio_url, ayah_audio_url
r = next(r for r in engine.reciters.all() if r.name == "Mishary Alafasy")
surah_audio_url(r, 1)                                    # full-surah mp3
ayah_audio_url(r, engine.quran.global_ayah_number(2, 1)) # single-ayah mp3

# Search
engine.search.search_verses("lord of the worlds")
engine.search.parse_reference("2:255")                   # {"surah": 2, "ayah": 255}

# Sorting
from quran_engine import sort_surahs
sort_surahs(engine.quran.all(), "ayahs", "descending")[0].id   # 2
```

## Modules

`quran` · `juz_page` · `tajweed` · `audio` · `search` · `sorting` · `cache` · `text` — one per feature, mirroring the JS package and the `docs/` specs.

## Tajweed strategy

This port uses **strategy (A)** from the porting guide: it loads the pre-computed annotation corpus (`data/tajweed-annotations.json`) and maps each rule to its color. Annotation offsets are UTF-16, so the port converts them with `quran_engine.text.utf16_slice` (Python strings are code-point indexed).

## Tests

```bash
python tests/test_engine.py        # or: python -m pytest
```

## License

MIT — see [../../LICENSE](../../LICENSE) and [../../CREDITS.md](../../CREDITS.md).
