// WordInfoView.swift
// Detail sheet shown when the user taps the Info button on a word.
// Local data (word, part of speech, definition, stored example) is displayed
// immediately. Enriched data (extra examples, synonyms, origin) is fetched
// from the Free Dictionary API and appears once the request completes.

import SwiftUI

struct WordInfoView: View {

    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    @State private var info: WordInfo?  = nil
    @State private var isLoading: Bool  = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Header ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text(word.word)
                            .font(.largeTitle).bold()
                        Text(word.partOfSpeech)
                            .font(.subheadline).italic()
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // ── Definition (always available) ─────────────────────
                    infoSection(title: "Definition", icon: "text.book.closed") {
                        Text(word.definition)
                            .font(.body)
                    }

                    // ── Enriched sections (loaded from API) ───────────────
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading details…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    } else {
                        enrichedSections
                    }
                }
                .padding()
            }
            .navigationTitle(word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            info      = await WordInfoService.shared.fetch(for: word.word)
            isLoading = false
        }
    }

    // ── Enriched sections ─────────────────────────────────────────────────────
    // Rendered only after the API response arrives.
    @ViewBuilder
    private var enrichedSections: some View {
        let examples = combinedExamples

        if !examples.isEmpty {
            infoSection(title: examples.count > 1 ? "Examples" : "Example",
                        icon: "quote.opening") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(examples, id: \.self) { ex in
                        Text("\u{201C}\(ex)\u{201D}")
                            .font(.body).italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let synonyms = info?.synonyms, !synonyms.isEmpty {
            infoSection(title: "Synonyms", icon: "arrow.left.arrow.right") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(synonyms, id: \.self) { syn in
                        Text(syn)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
            }
        }

        if let origin = info?.origin {
            infoSection(title: "Origin", icon: "clock.arrow.circlepath") {
                Text(origin)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Merges the local stored example with API examples, deduplicating, up to 2.
    private var combinedExamples: [String] {
        var result: [String] = []
        if !word.example.isEmpty { result.append(word.example) }
        for ex in info?.examples ?? [] {
            guard result.count < 2 else { break }
            if ex.lowercased() != word.example.lowercased() {
                result.append(ex)
            }
        }
        return result
    }

    @ViewBuilder
    private func infoSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.blue)
            content()
        }
    }
}

#Preview {
    WordInfoView(word: VocabularyStore.words[0])
}
