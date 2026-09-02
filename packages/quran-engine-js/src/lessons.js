// @ts-check
/**
 * The tajweed course: eight chapters from the Arabic alphabet to the rules of stopping, each
 * lesson carrying its prose, its drills, and Quranic examples to hear the rule in.
 *
 * Content, not algorithm - but it belongs in the engine for the same reason the rule catalogue
 * does: every app that teaches tajweed otherwise rewrites the same curriculum, and a lesson that
 * cites `2:255` should cite the same ayah everywhere.
 */

/**
 * @typedef {Object} Lesson
 * @property {string} id
 * @property {string} titleEn
 * @property {string} titleAr
 * @property {string} summary
 * @property {string[]} body       paragraphs
 * @property {{caption:string, text:string}[]} [drills]  practice fragments
 * @property {{surahId:number, ayahNumber:number, focus:string}[]} examples  ayahs to hear it in
 * @property {{fragments:{caption:string,text:string}[], countEn?:string, countAr?:string}} [mushafCard]
 * @property {string} [color]      the tajweed colour this rule is painted in, where it has one
 */

/**
 * @typedef {Object} Chapter
 * @property {string} id
 * @property {string} title
 * @property {string} subtitle
 * @property {Lesson[]} lessons
 */

export class TajweedLessons {
  /** @param {{chapters: Chapter[]}} [data] data/tajweed-lessons.json */
  constructor(data = /** @type any */ ({})) {
    /** @type {Chapter[]} */
    this._chapters = data?.chapters ?? [];
    this._byLesson = new Map();
    for (const chapter of this._chapters) {
      for (const lesson of chapter.lessons) this._byLesson.set(lesson.id, { chapter, lesson });
    }
  }

  /** Every chapter, in course order. */
  chapters() {
    return this._chapters;
  }

  /** @param {string} id */
  chapter(id) {
    return this._chapters.find((c) => c.id === id) ?? null;
  }

  /** Every lesson across every chapter, in course order. */
  allLessons() {
    return this._chapters.flatMap((c) => c.lessons);
  }

  /** @param {string} id */
  lesson(id) {
    return this._byLesson.get(id)?.lesson ?? null;
  }

  /** Which chapter a lesson belongs to. @param {string} id */
  chapterOf(id) {
    return this._byLesson.get(id)?.chapter ?? null;
  }

  /**
   * The lesson after this one, walking across chapter boundaries - the "next" button's answer.
   * @param {string} id
   */
  next(id) {
    const all = this.allLessons();
    const at = all.findIndex((l) => l.id === id);
    return at >= 0 && at + 1 < all.length ? all[at + 1] : null;
  }

  /** @param {string} id */
  previous(id) {
    const all = this.allLessons();
    const at = all.findIndex((l) => l.id === id);
    return at > 0 ? all[at - 1] : null;
  }
}
