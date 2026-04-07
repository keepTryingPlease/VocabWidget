// DeckScheduler.swift
//
// The deck is a flat array of DeckCards — each card is a (word, UUID) pair.
// The UUID gives SwiftUI a stable, unique identity even when the same word
// appears in multiple passes of the deck, which is how looping works.
//
// Loop / infinite scroll
// ──────────────────────
// When the user gets within 8 cards of the end, appendPassIfNeeded() adds a
// fresh shuffled pass of all eligible words. The deck grows seamlessly.
//
// Eligibility filter
// ──────────────────
// A word is eligible if it is not mastered, not disregarded, and has a
// Zipf frequency ≤ 4.2 (too-common words are excluded).
// Words are presented in random order — no zone sorting.

import Foundation
import Combine

// ── DeckCard ──────────────────────────────────────────────────────────────────

struct DeckCard: Identifiable {
    let id:     UUID    // unique per slot — stable once created
    let wordID: Int     // references VocabularyWord.id
}

// ── DeckScheduler ─────────────────────────────────────────────────────────────

class DeckScheduler: ObservableObject {

    @Published private(set) var deck: [DeckCard] = []

    // ── Public API ────────────────────────────────────────────────────────────

    func buildInitialDeck(masteredIDs: Set<Int>, disregardedIDs: Set<Int>) {
        deck = makePass(masteredIDs: masteredIDs, disregardedIDs: disregardedIDs)
    }

    func appendPassIfNeeded(currentIndex: Int, masteredIDs: Set<Int>, disregardedIDs: Set<Int>) {
        guard deck.count - currentIndex <= 8 else { return }
        deck.append(contentsOf: makePass(masteredIDs: masteredIDs, disregardedIDs: disregardedIDs))
    }

    // ── Pass builder ──────────────────────────────────────────────────────────

    private let maxZipf: Double = 4.2

    private func makePass(masteredIDs: Set<Int>, disregardedIDs: Set<Int>) -> [DeckCard] {
        let excluded = masteredIDs.union(disregardedIDs)
        return VocabularyStore.words
            .filter { !excluded.contains($0.id) && $0.frequency <= maxZipf }
            .map(\.id)
            .shuffled()
            .map { DeckCard(id: UUID(), wordID: $0) }
    }
}
