# 11 · Riwayah tajweed

Where a reading differs from Ḥafṣ, and why. Seven packs (one per verified non-Ḥafṣ riwayah), carrying each printed muṣḥaf's own coloured marks, its own legend, and a shared catalogue that explains what each rule *means*.

> **Key facts:** this is a **different layer** from [02 · Tajweed](02-tajweed.md). Extents are base-**letter** indices, not character offsets. The meaning of a colour is **per edition**, always read `legend(riwayah)`.

## Why it cannot be detected

The tajweed detector in [02](02-tajweed.md) reads the text and works out the rules: a nūn sākin before a bā is iqlāb, wherever it appears, in any reading. That is why it can ship as an algorithm.

Riwayah tajweed is the opposite kind of fact. That Warsh reads a particular alif with *taqlīl*, that al-Bazzī doubles the tāʾ of a particular word onto the one before it, that Ḥafṣ and Qālūn part company at a specific letter: none of that is derivable from the text, because it **is** the text's difference. It comes from each printed muṣḥaf: the imālah dot (U+065C), the taqlīl ring (U+06EA), the ṣilah wāw (U+06E5), the idghām bare-letter-plus-shadda orthography, and the colour marks the edition prints, all extracted once at build time and cross-checked against the printed originals.

So the engine ships it as **data**, not as a detector, and the data is per riwayah.

## Two things to get right

**1. A colour means what *this* edition says it means.** Every printed muṣḥaf has its own legend box, and the same colour is a different rule in a different riwayah. Never hard-code a palette; read the legend:

```js
engine.qiraatTajweed.legend("warsh");
// [{ code: "m", rule: "khilaf_harf", arabic: "الحرف المخالف لحفص",
//    english: "Letter differing from Ḥafṣ", short: "…", long: "…" }, …]
```

The `rule` **key** is stable across riwayat (`idgham` is `idgham` everywhere), which is why `describe(rule)` can explain it once for all seven. The `code` is the edition's own single-letter tag and is only meaningful inside that pack.

**2. Extents are letters, not characters.** A rule colours base letters in reading order, `firstLetter`…`lastLetter` inclusive, with diacritics not counted, or the whole word when `wholeWord` is true (`firstLetter` is `-1`). Map them onto your own rendering:

```js
engine.qiraatTajweed.wordRules(2, 3, "warsh");
// [{ word: 1, rule: "khilaf_harf", code: "m", firstLetter: 1, lastLetter: 1, wholeWord: false },
//  { word: 9, rule: "madd_badal",  code: "c", firstLetter: 3, lastLetter: 4, wholeWord: false }, …]
```

`word` is the 1-based index of the word within the ayah, in **that riwayah's** text.

## Finding the differences

`khilafMarkers` is the index behind "show me where these two readings part": the ayahs of a surah this riwayah marks as differing from Ḥafṣ somewhere, without walking every ayah's rules.

```js
engine.qiraatTajweed.khilafAyahs(2, "warsh");     // [253]
engine.qiraatTajweed.hasKhilaf(2, 253, "warsh");  // true
```

That is enough to drive a comparison view: list the marked ayahs, then pull `wordRules` for the one the reader opens.

## The rule catalogue

`data/tajweed-qiraat/rules.json` explains every rule key in one line and in a paragraph, shared across all seven packs so an app writes the explanation once:

```js
engine.qiraatTajweed.describe("taqlil");
// { short: "Vowel slightly inclined toward 'eh'.",
//   long:  "The colored vowel is slightly inclined from 'aa' toward 'eh' …" }
engine.qiraatTajweed.ruleKeys();
// ["ghunnah_kha_ghayn", "ha_dhamir", "ibtida_wasl", "idgham", "imalah", …]
```

The seventeen keys cover the differences the ten readings actually mark: `khilaf_word`, `khilaf_harf`, `idgham`, `imalah`, `imalah_taqlil`, `taqlil`, `silah_meem`, `ha_dhamir`, `sakt`, `ishmam_sad`, `ghunnah_kha_ghayn`, `madd_badal`, `madd_leen`, `raa_muraqqaqah`, `lam_mughallazah`, `tashdid_ta`, `ibtida_wasl`.

## Files

```
data/tajweed-qiraat/
├── rules.json          rule key → { short, long }
└── <slug>.json         warsh · qaloon · duri · susi · buzzi · qunbul · shubah
```

```json
{
  "riwayah": "warsh",
  "version": 2,
  "legend": [{ "code": "m", "rule": "khilaf_harf", "arabic": "…", "english": "…" }],
  "rules": { "2": { "3": { "1": [["m", 1, 1]], "9": [["c", 3, 4], ["g", 6, 6]] } } },
  "khilafMarkers": { "2": [253] }
}
```

`rules` is surah → ayah → word → `[code, firstLetter, lastLetter]`. Sparse: an ayah with nothing to colour is absent, which is most of them.

## Why only seven

The twelve riwayat whose text this engine does not publish have no pack here either; their rules index into that text by word position, so the offsets would point at nothing. See [10 · The printed muṣḥaf](10-mushaf.md#the-twelve-without-text). Ḥafṣ has no pack because "differs from Ḥafṣ" is not a thing Ḥafṣ does; its tajweed is the detector's job.

## API

| Method | Returns |
|---|---|
| `available()` | the riwayat with a pack loaded |
| `legend(riwayah)` | the edition's legend, each row carrying the shared explanation |
| `wordRules(surah, ayah, riwayah)` | what this riwayah colours in one ayah |
| `khilafAyahs(surah, riwayah)` | the ayahs of a surah that differ from Ḥafṣ somewhere |
| `hasKhilaf(surah, ayah, riwayah)` | whether one ayah does |
| `describe(rule)` | `{ short, long }` for a rule key |
| `ruleKeys()` | every key the catalogue explains |

```js
const engine = await loadFromDisk({ loadQiraatTajweed: true });
```

```python
engine = Engine.load(load_qiraat_tajweed=True)
```
