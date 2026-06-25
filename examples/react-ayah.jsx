// react-ayah.jsx
//
// A self-contained React component that renders a single ayah with tajweed
// coloring, its English translation, and a play button wired to the per-ayah
// audio feed.
//
// This is a SNIPPET (not run by the test harness), but every engine call below
// matches the real API in packages/quran-engine-js/src.
//
// In a bundler (Vite/Next/CRA) you import the JSON yourself and build the engine
// with createEngine(). Do this ONCE at app scope, not per render. Two common ways:
//
//   // (a) static import — bundles the data
//   import quran from "../data/quran.json";
//   import juz from "../data/juz.json";
//   import reciters from "../data/reciters.json";
//   import tajweedRules from "../data/tajweed-rules.json";
//   import { createEngine } from "@quran-tajweed-engine/core";
//   export const engine = createEngine({ quran, juz, reciters, tajweedRules });
//
//   // (b) fetch at runtime (keeps the 5 MB quran.json out of the main bundle) —
//   //     load it in an effect / loader and pass `engine` down via context/props.
//
// Here we accept `engine` as a prop so the component stays pure and testable.

import React, { useMemo, useRef } from "react";
import { ayahAudioUrl } from "@quran-tajweed-engine/core";

/**
 * Render one ayah with tajweed coloring + translation + a play button.
 *
 * @param {Object} props
 * @param {ReturnType<import("@quran-tajweed-engine/core").createEngine>} props.engine
 * @param {number} props.surah   surah id, 1..114
 * @param {number} props.ayah    ayah id within the surah
 * @param {string} [props.reciterName="Mishary Alafasy"]
 * @param {"saheeh"|"mustafa"} [props.translation="saheeh"]
 */
export function AyahView({ engine, surah, ayah, reciterName = "Mishary Alafasy", translation = "saheeh" }) {
  const audioRef = useRef(null);

  // Look up the ayah + its tajweed spans. Memoize so we only recompute when the
  // reference changes (tajweed detection is pure for a given text).
  const { record, spans } = useMemo(() => {
    const record = engine.quran.ayah(surah, ayah);
    const spans = record ? engine.tajweed(record.textArabic) : [];
    return { record, spans };
  }, [engine, surah, ayah]);

  if (!record) return <p>Ayah {surah}:{ayah} not found.</p>;

  const text = record.textArabic;
  const english = translation === "mustafa" ? record.textEnglishMustafa : record.textEnglishSaheeh;

  // Turn non-overlapping, in-order spans into React nodes. Text between spans is
  // rendered uncolored.
  const nodes = [];
  let cursor = 0;
  spans.forEach((s, i) => {
    if (s.start > cursor) nodes.push(text.slice(cursor, s.start)); // uncolored gap
    nodes.push(
      <span key={i} style={{ color: s.color ?? "inherit" }} title={s.category}>
        {text.slice(s.start, s.end)}
      </span>
    );
    cursor = s.end;
  });
  if (cursor < text.length) nodes.push(text.slice(cursor));

  const play = () => {
    const reciter = engine.reciters.all().find((r) => r.name === reciterName);
    if (!reciter || !audioRef.current) return;
    const globalN = engine.quran.globalAyahNumber(surah, ayah);
    audioRef.current.src = ayahAudioUrl(reciter, globalN);
    audioRef.current.play();
  };

  return (
    <article style={{ maxWidth: 640, margin: "1rem auto", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ font: "0.8rem/1 monospace", color: "#888" }}>{surah}:{ayah}</div>

      <p
        dir="rtl"
        lang="ar"
        style={{ fontSize: "2rem", textAlign: "right", lineHeight: 2, fontFamily: '"Scheherazade New", "Amiri", serif' }}
      >
        {nodes}
      </p>

      <p style={{ color: "#666" }}>{english}</p>

      <button onClick={play} style={{ cursor: "pointer" }}>▶ Play</button>
      <audio ref={audioRef} hidden />
    </article>
  );
}

export default AyahView;

// ---------------------------------------------------------------------------
// Usage:
//
//   import { createEngine } from "@quran-tajweed-engine/core";
//   import quran from "../data/quran.json";
//   import juz from "../data/juz.json";
//   import reciters from "../data/reciters.json";
//   import tajweedRules from "../data/tajweed-rules.json";
//
//   const engine = createEngine({ quran, juz, reciters, tajweedRules });
//
//   function App() {
//     return <AyahView engine={engine} surah={2} ayah={255} />;
//   }
// ---------------------------------------------------------------------------
