//! Small shared helpers.

/// Zero-pad a surah number to 3 digits: `1 -> "001"`, `57 -> "057"`, `114 -> "114"`.
pub fn zero_pad3(n: u32) -> String {
    format!("{:03}", n)
}

/// Slice a string by UTF-16 code-unit offsets and re-encode to a `String`.
///
/// The tajweed annotation `start`/`end` are UTF-16 offsets (the reference engine is
/// UTF-16). Rust strings are UTF-8/byte indexed, so we decode to `Vec<u16>`, slice,
/// and re-encode. Mirrors the strategy in `docs/PORTING.md`.
pub fn utf16_slice(text: &str, start: usize, end: usize) -> String {
    let units: Vec<u16> = text.encode_utf16().collect();
    let len = units.len();
    let s = start.min(len);
    let e = end.min(len).max(s);
    String::from_utf16_lossy(&units[s..e])
}
