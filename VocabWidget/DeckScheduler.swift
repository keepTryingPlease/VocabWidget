// DeckScheduler.swift
//
// Builds a flat array of DeckCards from the curated word list.
// Only words with quiz content are shown (testing mode).
// Remove the quiz filter in makePass to restore the full deck.

import Foundation
import Combine

struct DeckCard: Identifiable {
    let id:     UUID
    let wordID: Int
}

class DeckScheduler: ObservableObject {

    @Published private(set) var deck: [DeckCard] = []

    func buildInitialDeck() {
        deck = makePass()
    }

    func appendPassIfNeeded(currentIndex: Int) {
        guard deck.count - currentIndex <= 8 else { return }
        deck.append(contentsOf: makePass())
    }

    private func makePass() -> [DeckCard] {
        VocabularyStore.words
            .filter { $0.quiz != nil && !($0.quiz?.isEmpty ?? true) }  // TESTING: quiz words only
            .map(\.id)
            .shuffled()
            .map { DeckCard(id: UUID(), wordID: $0) }
    }
}
