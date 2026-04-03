// ContentView.swift
// The main screen of the app.
//
// LEARNING NOTES:
// - DragGesture.onChanged fires continuously as the finger moves, letting us
//   move the card in real time by storing translation in @State.
// - DragGesture.onEnded gives us both the final translation AND predictedEndTranslation
//   (velocity-based), so a quick flick completes the swipe even if short.
// - ZStack layers views back-to-front. The background card sits behind the
//   foreground card and scales up as the drag progresses, creating the illusion
//   of a physical stack.
// - DispatchQueue.main.asyncAfter lets us wait for the fly-off animation to finish
//   before resetting state (no visible jump).

import SwiftUI

struct ContentView: View {

    let allWords = VocabularyStore.words
    @State private var selectedWord: VocabularyWord? = nil

    // Which day we're viewing. 0 = today, -1 = yesterday, etc.
    @State private var dayOffset = 0

    // How far the user has dragged the foreground card. Drives real-time movement.
    @State private var dragOffset: CGFloat = 0
    @State private var isFetchingAudio = false

    // Swipe must exceed this distance (or predicted velocity equivalent) to complete.
    private let swipeThreshold: CGFloat = 120

    // 0.0 → 1.0 as drag approaches the threshold. Used to scale the background card.
    private var swipeProgress: CGFloat {
        min(abs(dragOffset) / swipeThreshold, 1.0)
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

                Text(dayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)

                // ── Card stack ────────────────────────────────────────────
                ZStack {

                    // Background card — the word that will appear after a completed swipe.
                    // Only rendered while the user is actively dragging.
                    // Starts slightly scaled down and grows to full size as swipeProgress → 1.
                    if abs(dragOffset) > 2 {
                        let goingDown = dragOffset > 0
                        let canShow   = goingDown || dayOffset < 0
                        if canShow {
                            wordContent(for: goingDown ? dayOffset - 1 : dayOffset + 1)
                                .scaleEffect(0.88 + 0.12 * swipeProgress)
                        }
                    }

                    // Foreground card — follows the finger in real time.
                    wordContent(for: dayOffset)
                        .offset(y: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation.height
                                }
                                .onEnded { value in
                                    handleSwipeEnd(value)
                                }
                        )
                }

                // ── Pronunciation button ──────────────────────────────────
                Button {
                    Task {
                        isFetchingAudio = true
                        await PronunciationService.shared.speak(VocabularyStore.word(forDayOffset: dayOffset).word)
                        isFetchingAudio = false
                    }
                } label: {
                    if isFetchingAudio {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "speaker.wave.2")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 16)

                Spacer()

                // ── Word Bank button ──────────────────────────────────────
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
            .onChange(of: dayOffset) { _, _ in isFetchingAudio = false }
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

    // ── Word content view ─────────────────────────────────────────────────────
    // Extracted so we can render it for both the foreground and background card.
    @ViewBuilder
    private func wordContent(for offset: Int) -> some View {
        let word = VocabularyStore.word(forDayOffset: offset)
        VStack(spacing: 16) {
            Text(word.word)
                .font(.custom("PlayfairDisplay-Bold", size: 36))
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            Text(word.definition)
                .font(.custom("Inter_18pt-Regular", size: 17))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("\u{201C}\(word.example)\u{201D}")
                .font(.custom("Inter_18pt-Regular", size: 15))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // ── Swipe logic ───────────────────────────────────────────────────────────
    private func handleSwipeEnd(_ value: DragGesture.Value) {
        let distance  = value.translation.height
        let predicted = value.predictedEndTranslation.height
        let goingDown = distance > 0
        let canSwipe  = goingDown || dayOffset < 0

        // Complete if drag exceeded threshold OR flick velocity would carry it far enough.
        let shouldComplete = canSwipe &&
            (abs(distance) > swipeThreshold || abs(predicted) > swipeThreshold * 2)

        if shouldComplete {
            // Fly the card off screen, then update state once it's gone.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                dragOffset = goingDown ? 1000 : -1000
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dayOffset += goingDown ? -1 : 1
                dragOffset = 0
            }
        } else {
            // Not far enough — snap back with a bouncy spring.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                dragOffset = 0
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

            Text(word.definition)
                .font(.body)
                .foregroundStyle(isHighlighted ? .white : .primary)

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
