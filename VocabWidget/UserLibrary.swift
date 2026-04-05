// UserLibrary.swift
// Tracks liked words, mastered words, and custom collections.
// Persisted to UserDefaults — the word data stays in words.json,
// this only stores word IDs.

import Foundation
import Combine

class UserLibrary: ObservableObject {

    @Published private(set) var likedIDs:      Set<Int>
    @Published private(set) var masteredIDs:   Set<Int>
    @Published private(set) var collections:   [String: Set<Int>]   // name → word IDs

    private enum Keys {
        static let liked        = "likedWordIDs"
        static let mastered     = "masteredWordIDs"
        static let collections  = "wordCollections"
        static let fingerprint  = "wordBankFingerprint"
        // Keys owned by other objects — cleared here on word bank change.
        static let scheduler    = "deckSchedulerState"
        static let milestones   = "shownMilestoneCounts"
    }

    init() {
        // ── Word bank change detection ────────────────────────────────────────
        // If the fingerprint doesn't match the current words.json, wipe all
        // persisted user data so stale IDs don't silently corrupt state.
        let storedFingerprint = UserDefaults.standard.string(forKey: Keys.fingerprint)
        if storedFingerprint != VocabularyStore.fingerprint {
            for key in [Keys.liked, Keys.mastered, Keys.collections,
                        Keys.scheduler, Keys.milestones] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
            likedIDs    = []
            masteredIDs = []
            collections = [:]
            return
        }

        // ── Normal load ───────────────────────────────────────────────────────
        let liked    = UserDefaults.standard.array(forKey: Keys.liked)    as? [Int] ?? []
        let mastered = UserDefaults.standard.array(forKey: Keys.mastered) as? [Int] ?? []
        likedIDs    = Set(liked)
        masteredIDs = Set(mastered)

        let saved = UserDefaults.standard.dictionary(forKey: Keys.collections) as? [String: [Int]] ?? [:]
        collections = saved.mapValues { Set($0) }
    }

    // ── Liked / Mastered ──────────────────────────────────────────────────────

    func isLiked(_ word: VocabularyWord)    -> Bool { likedIDs.contains(word.id)    }
    func isMastered(_ word: VocabularyWord) -> Bool { masteredIDs.contains(word.id) }

    var likedWords: [VocabularyWord] {
        VocabularyStore.words.filter { likedIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    var masteredWords: [VocabularyWord] {
        VocabularyStore.words.filter { masteredIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleLike(_ word: VocabularyWord) {
        if likedIDs.contains(word.id) { likedIDs.remove(word.id) }
        else                          { likedIDs.insert(word.id) }
        UserDefaults.standard.set(Array(likedIDs), forKey: Keys.liked)
    }

    func toggleMastered(_ word: VocabularyWord) {
        if masteredIDs.contains(word.id) { masteredIDs.remove(word.id) }
        else                             { masteredIDs.insert(word.id) }
        UserDefaults.standard.set(Array(masteredIDs), forKey: Keys.mastered)
    }

    // ── Collections ───────────────────────────────────────────────────────────

    var collectionNames: [String] { collections.keys.sorted() }

    func wordIsIn(_ word: VocabularyWord, collection name: String) -> Bool {
        collections[name]?.contains(word.id) ?? false
    }

    func words(inCollection name: String) -> [VocabularyWord] {
        guard let ids = collections[name] else { return [] }
        return VocabularyStore.words.filter { ids.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func createCollection(_ name: String) {
        guard !name.isEmpty, collections[name] == nil else { return }
        collections[name] = []
        saveCollections()
    }

    func deleteCollection(_ name: String) {
        collections.removeValue(forKey: name)
        saveCollections()
    }

    func toggleWord(_ word: VocabularyWord, inCollection name: String) {
        if collections[name]?.contains(word.id) == true {
            collections[name]?.remove(word.id)
        } else {
            collections[name, default: []].insert(word.id)
        }
        saveCollections()
    }

    private func saveCollections() {
        let saveable = collections.mapValues { Array($0) }
        UserDefaults.standard.set(saveable, forKey: Keys.collections)
    }
}
