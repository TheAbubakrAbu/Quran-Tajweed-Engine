# Glossary

Plain-English definitions of every Quran, recitation, and tajweed term used in this engine. No prior knowledge assumed. (Transliterations are approximate; Arabic is read right-to-left.)

## Quran structure

| Term | Meaning |
|---|---|
| **Quran** (قرآن) | The holy book of Islam: 114 chapters, 6,236 verses in this counting. |
| **Surah** (سورة) | A chapter. Numbered 1–114. Each has Arabic, transliterated, and English names. |
| **Ayah** (آية) | A verse. Numbered within its surah (e.g. "2:255" = surah 2, verse 255). |
| **Bismillah** (بسملة) | The opening phrase "In the name of Allah…" that begins most surahs. |
| **Makkan / Makki** (مكي) | Revealed in Mecca (generally earlier, shorter, on faith and the unseen). |
| **Madinan / Madani** (مدني) | Revealed in Medina (generally later, on law and community). |
| **Revelation order** | The chronological order in which surahs were revealed (differs from the mushaf order 1–114). |
| **Mushaf** (مصحف) | A physical/printed copy of the Quran. "Mushaf order" = the standard 1→114 sequence. |
| **Juz** (جزء), pl. **Ajzaa** | One of 30 roughly-equal parts the Quran is divided into for daily reading (a.k.a. *para*). |
| **Page** | A page of the standard Madani mushaf (~604 pages). Each ayah carries its page number. |
| **Sajdah** (سجدة) | A verse of prostration — on reciting it, the reader prostrates. Marked with ۩. |
| **Muqatta'at** (حروف مقطعة) | The "disconnected letters" that open 29 surahs (e.g. الم, حم) — recited letter-by-letter. |
| **Khatm / Khatmah** (ختمة) | A complete reading of the whole Quran, often planned over a period (e.g. a month). |

## Text, script & translation

| Term | Meaning |
|---|---|
| **Uthmani script** | The traditional Quranic spelling/orthography (as standardized under Caliph Uthman). |
| **Tashkeel / Harakat** (تشكيل / حركات) | The vowel and pronunciation marks written above/below letters (fatha, damma, kasra, sukoon, shadda, etc.). |
| **Diacritics** | General term for those marks. "Clean Arabic" = the text with diacritics removed. |
| **Transliteration** | The Arabic sounds written in Latin letters (e.g. *Bismi Allahi…*) for non-Arabic readers. |
| **Saheeh International** | A widely used modern English translation (`textEnglishSaheeh`). |
| **The Clear Quran** | Dr. Mustafa Khattab's English translation (`textEnglishMustafa`). |
| **Tafsir** (تفسير) | Scholarly explanation/commentary of the Quran. The surah intros here are from Maududi and Ibn Ashur. |

## Recitation & readings

| Term | Meaning |
|---|---|
| **Tajweed** (تجويد) | The rules of correct Quranic pronunciation — how letters are sounded, merged, hidden, and stretched. This engine colors them. |
| **Qira'ah** (قراءة), pl. **Qira'at** | A canonical "reading" of the Quran — a transmitted way of reciting, with minor differences in pronunciation/wording. There are 10 well-known ones. |
| **Riwayah** (رواية) | A specific transmission of a qira'ah through a named narrator. |
| **Hafs an Asim** | The most widespread riwayah today — the default text in this engine and most mushafs. |
| **Warsh, Qaloon, ad-Duri, as-Susi, al-Bazzi, Qunbul, Shubah** | Other riwayat included in `data/qiraat/` (used across North/West Africa and elsewhere). |
| **Reciter / Qari** (قارئ) | A person who recites the Quran. The engine lists 60+ with audio feeds. |
| **Murattal** (مرتل) | A measured, steady recitation style (most common for listening/learning). |
| **Mujawwad** (مجود) | A melodic, elaborated recitation style. |
| **Muallim** (معلم) | A "teacher" style, often call-and-response for learning. |
| **Waqf** (وقف) | A stop/pause in recitation. Mushafs print small waqf symbols indicating where/whether to pause. |

## Tajweed rules (the colored categories)

These are the 17 categories the engine detects. Colors are in `data/tajweed-rules.json`.

### Silent / joining (shown gray)
| Rule | Plain meaning |
|---|---|
| **Lam Shamsiyyah** (لام شمسية) | The "L" of *al-* goes silent before a "sun letter" (the next letter doubles instead): *ash-shams*, not *al-shams*. |
| **Dropped letter** | A letter written in the script but not pronounced. |
| **Hamzat al-Wasl** (همزة الوصل) | A "connecting hamza" (ٱ) — pronounced only when you *start* on it; silent when reading continuously. |
| **Idgham bila Ghunnah** (إدغام بلا غنة) | Merging a noon-sound into the next letter **without** a nasal hum (before ل or ر). |

### Ghunnah / nasal sounds (~2 beats of nasal hum)
| Rule | Plain meaning |
|---|---|
| **Ghunnah** (غنة) | A nasal hum made through the nose — the buzzing on ن or م with a shadda. |
| **Idgham with Ghunnah** (إدغام بغنة) | Merging a noon-sound into the next letter **with** a nasal hum (before ي ن م و). |
| **Ikhfaa** (إخفاء) | "Hiding" — a noon-sound is partly concealed with a nasal hum before certain letters. *Light* vs *heavy* depending on the next letter. |
| **Iqlaab** (إقلاب) | "Conversion" — a noon-sound turns into an *m* sound before ب. |

### Sifaat / articulation
| Rule | Plain meaning |
|---|---|
| **Qalqalah** (قلقلة) | A slight "bounce" or echo on the letters ق ط ب ج د when they have a sukoon or end a word. |
| **Tafkhim** (تفخيم) | "Heaviness" — certain letters (خ ص ض ط ظ غ ق, and sometimes ر) are pronounced full and thick. |

### Madd / elongation (stretching a vowel)
| Rule | Plain meaning | Length |
|---|---|---|
| **Madd Tabee'i (Natural)** (مد طبيعي) | The basic 2-count stretch on ا و ي. | 2 |
| **Madd (miniature marks)** | Same 2-count stretch, written with small superscript vowel marks. | 2 |
| **Madd Muttasil (Connected)** (مد متصل) | A madd letter followed by a hamza **in the same word** — stretched longer. | 4–5 |
| **Madd Munfasil (Separated)** (مد منفصل) | A madd at a word's end meeting a hamza at the **next word's** start. | 2/4/5 |
| **Madd Aarid / Leen (Stop madd)** (مد عارض للسكون) | Extra stretch that appears only when you **stop** at a word's end. | 2/4/6 |
| **Madd Lazim (Necessary)** (مد لازم) | An obligatory fixed 6-count stretch (madd followed by a permanent sukoon/shadda). | 6 |

> "Counts" (*harakat*) are the timing unit of tajweed — roughly the time to say one short vowel. They keep recitation rhythmically consistent. The engine **colors** these rules; it doesn't enforce timing.

## Engine terms

| Term | Meaning |
|---|---|
| **Global ayah number** | A verse's position 1–6236 across the whole Quran (used by the ayah-audio CDN). |
| **PaintOp / Span** | The engine's unit of tajweed output: a text range + a rule category + a color. |
| **Annotation corpus** | The pre-computed file of tajweed spans for every ayah (`data/tajweed-annotations.json`). |
| **Grapheme cluster** | One "visual character" = a base letter plus its attached marks. Tajweed works on these. |
| **UTF-16 offset** | How span positions are measured (see [architecture](architecture.md#string-offsets-the-one-cross-language-gotcha)). |
