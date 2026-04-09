// UserLibrary.swift
// Tracks user word interactions — persisted to UserDefaults.

import Foundation
import Combine

class UserLibrary: ObservableObject {

    @Published private(set) var favoriteIDs:  Set<Int>
    @Published private(set) var classroomIDs: Set<Int>

    private enum Keys {
        static let favorites    = "favoriteWordIDs"
        static let classroom    = "classroomWordIDs"
        static let fingerprint  = "wordBankFingerprint"
        static let scheduler    = "deckSchedulerState"
        static let milestones   = "shownMilestoneCounts"
    }

    init() {
        #if DEBUG
        for key in [Keys.favorites, Keys.classroom, Keys.scheduler,
                    Keys.milestones, Keys.fingerprint] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        favoriteIDs  = []
        classroomIDs = []
        UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
        return
        #endif

        let storedFingerprint = UserDefaults.standard.string(forKey: Keys.fingerprint)
        if storedFingerprint != VocabularyStore.fingerprint {
            for key in [Keys.favorites, Keys.classroom, Keys.scheduler, Keys.milestones] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
            favoriteIDs  = []
            classroomIDs = []
            return
        }

        let favs  = UserDefaults.standard.array(forKey: Keys.favorites)  as? [Int] ?? []
        let class_ = UserDefaults.standard.array(forKey: Keys.classroom) as? [Int] ?? []
        favoriteIDs  = Set(favs)
        classroomIDs = Set(class_)
    }

    // ── Favorites ─────────────────────────────────────────────────────────────

    func isFavorite(_ word: VocabularyWord) -> Bool { favoriteIDs.contains(word.id) }

    var favoriteWords: [VocabularyWord] {
        VocabularyStore.words.filter { favoriteIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleFavorite(_ word: VocabularyWord) {
        if favoriteIDs.contains(word.id) { favoriteIDs.remove(word.id) }
        else                             { favoriteIDs.insert(word.id) }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Keys.favorites)
    }

    // ── Classroom ─────────────────────────────────────────────────────────────

    func isInClassroom(_ word: VocabularyWord) -> Bool { classroomIDs.contains(word.id) }

    var classroomWords: [VocabularyWord] {
        VocabularyStore.words.filter { classroomIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func toggleClassroom(_ word: VocabularyWord) {
        if classroomIDs.contains(word.id) { classroomIDs.remove(word.id) }
        else                              { classroomIDs.insert(word.id) }
        UserDefaults.standard.set(Array(classroomIDs), forKey: Keys.classroom)
    }
}
