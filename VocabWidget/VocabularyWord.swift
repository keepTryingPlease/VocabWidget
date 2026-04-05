// VocabularyWord.swift
// Shared between the main app target AND the widget extension target.
// In Xcode: select this file → in the File Inspector (right panel) → check BOTH
// your main app target and your widget extension under "Target Membership".

import Foundation

struct VocabularyWord: Identifiable, Codable {
    let id: Int
    let word: String
    let partOfSpeech: String   // e.g. "noun", "adjective", "verb"
    let definition: String
    let examples: [String]     // up to 2 example sentences
    let synonyms: [String]     // up to 12 synonyms, merged from WordsAPI + Free Dictionary
    let origin: String?        // etymology, or nil if unavailable
    let level: String          // "beginner", "intermediate", "advanced"
    let isFeatured: Bool       // true = eligible for lock screen word of the day
    let mastered: Bool         // true = hidden from the active deck
}
