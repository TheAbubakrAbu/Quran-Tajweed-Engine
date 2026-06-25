# Server (Node / Deno / Bun + Go / Rust / Python)

Wrap the engine in a small JSON HTTP API. The engine is pure and offline — load it once at startup and
answer requests from memory. Audio endpoints return **URL strings** (the engine never proxies audio).

Example routes:

| Route | Returns |
|---|---|
| `GET /surah/:id` | surah metadata + ayahs |
| `GET /ayah/:s/:a` | one ayah + its tajweed spans |
| `GET /search?q=` | verse + surah matches |
| `GET /audio/surah/:reciter/:id` | full-surah mp3 URL |
| `GET /audio/ayah/:reciter/:s/:a` | single-ayah mp3 URL |

## Node / Deno / Bun (`quran-engine-js`)

Load the engine once. On Node use `loadFromDisk` (reads the repo `/data`); in the browser/edge bundle JSON
and use `createEngine`. The same code runs on Deno and Bun.

```js
import { createServer } from "node:http";
import { loadFromDisk } from "@quran-tajweed-engine/core/node";
import { surahAudioUrl, ayahAudioUrl } from "@quran-tajweed-engine/core";

const engine = await loadFromDisk();           // load once at startup

const json = (res, code, body) => {
  res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
};

createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const seg = url.pathname.split("/").filter(Boolean);   // e.g. ["ayah","2","255"]
  const reciterFor = (key) =>
    engine.reciters.byId(key) ?? engine.reciters.all().find((r) => r.name === key);

  try {
    // GET /surah/:id
    if (seg[0] === "surah" && seg.length === 2) {
      const s = engine.quran.surah(Number(seg[1]));
      return s ? json(res, 200, s) : json(res, 404, { error: "no such surah" });
    }

    // GET /ayah/:s/:a  → ayah + tajweed spans
    if (seg[0] === "ayah" && seg.length === 3) {
      const [s, a] = [Number(seg[1]), Number(seg[2])];
      const ayah = engine.quran.ayah(s, a);
      if (!ayah) return json(res, 404, { error: "no such ayah" });
      // engine.tajweed(text) → [{ start, end, category, text, color }]
      return json(res, 200, { ...ayah, tajweed: engine.tajweed(ayah.textArabic) });
    }

    // GET /search?q=...
    if (seg[0] === "search") {
      const q = url.searchParams.get("q") ?? "";
      return json(res, 200, {
        surahs: engine.search.searchSurahs(q).map((s) => ({ id: s.id, name: s.nameEnglish })),
        ref: engine.search.parseReference(q),                 // {surah, ayah} | null
        verses: engine.search.searchVerses(q, { limit: 50 }), // [{ id, surah, ayah }]
      });
    }

    // GET /audio/surah/:reciter/:id  and  /audio/ayah/:reciter/:s/:a
    if (seg[0] === "audio") {
      const reciter = reciterFor(decodeURIComponent(seg[2] ?? ""));
      if (!reciter) return json(res, 404, { error: "no such reciter" });
      if (seg[1] === "surah" && seg.length === 4) {
        return json(res, 200, { url: surahAudioUrl(reciter, Number(seg[3])) });
      }
      if (seg[1] === "ayah" && seg.length === 5) {
        const g = engine.quran.globalAyahNumber(Number(seg[3]), Number(seg[4]));
        return json(res, 200, { url: ayahAudioUrl(reciter, g) });
      }
    }

    json(res, 404, { error: "not found" });
  } catch (err) {
    json(res, 400, { error: String(err.message ?? err) });
  }
}).listen(3000, () => console.log("http://localhost:3000"));
```

**Tajweed snippet** — the `/ayah` route above already attaches it. The facade returns spans with
`{ start, end, category, text, color }` (color from `tajweed-rules.json`), ready to render client-side; see
[02-tajweed.md](../02-tajweed.md).

**Audio snippet** — `surahAudioUrl(reciter, id)` / `ayahAudioUrl(reciter, globalAyah)`. Resolve the reciter
by id (`reciter.id`) or name; compute the global ayah with `engine.quran.globalAyahNumber(s, a)`.

> **Deno / Bun:** replace the `node:http` server with `Deno.serve` / `Bun.serve`, and bundle the JSON +
> `createEngine` (or use a Node-compat import of `loadFromDisk`). The engine code is identical.

## Go (`quran-engine-go`)

Same shape with `net/http` and package `quranengine`. Load once with `quranengine.Load()` (or
`LoadFrom(dir)`), then:

```go
e, _ := quranengine.Load()
http.HandleFunc("/ayah/", func(w http.ResponseWriter, r *http.Request) {
    // parse :s and :a from r.URL.Path
    ayah := e.Ayah(s, a)
    spans := e.TajweedSpans(s, a)          // strategy A: rule -> colorHex
    json.NewEncoder(w).Encode(map[string]any{"ayah": ayah, "tajweed": spans})
})
// audio: e.SurahAudioURL(reciter, id) / e.AyahAudioURL(reciter, e.GlobalAyahNumber(s, a))
// search: e.SearchVerses(q, opts) / e.SearchSurahs(q) / e.ParseReference("2:255")
```

See the [`quran-engine-go` README](../../packages/quran-engine-go/README.md) for the full method list.

## Rust (`quran-engine-rust`)

Use `axum`/`actix`/`hyper` over the `Engine` facade. Load once with `Engine::load_default()` (or
`Engine::load(path)`):

```rust
let engine = Engine::load_default()?;
// GET /ayah/:s/:a
let ayah = engine.ayah(s, a);
let spans = engine.tajweed(s, a);          // Vec<TajweedSpan> { start, end, rule, color, text }
// audio: engine.surah_audio_url(reciter, id)? / engine.ayah_audio_url(reciter, g)
// search: engine.search_verses(q, &SearchOpts::default()) / engine.search_surahs(q) / engine.parse_reference("2:255")
```

See the [`quran-engine-rust` README](../../packages/quran-engine-rust/README.md).

## Python (`quran-engine-py`)

Pure standard library; pair it with FastAPI/Flask or `http.server`. Load once with `Engine.load()`:

```python
from quran_engine import Engine, surah_audio_url, ayah_audio_url
engine = Engine.load()

# GET /ayah/{s}/{a}
def ayah(s: int, a: int):
    ay = engine.quran.ayah(s, a)
    spans = engine.tajweed(s, a)                 # strategy A: rule -> color
    return {"ayah": ay.__dict__, "tajweed": [sp.__dict__ for sp in spans]}

# audio
r = next(r for r in engine.reciters.all() if r.name == "Mishary Alafasy")
surah_audio_url(r, 36)
ayah_audio_url(r, engine.quran.global_ayah_number(2, 255))

# search: engine.search.search_verses(q) / engine.search.search_surahs(q) / engine.search.parse_reference("2:255")
```

See the [`quran-engine-py` README](../../packages/quran-engine-py/README.md).

> All ports share the same contract ([PORTING.md](../PORTING.md)) — only the casing differs
> (`globalAyahNumber` ⇄ `global_ayah_number` ⇄ `GlobalAyahNumber`).

## See also

- [recipes.md](../recipes.md) — #2 (tajweed), #4–6 (audio), #7 (search).
- [01-quran.md](../01-quran.md) · [02-tajweed.md](../02-tajweed.md) · [06-ayah-search.md](../06-ayah-search.md)
- [04-surah-recitations.md](../04-surah-recitations.md) · [05-ayah-recitations.md](../05-ayah-recitations.md)
- [PORTING.md](../PORTING.md) · package READMEs under [`../../packages`](../../packages)
