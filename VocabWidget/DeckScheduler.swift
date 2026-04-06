// DeckScheduler.swift
// Controls which 50 words appear in the swipe deck each day.
//
// Adaptive difficulty
// ───────────────────
// Every time a fresh cycle is built (first launch, new day, or full-cycle
// wrap), unmastered words are split into three zones relative to the user's
// current skill estimate (mean Zipf of mastered words):
//
//   easy    Zipf > skill + 0.3   — confident recognition, quick wins
//   target  skill − 1.0 … skill + 0.3   — the learning edge
//   stretch Zipf < skill − 1.0   — challenging exposure
//
// The cycle is assembled by interleaving zones in a 3 : 13 : 4 block ratio
// (≈ 15 % easy / 65 % target / 20 % stretch), so every 50-word daily batch
// is naturally calibrated to the user's level without any manual tuning.
//
// As the user masters words their skill estimate drifts toward harder
// vocabulary, pulling the window down into lower Zipf territory
// automatically on the next cycle rebuild.
//
// State is persisted to UserDefaults and survives app restarts.

import Foundation
import Combine

class DeckScheduler: ObservableObject {

    static let batchSize = 50

    private struct DeckState: Codable {
        var cycleOrder:       [Int]   // word IDs in current cycle order
        var batchStart:       Int     // start index of today's batch
        var extraWords:       Int     // words unlocked beyond today's initial 50
        var lastAdvancedDate: String  // "yyyy-MM-dd"

        init(from decoder: Decoder) throws {
            let c            = try decoder.container(keyedBy: CodingKeys.self)
            cycleOrder       = try c.decode([Int].self,  forKey: .cycleOrder)
            batchStart       = try c.decode(Int.self,    forKey: .batchStart)
            extraWords       = (try? c.decode(Int.self,  forKey: .extraWords)) ?? 0
            lastAdvancedDate = try c.decode(String.self, forKey: .lastAdvancedDate)
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

    func todaysBatch() -> [Int] {
        guard let s = state, s.batchStart < s.cycleOrder.count else { return [] }
        let end = min(s.batchStart + Self.batchSize + s.extraWords, s.cycleOrder.count)
        return Array(s.cycleOrder[s.batchStart..<end])
    }

    func advanceIfNeeded(masteredIDs: Set<Int>, userSkill: Double) {
        let today = Self.todayString()
        if var s = state {
            guard s.lastAdvancedDate != today else { return }
            let nextStart = s.batchStart + Self.batchSize + s.extraWords
            if nextStart >= s.cycleOrder.count {
                state = buildFreshCycle(masteredIDs: masteredIDs, userSkill: userSkill)
            } else {
                s.batchStart       = nextStart
                s.extraWords       = 0
                s.lastAdvancedDate = today
                state              = s
            }
        } else {
            state = buildFreshCycle(masteredIDs: masteredIDs, userSkill: userSkill)
        }
        save()
    }

    func extendBatch(masteredIDs: Set<Int>, userSkill: Double) {
        guard var s = state else { return }
        let currentEnd = s.batchStart + Self.batchSize + s.extraWords
        if currentEnd >= s.cycleOrder.count {
            state = buildFreshCycle(masteredIDs: masteredIDs, userSkill: userSkill)
        } else {
            s.extraWords += Self.batchSize
            state         = s
        }
        save()
    }

    // ── Adaptive cycle builder ────────────────────────────────────────────────

    private func buildFreshCycle(masteredIDs: Set<Int>, userSkill: Double) -> DeckState {
        let unmastered = VocabularyStore.words.filter { !masteredIDs.contains($0.id) }

        // Split into zones relative to the user's current skill level.
        let easy    = unmastered.filter { $0.frequency >  userSkill + 0.3 }.map(\.id).shuffled()
        let target  = unmastered.filter { $0.frequency >= userSkill - 1.0
                                       && $0.frequency <= userSkill + 0.3 }.map(\.id).shuffled()
        let stretch = unmastered.filter { $0.frequency <  userSkill - 1.0 }.map(\.id).shuffled()

        return DeckState(
            cycleOrder:       interleave(easy: easy, target: target, stretch: stretch),
            batchStart:       0,
            extraWords:       0,
            lastAdvancedDate: Self.todayString()
        )
    }

    /// Interleaves three zone arrays in repeating 3 : 13 : 4 blocks
    /// (≈ 15 % easy / 65 % target / 20 % stretch per batch of 50).
    /// Zones that run out early are simply skipped; the remaining zones
    /// fill the rest of the cycle.
    private func interleave(easy: [Int], target: [Int], stretch: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(easy.count + target.count + stretch.count)

        var e = easy[...], t = target[...], s = stretch[...]

        while !e.isEmpty || !t.isEmpty || !s.isEmpty {
            let eSlice = e.prefix(3);  e = e.dropFirst(eSlice.count)
            let tSlice = t.prefix(13); t = t.dropFirst(tSlice.count)
            let sSlice = s.prefix(4);  s = s.dropFirst(sSlice.count)
            result.append(contentsOf: eSlice)
            result.append(contentsOf: tSlice)
            result.append(contentsOf: sSlice)
        }

        return result
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

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
