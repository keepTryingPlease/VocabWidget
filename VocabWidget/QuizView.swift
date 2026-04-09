// QuizView.swift
// Interactive quiz for hand-curated vocabulary words.
// Pass = 100% correct → word marked Learned.
// Fail = any wrong   → 24-hour retry lockout.
// Questions are shuffled on every launch so order can't be memorized.

import SwiftUI

private extension Color {
    static let quizBackground = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let quizSurface    = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let quizPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let quizSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
    static let quizAccent     = Color(red: 0.95, green: 0.78, blue: 0.35)
    static let quizCorrect    = Color(red: 0.25, green: 0.80, blue: 0.50)
    static let quizWrong      = Color(red: 0.90, green: 0.35, blue: 0.35)
}

struct QuizView: View {

    let word: VocabularyWord
    @ObservedObject var library: UserLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var shuffledQuestions: [QuizQuestion] = []
    @State private var phase:             QuizPhase      = .intro
    @State private var questionIndex:     Int            = 0
    @State private var selectedOption:    Int?           = nil
    @State private var correctCount:      Int            = 0
    @State private var isAdvancing:       Bool           = false
    @State private var passed:            Bool           = false

    private enum QuizPhase { case intro, question, results }

    private var currentQuestion: QuizQuestion? {
        guard shuffledQuestions.indices.contains(questionIndex) else { return nil }
        return shuffledQuestions[questionIndex]
    }

    var body: some View {
        ZStack {
            Color.quizBackground.ignoresSafeArea()

            switch phase {
            case .intro:    introScreen()
            case .question: questionScreen()
            case .results:  resultsScreen()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Shuffle question order fresh every time
            shuffledQuestions = (word.quiz ?? []).shuffled()
        }
    }

    // ── Intro ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func introScreen() -> some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text(word.word)
                    .font(.custom("PlayfairDisplay-Bold", size: 40))
                    .foregroundStyle(Color.quizPrimary)
                Text(word.partOfSpeech)
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(Color.quizSecondary)
            }

            VStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.quizAccent)
                Text("\(shuffledQuestions.count)-Question Quiz")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.quizPrimary)
                Text("Answer every question correctly to mark\nthis word as Learned.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.quizSecondary)
                    .multilineTextAlignment(.center)
                if library.isLearned(word) {
                    Label("Already learned — retaking for practice", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.quizCorrect)
                        .padding(.top, 4)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { phase = .question }
                } label: {
                    Text("Start Quiz")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.quizBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.quizAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Not Now") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.quizSecondary)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // ── Question ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private func questionScreen() -> some View {
        if let q = currentQuestion {
            VStack(spacing: 0) {
                progressBar()
                    .padding(.top, 56)
                    .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 24) {
                    Text(q.title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color.quizAccent)

                    Text(q.prompt)
                        .font(.custom("PlayfairDisplay-Bold", size: 26))
                        .foregroundStyle(Color.quizPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 12) {
                    ForEach(q.options.indices, id: \.self) { i in
                        optionButton(index: i, option: q.options[i], question: q)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
            }
            .id(questionIndex)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    @ViewBuilder
    private func progressBar() -> some View {
        let total = shuffledQuestions.count
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < questionIndex
                          ? Color.quizCorrect
                          : (i == questionIndex ? Color.quizAccent : Color.quizSurface))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: questionIndex)
            }
        }
    }

    @ViewBuilder
    private func optionButton(index: Int, option: String, question: QuizQuestion) -> some View {
        let isSelected = selectedOption == index
        let isCorrect  = index == question.answerIndex
        let answered   = selectedOption != nil

        let bg: Color = {
            guard answered else { return Color.quizSurface }
            if isCorrect  { return Color.quizCorrect.opacity(0.18) }
            if isSelected { return Color.quizWrong.opacity(0.18) }
            return Color.quizSurface
        }()

        let border: Color = {
            guard answered else { return Color.quizSurface }
            if isCorrect  { return Color.quizCorrect }
            if isSelected { return Color.quizWrong }
            return Color.quizSurface
        }()

        Button {
            guard selectedOption == nil, !isAdvancing else { return }
            selectedOption = index
            if isCorrect { correctCount += 1 }
            isAdvancing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { advance() }
        } label: {
            HStack(spacing: 14) {
                Text(["A", "B", "C"][index])
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(answered && isCorrect ? Color.quizCorrect
                                     : answered && isSelected ? Color.quizWrong
                                     : Color.quizSecondary)
                    .frame(width: 22, height: 22)
                    .background(Color.quizBackground.opacity(0.6))
                    .clipShape(Circle())

                Text(option)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.quizPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if answered && isCorrect {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.quizCorrect)
                } else if answered && isSelected && !isCorrect {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.quizWrong)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(border, lineWidth: answered ? 1.0 : 0))
            .animation(.easeOut(duration: 0.2), value: selectedOption)
        }
        .disabled(answered)
    }

    // ── Results ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func resultsScreen() -> some View {
        if passed {
            passScreen()
        } else {
            failScreen()
        }
    }

    @ViewBuilder
    private func passScreen() -> some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.quizCorrect)

                Text("Word Learned!")
                    .font(.custom("PlayfairDisplay-Bold", size: 30))
                    .foregroundStyle(Color.quizPrimary)

                Text("\"\(word.word)\" has been added to your Learned list.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.quizSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.quizBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.quizCorrect)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func failScreen() -> some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                scoreRing()

                Text("Not quite.")
                    .font(.custom("PlayfairDisplay-Bold", size: 30))
                    .foregroundStyle(Color.quizPrimary)

                Text("You need a perfect score to mark a word as Learned.\nCome back in 24 hours to try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.quizSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button("Got It") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.quizPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.quizSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func scoreRing() -> some View {
        let total    = shuffledQuestions.count
        let fraction = total > 0 ? Double(correctCount) / Double(total) : 0

        ZStack {
            Circle()
                .stroke(Color.quizSurface, lineWidth: 8)
                .frame(width: 110, height: 110)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.quizWrong, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(correctCount)/\(total)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.quizPrimary)
                Text("correct")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.quizSecondary)
            }
        }
    }

    // ── Advance logic ─────────────────────────────────────────────────────────

    private func advance() {
        let nextIndex = questionIndex + 1
        if nextIndex < shuffledQuestions.count {
            withAnimation(.easeInOut(duration: 0.25)) {
                questionIndex  = nextIndex
                selectedOption = nil
                isAdvancing    = false
            }
        } else {
            // Quiz complete — evaluate result
            let allCorrect = correctCount == shuffledQuestions.count
            passed = allCorrect
            if allCorrect {
                library.markLearned(word)
            } else {
                library.setQuizCooldown(for: word)
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                phase       = .results
                isAdvancing = false
            }
        }
    }
}

#Preview {
    QuizView(
        word: VocabularyStore.words.first(where: { $0.quiz != nil }) ?? VocabularyStore.words[0],
        library: UserLibrary()
    )
}
