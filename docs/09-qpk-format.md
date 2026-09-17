# The QPK pack format

`.qpk` is the optional binary build artifact for apps. This document specifies it completely, so any language can read a pack without consulting the Swift source.

**The JSON in [`data/`](../data) remains canonical and portable.** Packs are reproducible from it, and nothing is in a pack that is not in the JSON. If you are porting the engine, reading the JSON is the supported path: this format is for shipping apps that care about install size and launch cost.

## Why it exists

Al-Islam ships ~17 MB of Quran JSON, decodes it on first launch, and writes a binary-plist cache to Application Support which it maps on later launches. The device pays **twice** (once in bundle size for the JSON, again in disk for the derived cache), and the first launch pays the whole decode.

The packs are **3.1 MB** and *are* the decoded form:

| Pack | JSON | Pack | Ratio |
|---|---:|---:|---:|
| `quran.qpk` | 4.65 MB | 1.04 MB | 4.46x |
| `qiraat.qpk` | 10.37 MB | 1.40 MB | 7.42x |
| `surahinfos.qpk` | 1.82 MB | 0.68 MB | 2.68x |
| **Total** | **16.83 MB** | **3.12 MB** | **5.40x** |

No JSON parse, no derived cache, and the large text stays on disk until something asks for it.

## Conventions

- **Little-endian** throughout.
- **String** = `u32` byte length, then that many bytes of UTF-8. Not NUL-terminated.
- Offsets are absolute from the start of the file.
- Records are not naturally aligned. Read integers byte by byte, or use unaligned loads.
- All three packs share the same container; only the eager section differs.

## Header: 48 bytes at offset 0

| Offset | Type | Field |
|---:|---|---|
| 0 | `u32` | magic, `0x4B505251`, `"QRPK"` |
| 4 | `u16` | format version, currently **1** |
| 6 | `u8` | eager codec |
| 7 | `u8` | block codec |
| 8 | `u16` | block count |
| 10 | `u16` | reserved, 0 |
| 12 | `u32` | record count, surahs (114) / readings (7) / infos (114) |
| 16 | `u32` | unit count, ayahs (6236) / total ayah rows / total sources |
| 20 | `u32` | eager section offset |
| 24 | `u32` | eager compressed length |
| 28 | `u32` | eager raw length |
| 32 | `u64` | source fingerprint, FNV-1a over the JSON this was built from |
| 40 | `u64` | reserved, 0 |

**Codec values:** `1` = LZFSE, `2` = LZMA. Current builds use LZMA for both sections; Apple's LZMA output reads as standard XZ.

Reject the file if the magic or version does not match. Bound any allocation by what the buffer could actually hold: a truncated file otherwise hands you a count read out of garbage.

## Block table: 16 bytes per block, starting at offset 48

| Offset | Type | Field |
|---:|---|---|
| 0 | `u32` | first record in this block |
| 4 | `u32` | offset |
| 8 | `u32` | compressed length |
| 12 | `u32` | raw length |

## `quran.qpk`

The eager section holds **everything except ayah text** (about 300 KB), which is what lets any surah open with none of its text loaded.

```
u32   surah count
  per surah:
    u32     id
    u8      isMakkan            (1 = makkan, 0 = madinan)
    String  nameArabic
    String  nameTransliteration
    String  nameEnglish
    String  revelationExceptions
    u32     numberOfAyahs
    u32     pageStart
    u32     pageEnd
    u32     numberOfPages
    u32     firstJuz
    u32     lastJuz
    u32     revelationOrder
    u32     wordCount
    u32     letterCount
    u8      juzChangesWithinSurah
    u32     juz count,  then that many u32 juz numbers
    u32     similarNames count, then that many Strings
    u32     firstRow            global row of this surah's first ayah
u32   ayah count
  per ayah (18 bytes, fixed):
    u32     id                  1-based within its surah
    u16     juz
    u16     page
    u32     wordCount
    u32     letterCount
    u16     block index
```

**Blocks** hold the four text fields per ayah, back to back, in row order: `textArabic`, `textTransliteration`, `textEnglishSaheeh`, `textEnglishMustafa`. Ayah `row` is at slot `(row - blockFirstRow) * 4`.

**A surah is a slice, not a filter.** `firstRow` plus `numberOfAyahs` gives its rows directly. The packer verifies that each surah's declared `numberOfAyahs` matches the ayahs it actually carries and **fails loudly** if not, because shipping a mismatch would show readers the wrong ayahs.

**Blocks never straddle a surah.** A reader opening a surah touches a contiguous run, usually one block.

## `qiraat.qpk`

```
u32   reading count
  per reading:
    String  key                 warsh · qaloon · duri · susi · bazzi · qunbul · shubah
    u32     surah count
      per surah:  u32 surah id, u32 ayah count
    u16     block index         one block per reading
```

Which surahs a reading covers, and how many ayahs each has, are **resident**, so `existsInQiraah` and `numberOfAyahs(for:)` are answered with no text touched at all. Most users never open a qiraah, and this is why that costs nothing.

**Blocks** hold, per surah in the order the eager section lists them, that surah's ayahs as `u32 ayahNumber` followed by a `String` of text. To reach one surah, skip the preceding surahs using their eager ayah counts.

## `surahinfos.qpk`

```
u32   entry count
  per entry:
    u32     surah id
    u32     source count, then that many Strings   (source NAMES only)
    u16     block index
```

Source names are resident, so a picker ("Maududi / Ibn Ashur") can be built without touching any prose.

**One block per surah**: 114 blocks. "About this surah" is opened for exactly one surah at a time and the prose is large, so a shared block would decompress 113 surahs nobody asked for. That is why this pack's ratio (2.68x) is lower than the others: it trades compression for genuine laziness, deliberately.

**Blocks** hold the `contents` string of each source, in the same order as the names.

## Reading a pack: the minimum path

1. Read and validate the 48-byte header.
2. Read the block table.
3. Decompress the eager section; parse per the layouts above.
4. To read a value in a block: decompress that block, split into strings, index by slot.
5. Cache decompressed blocks with a byte budget, and drop them under memory pressure, everything here is rebuildable from the bundle.

## Reference implementations

- **Swift**: `Al-Islam-iOS/iPhone/Quran/QuranPack.swift`. Compiles standalone; `QuranPackContainer` is the shared plumbing and `QuranPack` / `QiraatPack` / `SurahInfoPack` are the typed readers.
- Verified with 135,289 assertions against the source JSON, 0 failures.

## Manifest

`manifest.json` is written beside the packs: format version, block target, codec, and per pack the sha256, byte size, record/unit/block counts. Verify against it before trusting a pack you did not build.

## Tuning

Block size defaults to 256 KB of raw text (`QPK_BLOCK`, in KB). `QPK_TEXT` selects the block codec (`1` = LZFSE, `2` = LZMA). LZMA is the default because these blocks are read once and cached, so the better ratio wins; LZFSE would matter if something scanned every block on every keystroke, which nothing here does.
