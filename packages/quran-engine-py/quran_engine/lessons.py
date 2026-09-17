"""The tajweed course: chapters, lessons, drills, Quranic examples. Mirrors src/lessons.js.

Chapters, lessons and their examples are passed through as the dicts data/tajweed-lessons.json
(version 4) holds. Each example is {surahId, ayahNumber, focus, wordSpan?}: `wordSpan` is the
0-based inclusive token range of the words to listen at, into the ayah's raw text, and is absent
when the lesson names the whole ayah. The data carries no copy of the words (the old `word`
string is gone): read them out of `engine.quran` by the span.

Version 4 carries the same idea into the lesson body. A drill, a rule-card fragment or a quiz
question holds its Arabic in exactly one of two places: `text` (or `arabic` on a quiz) when a
tutor wrote it, which covers the invented drill syllables, the single letters and the
isti'adhah; or `ayah` when the Arabic IS Quran, and then there is no text at all. An `ayah` is
[surah, ayahNumber, first, last], the span again 0-based and inclusive, so a consumer that
ignores the field renders an empty row rather than a verse.
"""
from __future__ import annotations
from typing import Optional


class TajweedLessons:
    def __init__(self, data: Optional[dict] = None):
        self._chapters: list[dict] = (data or {}).get("chapters", [])
        self._by_lesson: dict[str, tuple[dict, dict]] = {}
        for chapter in self._chapters:
            for lesson in chapter["lessons"]:
                self._by_lesson[lesson["id"]] = (chapter, lesson)

    def chapters(self) -> list[dict]:
        return self._chapters

    def chapter(self, chapter_id: str) -> Optional[dict]:
        return next((c for c in self._chapters if c["id"] == chapter_id), None)

    def all_lessons(self) -> list[dict]:
        return [lesson for chapter in self._chapters for lesson in chapter["lessons"]]

    def lesson(self, lesson_id: str) -> Optional[dict]:
        found = self._by_lesson.get(lesson_id)
        return found[1] if found else None

    def chapter_of(self, lesson_id: str) -> Optional[dict]:
        found = self._by_lesson.get(lesson_id)
        return found[0] if found else None

    def next(self, lesson_id: str) -> Optional[dict]:
        """The lesson after this one, walking across chapter boundaries."""
        lessons = self.all_lessons()
        at = next((i for i, l in enumerate(lessons) if l["id"] == lesson_id), -1)
        return lessons[at + 1] if 0 <= at < len(lessons) - 1 else None

    def previous(self, lesson_id: str) -> Optional[dict]:
        lessons = self.all_lessons()
        at = next((i for i, l in enumerate(lessons) if l["id"] == lesson_id), -1)
        return lessons[at - 1] if at > 0 else None
