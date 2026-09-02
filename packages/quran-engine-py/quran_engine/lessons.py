"""The tajweed course: chapters, lessons, drills, Quranic examples. Mirrors src/lessons.js."""
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
