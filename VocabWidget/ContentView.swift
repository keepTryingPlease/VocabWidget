// ContentView.swift
// The main screen of the app.
//
// LEARNING NOTES:
// - `@State` is SwiftUI's simplest way to store local view state.
//   When a @State var changes, SwiftUI re-renders the view automatically.
// - `NavigationStack` gives you the top nav bar and enables push navigation.
// - `ScrollView + VStack` is the standard pattern for a vertically
//   scrolling page of content.
// - `ForEach` is SwiftUI's loop construct for rendering collections of views.

import SwiftUI

struct ContentView: View {

    // We grab the word list and today's word at view init time.
    // These don't change while the app is open, so plain `let` is fine.
    let allWords = VocabularyStore.words
    let todayWord = VocabularyStore.wordOfTheDay

    // Track whether the detail sheet is showing.
    @State private var selectedWord: VocabularyWord? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Today's Word ──────────────────────────────────────
                    WordCard(word: todayWord, isHighlighted: true)
                        .padding(.top, 8)

                    // ── All Words ─────────────────────────────────────────
                    HStack {
                        Text("Word Bank")
                            .font(.title2).bold()
                        Spacer()
                        Text("\(allWords.count) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    ForEach(allWords) { word in
                        Button {
                            selectedWord = word
                        } label: {
                            WordCard(word: word, isHighlighted: false)
                        }
                        .buttonStyle(.plain)  // removes default blue tint
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Word of the Day")
            .sheet(item: $selectedWord) { word in
                // Sheet slides up when a word card is tapped.
                WordDetailView(word: word)
            }
            // onOpenURL handles deep links from the widget.
            // When the user taps the widget, the system opens the app with the URL
            // "vocabwidget://word/{id}". We parse the id and open that word's detail sheet.
            .onOpenURL { url in
                guard url.scheme == "vocabwidget",
                      url.host == "word",
                      let id = Int(url.lastPathComponent),
                      let match = allWords.first(where: { $0.id == id })
                else { return }
                selectedWord = match
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordCard
// A reusable card view. When `isHighlighted` is true it gets special styling
// to visually distinguish the word of the day from the rest of the list.
// ─────────────────────────────────────────────────────────────────────────────
struct WordCard: View {
    let word: VocabularyWord
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Badge shown only on today's word
            if isHighlighted {
                Label("Today's Word", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            // Word + part of speech on one line
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word.word)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(isHighlighted ? .white : .primary)

                Text(word.partOfSpeech)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }

            // Definition
            Text(word.definition)
                .font(.body)
                .foregroundStyle(isHighlighted ? .white : .primary)

            // Example sentence
            Text("\u{201C}\(word.example)\u{201D}")
                .font(.caption)
                .italic()
                .foregroundStyle(isHighlighted ? .white.opacity(0.75) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(isHighlighted ? Color.blue : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordDetailView
// Full-screen detail sheet shown when you tap a word card.
// LEARNING NOTE: `@Environment(\.dismiss)` gives you a closure you can call
// to close a sheet or pop a navigation link without needing to pass state down.
// ─────────────────────────────────────────────────────────────────────────────
struct WordDetailView: View {
    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.word)
                            .font(.largeTitle)
                            .bold()
                        Text(word.partOfSpeech)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Definition section
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Definition", systemImage: "text.book.closed")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(word.definition)
                            .font(.body)
                    }

                    // Example section
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Example", systemImage: "quote.opening")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text("\u{201C}\(word.example)\u{201D}")
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
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
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// The #Preview macro lets Xcode render your view in the canvas without running
// the simulator. Great for fast iteration on UI.
// ─────────────────────────────────────────────────────────────────────────────
#Preview {
    ContentView()
}
