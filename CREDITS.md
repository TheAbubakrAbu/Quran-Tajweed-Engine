# Credits & data provenance

This engine would not exist without the people and projects below. Please preserve this attribution in
any redistribution.

## Upstream project

All data and algorithms in this repository are extracted from the open-source **Al-Islam | Islamic Pillars**
app, with full credit to its author:

- **Author:** Abubakr Elmallah
- **Project:** Al-Islam | Islamic Pillars — <https://github.com/TheAbubakrAbu/Al-Islam-Islamic-Pillars>
- **License:** MIT (© 2025 Abubakr Elmallah)
- **App Store:** <https://apps.apple.com/us/app/al-islam-islamic-pillars/id6449729655>

The tajweed engine specification, the search/sort/juz/page logic, and the reciter directory are ports of
the Swift implementation in that project (`QuranData.swift`, `QuranStructs.swift`, `TajweedRules.swift`,
`QuranPlayer.swift`, `Settings.swift`, `Globals.swift`).

## Quran text

- **Arabic:** the Hafs an Asim Uthmani script.
- **Alternate readings (qiraat):** Warsh, Qaloon, ad-Duri, as-Susi, al-Bazzi, Qunbul, and Shubah riwayat.

The Quran is the sacred scripture of Islam. The Arabic text must be preserved **exactly** and never altered. Treat it with the respect it is due.

## Translations

- **Saheeh International** — `textEnglishSaheeh`.
- **Dr. Mustafa Khattab, *The Clear Quran*** — `textEnglishMustafa`.

These translations are included for study and accessibility. They remain the work and rights of their respective publishers; consult their terms for redistribution beyond fair educational use.

## Surah introductions (`surah-info.json`)

- **Sayyid Abul A'la Maududi** — *Tafhim al-Qur'an* introductions (`Maududi`).
- **Ibn Ashur** — *al-Tahrir wa al-Tanwir* introductions (`Ibn Ashur` / `ابن عاشور`).

## Audio (URLs only — no audio files are bundled)

- **Full-surah recitations:** hosted on the **mp3quran.net** CDNs.
- **Ayah-by-ayah recitations:** the **alquran.cloud** network (`cdn.islamic.network`).

This engine constructs URLs to these third-party services; it neither hosts nor redistributes audio. Respect each provider's terms of use.

## A note on intent

This project is offered as *sadaqah jariyah* — a contribution for the benefit of the Muslim community and anyone building tools to read, learn, and listen to the Quran. If it helps you, please keep the chain of attribution intact and consider contributing improvements back.