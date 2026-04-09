// WordInfoView.swift
// Detail sheet shown when the user taps the Info button on a word.
// All data (examples, synonyms, etymology) is read directly from the
// VocabularyWord model — no network calls needed at runtime.

import SwiftUI

struct WordInfoView: View {

    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

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

                    // ── Definition ────────────────────────────────────────
                    infoSection(title: "Definition", icon: "text.book.closed") {
                        Text(word.definition)
                            .font(.body)
                    }

                    // ── Key Idea ──────────────────────────────────────────
                    if let keyIdea = word.keyIdea {
                        infoSection(title: "Key Idea", icon: "lightbulb") {
                            Text(keyIdea)
                                .font(.body).italic()
                                .foregroundStyle(.primary)
                        }
                    }

                    // ── Examples ──────────────────────────────────────────
                    if !word.examples.isEmpty {
                        infoSection(
                            title: word.examples.count > 1 ? "Examples" : "Example",
                            icon: "quote.opening"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(word.examples, id: \.self) { example in
                                    Text("\u{201C}\(example)\u{201D}")
                                        .font(.body).italic()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // ── Nuance ────────────────────────────────────────────
                    if let nuance = word.nuance {
                        infoSection(title: "Usage Note", icon: "pencil.and.outline") {
                            Text(nuance)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ── Typical Usage ─────────────────────────────────────
                    if let typicalUsage = word.typicalUsage {
                        infoSection(title: "Typical Usage", icon: "text.alignleft") {
                            Text(typicalUsage)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ── Synonyms ──────────────────────────────────────────
                    if !word.synonyms.isEmpty {
                        infoSection(title: "Synonyms", icon: "arrow.left.arrow.right") {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(word.synonyms, id: \.self) { synonym in
                                    Text(synonym)
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

                    // ── Origin ────────────────────────────────────────────
                    if let origin = word.origin {
                        infoSection(title: "Origin", icon: "clock.arrow.circlepath") {
                            Text(origin)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
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
