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

// ---- Engine facade ----
export interface Engine {
  quran: Quran;
  juzPage: JuzPage;
  reciters: Reciters;
  search: Search;
  namesOfAllah: NamesOfAllah;
  muqattaat: Muqattaat;
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
}, opts?: { riwayah?: string }): Engine;
