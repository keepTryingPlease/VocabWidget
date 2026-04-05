// ContentView.swift
// The main screen of the app.
//
// LEARNING NOTES:
// - Instagram Reels-style full-screen paging: the entire screen — level pill,
//   word content, pronunciation button, word bank button — moves as one unit.
//   The adjacent screen is offset by exactly one screen-height, so it sits just
//   out of view until the drag pulls it in.
// - GeometryReader wraps the outer ZStack to capture the true screen height.
//   This height is used both to position adjacent pages and to animate the
//   fly-out on swipe completion.
// - .clipped() on the ZStack clips anything that strays outside the screen
//   bounds, giving the illusion of a clean vertical pager.
// - Background pages get .allowsHitTesting(false) so only the foreground page's
//   buttons are tappable.
// - Rubberband resistance (raw * 0.15) gives tactile feedback when the user
//   tries to swipe back from the very first word in the deck.
// - For the level-switch animation, all state changes are batched in a single
//   Transaction with no animation, so the new screen appears off-screen instantly
//   before the spring animation slides it in — eliminating any flash.

import SwiftUI

// App-wide colour palette
private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
}

struct ContentView: View {

    let allWords = VocabularyStore.words
    @State private var selectedWord: VocabularyWord? = nil
    @State private var infoWord:     VocabularyWord? = nil

    // Active vocabulary level. Changing it resets the deck to position 0.
    @State private var selectedLevel: String = "beginner"

    // Position in the current level's deck. 0 = first card, -1 = second, etc.
    @State private var dayOffset = 0

    // How far the user has dragged. Drives real-time screen movement.
    @State private var dragOffset: CGFloat = 0
    // Used only for the level-switch entry animation (separate from drag).
    @State private var entryOffset: CGFloat = 0
    // Full screen height — captured from GeometryReader, used to position pages.
    @State private var screenHeight: CGFloat = 852
    @State private var isFetchingAudio = false

    // Swipe must exceed this distance (or predicted velocity equivalent) to complete.
    private let swipeThreshold: CGFloat = 100

    // Words filtered to the active level, in their shuffled deck order.
    private var filteredWords: [VocabularyWord] {
        VocabularyStore.words.filter { $0.level == selectedLevel }
    }

    // Returns the word at a given deck offset within the active level.
    private func word(forOffset offset: Int) -> VocabularyWord {
        guard !filteredWords.isEmpty else { return VocabularyStore.words[0] }
        let count = filteredWords.count
        let index = (((-offset) % count) + count) % count
        return filteredWords[index]
    }

