// Deterministic typo tolerance for typed food search — no model, no network.
//
// The vocabulary is every word the app can actually show: curated food names +
// aliases, restaurant item words and chain keys. A query word that is long
// enough, doesn't begin or form-match any vocabulary word (so "chick" and
// "bananas" are left alone) and sits exactly one edit from ONE vocabulary word
// is replaced by that word ("bananna" → "banana", "grenola" → "granola").
// Several candidates → the most frequent word wins, then A–Z.
//
// Domain layer: Foundation only.

import Foundation

struct SearchVocabulary: Sendable {

    /// Query words shorter than this are never corrected (too many neighbours).
    static let minCorrectableLength = 5

    private let frequency: [String: Int]
    /// Words that name a FOOD (everything except chain keys), for the chain-split guard.
    private let foodWords: Set<String>
    private let sortedWords: [String]
    private let formSet: Set<String>
    private let byLength: [Int: [String]]

    /// - Parameters:
    ///   - wordLists: name / alias / menu-item words, already folded (`FoodSearchQuery.normalizedWords`).
    ///   - chainKeys: run-together chain names and aliases ("shakeshack").
    init(wordLists: [[String]], chainKeys: [String]) {
        var freq: [String: Int] = [:]
        var food = Set<String>()
        for list in wordLists {
            for w in list where w.count >= 3 && w.allSatisfy(\.isLetter) {
                freq[w, default: 0] += 1
                food.insert(w)
            }
        }
        for k in chainKeys where k.count >= 3 && k.allSatisfy(\.isLetter) { freq[k, default: 0] += 1 }
        frequency = freq
        foodWords = food
        let words = freq.keys.sorted()
        sortedWords = words
        formSet = Set(words.flatMap(FoodSearchQuery.forms))
        byLength = Dictionary(grouping: words.filter { $0.count >= 4 }, by: \.count)
    }

    func isFoodWord(_ w: String) -> Bool { foodWords.contains(w) }

    /// True when some vocabulary word starts with `w` (the user is mid-word) or
    /// shares a singular form with it.
    func isKnown(_ w: String) -> Bool {
        if FoodSearchQuery.forms(w).contains(where: formSet.contains) { return true }
        // First sorted word >= w; it starts with w iff any word does.
        var lo = 0, hi = sortedWords.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedWords[mid] < w { lo = mid + 1 } else { hi = mid }
        }
        return lo < sortedWords.count && sortedWords[lo].hasPrefix(w)
    }

    /// The single vocabulary word one edit (insert, delete, substitute or
    /// adjacent swap) from `w`, or nil when `w` is short, already fine, or has
    /// no neighbour.
    func correction(for w: String) -> String? {
        guard w.count >= Self.minCorrectableLength, w.allSatisfy(\.isLetter), !isKnown(w) else { return nil }
        let a = Array(w)
        var best: (word: String, freq: Int)?
        for len in (w.count - 1)...(w.count + 1) {
            for cand in byLength[len] ?? [] where RestaurantMatcher.editDistance(a, Array(cand), cap: 1) == 1 {
                let f = frequency[cand] ?? 0
                if best == nil || f > best!.freq || (f == best!.freq && cand < best!.word) { best = (cand, f) }
            }
        }
        return best?.word
    }
}
