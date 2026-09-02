// Type declarations for @quran-tajweed-engine/core
// The runtime is plain ESM JavaScript with JSDoc; these declarations mirror the public API.

export interface Ayah {
  id: number;
  textArabic: string;
  textTransliteration: string;
  textEnglishSaheeh: string;
  textEnglishMustafa: string;
  juz?: number;
  page?: number;
  wordCount?: number;
  letterCount?: number;
}

export interface Surah {
  id: number;
  type: string; // "makkan" | "madinan"
  nameArabic: string;
  nameTransliteration: string;
  nameEnglish: string;
  numberOfAyahs: number;
  pageStart?: number;
  pageEnd?: number;
  numberOfPages?: number;
  firstJuz?: number;
  lastJuz?: number;
  juzs?: number[];
  revelationOrder?: number;
  similarNames?: string[];
  wordCount?: number;
  letterCount?: number;
  ayahs: Ayah[];
}

export interface JuzEntry {
  id: number;
  nameArabic: string;
  nameTransliteration: string;
  startSurah: number;
  startAyah: number;
  endSurah: number;
  endAyah: number;
}

export interface Reciter {
  id: string;
  name: string;
  ayahIdentifier: string;
  ayahBitrate: string;
  surahLink: string;
  qiraah: string | null;
  group?: string;
}

export interface VerseIndexEntry {
  id: string;
  surah: number;
  ayah: number;
  arabicTashkeelBlob: string;
  englishExactBlob: string;
  arabicBlob: string;
  silentArabicBlob: string;
  englishBlob: string;
  arabicTokens: string[];
  silentArabicTokens: string[];
  englishTokens: string[];
}

export interface PaintOp { start: number; end: number; priority: number; category: string; }
export interface TajweedSpan { start: number; end: number; category: string; text: string; }
export interface ColoredTajweedSpan extends TajweedSpan { color: string | null; }

export type SortMode = "surah" | "revelation" | "ayahs" | "page" | "words" | "letters";
export type SortDirection = "surahOrder" | "ascending" | "descending";

// ---- Quran ----
export class Quran {
  surahs: Surah[];
  totalAyahs: number;
  constructor(opts: { surahs: Surah[]; surahInfo?: any[]; qiraat?: Record<string, Record<string, { id: number; text: string }[]>>; qiraatCounts?: Record<string, Record<string, number>> });
  all(): Surah[];
  surah(id: number): Surah | undefined;
  ayah(surahId: number, ayahId: number): Ayah | undefined;
  globalAyahNumber(surahId: number, ayahId: number): number;
  info(surahId: number): { name: string; contents: string }[];
  surahFromEnd(n: number): Surah | undefined;
  isSajdahAyah(surahId: number, ayahId: number): boolean;
  sajdahAyahs(): { surah: Surah; ayah: Ayah }[];
  pageChangesWithinSurah(surahId: number): boolean;
  juzChangesWithinSurah(surahId: number): boolean;
  pageOrJuzChangesWithinSurah(surahId: number): boolean;
  existsInQiraah(surahId: number, ayahId: number, riwayah?: string): boolean;
  numberOfAyahsInQiraah(surahId: number, riwayah?: string): number;
  /** A reading's own verses, in ITS numbering. Empty unless the qiraah text is loaded. */
  qiraahVerses(surahId: number, riwayah: string): { id: number; text: string }[];
  loadedRiwayat(): string[];
  arabicText(surahId: number, ayahId: number, riwayah?: string): string | undefined;
  cleanArabicText(surahId: number, ayahId: number, riwayah?: string): string | undefined;
  eachAyah(): Generator<{ surah: Surah; ayah: Ayah }>;
}
export function createQuran(opts: ConstructorParameters<typeof Quran>[0]): Quran;

// ---- Tajweed ----
export const PRIORITY: Record<string, number>;
export const MUQATTAAT: Set<number>;
export function detectPaintOps(arabicText: string, opts?: { surahId?: number; ayahId?: number; includeStopBased?: boolean }): PaintOp[];
export function resolveSpans(arabicText: string, ops: PaintOp[]): TajweedSpan[];
export function tajweedSpans(arabicText: string, opts?: { surahId?: number; ayahId?: number; includeStopBased?: boolean }): TajweedSpan[];

