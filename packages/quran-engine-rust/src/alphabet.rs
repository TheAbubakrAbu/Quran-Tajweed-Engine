//! The Arabic alphabet as a Quran reader meets it: every letter with its joining forms, its name and
//! transliteration, and — the part that matters for tajweed — its WEIGHT.
//!
//! Weight is why this belongs in a tajweed engine rather than in a phrasebook. Every letter is
//! pronounced thin (tarqiq) or full (tafkhim), a few depend on context (raa, and the lam of the
//! divine name), and alif has no weight of its own at all: it inherits the letter before it. That
//! single fact is behind a large share of beginner mistakes, and it is a property of the letter, not
//! of any particular verse, so it lives here beside the letter and not in the annotation corpus.
//!
//! Also carried: the letters outside the 28, the six Persian/Urdu letters some printed mushafs use,
//! the Eastern-Arabic numerals, the tashkeel marks, and the waqf (stopping) signs.
//!
//! See `../../docs/16-arabic-alphabet.md`.

use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ArabicLetter {
    #[serde(default)]
    pub id: u32,
    #[serde(default)]
    pub letter: String,
    #[serde(default)]
    pub forms: Vec<String>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub transliteration: String,
    #[serde(default)]
    pub show_tashkeel: bool,
    #[serde(default)]
    pub sound: String,
    /// `"light"`, `"heavy"`, `"conditional"`, `"followsPrevious"` — or `None` where none is recorded.
    #[serde(default)]
    pub weight: Option<String>,
    /// Why, in one sentence.
    #[serde(default)]
    pub weight_rule: Option<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
pub struct Tashkeel {
    #[serde(default)]
    pub english: String,
    #[serde(default)]
    pub arabic: String,
    #[serde(default)]
    pub mark: String,
    #[serde(default)]
    pub transliteration: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
pub struct StoppingSign {
    #[serde(default)]
    pub symbol: String,
    #[serde(default)]
    pub title: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ArabicNumeral {
    #[serde(default)]
    pub number: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub transliteration: String,
    #[serde(default)]
    pub english_number: String,
}

/// `data/arabic-alphabet.json`.
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ArabicAlphabetFile {
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub weights: HashMap<String, String>,
    #[serde(default)]
    pub standard_letters: Vec<ArabicLetter>,
    #[serde(default)]
    pub other_letters: Vec<ArabicLetter>,
    #[serde(default)]
    pub non_arabic_script_letters: Vec<ArabicLetter>,
    #[serde(default)]
    pub numbers: Vec<ArabicNumeral>,
    #[serde(default)]
    pub tashkeel: Vec<Tashkeel>,
    #[serde(default)]
    pub stopping_signs: Vec<StoppingSign>,
    #[serde(default)]
    pub stopping_signs_source: String,
}

use crate::Engine;

impl Engine {
    /// The 28 letters of the alphabet, in order.
    pub fn letters(&self) -> &[ArabicLetter] {
        &self.alphabet.standard_letters
    }

    /// Hamza, ta marbuta, lam-alif and the rest: written forms outside the 28.
    pub fn other_letters(&self) -> &[ArabicLetter] {
        &self.alphabet.other_letters
    }

    /// The Persian/Urdu letters some printed mushafs use for non-Arabic sounds.
    pub fn non_arabic_script_letters(&self) -> &[ArabicLetter] {
        &self.alphabet.non_arabic_script_letters
    }

    /// Every letter this reference knows, the 28 first.
    pub fn all_letters(&self) -> Vec<&ArabicLetter> {
        self.letters()
            .iter()
            .chain(self.other_letters())
            .chain(self.non_arabic_script_letters())
            .collect()
    }

    /// One letter by its isolated form. Accepts any of its joining forms too, so a letter lifted out
    /// of a word still resolves.
    pub fn letter(&self, letter: &str) -> Option<&ArabicLetter> {
        let wanted = letter.trim();
        if wanted.is_empty() {
            return None;
        }
        self.all_letters()
            .into_iter()
            .find(|entry| entry.letter == wanted || entry.forms.iter().any(|f| f == wanted))
    }

    pub fn letter_by_id(&self, id: u32) -> Option<&ArabicLetter> {
        self.all_letters().into_iter().find(|entry| entry.id == id)
    }

    /// The tajweed weight of a letter, or `None` when the reference records none.
    pub fn letter_weight(&self, letter: &str) -> Option<&str> {
        self.letter(letter)?.weight.as_deref()
    }

    /// What a weight name means, in one line.
    pub fn weight_descriptions(&self) -> &HashMap<String, String> {
        &self.alphabet.weights
    }

    /// The letters pronounced full — the isti'la letters.
    pub fn heavy_letters(&self) -> Vec<&ArabicLetter> {
        self.letters().iter().filter(|l| l.weight.as_deref() == Some("heavy")).collect()
    }

    pub fn tashkeel(&self) -> &[Tashkeel] {
        &self.alphabet.tashkeel
    }

    /// The waqf signs, with what each one tells the reciter to do.
    pub fn stopping_signs(&self) -> &[StoppingSign] {
        &self.alphabet.stopping_signs
    }

    pub fn stopping_sign(&self, symbol: &str) -> Option<&StoppingSign> {
        self.stopping_signs().iter().find(|sign| sign.symbol == symbol)
    }

    /// The Eastern-Arabic numerals, 0 through 10.
    pub fn arabic_numbers(&self) -> &[ArabicNumeral] {
        &self.alphabet.numbers
    }

    pub fn stopping_signs_source(&self) -> &str {
        &self.alphabet.stopping_signs_source
    }
}
