// DeckScheduler.swift
// Controls which 50 words appear in the swipe deck each day.
//
// How it works:
//   • All unmastered words for a level are shuffled into a "cycle order"
//     when the scheduler is first initialised for that level.
//   • Each day, the scheduler advances to the next batch of 50 words
//     in that order.
//   • When the end of the order is reached, a new cycle begins: all
//     currently-unmastered words are reshuffled so the user never sees
//     the same sequence twice.
//   • Mastered words are excluded at display time (via filteredWords in
//     ContentView), but a new cycle also excludes them from the order
//     so they don't reappear when the deck wraps.
//
// State is persisted to UserDefaults and survives app restarts.

import Foundation
import Combine

class DeckScheduler: ObservableObject {

    static let batchSize = 50

    // Per-level state stored in UserDefaults.
    private struct LevelState: Codable {
        var cycleOrder:        [Int]    // word IDs in current shuffled cycle order
        var batchStart:        Int      // start index of today's batch
        var extraWords:        Int      // extra words unlocked beyond today's initial 50
        var lastAdvancedDate:  String   // "yyyy-MM-dd"

        // Backward-compatible decode: extraWords may be absent in existing saved state.
        init(from decoder: Decoder) throws {
            let c            = try decoder.container(keyedBy: CodingKeys.self)
            cycleOrder       = try c.decode([Int].self,    forKey: .cycleOrder)
            batchStart       = try c.decode(Int.self,      forKey: .batchStart)
            extraWords       = (try? c.decode(Int.self,    forKey: .extraWords)) ?? 0
            lastAdvancedDate = try c.decode(String.self,   forKey: .lastAdvancedDate)
        }

        init(cycleOrder: [Int], batchStart: Int, extraWords: Int, lastAdvancedDate: String) {
            self.cycleOrder       = cycleOrder
            self.batchStart       = batchStart
            self.extraWords       = extraWords
            self.lastAdvancedDate = lastAdvancedDate
        }
    }

    @Published private var states: [String: LevelState]

    private let storageKey = "deckSchedulerState"

    init() {
        if let data    = UserDefaults.standard.data(forKey: "deckSchedulerState"),
           let decoded = try? JSONDecoder().decode([String: LevelState].self, from: data) {
            states = decoded
        } else {
            states = [:]
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Returns today's batch of word IDs for the given level (initial 50 + any live extensions).
    /// Always call advanceIfNeeded first to ensure the state is current.
    func todaysBatch(for level: String) -> [Int] {
        guard let state = states[level],
              state.batchStart < state.cycleOrder.count else { return [] }
        let end = min(state.batchStart + Self.batchSize + state.extraWords, state.cycleOrder.count)
        return Array(state.cycleOrder[state.batchStart..<end])
    }

    /// Appends the next 50 unmastered words to today's visible batch so the
    /// user can keep scrolling without hitting an empty state.
    /// Safe to call multiple times — each call unlocks one more batch of 50.
    func extendBatch(for level: String, masteredIDs: Set<Int>) {
        guard var state = states[level] else { return }
        let currentEnd = state.batchStart + Self.batchSize + state.extraWords
        if currentEnd >= state.cycleOrder.count {
            // Reached the end of the full cycle — start a fresh cycle.
            state.cycleOrder     = buildCycleOrder(for: level, masteredIDs: masteredIDs)
            state.batchStart     = 0
            state.extraWords     = 0
            // Keep lastAdvancedDate so a date change still triggers the normal advance tomorrow.
        } else {
            state.extraWords += Self.batchSize
        }
        states[level] = state
        save()
    }

    /// Advances to the next batch if the calendar date has changed since the
    /// last advance, or initialises the level if it has never been scheduled.
    /// Pass the current set of mastered IDs so new cycles exclude them.
    func advanceIfNeeded(for level: String, masteredIDs: Set<Int>) {
        let today = Self.todayString()

        if var state = states[level] {
            guard state.lastAdvancedDate != today else { return }

            let nextStart = state.batchStart + Self.batchSize + state.extraWords
            if nextStart >= state.cycleOrder.count {
                // Reached the end of the cycle — rebuild with a fresh shuffle
                states[level] = buildCycle(for: level, masteredIDs: masteredIDs)
            } else {
                state.batchStart       = nextStart
                state.extraWords       = 0          // reset extensions at the daily boundary
                state.lastAdvancedDate = today
                states[level]          = state
            }
        } else {
            // First time this level has been scheduled
            states[level] = buildCycle(for: level, masteredIDs: masteredIDs)
        }

        save()
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private func buildCycleOrder(for level: String, masteredIDs: Set<Int>) -> [Int] {
        VocabularyStore.words
            .filter { $0.level == level && !masteredIDs.contains($0.id) }
            .map    { $0.id }
            .shuffled()
    }

    private func buildCycle(for level: String, masteredIDs: Set<Int>) -> LevelState {
        LevelState(
            cycleOrder:       buildCycleOrder(for: level, masteredIDs: masteredIDs),
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
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
