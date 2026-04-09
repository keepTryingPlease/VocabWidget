// UserLibrary.swift
// Tracks user word interactions — persisted to UserDefaults.

import Foundation
import Combine

class UserLibrary: ObservableObject {

    @Published private(set) var favoriteIDs:    Set<Int>
    @Published private(set) var classroomIDs:   Set<Int>
    @Published private(set) var learnedIDs:     Set<Int>
    @Published private(set) var quizCooldowns:  [Int: Date]   // wordID → retry-after date

    private enum Keys {
        static let favorites    = "favoriteWordIDs"
        static let classroom    = "classroomWordIDs"
        static let learned      = "learnedWordIDs"
        static let cooldowns    = "quizCooldowns"
        static let fingerprint  = "wordBankFingerprint"
        static let milestones   = "shownMilestoneCounts"
    }

    init() {
        #if DEBUG
        for key in [Keys.favorites, Keys.classroom, Keys.learned,
                    Keys.cooldowns, Keys.milestones, Keys.fingerprint] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        favoriteIDs   = []
        classroomIDs  = []
        learnedIDs    = []
        quizCooldowns = [:]
        UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
        return
        #endif

        let storedFingerprint = UserDefaults.standard.string(forKey: Keys.fingerprint)
        if storedFingerprint != VocabularyStore.fingerprint {
            for key in [Keys.favorites, Keys.classroom, Keys.learned,
                        Keys.cooldowns, Keys.milestones] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(VocabularyStore.fingerprint, forKey: Keys.fingerprint)
            favoriteIDs   = []
            classroomIDs  = []
            learnedIDs    = []
            quizCooldowns = [:]
            return
        }

        favoriteIDs  = Set(UserDefaults.standard.array(forKey: Keys.favorites)  as? [Int] ?? [])
        classroomIDs = Set(UserDefaults.standard.array(forKey: Keys.classroom)  as? [Int] ?? [])
        learnedIDs   = Set(UserDefaults.standard.array(forKey: Keys.learned)    as? [Int] ?? [])

        // Cooldowns stored as [String: Double] (wordID string → timestamp)
        let raw = UserDefaults.standard.dictionary(forKey: Keys.cooldowns) as? [String: Double] ?? [:]
        quizCooldowns = Dictionary(uniqueKeysWithValues:
            raw.compactMap { k, v -> (Int, Date)? in
                guard let id = Int(k) else { return nil }
                return (id, Date(timeIntervalSince1970: v))
            }
        )
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

    // ── Learned ───────────────────────────────────────────────────────────────

    func isLearned(_ word: VocabularyWord) -> Bool { learnedIDs.contains(word.id) }

    var learnedWords: [VocabularyWord] {
        VocabularyStore.words.filter { learnedIDs.contains($0.id) }.sorted { $0.word < $1.word }
    }

    func markLearned(_ word: VocabularyWord) {
        learnedIDs.insert(word.id)
        // Clear any cooldown — they passed
        quizCooldowns.removeValue(forKey: word.id)
        UserDefaults.standard.set(Array(learnedIDs), forKey: Keys.learned)
        saveCooldowns()
    }

    // ── Quiz cooldowns ────────────────────────────────────────────────────────

    /// Returns the date after which the user may retake the quiz, or nil if no lockout.
    /// Pure read — never mutates state (safe to call from view body).
    func quizCooldownExpiry(for word: VocabularyWord) -> Date? {
        guard let expiry = quizCooldowns[word.id], expiry > Date() else { return nil }
        return expiry
    }

    func canTakeQuiz(for word: VocabularyWord) -> Bool {
        quizCooldownExpiry(for: word) == nil
    }

    /// Call this when the user fails a quiz — locks them out for 24 hours.
    func setQuizCooldown(for word: VocabularyWord) {
        quizCooldowns[word.id] = Date().addingTimeInterval(24 * 3600)
        saveCooldowns()
    }

    private func saveCooldowns() {
        let saveable = Dictionary(uniqueKeysWithValues:
            quizCooldowns.map { (String($0.key), $0.value.timeIntervalSince1970) }
        )
        UserDefaults.standard.set(saveable, forKey: Keys.cooldowns)
    }
}
