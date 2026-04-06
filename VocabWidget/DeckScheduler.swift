// DeckScheduler.swift
//
// The deck is a flat array of DeckCards — each card is a (word, UUID) pair.
// The UUID gives SwiftUI a stable, unique identity even when the same word
// appears in multiple passes of the deck, which is how looping works.
//
// Loop / infinite scroll
// ──────────────────────
// When the user gets within 8 cards of the end, appendPass() adds a fresh
// zone-sorted pass of ALL currently unmastered words. The deck grows
// seamlessly — the user never hits a wall.
//
// Real-time difficulty adaptation
// ────────────────────────────────
// After the user masters a word, rebuildAhead() replaces every card AFTER
// the current position with a freshly zone-sorted pass using the updated
// skill level. Cards already seen (before current) are left alone.
// The net effect: the very next card after a mastery is already calibrated
// to the new difficulty target.
//
// Zone split relative to userSkill (mean Zipf of mastered words):
//
//   easy    Zipf > skill + 0.3            ~15%   confidence / quick wins
//   target  skill − 1.0 … skill + 0.3    ~65%   active learning edge
//   stretch Zipf < skill − 1.0            ~20%   challenging exposure

import Foundation
import Combine

// ── DeckCard ──────────────────────────────────────────────────────────────────

struct DeckCard: Identifiable {
    let id:     UUID            // unique per slot — stable once created
    let wordID: Int             // references VocabularyWord.id
}

// ── DeckScheduler ─────────────────────────────────────────────────────────────

class DeckScheduler: ObservableObject {

    @Published private(set) var deck: [DeckCard] = []

    // ── Public API ────────────────────────────────────────────────────────────

    /// Builds the initial deck on cold start.
    func buildInitialDeck(masteredIDs: Set<Int>, userSkill: Double) {
        deck = makePass(masteredIDs: masteredIDs, userSkill: userSkill)
    }

    /// Appends another full pass when the user is within 8 cards of the end.
    /// The new pass uses the current skill level, so accumulated masteries
    /// are reflected the next time the user cycles through.
    func appendPassIfNeeded(currentIndex: Int, masteredIDs: Set<Int>, userSkill: Double) {
        guard deck.count - currentIndex <= 8 else { return }
        deck.append(contentsOf: makePass(masteredIDs: masteredIDs, userSkill: userSkill))
    }

    /// Replaces everything after `cardID` in the deck with a fresh zone-sorted
    /// pass. Called immediately after each mastery so the next card is already
    /// calibrated to the updated skill level.
    /// Returns the ID of the new first card ahead (nil if no unmastered words left).
    @discardableResult
    func rebuildAhead(after cardID: UUID, masteredIDs: Set<Int>, userSkill: Double) -> UUID? {
        guard let idx = deck.firstIndex(where: { $0.id == cardID }) else { return nil }
        let kept  = Array(deck.prefix(through: idx))
        let fresh = makePass(masteredIDs: masteredIDs, userSkill: userSkill)
        deck = kept + fresh
        return fresh.first?.id
    }

    // ── Zone-sorted pass builder ──────────────────────────────────────────────

    private func makePass(masteredIDs: Set<Int>, userSkill: Double) -> [DeckCard] {
        let unmastered = VocabularyStore.words.filter { !masteredIDs.contains($0.id) }

        let easy    = unmastered.filter { $0.frequency >  userSkill + 0.3 }
                                .map(\.id).shuffled()
        let target  = unmastered.filter { $0.frequency >= userSkill - 1.0
                                       && $0.frequency <= userSkill + 0.3 }
                                .map(\.id).shuffled()
        let stretch = unmastered.filter { $0.frequency <  userSkill - 1.0 }
                                .map(\.id).shuffled()

        return interleave(easy: easy, target: target, stretch: stretch)
            .map { DeckCard(id: UUID(), wordID: $0) }
    }

    /// Interleaves three arrays in 3 : 13 : 4 blocks (≈ 15 / 65 / 20 %).
    private func interleave(easy: [Int], target: [Int], stretch: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(easy.count + target.count + stretch.count)
        var e = easy[...], t = target[...], s = stretch[...]
        while !e.isEmpty || !t.isEmpty || !s.isEmpty {
            let es = e.prefix(3);  e = e.dropFirst(es.count)
            let ts = t.prefix(13); t = t.dropFirst(ts.count)
            let ss = s.prefix(4);  s = s.dropFirst(ss.count)
            result.append(contentsOf: es)
            result.append(contentsOf: ts)
            result.append(contentsOf: ss)
        }
        return result
    }
}
