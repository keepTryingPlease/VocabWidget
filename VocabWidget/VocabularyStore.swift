// VocabularyStore.swift
// Shared between the main app target AND the widget extension target.
// In Xcode: select this file → File Inspector → check both targets under "Target Membership".
//
// LEARNING NOTES:
// - Words are loaded once from words.json in the app bundle. Bundle access is
//   fast and works offline — no network needed.
// - `words` is the full shuffled deck used by the app's swipe UI.
//   The shuffle seed is fixed to the current year so the order stays consistent
//   within a year but changes annually.
// - `featuredWords` filters to only the curated isFeatured == true entries.
//   The widget uses this smaller pool for its daily word.
// - Both the app and the widget run this same code independently, so they always
//   agree on which word is "today's featured word" — no App Groups needed.

import Foundation

struct VocabularyStore {

    // ---------------------------------------------------------
    // MARK: - Full word list (shuffled for the app deck)
    // Order is stable within a calendar year (seeded by year),
    // then reshuffles at the new year for freshness.
    // ---------------------------------------------------------
    static let words: [VocabularyWord] = {
        // Step 1: locate the file
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            print("❌ VocabularyStore: words.json not found in bundle")
            print("   Bundle path: \(Bundle.main.bundlePath)")
            print("   All bundle resources: \(Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil))")
            return []
        }
        // Step 2: read the data
        guard let data = try? Data(contentsOf: url) else {
            print("❌ VocabularyStore: failed to read words.json at \(url)")
            return []
        }
        // Step 3: decode
        do {
            let list = try JSONDecoder().decode([VocabularyWord].self, from: data)
            print("✅ VocabularyStore: loaded \(list.count) words")
            // Seed the shuffle with the current year so order is stable day-to-day
            // but refreshes each January 1st.
            let year = Calendar.current.component(.year, from: Date())
            var rng  = SeededRandomNumberGenerator(seed: UInt64(year))
            return list.shuffled(using: &rng)
        } catch {
            print("❌ VocabularyStore: JSON decode failed — \(error)")
            return []
        }
    }()

    // ---------------------------------------------------------
    // MARK: - Word bank fingerprint
    // A stable checksum derived from the sorted word IDs.
    // Changes whenever words.json is replaced with a different set of words,
    // allowing UserLibrary to detect and reset stale user data.
    // ---------------------------------------------------------
    static let fingerprint: String = {
        var hash: UInt64 = 5381
        for id in words.map(\.id).sorted() {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(bitPattern: Int64(id))
        }
        return "\(words.count)-\(hash)"
    }()

    // ---------------------------------------------------------
    // MARK: - Featured words (widget pool)
    // Only words marked isFeatured: true. The widget picks one
    // per day using the day-of-year as an index into this list.
    // ---------------------------------------------------------
    static let featuredWords: [VocabularyWord] = words.filter { $0.isFeatured }

    // ---------------------------------------------------------
    // MARK: - Word of the Day (widget)
    // Deterministic: same result on the app and the widget for
    // the same calendar day.
    // ---------------------------------------------------------
    static var wordOfTheDay: VocabularyWord {
        featuredWord(forDayOffset: 0)
    }

    static func featuredWord(forDayOffset offset: Int) -> VocabularyWord {
        guard !featuredWords.isEmpty else { return words[0] }
        let calendar  = Calendar.current
        let date      = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index     = (dayOfYear - 1) % featuredWords.count
        return featuredWords[index]
    }

    // ---------------------------------------------------------
    // MARK: - App deck word (swipe UI)
    // Uses the shuffled full list so the app shows a different
    // sequence than the widget's curated daily word.
    // ---------------------------------------------------------
    static func word(forDayOffset offset: Int) -> VocabularyWord {
        guard !words.isEmpty else {
            // Fallback placeholder if JSON failed to load.
            return VocabularyWord(id: 0, word: "Serendipity", partOfSpeech: "noun",
                                  definition: "A happy accident.",
                                  examples: ["Finding the café was pure serendipity."],
                                  synonyms: [], origin: nil,
                                  level: "beginner", isFeatured: true, mastered: false)
        }
        // Wrap the offset around the full word list.
        // dayOffset 0 = words[0], -1 = words[last], etc.
        let count = words.count
        let index = (((-offset) % count) + count) % count
        return words[index]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SeededRandomNumberGenerator
// Swift's built-in shuffle is non-deterministic. This gives us a reproducible
// shuffle when seeded with the same value (e.g. the current year).
// ─────────────────────────────────────────────────────────────────────────────
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9e3779b97f4a7c15
        // Warm up the generator.
        _ = next(); _ = next()
    }

    mutating func next() -> UInt64 {
        // xorshift64* — fast, good statistical properties.
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
