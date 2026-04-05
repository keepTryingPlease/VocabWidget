// MilestoneManager.swift
// Defines every mastery milestone and tracks which ones have already
// been shown. Milestones fire based on total words mastered globally
// (across all levels). Each milestone only ever fires once.

import Foundation

// ── Milestone model ───────────────────────────────────────────────────────────

struct Milestone: Identifiable {
    let count:   Int
    let icon:    String    // SF Symbol name
    let title:   String
    let message: String
    let isBig:   Bool      // true → celebration sheet; false → brief toast

    var id: Int { count }
}

// ── Milestone ladder ──────────────────────────────────────────────────────────

extension Milestone {
    static let all: [Milestone] = [
        Milestone(
            count: 1,    icon: "checkmark.circle",
            title: "First Word Mastered",
            message: "The journey begins. One down, everything else ahead.",
            isBig: false
        ),
        Milestone(
            count: 5,    icon: "star",
            title: "5 Words!",
            message: "Your brain is warming up.",
            isBig: false
        ),
        Milestone(
            count: 10,   icon: "bolt.fill",
            title: "10 Words Mastered!",
            message: "Keep it up!",
            isBig: false
        ),
        Milestone(
            count: 25,   icon: "flame.fill",
            title: "25 Words!",
            message: "You're getting somewhere.",
            isBig: false
        ),
        Milestone(
            count: 50,   icon: "eyeglasses",
            title: "50 Words Mastered!",
            message: "You're on your way to becoming a smartie pants.",
            isBig: true
        ),
        Milestone(
            count: 100,  icon: "trophy.fill",
            title: "Triple Digits!",
            message: "100 words. You're the real deal.",
            isBig: true
        ),
        Milestone(
            count: 200,  icon: "books.vertical.fill",
            title: "200 Words!",
            message: "Walking dictionary energy.",
            isBig: true
        ),
        Milestone(
            count: 300,  icon: "text.book.closed.fill",
            title: "300 Words!",
            message: "People are starting to notice.",
            isBig: true
        ),
        Milestone(
            count: 500,  icon: "graduationcap.fill",
            title: "500 Words Mastered!",
            message: "Half a thousand words. You're genuinely impressive.",
            isBig: true
        ),
        Milestone(
            count: 1000, icon: "crown.fill",
            title: "One Thousand Words!",
            message: "You're in rarefied air now. Four digits of mastery.",
            isBig: true
        ),
        Milestone(
            count: 1500, icon: "sparkles",
            title: "1,500 Words!",
            message: "Unstoppable. Absolutely unstoppable.",
            isBig: true
        ),
        Milestone(
            count: 2000, icon: "star.circle.fill",
            title: "2,000 Words Mastered!",
            message: "Genius status. Officially.",
            isBig: true
        ),
    ]
}

// ── Manager ───────────────────────────────────────────────────────────────────

class MilestoneManager: ObservableObject {

    private var shownCounts: Set<Int>
    private let storageKey = "shownMilestoneCounts"

    init() {
        let saved = UserDefaults.standard.array(forKey: "shownMilestoneCounts") as? [Int] ?? []
        shownCounts = Set(saved)
    }

    /// Returns a Milestone if the new global mastered count just crossed one
    /// that hasn't been shown before. Returns nil otherwise.
    func milestone(forNewCount count: Int) -> Milestone? {
        guard let hit = Milestone.all.first(where: { $0.count == count }),
              !shownCounts.contains(count) else { return nil }
        shownCounts.insert(count)
        UserDefaults.standard.set(Array(shownCounts), forKey: storageKey)
        return hit
    }
}
