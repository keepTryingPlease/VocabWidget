// VocabularyWord.swift
// Shared between the main app target AND the widget extension target.
// In Xcode: select this file → in the File Inspector (right panel) → check BOTH
// your main app target and your widget extension under "Target Membership".

import Foundation

// ── Quiz ─────────────────────────────────────────────────────────────────────

struct QuizQuestion: Identifiable, Codable {
    let id: Int            // 0-based index within the word's quiz array
    let title: String      // e.g. "Meaning Match", "Fill in the Blank"
    let prompt: String     // The question text or word displayed above options
    let options: [String]  // Always 3 options
    let answerIndex: Int   // 0-based index of the correct answer
}

// ── Word ─────────────────────────────────────────────────────────────────────

struct VocabularyWord: Identifiable, Codable {
    let id: Int
    let word: String
    let partOfSpeech: String   // e.g. "noun", "adjective", "verb"
    let definition: String
    let examples: [String]     // up to 2 example sentences
    let synonyms: [String]     // up to 12 synonyms, merged from WordsAPI + Free Dictionary
    let origin: String?        // etymology, or nil if unavailable
    let frequency: Double      // Zipf score (1–7). Higher = more common/easier.
                               // Typical vocab range: 2.0–5.0.
    let isFeatured: Bool       // true = eligible for lock screen word of the day
    let mastered: Bool         // true = hidden from the active deck
    let keyIdea: String?       // one-line conceptual hook, e.g. "A hidden flaw that undermines everything"
    let nuance: String?        // usage note distinguishing this word from near-synonyms
    let typicalUsage: String?  // contexts and collocations where the word naturally appears
    let quiz: [QuizQuestion]?  // nil for most words; populated for hand-curated words
}
