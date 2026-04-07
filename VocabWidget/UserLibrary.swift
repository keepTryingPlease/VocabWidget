// UserLibrary.swift
// Tracks user word interactions — persisted to UserDefaults.
// Word data lives in words.json; this only stores word IDs.

import Foundation
import Combine

class UserLibrary: ObservableObject {

    @Published private(set) var likedIDs:        Set<Int>
    @Published private(set) var masteredIDs:     Set<Int>
    @Published private(set) var savedIDs:        Set<Int>   // swipe-right "want to learn"
    @Published private(set) var disregardedIDs:  Set<Int>   // swipe-left, never shown again
    @Published private(set) var collections:     [String: Set<Int>]

    private enum Keys {
        static let liked        = "likedWordIDs"
        static let mastered     = "masteredWordIDs"
        static let saved        = "savedWordIDs"
        static let disregarded  = "disregardedWordIDs"
        static let collections  = "wordCollections"
        static let fingerprint  = "wordBankFingerprint"
        // Keys owned by other objects — cleared here on word bank change.
        static let scheduler    = "deckSchedulerState"
        static let milestones   = "shownMilestoneCounts"
    }

    init() {
        // ── DEV: wipe all state on every launch so testing always starts fresh ─
        #if DEBUG
        for key in [Keys.liked, Keys.mastered, Keys.saved, Keys.disregarded,
                    Keys.collections, Keys.scheduler, Keys.milestones, Keys.fingerprint] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        likedIDs       = []
        masteredIDs    = []
        savedIDs       = []
        disregardedIDs = []
        collections    = [:]
        UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
        return
        #endif

        // ── Word bank change detection ────────────────────────────────────────
        let storedFingerprint = UserDefaults.standard.string(forKey: Keys.fingerprint)
        if storedFingerprint != VocabularyStore.fingerprint {
            for key in [Keys.liked, Keys.mastered, Keys.saved, Keys.disregarded,
                        Keys.collections, Keys.scheduler, Keys.milestones] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
            likedIDs       = []
            masteredIDs    = []
            savedIDs       = []
            disregardedIDs = []
            collections    = [:]
            return
        }

        // ── Normal load ───────────────────────────────────────────────────────
        let liked       = UserDefaults.standard.array(forKey: Keys.liked)       as? [Int] ?? []
        let mastered    = UserDefaults.standard.array(forKey: Keys.mastered)    as? [Int] ?? []
        let saved       = UserDefaults.standard.array(forKey: Keys.saved)       as? [Int] ?? []
        let disregarded = UserDefaults.standard.array(forKey: Keys.disregarded) as? [Int] ?? []
        likedIDs       = Set(liked)
        masteredIDs    = Set(mastered)
        savedIDs       = Set(saved)
        disregardedIDs = Set(disregarded)

        let raw = UserDefaults.standard.dictionary(forKey: Keys.collections) as? [String: [Int]] ?? [:]
        collections = raw.mapValues { Set($0) }
    }

    // ── Liked ─────────────────────────────────────────────────────────────────

    func isLiked(_ word: VocabularyWord)    -> Bool { likedIDs.contains(word.id) }

    var likedWords: [VocabularyWord] {
        VocabularyStore.words.filter { likedIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleLike(_ word: VocabularyWord) {
        if likedIDs.contains(word.id) { likedIDs.remove(word.id) }
        else                          { likedIDs.insert(word.id) }
        UserDefaults.standard.set(Array(likedIDs), forKey: Keys.liked)
    }

    // ── Mastered ──────────────────────────────────────────────────────────────

    func isMastered(_ word: VocabularyWord) -> Bool { masteredIDs.contains(word.id) }

    var masteredWords: [VocabularyWord] {
        VocabularyStore.words.filter { masteredIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleMastered(_ word: VocabularyWord) {
        if masteredIDs.contains(word.id) { masteredIDs.remove(word.id) }
        else                             { masteredIDs.insert(word.id) }
        UserDefaults.standard.set(Array(masteredIDs), forKey: Keys.mastered)
    }

    // ── Saved (swipe right — "want to learn") ────────────────────────────────

    func isSaved(_ word: VocabularyWord) -> Bool { savedIDs.contains(word.id) }

    var savedWords: [VocabularyWord] {
        VocabularyStore.words.filter { savedIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleSaved(_ word: VocabularyWord) {
        if savedIDs.contains(word.id) { savedIDs.remove(word.id) }
        else                          { savedIDs.insert(word.id) }
        UserDefaults.standard.set(Array(savedIDs), forKey: Keys.saved)
    }

    // ── Disregarded (swipe left — hidden forever) ─────────────────────────────

    func isDisregarded(_ word: VocabularyWord) -> Bool { disregardedIDs.contains(word.id) }

    func disregard(_ word: VocabularyWord) {
        disregardedIDs.insert(word.id)
        UserDefaults.standard.set(Array(disregardedIDs), forKey: Keys.disregarded)
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

    // ── Export helpers ────────────────────────────────────────────────────────

    /// Plain-text word list — one word per line, for pasting into words_to_add.txt.
    var savedExportText: String {
        savedWords.map(\.word).joined(separator: "\n")
    }
}
