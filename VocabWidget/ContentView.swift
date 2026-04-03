// ContentView.swift
// The main screen of the app.
//
// LEARNING NOTES:
// - `@State` is SwiftUI's simplest way to store local view state.
//   When a @State var changes, SwiftUI re-renders the view automatically.
// - `NavigationStack` gives you the top nav bar and enables push navigation.
// - `NavigationLink` pushes a new view onto the stack when tapped.
// - `DragGesture` detects swipe direction via translation.width.

import SwiftUI

struct ContentView: View {

    let allWords = VocabularyStore.words

    // Track whether the deep-link detail sheet is showing.
    @State private var selectedWord: VocabularyWord? = nil

    // 0 = today, -1 = yesterday, -2 = two days ago, etc.
    @State private var dayOffset = 0

    private var browsedWord: VocabularyWord {
        VocabularyStore.word(forDayOffset: dayOffset)
    }

    private var dayLabel: String {
        switch dayOffset {
        case 0:  return "Today"
        case -1: return "Yesterday"
        default:
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE, MMM d"
            return fmt.string(from: date)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                Spacer()

                // ── Day navigation ────────────────────────────────────────
                HStack {
                    Button {
                        withAnimation(.spring()) { dayOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(dayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.spring()) { dayOffset += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(dayOffset < 0 ? .secondary : .tertiary)
                    }
                    .disabled(dayOffset == 0)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // ── Centered word display ─────────────────────────────────
                // All text is center-aligned. Swipe left/right to change day.
                VStack(spacing: 16) {
                    Text(browsedWord.word)
                        .font(.largeTitle)
                        .bold()
                        .multilineTextAlignment(.center)

                    Divider()
                        .padding(.horizontal, 40)

                    Text(browsedWord.definition)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("\u{201C}\(browsedWord.example)\u{201D}")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            withAnimation(.spring()) {
                                if value.translation.width < 0 {
                                    dayOffset -= 1
                                } else if value.translation.width > 0 && dayOffset < 0 {
                                    dayOffset += 1
                                }
                            }
                        }
                )

                Spacer()

                // ── Word Bank button ──────────────────────────────────────
                // NavigationLink pushes WordBankView onto the stack.
                NavigationLink {
                    WordBankView()
                } label: {
                    Label("Word Bank", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .navigationBarHidden(true)
            // onOpenURL handles deep links from tapping the widget.
            // URL format: vocabwidget://word/{id}
            .sheet(item: $selectedWord) { word in
                WordDetailView(word: word)
            }
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
// MARK: - WordBankView
// Full list of all words, pushed via NavigationLink from ContentView.
// ─────────────────────────────────────────────────────────────────────────────
struct WordBankView: View {
    let allWords = VocabularyStore.words
    @State private var selectedWord: VocabularyWord? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(allWords) { word in
                    Button {
                        selectedWord = word
                    } label: {
                        WordCard(word: word, isHighlighted: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .navigationTitle("Word Bank")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedWord) { word in
            WordDetailView(word: word)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordCard
// Used in WordBankView. Leading-aligned card for list display.
// ─────────────────────────────────────────────────────────────────────────────
struct WordCard: View {
    let word: VocabularyWord
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

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
// Full-screen detail sheet shown when tapping a word in the word bank.
// ─────────────────────────────────────────────────────────────────────────────
struct WordDetailView: View {
    let word: VocabularyWord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

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

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Definition", systemImage: "text.book.closed")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(word.definition)
                            .font(.body)
                    }

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
// ─────────────────────────────────────────────────────────────────────────────
#Preview {
    ContentView()
}