// ---- Juz / Page ----
export class JuzPage {
  juzList: JuzEntry[];
  constructor(quran: Quran, juzList: JuzEntry[]);
  juzes(): JuzEntry[];
  juz(id: number): JuzEntry | undefined;
  ayahsInJuz(juz: number): { surah: Surah; ayah: Ayah }[];
  ayahsOnPage(page: number): { surah: Surah; ayah: Ayah }[];
  firstAyahOfJuz(juz: number): { surah: Surah; ayah: Ayah } | undefined;
  firstAyahOfPage(page: number): { surah: Surah; ayah: Ayah } | undefined;
  juzForAyah(surahId: number, ayahId: number): number | undefined;
  pageForAyah(surahId: number, ayahId: number): number | undefined;
  totalPages(): number;
  surahsInJuz(juz: number): number[];
  juzFromEnd(n: number): JuzEntry | undefined;
  juzStats(juz: number): { surahCount: number; ayahCount: number; wordCount: number; letterCount: number; pageCount: number } | undefined;
}

// ---- Sorting ----
export function sortSurahs(surahs: Surah[], mode?: SortMode, direction?: SortDirection): Surah[];
export function supportsDirection(mode: SortMode): boolean;
export function filterByRevelationType(surahs: Surah[], type: "makkan" | "madinan"): Surah[];
export type CountFilter = { op: "<" | "<=" | ">" | ">=" | "=="; value: number };
export function filterByCounts(surahs: Surah[], filters?: { ayahs?: CountFilter; pages?: CountFilter }): Surah[];

// ---- Names of Allah ----
export interface NameOfAllah {
  name: string;
  transliteration: string;
  number: number;
  found: string;
  meaning: string;
  desc: string;
  otherNames: string[];
}
export class NamesOfAllah {
  list: NameOfAllah[];
  constructor(list?: NameOfAllah[]);
  all(): NameOfAllah[];
  byNumber(number: number): NameOfAllah | undefined;
}

// ---- Muqatta'at ----
export interface MuqattaatPronunciation {
  surah: number;
  ayah: number;
  letters: string[];
  transliteration: string;
  spelledOutArabic: string;
}
export class Muqattaat {
  letterNames: Record<string, string>;
  ayahs: MuqattaatPronunciation[];
  constructor(data?: { letterNames?: Record<string, string>; ayahs?: MuqattaatPronunciation[] });
  all(): MuqattaatPronunciation[];
  pronunciation(surahId: number, ayahId: number): MuqattaatPronunciation | undefined;
  letterName(letter: string): string | undefined;
}

// ---- Audio ----
export function surahAudioUrl(reciter: Reciter, surahNumber: number): string;
export function ayahAudioUrl(reciter: Reciter, globalAyahNumber: number): string;
export function defaultsToMinshawi(reciter: Reciter): boolean;
export function ayahNowPlayingName(reciter: Reciter): string;
export class Reciters {
  list: Reciter[];
  constructor(list: Reciter[]);
  all(): Reciter[];
  byId(id: string): Reciter | undefined;
  withSurahFeed(): Reciter[];
  byQiraah(qiraah: string | null): Reciter[];
  qiraat(): string[];
}

// ---- Search ----
export class Search {
  index: VerseIndexEntry[];
  constructor(quran: Quran, opts?: { riwayah?: string });
  rebuild(): void;
  searchVerses(query: string, opts?: { offset?: number; limit?: number; ignoreSilentLetters?: boolean }): VerseIndexEntry[];
  searchSurahs(query: string): Surah[];
  parseReference(query: string): { surah: number; ayah?: number } | null;
}

// ---- Cache ----
export interface CacheStore {
  has(key: string): Promise<boolean>;
  get(key: string): Promise<ArrayBuffer | Uint8Array | null>;
  put(key: string, data: ArrayBuffer | Uint8Array): Promise<void>;
  delete(key: string): Promise<void>;
}
export function sanitizeReciterDir(reciterId: string): string;
export function localSurahPath(reciter: { id: string }, surahNumber: number): string;
export function sharedAudioPath(sha256Hex: string, ext?: string): string;
export function memoryStore(): CacheStore;
export class AudioCache {
  constructor(store: CacheStore, opts?: { fetch?: typeof fetch });
  surah(reciter: { id: string }, surahNumber: number, url: string): Promise<Uint8Array>;
  hasSurah(reciter: { id: string }, surahNumber: number): Promise<boolean>;
  removeSurah(reciter: { id: string }, surahNumber: number): Promise<void>;
}

