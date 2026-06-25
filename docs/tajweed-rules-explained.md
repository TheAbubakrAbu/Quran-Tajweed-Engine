# Tajweed rules explained (in detail)

A plain-English, teaching-oriented explanation of **what every tajweed rule means** — what *idgham*,
*ikhfaa*, *ghunnah*, *qalqalah*, *madd*, *tafkhim* actually are, when they apply, and how they sound. If
[docs/02-tajweed.md](02-tajweed.md) is the engineering spec for *detecting* the rules, this is the human
guide to *understanding* them.

> **Scope:** This guide applies specifically to **riwayat Hafs an Asim**, the most widely recited reading
> today and the standard in most printed mushafs. Other riwayat (Warsh, Qaloon, Khalaf, …) differ in some
> details — elongation lengths, treatment of hamzah, and certain pronunciations — so not every rule here
> applies identically to them.
>
> **Source:** the "Tajweed Foundations" lessons in the open-source [Al-Islam](https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars)
> app (see [CREDITS.md](../CREDITS.md)); stopping-sign meanings from
> [Studio Arabiya](https://studioarabiya.com/blog/tajweed-rules-stopping-pausing-signs/). The per-rule
> color and trigger-letter tables are generated from [`data/tajweed-rules.json`](../data/tajweed-rules.json)
> into [tajweed-rules-reference.md](tajweed-rules-reference.md).

## What is tajweed?

**Tajweed** (تجويد) is the science and practice of reciting the Quran correctly and beautifully — giving
each letter its proper articulation and characteristics. The word comes from the root ج-و-د (*j-w-d*),
"to improve / make excellent." It means reciting the words of Allah precisely, clearly, and with care,
preserving the oral tradition passed down from the Prophet ﷺ. Allah commands: *"And recite the Quran with
measured recitation (tartil)."* (Quran 73:4)

Pronunciation rests on two pillars:
- **Makharij** (مخارج الحروف) — the *points of articulation*, where each letter originates in the mouth/throat.
- **Sifat** (صفات الحروف) — the *characteristics* of letters: heaviness (tafkhim), lightness (tarqiq), echo (qalqalah), etc.

Even small changes in pronunciation can change meaning, so tajweed protects both the beauty **and the
accuracy** of the Quran.

## Counts (harakat)

Many rules are measured in **counts** (*harakat*) — roughly the time to say one short vowel. Counts keep
recitation rhythmically consistent. Consistency matters more than exact length: holding a 4-count madd
*everywhere* is better than randomly varying 2–6.

| Rule | Counts |
|---|---|
| Natural madd · Badal · ʿIwad · Tamkin · Silah sughra | 2 |
| Ghunnah (ikhfaa, idgham w/ ghunnah, shafawi, mushaddadah) | 2 |
| Madd Munfasil · Munfasil Hukmi · Silah kubra | 2 / 4 / 5 |
| Madd Muttasil | 4 / 5 |
| Madd Aarid lis-Sukoon · Leen | 2 / 4 / 6 |
| Madd Lazim (Harfi & Kalimi) | 6 (always) |

---

## Heavy & light (tafkhim & tarqiq)

Letters differ in **weight**. Some are always heavy, some always light, some conditional.

- **Heavy (tafkhim, تفخيم)** — the *istiʿla* letters **خ ص ض غ ط ق ظ**. Pronounced with the back of the
  tongue raised, a full, deep sound — heavy even with kasrah. (e.g. قَالَ, صِرَاط, طَبَعَ.)
- **Light (tarqiq, ترقيق)** — every other letter: relaxed tongue, no back-tongue elevation, clear and sharp.
- **Conditional:**
  - **Raa (ر)** — heavy with fatha (ـَ) or damma (ـُ); light with kasrah (ـِ). Look at the vowel *on the raa
    itself*. (Heavy: رَبّ, رُزِقُوا · Light: رِجَال, فِرْعَوْن.)
  - **Laam (ل)** — always light **except** in the Name *Allah* (ٱللَّه) when preceded by fatha or damma →
    heavy (قَالَ ٱللَّهُ). After a kasrah it stays light (بِٱللَّهِ).
  - **Alif (ا)** — has no sound of its own; it **inherits** the weight of the letter before it (heavy after
    a heavy letter, light after a light one).

The engine colors heavy letters with the `tafkhim` category. See per-letter weights in
[arabic-alphabet.md](arabic-alphabet.md#tajweed-weight-heavy-vs-light).

---

## "Al-" : sun letters & moon letters (Shamsiyyah & Qamariyyah)

When the definite article **ٱلـ ("al-")** precedes a word, the laam (ل) is pronounced — or not — depending
on the next letter. **The mushaf shows you which** via a sukun or a shaddah.

- **Qamariyyah (moon letters)** — the laam is **pronounced clearly**. The laam carries a sukun (ٱلْ), and
  the sound is "al-". Moon letters: **ا ب ج ح خ ع غ ف ق ك م هـ و ي**. (ٱلْقَمَر = *al-qamar*, ٱلْكِتَاب = *al-kitab*.)
- **Shamsiyyah (sun letters)** — the laam is **not pronounced**. It **merges** into the following letter,
  which doubles (shown by a shaddah). Sun letters: **ت ث د ذ ر ز س ش ص ض ط ظ ل ن**. (ٱلشَّمْس = *ash-shams*,
  not *al-shams*; ٱلرَّحْمَٰن = *ar-rahman*.)

**The shaddah is your visual cue:** if you see it on the letter after "al-", the laam is gone. This is
*idgham* of the laam, not deletion. (In the engine, the silent laam is the `lamShamsiyah` category.)

---

## Noon Sakinah & Tanween — the four rules

A **noon sakinah** is a noon with sukun (نْ). **Tanween** (ـً ـٍ ـٌ) looks like doubled vowels but is
pronounced as a **hidden noon sound** at the end of a word (بًا → *ban*, بٌ → *bun*, بٍ → *bin*). What
happens to that noon sound depends **entirely on the next letter** — there are four rules:

### 1. Idhaar (إظهار) — "clear"
The noon sound is pronounced **clearly and fully**, no merging, no nasal hum. Triggered by the **six throat
letters: ء ه ع ح غ خ** (the throat blocks merging). Example: مِنْ هَادٍ = *min hadin*.

### 2. Idghaam (إدغام) — "merging"
The noon sound **merges into** the following letter. Trigger letters: **ي ر م ل و ن** (mnemonic
*yarmaluun*). Two kinds:
- **Idghaam with ghunnah** — before **ي ن م و**: the merge keeps a nasal hum (ghunnah). مَن يَقُول = *may-yaqul*.
- **Idghaam without ghunnah** — before **ل ر**: a clean merge, no nasalization. مِن رَّبِّهِم = *mir-rabbihim*.

> **What "idgham" literally means:** to *insert / merge* one sound into another so they become one doubled
> letter. The first letter loses its independent sound.

### 3. Iqlaab (إقلاب) — "conversion"
Before the single letter **ب**, the noon sound **changes into a meem (م)** with a ghunnah. The noon is not
pronounced at all — it becomes a hidden meem. سَمِيعٌۢ بَصِير = *samiʿum-basir*. (Often marked with a small
meem ۢ above the noon/tanwin.)

### 4. Ikhfaa (إخفاء) — "hiding"
The noon is **partially hidden** — pronounced with a ghunnah, between full clarity and full merging; the
tongue does not quite touch the articulation point. Triggered by the **remaining 15 letters** (everything
not in the other three groups). مِن شَرِّ = *min-sharri* (nasal). The engine splits ikhfaa by the heaviness
of the next letter into **light** (before ت ث ج د ذ ز س ش ف ك) and **heavy** (before ص ض ط ظ ق).

> **Ghunnah strength:** strongest in ikhfaa and idgham-with-ghunnah; medium for a noon/meem with shaddah;
> none for idgham-without-ghunnah.

---

## Meem Sakinah — the three "shafawi" rules

A **meem sakinah** is a meem with sukun (مْ). Its three rules are called **shafawi** ("of the lips," from
*shafah* = lip) because meem is a lip letter. The rule depends on the letter after the meem:

1. **Ikhfaa Shafawi** — meem sakinah **+ ب**. The meem is hidden lightly with a ghunnah for ~2 counts; the
   lips come close but don't fully close. (أَم بِهِۦ = *am bihi*, nasal.)
2. **Idgham Shafawi** — meem sakinah **+ م**. The first meem merges into the second → a doubled meem with
   ghunnah (~2 counts). (لَهُم مَّا = *lahum-maa*.)
3. **Idhaar Shafawi** — meem sakinah **+ any other letter**. The meem is pronounced clearly, no extra
   ghunnah. (عَلَيْكُمْ سَلَامٌ.)

> **Meem mushaddadah (مّ)** — a meem with shaddah — is always held with a strong ghunnah for ~2 counts
> (ثُمَّ, لَمَّا). It's closely related, though not one of the three meem-sakinah rules. The engine colors
> both meem and noon shaddah as `generalGhunnah`.

---

## Ghunnah (غُنَّة)

**Ghunnah** is the **nasal hum** produced through the nose. It is the sound carried during ikhfaa, idgham
with ghunnah, iqlaab, and on any noon/meem with a shaddah. Its baseline length is **2 counts**. It's not a
separate "step" you add — it's the resonance you hold while the rule plays out.

---

## Qalqalah (قَلْقَلَة) — the echo/bounce

**Qalqalah** is a slight **bouncing/echoing** sound on five letters — **ق ط ب ج د** (mnemonic *Qutb Jad*) —
when they carry a sukun or you stop on them. It is **not** a vowel and **not** silence; its purpose is to
keep the letter from being cut off. Think of it as *releasing* the letter, not opening the mouth.

- Occurs when one of the five letters has a sukun, or is stopped on (waqf). (أَحَدْ, يَجْعَل, أَجْر, يَقْطَع.)
- **It is wrong** if it sounds like an added "a" vowel, and **also wrong** if it disappears entirely. A
  slight, effortless echo — no more.

---

## Madd (مَدّ) — elongation

**Madd** means to **lengthen** a vowel sound. In recitation this lengthening is measured and rule-based,
not stylistic, and is counted in *harakat* (counts). The madd letters are **ا و ي**.

### Natural madd (Madd Tabiʿi) — 2 counts
The default. A madd letter with its matching vowel and **nothing special after** (no hamzah, no sukun):
alif after fatha, waw after damma, yaa after kasra. (قَالَ, يَقُولُ, فِيهِ.) Two counts — no more, no less.

### Madd Wajib Muttasil ("connected") — 4 or 5 counts
A madd letter **followed by a hamzah in the *same* word**. Mandatory (*wajib*) lengthening. (جَاءَ,
ٱلسَّمَاءِ, سُوءَ.) Be consistent in your chosen length.

### Madd Jaiz Munfasil ("separated") — 2, 4, or 5 counts
A madd letter at the **end of a word** followed by a hamzah at the **start of the next word**. (فِي
أَنفُسِكُمْ, قَالُوا إِنَّا.) If you lengthen it, lengthen it consistently throughout your recitation.

### Madd Munfasil Hukmi ("ruled" separated) — 2, 4, or 5 counts
A special case that *looks* connected but is *recited* separated. A superscript madd letter (dagger alif ٰ,
small waw ۥ, or small yaa ۦ) carrying a maddah (ٓ) sits inside **one written word** followed by a hamzah —
but that carrier is actually the tail of a joined vocative **يَا ("O…")** or demonstrative **هَا ("these…")**
particle, so in meaning it is two words. (يَٰٓأَيُّهَا = *ya-ayyuha*, هَٰٓأَنتُمۡ = *ha-antum*, يَٰٓـَٔادَمُ = *ya-Adam*.)

One word can hold **both**: هَٰٓؤُلَآءِ → *هَٰٓؤُ* is Munfasil Hukmi (the joined هَا), while *لَآءِ* is a true
Muttasil (a real alif + hamzah in one word). There are 21 such written words in the Hafs mushaf (the engine
lists them; see [docs/02 §6.1](02-tajweed.md)). **Not** every dagger-alif + hamzah is hukmi — when both sit
inside one genuine word with no joined يَا/هَا (e.g. أُوْلَٰٓئِكَ, مَلَٰٓئِكَة, إِسۡرَٰٓءِيل) it's ordinary Muttasil.

### Other madd types
- **Madd Badal** — a hamzah **before** the madd (the reverse of muttasil). 2 counts; not lengthened. (ءَامَنُوا, ءَادَمَ.)
- **Madd ʿIwad** — when you **stop** on a word ending in tanwin-fath (ـً), the tanwin drops and the alif is
  stretched 2 counts. Not aarid lis-sukoon. (stop on عَلِيمًا → *ʿaliimaa*.)
- **Madd Tamkin** — a kasrah+shaddah yaa meeting a madd yaa; 2 counts, without swallowing either yaa. (ٱلنَّبِيِّـۧنَ.)
- **Madd Silah** — the attached pronoun **ه** ("his/its") between two voweled letters gets a hidden waw/yaa.
  *Sughra* (small) = 2 counts; *Kubra* (large) = 4–5 counts when a hamzah follows (then it behaves like Munfasil). (إِنَّهُۥ كَانَ; بِهِۦٓ أَحَدَۢا.)
- **Dagger alif & tiny madd marks** — superscript ٰ ۥ ۦ are still a 2-count natural madd even though written
  small (unless they carry a maddah before a hamzah → the hukmi case above).

### Ending madd (stop-based)
Appears only when you **stop** on a word:
- **Madd Aarid lis-Sukoon** — a natural madd whose final letter becomes temporarily sakin because you
  stopped. 2, 4, or 6 counts. (stop on ٱلۡعَٰلَمِينَ / ٱلرَّحِيمِ.)
- **Madd Leen** — a sakin waaw or yaa preceded by a fatha, stretched softly when you stop. (خَوۡف, بَيۡت,
  قُرَيۡش.) Keep it no longer than the aarid length you chose.

The engine detects these (`maddSukoon`) but, like the app, does **not** paint them by default.

### Madd Lazim ("necessary") — 6 counts, always
The strongest, longest madd: a madd letter followed by a **permanent sukun**. Two kinds:
- **Lazim Harfi** — in the disconnected opening letters (*muqattaʿat*) of some surahs whose *letter name*
  contains a madd + sukun: الٓمٓ (*Alif-Laaaam-Miiim*), كٓهيعٓصٓ, حٰمٓ. Not every opening letter is lengthened
  — read the letter's name (ألف and لام-when-not-internally-sukun are read short; م س ص ن ق ك ي ع ط ه ر carry madd).
- **Lazim Kalimi** — in ordinary words: ٱلضَّآلِّينَ (*ad-daaalliin*), ٱلطَّآمَّة.

---

## Hamzatul-Wasl (هَمْزَة الوَصْل) — the connecting hamzah

The **hamzah of connection** (written as an alif with a small ṣād-like sign: **ٱ**) is pronounced **only
when you begin reciting from that word**. If you connect from the previous word, it is **dropped**. (The
engine colors it silent — `hamzatWaslSilent` — when it isn't the start.)

How to pronounce it **when starting** on the word:
1. **With "Al-" (ٱل)** → start with **"a"** (fatha): ٱلۡكِتَٰب → *al-kitāb*, ٱلرَّحۡمَٰن → *ar-raḥmān*.
2. **A noun without "Al-"** → start with **"i"** (kasra): ٱسۡم → *ism*, ٱبۡن → *ibn*.
3. **A verb** → look at the **third letter**: if it has damma, start with **"u"** (ٱتۡلُ → *utlu*); otherwise
   start with **"i"**.
4. **Some verbs are exceptions** (e.g. ٱئۡتُونِي → *iʾtūnī*) and are learned individually.
5. **After tanwin** — when a word ending in tanwin meets a hamzatul-wasl, a connecting kasra-noon is inserted
   while continuing: بِغُلَٰمٍ ٱسۡمُهُۥ → *bighulāmin-ismuhu*.

When **continuing** from the previous word, it's simply dropped: ذَٰلِكَ ٱلۡكِتَٰبُ → *dhālika l-kitāb*.

---

## The four kinds of sukoon in the mushaf

The Uthmani script uses different sukoon-style marks to tell you whether a letter is pronounced, skipped,
or pronounced only at a stop:

1. **Normal sukoon (ـۡ)** — pronounce the consonant with no vowel after it. (رَزَقۡنَٰهُم.)
2. **Permanent silent letter** — written but **never** pronounced, whether you continue or stop. (the silent
   alif in كَانُواْ.)
3. **Stop-only letter (ـ۠)** — skipped when continuing, **pronounced if you stop**. (قَوَارِيرَا۠, أَنَا۠.)
4. **No mark at all** — either a **madd letter** (stretch 2 counts) or a consonant under a **special rule**
   (e.g. the hidden ikhfaa noon in يُنفِقُونَ). Qalqalah likewise has no printed mark — you know it by rule.

---

## Waqf (وَقْف) — stopping

**Waqf** is a deliberate, rule-based pause at the end of a word, intending to resume correctly. It is *not*
random breathing: where you stop affects meaning. As scholars said, *"knowing where to stop is half of
recitation."*

**The golden rule:** every final vowel becomes a **sukun** when you stop, except special cases.
- Final damma/fatha/kasra → dropped; the letter goes sakin (ٱلۡعَٰلَمِينَ → *…lamīn*).
- **Tanwin** is never pronounced at a stop (بَصِيرٌ → *baṣīr*), **except** fathatayn + alif, where the tanwin
  drops but the written alif remains as a long "ā" (كِتَابًا → *kitābā* — this is Madd ʿIwad).
- **Taa marbuuTah (ة)** → pronounced as a silent-h (haa sakinah): رَحْمَةٌ → *raḥmah*.
- **Long vowels (ا و ي)** → remain (يَقُولُ → *yaqūl*).

### Categories of stop
| Category | Meaning | Ruling |
|---|---|---|
| **Tam** (complete) | meaning is complete & independent | best place to stop |
| **Kafi** (sufficient) | meaning complete but connected to what follows | permissible |
| **Hasan** (good) | wording makes sense but meaning incomplete | only for breath, not preferred |
| **Qabih** (bad) | breaks the meaning / creates error | not allowed |

> A dangerous stop: pausing at لَا تَقۡرَبُوا۟ ٱلصَّلَوٰةَ alone implies "do not approach prayer" — the ayah
> continues وَأَنتُمۡ سُكَٰرَىٰ ("while intoxicated"). **You stop where the meaning stops, not where the lungs give up.**

The printed **waqf signs** (مـ، قلى، ج، س، صلى، لا، ∴ ∴, plus ۩ sujood and ۞ hizb) are listed with meanings
in [arabic-alphabet.md → stopping signs](arabic-alphabet.md#waqf--stopping-signs).

---

## How the engine maps to these rules

| Rule explained here | Engine category | Doc |
|---|---|---|
| Sun-letter laam | `lamShamsiyah` | [02](02-tajweed.md) |
| Silent connecting hamzah | `hamzatWaslSilent` | 02 |
| Idgham without ghunnah | `idghamBilaGhunnah` | 02 |
| Idgham with ghunnah | `idghamGhunnah` | 02 |
| Noon/meem shaddah ghunnah | `generalGhunnah` | 02 |
| Ikhfaa (light / heavy) | `ikhfaaLight` / `ikhfaaHeavy` | 02 |
| Iqlaab | `iqlaab` | 02 |
| Qalqalah | `qalqalah` | 02 |
| Tafkhim (heavy letters) | `tafkhim` | 02 |
| Natural / miniature madd | `maddNatural` / `maddNaturalMiniature` | 02 |
| Muttasil / Munfasil / Lazim | `maddConnected` / `maddSeparated` / `maddNecessary` | 02 |
| Aarid / Leen (stop-based) | `maddSukoon` (computed, not painted) | 02 |

To *learn* the rules, read this page. To *detect and color* them in code, see [docs/02-tajweed.md](02-tajweed.md)
and the generated [rule reference](tajweed-rules-reference.md).
