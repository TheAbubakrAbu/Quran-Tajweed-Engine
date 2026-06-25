"""Offline-download path helpers. Mirrors src/cache.js / docs 08."""
from __future__ import annotations
import re

_SAFE = re.compile(r"[^A-Za-z0-9\-_]")


def sanitize_reciter_dir(reciter_id: str) -> str:
    """Keep [A-Za-z0-9-_], replace everything else with '_', cap at 180 chars."""
    safe = _SAFE.sub("_", reciter_id)[:180]
    return safe or "reciter"


def local_surah_path(reciter_id: str, surah_number: int) -> str:
    return f"{sanitize_reciter_dir(reciter_id)}/{surah_number:03d}.mp3"


def shared_audio_path(sha256_hex: str, ext: str = "mp3") -> str:
    return f"SharedAudio/{sha256_hex}.{ext}"
