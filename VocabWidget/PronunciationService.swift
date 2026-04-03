// PronunciationService.swift
// Fetches pronunciation audio from the Free Dictionary API and plays it back.
//
// LEARNING NOTES:
// - `async/await` lets us write asynchronous code that reads like synchronous code.
//   `try await URLSession.shared.data(from:)` suspends the function until the
//   network response arrives, without blocking the main thread.
// - `@MainActor` ensures all property access and UI-touching code runs on the
//   main thread, which is required for ObservableObject + SwiftUI.
// - AVAudioSession.Category.playback means audio plays even when the phone is
//   on silent — important for a pronunciation feature.
// - In-memory cache means we only hit the API once per word per app session.
//
// API used: https://api.dictionaryapi.dev — free, no key required.

import Foundation
import AVFoundation

@MainActor
class PronunciationService {

    static let shared = PronunciationService()

    // Cached audio URLs keyed by lowercase word.
    private var urlCache: [String: URL] = [:]
    private var player: AVPlayer?

    // Fetch the audio URL for a word (from cache or API), then play it.
    // Fails silently if the word isn't in the API or the device is offline.
    func speak(_ word: String) async {
        let key = word.lowercased()
        do {
            let audioURL: URL
            if let cached = urlCache[key] {
                audioURL = cached
            } else {
                guard let fetched = try await fetchAudioURL(for: key) else { return }
                urlCache[key] = fetched
                audioURL = fetched
            }
            // Allow playback even when the phone is on silent.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: audioURL)
            player?.play()
        } catch {
            // Network error or word not found — do nothing.
        }
    }

    private func fetchAudioURL(for word: String) async throws -> URL? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let apiURL = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)")
        else { return nil }

        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)

        // Walk all phonetics across all entries, take the first non-empty audio URL.
        let audioString = entries
            .flatMap { $0.phonetics }
            .first { !($0.audio ?? "").isEmpty }?
            .audio

        guard let str = audioString, !str.isEmpty else { return nil }
        return URL(string: str)
    }
}

// Minimal Codable models — only decode what we need from the API response.
private struct DictionaryEntry: Codable {
    let phonetics: [Phonetic]
}

private struct Phonetic: Codable {
    let audio: String?
}
