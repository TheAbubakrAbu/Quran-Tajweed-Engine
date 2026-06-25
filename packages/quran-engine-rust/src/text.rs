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
