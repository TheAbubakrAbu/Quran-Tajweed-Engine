import Foundation

/// Sanitize a reciter id into a filesystem-safe directory name. Mirrors `sanitizeReciterDir`:
/// keep `[A-Za-z0-9-_]`, replace everything else with `_`, cap at 180 chars, fallback `"reciter"`.
public func sanitizeReciterDir(_ reciterId: String) -> String {
    var chars = [Character]()
    for ch in reciterId {
        if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_") {
            chars.append(ch)
        } else {
            chars.append("_")
        }
        if chars.count == 180 { break }
    }
    let safe = String(chars)
    return safe.isEmpty ? "reciter" : safe
}

/// Relative path (under the downloads root) for a downloaded full-surah file.
/// Mirrors `localSurahPath`.
public func localSurahPath(_ reciter: Reciter, _ surahNumber: Int) -> String {
    "\(sanitizeReciterDir(reciter.id))/\(zeroPad3(surahNumber)).mp3"
}

/// Relative path of the content-addressed shared file for a given content hash.
public func sharedAudioPath(_ sha256Hex: String, ext: String = "mp3") -> String {
    "SharedAudio/\(sha256Hex).\(ext)"
}
