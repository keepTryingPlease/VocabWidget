// DeckScheduler.swift
// Maintains the zone-sorted order of unmastered words for the swipe deck.
//
// Every call to rebuild() recomputes the word order from scratch based on
// the user's current skill level, so the deck adapts in real-time — the
// card immediately following the one just mastered already reflects the
// updated difficulty target.
//
// Zone split (relative to userSkill, the mean Zipf of mastered words):
//
//   easy    Zipf > skill + 0.3            ~15% of deck  confidence / quick wins
//   target  skill − 1.0  …  skill + 0.3  ~65% of deck  active learning edge
//   stretch Zipf < skill − 1.0            ~20% of deck  challenging exposure
//
// Zones are interleaved in 3 : 13 : 4 blocks so the proportions hold
// across any window of cards, not just the full deck.

import Foundation
import Combine

class DeckScheduler: ObservableObject {

    /// The current ordered list of word IDs. ContentView filters this against
    /// masteredIDs to produce filteredWords. @Published so SwiftUI re-renders
    /// automatically when rebuild() is called.
    @Published private(set) var cycleOrder: [Int] = []

    // ── Public API ────────────────────────────────────────────────────────────

    /// Recomputes the full deck order using zone-based interleaving.
    /// Call on first launch and after every mastery event.
    func rebuild(masteredIDs: Set<Int>, userSkill: Double) {
        let unmastered = VocabularyStore.words.filter { !masteredIDs.contains($0.id) }

        let easy    = unmastered.filter { $0.frequency >  userSkill + 0.3 }
                                .map(\.id).shuffled()
        let target  = unmastered.filter { $0.frequency >= userSkill - 1.0
                                       && $0.frequency <= userSkill + 0.3 }
                                .map(\.id).shuffled()
        let stretch = unmastered.filter { $0.frequency <  userSkill - 1.0 }
                                .map(\.id).shuffled()

        cycleOrder = interleave(easy: easy, target: target, stretch: stretch)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /// Interleaves three shuffled zone arrays in repeating 3 : 13 : 4 blocks.
    /// Zones that run out early are simply skipped; remaining zones continue.
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
}
