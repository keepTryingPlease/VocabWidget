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

class DeckScheduler: ObservableObject {

    static let batchSize = 50

    // Per-level state stored in UserDefaults.
    private struct LevelState: Codable {
        var cycleOrder:        [Int]    // word IDs in current shuffled cycle order
        var batchStart:        Int      // start index of today's batch
        var lastAdvancedDate:  String   // "yyyy-MM-dd"
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

    /// Returns today's batch of word IDs for the given level.
    /// Always call advanceIfNeeded first to ensure the state is current.
    func todaysBatch(for level: String) -> [Int] {
        guard let state = states[level],
              state.batchStart < state.cycleOrder.count else { return [] }
        let end = min(state.batchStart + Self.batchSize, state.cycleOrder.count)
        return Array(state.cycleOrder[state.batchStart..<end])
    }

    /// Advances to the next batch if the calendar date has changed since the
    /// last advance, or initialises the level if it has never been scheduled.
    /// Pass the current set of mastered IDs so new cycles exclude them.
    func advanceIfNeeded(for level: String, masteredIDs: Set<Int>) {
        let today = Self.todayString()

        if var state = states[level] {
            guard state.lastAdvancedDate != today else { return }

            let nextStart = state.batchStart + Self.batchSize
            if nextStart >= state.cycleOrder.count {
                // Reached the end of the cycle — rebuild with a fresh shuffle
                states[level] = buildCycle(for: level, masteredIDs: masteredIDs)
            } else {
                state.batchStart       = nextStart
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

    private func buildCycle(for level: String, masteredIDs: Set<Int>) -> LevelState {
        let order = VocabularyStore.words
            .filter { $0.level == level && !masteredIDs.contains($0.id) }
            .map    { $0.id }
            .shuffled()
        return LevelState(
            cycleOrder:       order,
            batchStart:       0,
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
