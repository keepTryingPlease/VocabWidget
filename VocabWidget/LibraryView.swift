// LibraryView.swift
// Shows two sections: Favorites and Classroom.

import SwiftUI

struct LibraryView: View {

    @ObservedObject var library: UserLibrary
    @Environment(\.dismiss) private var dismiss

    enum Tab { case favorites, classroom }
    @State private var selectedTab: Tab = .favorites

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Tab picker ────────────────────────────────────────────
                Picker("", selection: $selectedTab) {
                    Label("Favorites", systemImage: "heart.fill").tag(Tab.favorites)
                    Label("Classroom", systemImage: "graduationcap.fill").tag(Tab.classroom)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // ── Content ───────────────────────────────────────────────
                switch selectedTab {
                case .favorites:
                    wordList(library.favoriteWords,
                             emptyMessage: "No favorites yet.\nTap ♥ on any card to save a word.")
                case .classroom:
                    wordList(library.classroomWords,
                             emptyMessage: "Classroom is empty.\nTap the graduation cap on any card to add a word.")
                }
            }
            .navigationTitle(selectedTab == .favorites ? "Favorites" : "Classroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // ── Word list ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func wordList(_ words: [VocabularyWord], emptyMessage: String) -> some View {
        if words.isEmpty {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: selectedTab == .favorites ? "heart" : "graduationcap")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Spacer()
            }
        } else {
            List {
                ForEach(words) { word in
                    wordRow(word)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let word = words[idx]
                        switch selectedTab {
                        case .favorites: library.toggleFavorite(word)
                        case .classroom: library.toggleClassroom(word)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func wordRow(_ word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word.word)
                    .font(.headline)
                Spacer()
                Text(word.partOfSpeech)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            Text(word.definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
