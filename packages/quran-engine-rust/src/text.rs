//! Arabic/English text normalization for search. Ports the load-bearing parts of `src/text.js`.
//!
//! The boolean-search-specific helpers (tashkeel blob, exact-phrase blob, silent-letter removal)
//! are intentionally omitted along with the boolean grammar; see `search.rs`.

/// Canonical Arabic fold map (carrier -> bare letter / removed). Mirrors `CANONICAL_ARABIC_MAP`.
fn fold_char(c: char) -> Option<char> {
    // Returns Some(replacement) or None when the char should be removed entirely.
    match c {
        '\u{0670}' => Some('ا'), // dagger alif
        'ٱ' => Some('ا'),
        'أ' | 'إ' | 'آ' | 'ٲ' | 'ٳ' | 'ٵ' => Some('ا'),
        'ؤ' | 'ٶ' | 'ٷ' | 'ۥ' => Some('و'),
        'ئ' | 'ٸ' | 'ۦ' => Some('ي'),
        'ء' | 'ٴ' => None,
        'ى' => Some('ا'), // alif maqsura -> alif
        'ة' => Some('ه'), // teh marbuta -> heh
        other => Some(other),
    }
}

fn is_kept_operator(c: char) -> bool {
    matches!(c, '&' | '|' | '!' | '#')
}

/// Unicode combining-mark ranges relevant to Arabic (a pragmatic subset of `\p{M}` covering the
/// Quranic marks). Used to strip diacritics during the search fold.
fn is_combining_mark(c: char) -> bool {
    let cp = c as u32;
    (0x0300..=0x036F).contains(&cp)   // combining diacritical marks
        || (0x0610..=0x061A).contains(&cp)
        || (0x064B..=0x065F).contains(&cp)
        || cp == 0x0670
        || (0x06D6..=0x06ED).contains(&cp)
        || (0x08E0..=0x08FF).contains(&cp)
}

/// Treat as punctuation/symbol to strip (a pragmatic stand-in for `\p{P}|\p{S}`).
fn is_punct_or_symbol(c: char) -> bool {
    if c.is_alphanumeric() || c.is_whitespace() {
        return false;
    }
    // ASCII punctuation/symbols and common Arabic punctuation.
    c.is_ascii_punctuation()
        || matches!(
            c,
            '،' | '؛' | '؟' | '٪' | '۔' | '«' | '»' | '“' | '”' | '‘' | '’' | '—' | '–' | '…'
        )
        || (c as u32) >= 0x2000 && (c as u32) <= 0x206F // general punctuation block
}

/// Collapse runs of whitespace into single spaces.
pub fn collapsing_whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The core search normalizer. Mirrors `cleanSearch`:
/// fold Arabic carriers -> strip punctuation/symbols/combining marks (keep `& | ! #`)
/// -> lowercase -> collapse whitespace.
pub fn clean_search(text: &str) -> String {
    let mut cleaned = String::new();
    for c in text.chars() {
        let folded = match fold_char(c) {
            Some(f) => f,
            None => continue,
        };
        if is_kept_operator(folded) {
            cleaned.push(folded);
            continue;
        }
        if is_combining_mark(folded) || is_punct_or_symbol(folded) {
            continue;
        }
        cleaned.push(folded);
    }
    collapsing_whitespace(&cleaned.to_lowercase())
}

/// Remove Quranic recitation marks / diacritics ("clean Arabic"). Mirrors
/// `removingArabicDiacriticsAndSigns`.
pub fn removing_arabic_diacritics_and_signs(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars() {
        let cp = c as u32;
        if cp == 0x0671 {
            out.push('ا'); // hamzat wasl -> alif
            continue;
        }
        if (0x064B..=0x065F).contains(&cp)
            || (0x06D6..=0x06ED).contains(&cp)
            || cp == 0x0670
            || cp == 0x0657
            || cp == 0x0674
            || cp == 0x0656
        {
            continue;
        }
        out.push(c);
    }
    out
}

