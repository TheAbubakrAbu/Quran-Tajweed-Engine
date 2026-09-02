"""How far apart two readings actually are, measured word by word.

The Ten Qiraat are usually described in prose ("Warsh reads with taqlil, Hafs does not"), which says
what differs but never how much. This measures it: align the two readings' words and sort every pair
into one of three buckets.

* **identical** - the same word, written the same way, marks and all.
* **same_skeleton** - the same consonantal skeleton (rasm), different vowels or spelling. This is
  the overwhelming majority of what "a different qiraah" means, and it is what the uthmani rasm was
  designed to allow: one written form, several sound readings.
* **different** - a different skeleton, i.e. a genuinely different word form.

WHY ALIGNMENT IS NOT INDEXING. Readings merge and split ayahs (Warsh's al-Baqarah has 285 ayahs to
Hafs' 286, because it reads الٓمٓ and ذٰلك الكتٰب as one), so ayah n of one is not ayah n of the
other. The comparison walks the whole SURAH's word stream on both sides with a two-pointer alignment
and bounded lookahead rather than pairing by index. Words that cannot be resynced are reported as
``added`` or ``dropped`` rather than silently dropped from the count.

WHAT IT CANNOT TELL YOU. This measures the two printed TEXTS, which is not the same as measuring the
two recitations: a difference that lives only in how a letter is sounded (imalah, taqlil, ishmam)
shows up here only where the print marks it.

See ../../docs/17-qiraat-comparison.md.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .quran import Quran
from .text import removing_arabic_diacritics_and_signs

#: Letters folded together before comparing skeletons: the same consonant, written differently.
_SKELETON_FOLD = {
    "ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا", "ى": "ا", "ٰ": "ا",
    "ؤ": "و", "ئ": "ي", "ة": "ه",
    "ء": "", "ـ": "",
}

#: How far ahead to look for a resync before declaring a word added or dropped.
_LOOKAHEAD = 3


def skeleton(word: str) -> str:
    """The consonantal skeleton of a word: diacritics and recitation signs gone, the letters that
    are written differently for the same consonant folded together."""
    out = []
    for ch in removing_arabic_diacritics_and_signs(word):
        out.append(_SKELETON_FOLD.get(ch, ch))
    return "".join(out)


@dataclass(frozen=True)
class WordDifference:
    #: 1-based word position in the BASE reading's surah.
    position: int
    #: The base reading's word ("" when the other reading adds one).
    base: str
    #: The compared reading's word ("" when it drops one).
    other: str
    #: "sameSkeleton" | "different" | "added" | "dropped"
    kind: str


@dataclass
class ComparisonTotals:
    #: Words compared, in the base reading.
    words: int = 0
    identical: int = 0
    same_skeleton: int = 0
    different: int = 0
    #: Words the compared reading has and the base does not.
    added: int = 0
    #: Words the base has and the compared reading does not.
    dropped: int = 0

    @property
    def identical_percent(self) -> float:
        return (100.0 * self.identical / self.words) if self.words else 0.0


class QiraatComparison:
    def __init__(self, quran: Quran) -> None:
        self._quran = quran

    def available(self) -> list[str]:
        """The riwayat whose text is loaded and so can be compared, in slug order. "hafs" is always
        one of them: it is quran.json itself."""
        return sorted({"hafs", *self._quran.loaded_riwayat()})

    def words(self, surah_id: int, riwayah: str) -> list[str]:
        """Every word of a surah in one reading, in order."""
        surah = self._quran.surah(surah_id)
        if surah is None:
            return []
        # The riwayah's OWN verses, in ITS numbering: readings merge and split ayahs, so walking
        # Hafs' ayah ids and asking for each would compare different verses (and silently fall back
        # to Hafs for the ids the reading does not have).
        if riwayah.lower() == "hafs":
            verses = [a.text_arabic for a in surah.ayahs]
        else:
            verses = [v["text"] for v in self._quran.qiraah_verses(surah_id, riwayah)]
        return [token for text in verses for token in text.split()]

    def compare_surah(self, surah_id: int, riwayah: str, *,
                      against: str = "hafs") -> ComparisonTotals:
        """Compare one surah, word by word."""
        return _totals(self._align(surah_id, against, riwayah))

    def compare(self, riwayah: str, *, against: str = "hafs") -> ComparisonTotals:
        """Compare the whole Quran. This walks every word of both readings - about 155,000
        comparisons - so cache the result rather than calling it per render."""
        total = ComparisonTotals()
        for surah in self._quran.all():
            part = self.compare_surah(surah.id, riwayah, against=against)
            total.words += part.words
            total.identical += part.identical
            total.same_skeleton += part.same_skeleton
            total.different += part.different
            total.added += part.added
            total.dropped += part.dropped
        return total

    def differences(self, surah_id: int, riwayah: str, *, against: str = "hafs",
                    limit: int = 0) -> list[WordDifference]:
        """The words that are not identical, in reading order."""
        rows = [row for row in self._align(surah_id, against, riwayah) if row.kind != "identical"]
        return rows[:limit] if limit > 0 else rows

    def _align(self, surah_id: int, base: str, other: str) -> list[WordDifference]:
        left = self.words(surah_id, base)
        right = self.words(surah_id, other)
        rows: list[WordDifference] = []

        i = j = 0
        while i < len(left) and j < len(right):
            if left[i] == right[j]:
                rows.append(WordDifference(i + 1, left[i], right[j], "identical"))
                i += 1
                j += 1
                continue
            if skeleton(left[i]) == skeleton(right[j]):
                rows.append(WordDifference(i + 1, left[i], right[j], "sameSkeleton"))
                i += 1
                j += 1
                continue
            # Not a match. Before calling it a different word, see whether one side simply has an
            # extra word here - a merge or a split - by looking for the next place they agree.
            resync = _find_resync(left, right, i, j)
            if resync is not None:
                ri, rj = resync
                for k in range(i, ri):
                    rows.append(WordDifference(k + 1, left[k], "", "dropped"))
                for k in range(j, rj):
                    rows.append(WordDifference(i + 1, "", right[k], "added"))
                i, j = ri, rj
                continue
            rows.append(WordDifference(i + 1, left[i], right[j], "different"))
            i += 1
            j += 1

        while i < len(left):
            rows.append(WordDifference(i + 1, left[i], "", "dropped"))
            i += 1
        while j < len(right):
            rows.append(WordDifference(len(left), "", right[j], "added"))
            j += 1
        return rows


def _find_resync(left: list[str], right: list[str], i: int, j: int) -> Optional[tuple[int, int]]:
    """The nearest offset within the lookahead window at which the two streams agree again by
    skipping words on ONE side only - an insertion or a deletion.

    Skipping on both sides at once is deliberately not a resync: that is a substitution, one word
    standing where another does, which is the ``different`` bucket. Allowing it here collapsed every
    genuine word difference into a dropped+added pair and left ``different`` permanently at zero.
    """
    for skip in range(1, _LOOKAHEAD + 1):
        if i + skip < len(left) and skeleton(left[i + skip]) == skeleton(right[j]):
            return i + skip, j
        if j + skip < len(right) and skeleton(left[i]) == skeleton(right[j + skip]):
            return i, j + skip
    return None


def _totals(rows: list[WordDifference]) -> ComparisonTotals:
    out = ComparisonTotals()
    for row in rows:
        if row.kind == "added":
            out.added += 1
            continue
        out.words += 1
        if row.kind == "identical":
            out.identical += 1
        elif row.kind == "sameSkeleton":
            out.same_skeleton += 1
        elif row.kind == "dropped":
            out.dropped += 1
        else:
            out.different += 1
    return out