    private var levelDisplayName: String {
        switch selectedLevel {
        case "beginner":     return "Beginner"
        case "intermediate": return "Intermediate"
        case "advanced":     return "Advanced"
        default:             return selectedLevel.capitalized
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { screen in
                ZStack {

                    // Page above — visible when swiping down (going back).
                    if dragOffset > 2 && dayOffset < 0 {
                        screenContent(for: dayOffset + 1)
                            .offset(y: -screen.size.height + dragOffset)
                            .allowsHitTesting(false)
                    }

                    // Page below — visible when swiping up (going forward).
                    if dragOffset < -2 {
                        screenContent(for: dayOffset - 1)
                            .offset(y: screen.size.height + dragOffset)
                            .allowsHitTesting(false)
                    }

                    // Foreground page — follows the finger and any entry animation.
                    screenContent(for: dayOffset)
                        .offset(y: dragOffset + entryOffset)
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let raw = value.translation.height
                            // Rubberband resistance when trying to go back past the first page.
                            dragOffset = (raw > 0 && dayOffset >= 0) ? raw * 0.15 : raw
                        }
                        .onEnded { value in
                            handleSwipeEnd(value, height: screen.size.height)
                        }
                )
                .onAppear { screenHeight = screen.size.height }
                .onChange(of: screen.size) { _, new in screenHeight = new.height }
            }
            .ignoresSafeArea()
            .background(Color.appBackground)
            .navigationBarHidden(true)
            .onChange(of: dayOffset) { _, _ in isFetchingAudio = false }
            .sheet(item: $selectedWord) { word in
                WordDetailView(word: word)
            }
            .sheet(item: $infoWord) { word in
                WordInfoView(word: word)
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

    // ── Full-screen page ──────────────────────────────────────────────────────
    // Every swipeable page is the entire screen: level pill, word, pronunciation
    // button, and action buttons all move together as one unit.
    @ViewBuilder
    private func screenContent(for offset: Int) -> some View {
        VStack(spacing: 0) {

            Spacer()

            // ── Level selector pill ───────────────────────────────────
            Menu {
                Button { switchLevel(to: "beginner") } label: {
                    Label("Beginner",     systemImage: selectedLevel == "beginner"     ? "checkmark" : "")
                }
                Button { switchLevel(to: "intermediate") } label: {
                    Label("Intermediate", systemImage: selectedLevel == "intermediate" ? "checkmark" : "")
                }
                Button { switchLevel(to: "advanced") } label: {
                    Label("Advanced",     systemImage: selectedLevel == "advanced"     ? "checkmark" : "")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(levelDisplayName)
                        .font(.custom("Inter_18pt-Regular", size: 13))
                        .foregroundStyle(Color.appPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.appSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Color.appPrimary.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.appSecondary.opacity(0.35), lineWidth: 1))
            }
            .padding(.bottom, 24)

            // ── Word content ──────────────────────────────────────────
            wordContent(for: offset)

            // ── Pronunciation button ──────────────────────────────────
            Button {
                Task {
                    isFetchingAudio = true
                    await PronunciationService.shared.speak(word(forOffset: dayOffset).word)
                    isFetchingAudio = false
                }
            } label: {
                if isFetchingAudio {
                    ProgressView()
                        .tint(Color.appSecondary)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "speaker.wave.2")
                        .font(.title2)
                        .foregroundStyle(Color.appSecondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.top, 16)

            Spacer()

            // ── Action buttons ────────────────────────────────────────
            HStack(spacing: 0) {
                actionButton(icon: "info.circle",     label: "Info") {
                    infoWord = word(forOffset: dayOffset)
                }
                actionButton(icon: "heart",           label: "Like")
                actionButton(icon: "checkmark.seal",  label: "Mastered")
                actionButton(icon: "square.stack",    label: "Collections")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // ── Action button ─────────────────────────────────────────────────────────
    @ViewBuilder
    private func actionButton(
        icon: String,
        label: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appSecondary)
                Text(label)
                    .font(.custom("Inter_18pt-Regular", size: 10))
                    .foregroundStyle(Color.appSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // ── Word content ──────────────────────────────────────────────────────────
    @ViewBuilder
    private func wordContent(for offset: Int) -> some View {
        let word = word(forOffset: offset)
        VStack(spacing: 16) {
            Text(word.word)
                .font(.custom("PlayfairDisplay-Bold", size: 36))
                .foregroundStyle(Color.appPrimary)
                .multilineTextAlignment(.center)

            Divider()
                .overlay(Color.appSecondary.opacity(0.4))
                .padding(.horizontal, 40)

            Text(word.definition)
                .font(.custom("Inter_18pt-Regular", size: 17))
                .foregroundStyle(Color.appPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("\u{201C}\(word.example)\u{201D}")
                .font(.custom("Inter_18pt-Regular", size: 15))
                .italic()
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // ── Swipe logic ───────────────────────────────────────────────────────────
    private func handleSwipeEnd(_ value: DragGesture.Value, height: CGFloat) {
        let distance  = value.translation.height
        let predicted = value.predictedEndTranslation.height
        let goingUp   = distance < 0          // swipe up = advance to next word
        let canSwipe  = goingUp || dayOffset < 0

        // Complete if drag exceeded threshold OR flick velocity would carry it far enough.
        let shouldComplete = canSwipe &&
            (abs(distance) > swipeThreshold || abs(predicted) > swipeThreshold * 2)

        if shouldComplete {
            // Fly the page off screen, then update state once it's gone.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                dragOffset = goingUp ? -height : height
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                dayOffset += goingUp ? -1 : 1
                dragOffset = 0
            }
        } else {
            // Not far enough — snap back with a bouncy spring.
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                dragOffset = 0
            }
        }
    }

    // ── Level switch ──────────────────────────────────────────────────────────
    // Batch all state changes atomically (no animation) so the new screen appears
    // off-screen instantly, then animate it sliding in from below.
    private func switchLevel(to level: String) {
        guard level != selectedLevel else { return }
        isFetchingAudio = false
        let t = Transaction(animation: nil)
        withTransaction(t) {
            selectedLevel = level
            dayOffset     = 0
            entryOffset   = screenHeight
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            entryOffset = 0
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - WordDetailView
// Full-screen detail sheet — used by the widget deep link (vocabwidget://word/id).
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
