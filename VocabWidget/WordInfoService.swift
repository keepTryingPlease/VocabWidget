// WordInfoService.swift
// Fetches enriched word data (extra examples, synonyms, etymology) from the
// Free Dictionary API and caches results for the session.
//
// API used: https://api.dictionaryapi.dev — free, no key required.

import Foundation

// Enriched data returned from the API. All fields are optional — the sheet
// shows whatever is available and omits sections that come back empty.
struct WordInfo {
    let examples:  [String]   // up to 2, sourced from the API
    let synonyms:  [String]   // deduplicated, capped at 8
    let origin:    String?    // etymology string, if the API has one
}

@MainActor
class WordInfoService {

    static let shared = WordInfoService()
    private var cache: [String: WordInfo] = [:]

    func fetch(for word: String) async -> WordInfo {
        let key = word.lowercased()
        if let cached = cache[key] { return cached }

        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)")
        else { return WordInfo(examples: [], synonyms: [], origin: nil) }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries   = try JSONDecoder().decode([DictEntry].self, from: data)

            var rawSynonyms: [String] = []
            var rawExamples: [String] = []
            var origin: String?       = nil

            for entry in entries {
                if let o = entry.origin, !o.isEmpty, origin == nil {
                    origin = o
                }
                for meaning in entry.meanings {
                    // Synonyms at the meaning level (more common location)
                    rawSynonyms += meaning.synonyms
                    for def in meaning.definitions {
                        rawSynonyms += def.synonyms
                        if let ex = def.example, !ex.isEmpty, rawExamples.count < 2 {
                            rawExamples.append(ex)
                        }
                    }
                }
            }

            // Deduplicate synonyms preserving order, cap at 8.
            var seen = Set<String>()
            let synonyms = rawSynonyms
                .filter { seen.insert($0.lowercased()).inserted }
                .prefix(8)
                .map { $0 }

            let info = WordInfo(examples: rawExamples, synonyms: synonyms, origin: origin)
            cache[key] = info
            return info
        } catch {
            let empty = WordInfo(examples: [], synonyms: [], origin: nil)
            cache[key] = empty
            return empty
        }
    }
}

// ── API response models ────────────────────────────────────────────────────────
private struct DictEntry: Codable {
    let origin:   String?
    let meanings: [DictMeaning]
}

private struct DictMeaning: Codable {
    let definitions: [DictDefinition]
    let synonyms:    [String]
}

private struct DictDefinition: Codable {
    let example:  String?
    let synonyms: [String]
}
