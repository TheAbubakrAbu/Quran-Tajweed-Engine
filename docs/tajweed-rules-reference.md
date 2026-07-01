# Tajweed rule reference (generated)

> Generated from [`data/tajweed-rules.json`](../data/tajweed-rules.json) by
> `scripts/generate-tajweed.mjs`. **Do not edit by hand** — edit the master and regenerate.
> For plain-English explanations of each rule, see [tajweed-rules-explained.md](tajweed-rules-explained.md).

17 rule categories across 4 sections.

## Sukūn — Silent

| Rule | Color | Counts | Trigger letters | Meaning |
|---|---|---|---|---|
| **Solar Lam** (Laam Shamiyyah) — `lamShamsiyah` | `#B4B4B4` | — | — | The laam of 'al-' assimilates into a following sun letter (which doubles). |
| **Written but Not Pronounced** (Harf Ghayr Mantuq) — `droppedLetter` | `#B4B4B4` | — | — | A letter written in the Uthmani script but not pronounced. |
| **Joining Hamzah** (Hamzat al-Wasl) — `hamzatWaslSilent` | `#B4B4B4` | — | — | Hamzat al-wasl — the 'connecting hamzah' — is silent when joining from a previous word. |
| **Merge Without Ghunnah** (Idgham Bilaa Ghunnah) — `idghamBilaGhunnah` | `#B4B4B4` | — | When noon (ن) or tanween comes before: ل، ر | Idgham = merging; bila ghunnah = without a nasal hum. |

## Ghunnah — Nasal

| Rule | Color | Counts | Trigger letters | Meaning |
|---|---|---|---|---|
| **Shaddah Ghunnah** (Ghunnah Aammah) — `generalGhunnah` | `#45BC73` | 2 counts | Noon or meem with shaddah; also used on selected nasal merge targets | Ghunnah = the nasal hum held on noon/meem with shaddah (~2 counts). |
| **Merge with Ghunnah** (Idgham Bighunnah) — `idghamGhunnah` | `#45BC73` | 2 counts | When a noon sound (ن or tanween) comes before: ي، ن، م، و | Idgham = merging; bi-ghunnah = with a nasal hum. |
| **Hidden Letter (Light)** (Ikhfaa (Light)) — `ikhfaaLight` | `#45BC73` | 2 counts | When a noon sound (ن or tanween) comes before lighter letters: ت، ث، ج، د، ذ، ز، س، ش، ف، ك | Ikhfaa = hiding/concealing the noon sound with a light nasal hum. |
| **Hidden Letter (Heavy)** (Ikhfaa (Heavy)) — `ikhfaaHeavy` | `#1FAA94` | 2 counts | When a noon sound (ن or tanween) comes before heavier letters: ص، ض، ط، ظ، ق | Ikhfaa = hiding/concealing the noon sound with a heavy nasal hum. |
| **Noon into Meem** (Iqlaab) — `iqlaab` | `#75B233` | 2 counts | When noon (ن) or tanween comes before: ب (changes to meem sound) | Iqlaab = conversion of the noon sound into a meem before baa. |

## Sifaat — Articulation

| Rule | Color | Counts | Trigger letters | Meaning |
|---|---|---|---|---|
| **Bounce Letter** (Qalqalah) — `qalqalah` | `#78CCF9` | — | Letters that bounce when they have sukoon or are stopped on: ق، ط، ب، ج، د | Qalqalah = a slight echo/bounce on qutb-jad letters at sukoon or stop. |
| **Heavy Letter** (Tafkheem) — `tafkhim` | `#3B85C2` | — | Letters pronounced heavily (elevated tongue): خ، ص، ض، غ، ط، ق، ظ | Tafkhim = heaviness; the istiʿla letters are pronounced full and deep. |

## Madd — Elongation

| Rule | Color | Counts | Trigger letters | Meaning |
|---|---|---|---|---|
| **Madd Letters (2 Counts)** (Madd Tabee Letters) — `maddNatural` | `#B98C2F` | 2 counts | Occurs on madd letters: ا، و، ي (normal 2-count elongation) | Madd Tabiʿi = the natural 2-count elongation of a madd letter. |
| **Tiny Madd Marks** (Madd Tabee Tiny Marks) — `maddNaturalMiniature` | `#B98C2F` | 2 counts | Occurs on miniature madd marks: alif sagheerah, waw sagheerah, ya sagheerah | A 2-count natural madd written with a superscript (miniature) mark. |
| **Ending Madd** (Ending Madd) — `maddSukoon` | `#E37935` | 2, 4, or 6 counts | When stopping creates madd aarid lis-sukoon after ا، و، ي, or madd leen after َ + وۡ / َ + يۡ | Stop-based madd (Aarid lis-Sukoon / Leen), lengthened only when pausing. |
| **Madd Lazim** (Madd Laazim) — `maddNecessary` | `#AE2517` | 6 counts | When madd letters (ا، و، ي) are followed by a permanent sukoon or shaddah | Madd Lazim = 'necessary' madd: madd + a permanent sukoon/shaddah, fixed 6 counts. |
| **Madd Munfasil** (Madd Munfasil) — `maddSeparated` | `#EB51AA` | 2, 4, or 5 counts | When madd letters (ا، و، ي) are followed by hamzah in the next word | Madd Munfasil = 'separated' madd: madd at a word end before a hamzah starting the next word. |
| **Madd Muttasil** (Madd Muttasil) — `maddConnected` | `#D9453E` | 4 or 5 counts | When madd letters (ا، و، ي) are followed by hamzah in the same word | Madd Muttasil = 'connected' madd: a madd letter + hamzah inside one word. |

## Letter sets

- **heavyBaseLetters**: خ ص ض ط ظ غ ق
- **qalqalahLetters**: ق ط ب ج د
- **sunLetters**: ت ث د ذ ر ز س ش ص ض ط ظ ل ن
- **alifFollowerLetters**: ا ى
- **noonTanweenTargetOnlyIdghamLetters**: ن
- **noonTanweenSplitIdghamLetters**: م ي و
- **noonTanweenSourceOnlyIdghamLetters**: ل ر
- **ikhfaaHeavyLetters**: ص ض ط ظ ق
- **ikhfaaLightLetters**: ت ث ج د ذ ز س ش ف ك