// ---- Text utils ----
export function cleanSearch(text: string, opts?: { whitespace?: boolean }): string;
export function arabicTashkeelBlob(text: string): string;
export function exactPhraseBlob(text: string): string;
export function searchTokens(cleanedText: string): string[];
export function containsArabicLetters(text: string): boolean;
export function removingArabicDiacriticsAndSigns(text: string): string;
export function removingArabicMarks(text: string): string;
export function arabicDigitsToWestern(text: string): string;
export function collapsingWhitespace(text: string): string;
export function removingSilentArabicLettersForSearch(text: string): string;
export function splitGraphemeClusters(text: string): string[];

// ---- The printed mushaf ----
export interface RiwayahEntry {
  riwayah: string;
  tag: string;
  name: string;
  nameArabic: string;
  imam: string;
  imamArabic: string;
  narratorDiedAH: number;
  pdf: string;
  pdfBytes: number;
  pages: string;
  lines: string | null;
  tajweed: string | null;
  /** False for the twelve riwayat whose machine-extracted text is not published. */
  textIncluded: boolean;
}
export class Mushaf {
  constructor(data?: { index?: any; pages?: Record<string, any>; lines?: Record<string, any> });
  riwayat(): RiwayahEntry[];
  riwayatWithText(): RiwayahEntry[];
  riwayah(slug: string): RiwayahEntry | null;
  totalPages(): number;
  pdfPath(slug: string): string | null;
  page(surahId: number, ayahId: number, riwayah?: string): number | null;
  ayahsOnPage(page: number, riwayah?: string): { surah: number; ayah: number }[];
  firstAyahOfPage(page: number, riwayah?: string): { surah: number; ayah: number } | null;
  lineBreaks(surahId: number, ayahId: number, riwayah?: string): number[] | null;
  hasTajweedPack(riwayah: string): boolean;
}

// ---- Riwayah tajweed ----
export interface LegendEntry {
  code: string;
  rule: string;
  arabic: string;
  english: string;
  short?: string;
  long?: string;
}
export interface WordRule {
  word: number;
  rule: string;
  code: string;
  arabic: string;
  english: string;
  /** Inclusive base-letter index in reading order, or -1 for the whole word. */
  firstLetter: number;
  lastLetter: number;
  wholeWord: boolean;
}
export class QiraatTajweed {
  constructor(data?: { rules?: Record<string, { short: string; long: string }>; riwayat?: Record<string, any> });
  available(): string[];
  legend(riwayah: string): LegendEntry[];
  wordRules(surahId: number, ayahId: number, riwayah: string): WordRule[];
  khilafAyahs(surahId: number, riwayah: string): number[];
  hasKhilaf(surahId: number, ayahId: number, riwayah: string): boolean;
  describe(rule: string): { short: string; long: string } | null;
  ruleKeys(): string[];
}

// ---- Word by word ----
export interface Word {
  position: number;
  arabic: string;
  english: string;
  transliteration: string;
}
export class WordByWord {
  constructor(data?: { english?: Record<string, string[][]>; transliteration?: Record<string, string[][]> }, quran?: Quran);
  readonly isLoaded: boolean;
  words(surahId: number, ayahId: number): Word[];
  word(surahId: number, ayahId: number, position: number): Word | null;
  glosses(surahId: number, ayahId: number): string[] | null;
  transliterations(surahId: number, ayahId: number): string[] | null;
  find(term: string, opts?: { limit?: number }): { surah: number; ayah: number; position: number; english: string; transliteration: string }[];
}

