"""Recitation audio URL builders + reciter directory. Mirrors src/audio.js / docs 04-05."""
from __future__ import annotations
from .models import Reciter

_MINSHAWI_FALLBACK_NAME = "Muhammad Al-Minshawi (Murattal)"


def _pad3(n: int) -> str:
    return f"{n:03d}"


def surah_audio_url(reciter: Reciter, surah_number: int) -> str:
    if not (1 <= surah_number <= 114):
        raise ValueError(f"surah out of range: {surah_number}")
    if not reciter.surah_link:
        raise ValueError(f'Reciter "{reciter.name}" has no full-surah feed')
    return f"{reciter.surah_link}{_pad3(surah_number)}.mp3"


def ayah_audio_url(reciter: Reciter, global_ayah_number: int) -> str:
    return (
        "https://cdn.islamic.network/quran/audio/"
        f"{reciter.ayah_bitrate}/{reciter.ayah_identifier}/{global_ayah_number}.mp3"
    )


def defaults_to_minshawi(reciter: Reciter) -> bool:
    return "minshawi" in reciter.ayah_identifier and "Minshawi" not in reciter.name


def ayah_now_playing_name(reciter: Reciter) -> str:
    if defaults_to_minshawi(reciter):
        return _MINSHAWI_FALLBACK_NAME
    if reciter.qiraah:
        return f"{reciter.name} ({reciter.qiraah})"
    return reciter.name


class Reciters:
    def __init__(self, reciters: list[Reciter]):
        self.list = sorted(reciters, key=lambda r: r.name)
        self._by_id = {r.id: r for r in self.list}

    def all(self) -> list[Reciter]:
        return self.list

    def by_id(self, rid: str) -> Reciter | None:
        return self._by_id.get(rid)

    def with_surah_feed(self) -> list[Reciter]:
        return [r for r in self.list if r.surah_link and not r.surah_link.endswith(".mp3")]

    def by_qiraah(self, qiraah: str | None) -> list[Reciter]:
        if not qiraah or qiraah.lower() == "hafs":
            return [r for r in self.list if not r.qiraah]
        return [r for r in self.list if r.qiraah == qiraah]

    def qiraat(self) -> list[str]:
        seen, out = set(), []
        for r in self.list:
            if r.qiraah and r.qiraah not in seen:
                seen.add(r.qiraah)
                out.append(r.qiraah)
        return out