/// Convert Arabic-Indic and Eastern-Arabic digits to Western. Mirrors `arabicDigitsToWestern`.
pub fn arabic_digits_to_western(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '٠' | '۰' => '0',
            '١' | '۱' => '1',
            '٢' | '۲' => '2',
            '٣' | '۳' => '3',
            '٤' | '۴' => '4',
            '٥' | '۵' => '5',
            '٦' | '۶' => '6',
            '٧' | '۷' => '7',
            '٨' | '۸' => '8',
            '٩' | '۹' => '9',
            other => other,
        })
        .collect()
}

/// Arabic-script letter ranges. Mirrors `ARABIC_LETTER_RANGES`.
pub fn contains_arabic_letters(text: &str) -> bool {
    text.chars().any(|c| {
        let cp = c as u32;
        (0x0600..=0x06FF).contains(&cp)
            || (0x0750..=0x077F).contains(&cp)
            || (0x08A0..=0x08FF).contains(&cp)
            || (0xFB50..=0xFDFF).contains(&cp)
            || (0xFE70..=0xFEFF).contains(&cp)
            || (0x1EE00..=0x1EEFF).contains(&cp)
    })
}

/// Tokenize a cleaned blob on spaces.
pub fn search_tokens(cleaned: &str) -> Vec<String> {
    cleaned.split(' ').filter(|t| !t.is_empty()).map(|t| t.to_string()).collect()
}

/// True if a code point is an Arabic "tashkeel" (diacritic) mark. Mirrors `inTashkeel`.
fn in_tashkeel(cp: u32) -> bool {
    (0x0610..=0x061A).contains(&cp)
        || (0x064B..=0x065F).contains(&cp)
        || cp == 0x0670
        || (0x06D6..=0x06ED).contains(&cp)
}

/// Keep ONLY tashkeel scalars (inverse of `clean_search`). Mirrors `arabicTashkeelBlob`.
pub fn arabic_tashkeel_blob(text: &str) -> String {
    text.chars().filter(|c| in_tashkeel(*c as u32)).collect()
}

/// Lowercase + whitespace-collapse without stripping marks. Mirrors `exactPhraseBlob`.
pub fn exact_phrase_blob(text: &str) -> String {
    collapsing_whitespace(&text.to_lowercase())
}

/// Split a string into grapheme clusters (base char + trailing combining marks). Sufficient for
/// Arabic Quranic text; mirrors the combining-mark fallback of `splitGraphemeClusters`.
fn split_grapheme_clusters(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for c in text.chars() {
        if !out.is_empty() && is_combining_mark(c) {
            out.last_mut().unwrap().push(c);
        } else {
            out.push(c.to_string());
        }
    }
    out
}

/// Drop "silent" Arabic letters for the lenient Arabic search variant. Mirrors
/// `removingSilentArabicLettersForSearch` (grapheme-cluster walk).
pub fn removing_silent_arabic_letters_for_search(text: &str) -> String {
    const VOWELS: [u32; 9] = [
        0x064E, 0x064F, 0x0650, 0x064B, 0x064C, 0x064D, 0x0656, 0x0657, 0x065A,
    ];
    let mut out = String::new();
    for cluster in split_grapheme_clusters(text) {
        let scalars: Vec<u32> = cluster.chars().map(|c| c as u32).collect();
        let base = scalars[0];
        let has = |cp: u32| scalars.contains(&cp);
        let has_std_sukoon = has(0x0652) && !has(0x06E1);
        // hamzatul wasl is always silent
        if base == 0x0671 {
            continue;
        }
        // alif/waw/ya/alif-maqsura with a plain sukoon
        if matches!(base, 0x0627 | 0x0648 | 0x064A | 0x0649) && has_std_sukoon {
            continue;
        }
        // lam with a plain sukoon
        if base == 0x0644 && has_std_sukoon {
            continue;
        }
        // waw carrying a dagger alif with no vowel/shadda/sukoon
        if base == 0x0648
            && has(0x0670)
            && !scalars
                .iter()
                .any(|s| VOWELS.contains(s) || *s == 0x0651 || *s == 0x0652)
        {
            continue;
        }
        out.push_str(&cluster);
    }
    out
}