// ---- Similar ayahs, themes, lessons ----
export interface SimilarMatch {
  surah: number;
  ayah: number;
  phrase: string;
  verified: boolean;
  labels: string[];
}
export class SimilarAyahs {
  constructor(data?: Record<string, any[]>);
  matches(surahId: number, ayahId: number): SimilarMatch[];
  has(surahId: number, ayahId: number): boolean;
  count(): number;
}
export interface Topic {
  id: string;
  name: string;
  description: string;
  category: string;
  domain: string;
  ayahs: string[];
}
export class Themes {
  constructor(data?: { topics: Topic[] });
  all(): Topic[];
  topic(id: string): Topic | null;
  domains(): string[];
  categories(domain?: string): string[];
  inDomain(domain: string): Topic[];
  inCategory(category: string): Topic[];
  topicsFor(surahId: number, ayahId: number): Topic[];
  search(query: string): Topic[];
}
export interface Lesson {
  id: string;
  titleEn: string;
  titleAr: string;
  summary: string;
  body: string[];
  drills?: { caption: string; text: string }[];
  examples: { surahId: number; ayahNumber: number; focus: string }[];
  mushafCard?: { fragments: { caption: string; text: string }[]; countEn?: string; countAr?: string };
  color?: string;
}
export interface Chapter { id: string; title: string; subtitle: string; lessons: Lesson[] }
export class TajweedLessons {
  constructor(data?: { chapters: Chapter[] });
  chapters(): Chapter[];
  chapter(id: string): Chapter | null;
  allLessons(): Lesson[];
  lesson(id: string): Lesson | null;
  chapterOf(id: string): Chapter | null;
  next(id: string): Lesson | null;
  previous(id: string): Lesson | null;
}

// ---- Surah sections ----
export interface SurahSection { from: number; to: number; english: string; arabic: string }
export interface OutlineNode extends SurahSection { children: OutlineNode[] }
export class SurahSections {
  constructor(data?: Record<string, { overview?: string; sections?: [number, number, string, string][] }>);
  overview(surahId: number): string;
  sections(surahId: number): SurahSection[];
  outline(surahId: number): OutlineNode[];
  sectionsFor(surahId: number, ayahId: number): SurahSection[];
  sectionFor(surahId: number, ayahId: number): SurahSection | null;
  hasSections(surahId: number): boolean;
  count(): number;
  search(query: string): (SurahSection & { surah: number })[];
}

// ---- Arabic alphabet ----
export interface ArabicLetter {
  id: number;
  letter: string;
  forms: string[];
  name: string;
  transliteration: string;
  showTashkeel: boolean;
  sound: string;
  weight?: "light" | "heavy" | "conditional" | "followsPrevious";
  weightRule?: string;
}
export interface Tashkeel { english: string; arabic: string; mark: string; transliteration: string }
export interface StoppingSign { symbol: string; title: string }
export interface ArabicNumeral { number: string; name: string; transliteration: string; englishNumber: string }
export class ArabicAlphabet {
  constructor(data?: any);
  letters(): ArabicLetter[];
  otherLetters(): ArabicLetter[];
  nonArabicScriptLetters(): ArabicLetter[];
  allLetters(): ArabicLetter[];
  letter(letter: string): ArabicLetter | null;
  letterById(id: number): ArabicLetter | null;
  weight(letter: string): string | null;
  weightDescriptions(): Record<string, string>;
  heavyLetters(): ArabicLetter[];
  tashkeel(): Tashkeel[];
  stoppingSigns(): StoppingSign[];
  stoppingSign(symbol: string): StoppingSign | null;
  numbers(): ArabicNumeral[];
  stoppingSignsSource(): string;
}

// ---- Qiraat comparison ----
export interface WordDifference {
  position: number;
  base: string;
  other: string;
  kind: "sameSkeleton" | "different" | "added" | "dropped";
}
export interface ComparisonTotals {
  words: number;
  identical: number;
  sameSkeleton: number;
  different: number;
  added: number;
  dropped: number;
  identicalPercent: number;
}
export class QiraatComparison {
  constructor(quran: Quran);
  available(): string[];
  words(surahId: number, riwayah: string): string[];
  compareSurah(surahId: number, riwayah: string, opts?: { against?: string }): ComparisonTotals;
  compare(riwayah: string, opts?: { against?: string }): ComparisonTotals;
  differences(surahId: number, riwayah: string, opts?: { against?: string; limit?: number }): WordDifference[];
}
export function skeleton(word: string): string;

// ---- Meaning search ----
export type Embedder = (word: string) => number[] | Float32Array | null | undefined;
export interface SemanticHit { id: string; score: number; meta?: any }
export class Semantic {
  constructor(opts: { embed: Embedder; minWordLength?: number });
  readonly size: number;
  index(documents: Iterable<{ id: string; text: string; meta?: any }>): this;
  search(query: string, opts?: { limit?: number; minScore?: number }): SemanticHit[];
  clear(): this;
}
export function cosine(a: Float32Array, b: Float32Array): number;

