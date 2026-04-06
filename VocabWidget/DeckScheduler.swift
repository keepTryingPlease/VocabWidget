// DeckScheduler.swift
// Controls which 50 words appear in the swipe deck each day.
//
// Single-deck design — no levels. All unmastered words are shuffled into one
// cycle order. Each day the next 50 advance into view. When the user reaches
// the last few cards, extendBatch silently loads 50 more so scrolling never
// hits a wall. A new calendar day resets to a fresh 50.
//
// State is persisted to UserDefaults and survives app restarts.

import Foundation
import Combine

class DeckScheduler: ObservableObject {

    static let batchSize = 50

    private struct DeckState: Codable {
        var cycleOrder:       [Int]   // word IDs in current shuffled cycle order
        var batchStart:       Int     // start index of today's batch
        var extraWords:       Int     // words added beyond today's initial 50
        var lastAdvancedDate: String  // "yyyy-MM-dd"

        // Backward-compatible: extraWords may be absent in older saved data.
        init(from decoder: Decoder) throws {
            let c            = try decoder.container(keyedBy: CodingKeys.self)
            cycleOrder       = try c.decode([Int].self,   forKey: .cycleOrder)
            batchStart       = try c.decode(Int.self,     forKey: .batchStart)
            extraWords       = (try? c.decode(Int.self,   forKey: .extraWords)) ?? 0
            lastAdvancedDate = try c.decode(String.self,  forKey: .lastAdvancedDate)
        }

        init(cycleOrder: [Int], batchStart: Int, extraWords: Int, lastAdvancedDate: String) {
            self.cycleOrder       = cycleOrder
            self.batchStart       = batchStart
            self.extraWords       = extraWords
            self.lastAdvancedDate = lastAdvancedDate
        }
    }

    @Published private var state: DeckState?

    private let storageKey = "deckSchedulerState_v2"

    init() {
        if let data    = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DeckState.self, from: data) {
            state = decoded
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Returns today's batch of word IDs (initial 50 + any live extensions).
    /// Call advanceIfNeeded first to ensure the state is current.
    func todaysBatch() -> [Int] {
        guard let s = state, s.batchStart < s.cycleOrder.count else { return [] }
        let end = min(s.batchStart + Self.batchSize + s.extraWords, s.cycleOrder.count)
        return Array(s.cycleOrder[s.batchStart..<end])
    }

    /// Advances to the next batch if the date has changed, or initialises on
    /// first launch. Pass current mastered IDs so new cycles exclude them.
    func advanceIfNeeded(masteredIDs: Set<Int>) {
        let today = Self.todayString()

        if var s = state {
            guard s.lastAdvancedDate != today else { return }
            let nextStart = s.batchStart + Self.batchSize + s.extraWords
            if nextStart >= s.cycleOrder.count {
                state = buildFreshCycle(masteredIDs: masteredIDs)
            } else {
                s.batchStart       = nextStart
                s.extraWords       = 0
                s.lastAdvancedDate = today
                state              = s
            }
        } else {
            state = buildFreshCycle(masteredIDs: masteredIDs)
        }
        save()
    }

    /// Appends the next 50 unmastered words to today's visible batch.
    /// Called automatically when the user is within 3 cards of the end.
    func extendBatch(masteredIDs: Set<Int>) {
        guard var s = state else { return }
        let currentEnd = s.batchStart + Self.batchSize + s.extraWords
        if currentEnd >= s.cycleOrder.count {
            state = buildFreshCycle(masteredIDs: masteredIDs)
        } else {
            s.extraWords += Self.batchSize
            state         = s
        }
        save()
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private func buildFreshCycle(masteredIDs: Set<Int>) -> DeckState {
        let order = VocabularyStore.words
            .filter { !masteredIDs.contains($0.id) }
            .map    { $0.id }
            .shuffled()
        return DeckState(
            cycleOrder:       order,
            batchStart:       0,
            extraWords:       0,
            lastAdvancedDate: Self.todayString()
        )
    }

    private static func todayString() -> String {
        let f        = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
