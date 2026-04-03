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
    let example: String
}