// ---- Ask AI ----
export interface Passage {
  kind: "ayah" | "surah" | "topic";
  reference: string;
  text: string;
  maxCharacters: number;
  isSubject: boolean;
  surah?: number;
  ayah?: number;
}
export class AskAI {
  constructor(parts: { quran: Quran; search: Search; themes?: Themes; semantic?: Semantic; translation?: "textEnglishSaheeh" | "textEnglishMustafa" });
  semantic: Semantic | null;
  buildSemanticIndex(embed: Embedder): Semantic;
  retrieve(question: string, opts?: { previousQuestion?: string; carried?: Passage[]; limit?: number }): Passage[];
  referencePassages(question: string): Passage[];
  keywordPassages(question: string, opts?: { limit?: number }): Passage[];
  themePassages(question: string, opts?: { limit?: number }): Passage[];
  semanticPassages(question: string, opts?: { limit?: number; minScore?: number }): Passage[];
  ayahPassage(surahId: number, ayahId: number, opts?: { isSubject?: boolean; maxCharacters?: number }): Passage | null;
  surahPassage(surahId: number): Passage | null;
  contentWords(question: string): string[];
  isBareFollowUp(question: string): boolean;
  termWeights(terms: string[]): number[];
}
export const QUESTION_WORDS: Set<string>;
export const PASSAGE_LIMIT: number;
export const PASSAGE_CHARACTER_LIMIT: number;
export const SUBJECT_CHARACTER_LIMIT: number;
export const CHAT_INSTRUCTIONS: string;
export function chatPrompt(question: string, passages: Passage[], opts?: { transcript?: { question: string; answer: string }[]; passageLimit?: number }): { instructions: string; prompt: string };

// ---- Engine facade ----
export interface Engine {
  quran: Quran;
  juzPage: JuzPage;
  reciters: Reciters;
  search: Search;
  namesOfAllah: NamesOfAllah;
  muqattaat: Muqattaat;
  mushaf: Mushaf;
  qiraatTajweed: QiraatTajweed;
  wordByWord: WordByWord;
  similarAyahs: SimilarAyahs;
  themes: Themes;
  tajweedLessons: TajweedLessons;
  askAI: AskAI;
  surahSections: SurahSections;
  alphabet: ArabicAlphabet;
  qiraatComparison: QiraatComparison;
  tajweedRules: any;
  tajweed(arabicText: string, opts?: object): ColoredTajweedSpan[];
  detectPaintOps: typeof detectPaintOps;
  resolveSpans: typeof resolveSpans;
}
export function createEngine(data: {
  quran: Surah[];
  juz: JuzEntry[];
  reciters: Reciter[];
  tajweedRules?: any;
  surahInfo?: any[];
  namesOfAllah?: NameOfAllah[];
  muqattaat?: { letterNames?: Record<string, string>; ayahs?: MuqattaatPronunciation[] };
  qiraat?: Record<string, Record<string, { id: number; text: string }[]>>;
  qiraatCounts?: Record<string, Record<string, number>>;
  mushafIndex?: { totalPages: number; note?: string; riwayat: RiwayahEntry[] };
  mushafPages?: Record<string, any>;
  mushafLines?: Record<string, any>;
  qiraatTajweedRules?: Record<string, { short: string; long: string }>;
  qiraatTajweed?: Record<string, any>;
  wordByWord?: { english: Record<string, string[][]>; transliteration: Record<string, string[][]> };
  similarAyahs?: Record<string, any[]>;
  themes?: { topics: Topic[] };
  tajweedLessons?: { chapters: Chapter[] };
}, opts?: { riwayah?: string }): Engine;

/** Node-only loader (`@quran-tajweed-engine/core/node`). */
export function loadFromDisk(opts?: {
  dataDir?: string;
  loadQiraat?: boolean;
  loadSurahInfo?: boolean;
  loadMushaf?: boolean;
  loadQiraatTajweed?: boolean;
  loadWordByWord?: boolean;
  loadSimilarAyahs?: boolean;
  riwayah?: string;
}): Promise<Engine>;
