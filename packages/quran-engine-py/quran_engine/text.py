"""Arabic text utilities (search normalization, UTF-16 slicing). Mirrors src/text.js."""
from __future__ import annotations
import re
import unicodedata

# Canonical Arabic fold map applied before stripping marks (Settings.canonicalArabicSearchMap).
_CANONICAL_ARABIC = {
    "ٰ": "ا",  # dagger alif
    "ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا", "ٲ": "ا", "ٳ": "ا", "ٵ": "ا",
    "ؤ": "و", "ئ": "ي", "ء": "", "ٴ": "", "ٶ": "و", "ٷ": "و", "ٸ": "ي",
    "ۥ": "و", "ۦ": "ي",  # small waw / small yeh
    "ى": "ا", "ة": "ه",
}
_KEEP_OPERATORS = set("&|!#")

_ARABIC_RANGES = [
    (0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF),
    (0xFB50, 0xFDFF), (0xFE70, 0xFEFF), (0x1EE00, 0x1EEFF),
]


def collapsing_whitespace(text: str) -> str:
    return " ".join(text.split())


def clean_search(text: str, whitespace: bool = False) -> str:
    """Fold Arabic carriers, strip punctuation/symbols/marks (keep & | ! #), lowercase, collapse spaces."""
    folded = text
    for k, v in _CANONICAL_ARABIC.items():
        folded = folded.replace(k, v)
    out = []
    for ch in folded:
        if ch in _KEEP_OPERATORS:
            out.append(ch)
            continue
        cat = unicodedata.category(ch)
        if cat[0] in ("P", "S", "M"):  # punctuation, symbol, combining mark
            continue
        out.append(ch)
    cleaned = collapsing_whitespace("".join(out).lower())
    if whitespace:
        cleaned = cleaned.strip()
    return cleaned


def search_tokens(cleaned: str) -> list[str]:
    return [t for t in cleaned.split(" ") if t]


def contains_arabic_letters(text: str) -> bool:
    return any(any(lo <= ord(ch) <= hi for lo, hi in _ARABIC_RANGES) for ch in text)


def arabic_digits_to_western(text: str) -> str:
    table = {
        "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
        "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
        "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
        "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
    }
    return "".join(table.get(ch, ch) for ch in text)


def removing_arabic_diacritics_and_signs(text: str) -> str:
    """Strip Quranic recitation marks for clean reading/search (Globals.removingArabicDiacriticsAndSigns)."""
    out = []
    for ch in text:
        cp = ord(ch)
        if cp == 0x0671:
            out.append("ا")
            continue
        if (0x064B <= cp <= 0x065F) or (0x06D6 <= cp <= 0x06ED) or cp in (0x0670, 0x0657, 0x0674, 0x0656):
            continue
        out.append(ch)
    return "".join(out)


# ---- UTF-16 slicing -----------------------------------------------------------
# The tajweed annotation offsets are UTF-16 code units. Python indexes by code point, so convert.

def utf16_slice(text: str, start: int, end: int) -> str:
    """Slice `text` by UTF-16 code-unit offsets (what the annotation start/end use)."""
    b = text.encode("utf-16-le")
    return b[start * 2:end * 2].decode("utf-16-le")
