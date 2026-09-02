"""The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name
and transliteration, and - the part that matters for tajweed - its WEIGHT.

Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the divine
name), and alif has no weight of its own at all: it inherits the letter before it. That single fact
is behind a large share of beginner mistakes, and it is a property of the letter, not of any
particular verse, so it lives here beside the letter and not in the annotation corpus.

Also carried: the letters outside the 28 (hamza, ta marbuta, lam-alif), the six Persian/Urdu letters
that appear in some printed mushafs, the Eastern-Arabic numerals the ayah markers use, the tashkeel
marks, and the waqf (stopping) signs.

See ../../docs/16-arabic-alphabet.md.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class ArabicLetter:
    id: int
    letter: str
    forms: list[str]
    name: str
    transliteration: str
    show_tashkeel: bool
    sound: str
    #: "light" | "heavy" | "conditional" | "followsPrevious", or None where none is recorded.
    weight: Optional[str] = None
    #: Why, in one sentence.
    weight_rule: Optional[str] = None

    @staticmethod
    def from_json(raw: dict) -> "ArabicLetter":
        return ArabicLetter(
            id=raw.get("id", 0),
            letter=raw.get("letter", ""),
            forms=list(raw.get("forms") or []),
            name=raw.get("name", ""),
            transliteration=raw.get("transliteration", ""),
            show_tashkeel=bool(raw.get("showTashkeel", False)),
            sound=raw.get("sound", ""),
            weight=raw.get("weight"),
            weight_rule=raw.get("weightRule"),
        )


@dataclass(frozen=True)
class Tashkeel:
    english: str
    arabic: str
    mark: str
    transliteration: str


@dataclass(frozen=True)
class StoppingSign:
    symbol: str
    title: str


@dataclass(frozen=True)
class ArabicNumeral:
    number: str
    name: str
    transliteration: str
    english_number: str


class ArabicAlphabet:
    def __init__(self, data: Optional[dict] = None) -> None:
        self._data = data or {}

    def letters(self) -> list[ArabicLetter]:
        """The 28 letters of the alphabet, in order."""
        return [ArabicLetter.from_json(r) for r in self._data.get("standardLetters", [])]

    def other_letters(self) -> list[ArabicLetter]:
        """Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28."""
        return [ArabicLetter.from_json(r) for r in self._data.get("otherLetters", [])]

    def non_arabic_script_letters(self) -> list[ArabicLetter]:
        """The Persian/Urdu letters some printed mushafs use for non-Arabic sounds."""
        return [ArabicLetter.from_json(r) for r in self._data.get("nonArabicScriptLetters", [])]

    def all_letters(self) -> list[ArabicLetter]:
        """Every letter this reference knows, the 28 first."""
        return self.letters() + self.other_letters() + self.non_arabic_script_letters()

    def letter(self, letter: str) -> Optional[ArabicLetter]:
        """One letter by its isolated form. Accepts any of its joining forms too, so a letter
        lifted out of a word still resolves."""
        wanted = letter.strip()
        if not wanted:
            return None
        for entry in self.all_letters():
            if entry.letter == wanted or wanted in entry.forms:
                return entry
        return None

    def letter_by_id(self, letter_id: int) -> Optional[ArabicLetter]:
        for entry in self.all_letters():
            if entry.id == letter_id:
                return entry
        return None

    def weight(self, letter: str) -> Optional[str]:
        """The tajweed weight of a letter, or None when the reference records none."""
        entry = self.letter(letter)
        return entry.weight if entry else None

    def weight_descriptions(self) -> dict[str, str]:
        """What a weight name means, in one line."""
        return dict(self._data.get("weights") or {})

    def heavy_letters(self) -> list[ArabicLetter]:
        """The letters pronounced full - the isti'la letters."""
        return [entry for entry in self.letters() if entry.weight == "heavy"]

    def tashkeel(self) -> list[Tashkeel]:
        return [Tashkeel(r.get("english", ""), r.get("arabic", ""), r.get("mark", ""),
                         r.get("transliteration", ""))
                for r in self._data.get("tashkeel", [])]

    def stopping_signs(self) -> list[StoppingSign]:
        """The waqf signs, with what each one tells the reciter to do."""
        return [StoppingSign(r.get("symbol", ""), r.get("title", ""))
                for r in self._data.get("stoppingSigns", [])]

    def stopping_sign(self, symbol: str) -> Optional[StoppingSign]:
        for sign in self.stopping_signs():
            if sign.symbol == symbol:
                return sign
        return None

    def numbers(self) -> list[ArabicNumeral]:
        """The Eastern-Arabic numerals, 0 through 10."""
        return [ArabicNumeral(r.get("number", ""), r.get("name", ""),
                              r.get("transliteration", ""), r.get("englishNumber", ""))
                for r in self._data.get("numbers", [])]

    def stopping_signs_source(self) -> str:
        return self._data.get("stoppingSignsSource", "")
