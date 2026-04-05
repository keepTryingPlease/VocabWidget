// VocabLockScreenWidget.swift
// The entire widget extension lives in this one file for the MVP.
//
// LEARNING NOTES — WidgetKit mental model:
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │  TimelineProvider  →  builds a list of TimelineEntry values  │
//  │  TimelineEntry     →  a (date, data) snapshot in time        │
//  │  Widget            →  the @main struct that wires it all up   │
//  │  View              →  SwiftUI view rendered from one entry    │
//  └─────────────────────────────────────────────────────────────┘
//
//  WidgetKit doesn't keep your widget alive continuously.
//  Instead, it asks your Provider for a Timeline of future entries,
//  renders them at the right moment, and discards the process.
//  For a daily-update word widget, we only need ONE entry per day.
//
// IMPORTANT: This file must be in your Widget Extension target, NOT
// the main app target. (Xcode sets this up automatically when you add
// a Widget Extension via File → New → Target → Widget Extension.)
//
// Also add VocabularyWord.swift and VocabularyStore.swift to this
// target via File Inspector → Target Membership.

import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TimelineEntry
// Conforms to TimelineEntry, which requires a `date` property.
// WidgetKit uses `date` to decide when to display this entry.
// You can add whatever other data you need alongside it.
// ─────────────────────────────────────────────────────────────────────────────
struct VocabEntry: TimelineEntry {
    let date: Date
    let word: VocabularyWord
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TimelineProvider
// Responsible for supplying WidgetKit with entries to render.
// You implement three methods:
//   placeholder  — shown while the widget loads for the first time (static)
//   getSnapshot  — shown in the widget gallery picker
//   getTimeline  — the real deal; called periodically by WidgetKit
// ─────────────────────────────────────────────────────────────────────────────
struct VocabProvider: TimelineProvider {

    func placeholder(in context: Context) -> VocabEntry {
        // This should return quickly without hitting network/disk.
        VocabEntry(date: .now, word: VocabularyStore.featuredWords.first ?? VocabularyStore.words[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (VocabEntry) -> Void) {
        // Called when Xcode or the widget gallery wants a preview.
        completion(VocabEntry(date: .now, word: VocabularyStore.wordOfTheDay))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VocabEntry>) -> Void) {
        // Build a timeline with one entry per day for the next 7 days.
        // This is more robust than a single entry — if iOS delays the reload
        // slightly, the correct word still shows for future days.

        var entries: [VocabEntry] = []
        let calendar = Calendar.current

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: .now) else { continue }
            // Use the featured-only pool so the widget always shows a curated word.
            let word = VocabularyStore.featuredWord(forDayOffset: dayOffset)
            entries.append(VocabEntry(date: date, word: word))
        }

        // .atEnd tells WidgetKit to call getTimeline again after the last entry.
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget Views
// WidgetKit renders one view per `widgetFamily`. We branch on `@Environment
// (\.widgetFamily)` to return the right layout for each size.
//
// Lock screen families (iOS 16+):
//   .accessoryInline      — single line of text along the top of the lock screen
//   .accessoryRectangular — multi-line rectangle (best for showing word + def)
//   .accessoryCircular    — small circle (good for a single word)
// ─────────────────────────────────────────────────────────────────────────────
struct VocabWidgetEntryView: View {
    let entry: VocabEntry

    // WidgetKit injects the current widget family through the environment.
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {

        // ── Medium home screen: full width, shows word + definition + example ─
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.word.word)
                        .font(.title2)
                        .bold()
                    Text(entry.word.partOfSpeech)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                Text(entry.word.definition)
                    .font(.subheadline)
                    .lineLimit(2)

                Text("\u{201C}\(entry.word.examples.first ?? "")\u{201D}")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

        // ── Single line: shown at the very top of the lock screen ────────────
        case .accessoryInline:
            // Keep it short — only a few words fit here.
            Text("\(entry.word.word) · \(entry.word.partOfSpeech)")
                .font(.caption)

        // ── Rectangle: most useful layout, shows word + short definition ─────
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.word.word)
                        .font(.caption)
                        .bold()
                        .lineLimit(1)
                    Text("· \(entry.word.partOfSpeech)")
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.word.definition)
                    .font(.caption2)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        // ── Circle: shows just the word ───────────────────────────────────────
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "text.book.closed")
                    .font(.caption)
                Text(entry.word.word)
                    .font(.caption2)
                    .bold()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

        // ── Fallback for any future families Apple adds ───────────────────────
        default:
            Text(entry.word.word)
                .font(.caption)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget Entry Point
// @main here refers to the widget extension's entry point, not the app's.
// (The two @main structs live in separate targets, so there's no conflict.)
// ─────────────────────────────────────────────────────────────────────────────
@main
struct VocabLockScreenWidget: Widget {

    // `kind` is a stable identifier for this widget — used if you add more widgets later.
    let kind = "VocabLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VocabProvider()) { entry in
            VocabWidgetEntryView(entry: entry)
                // containerBackground replaces the old .padding()/.background() approach
                // in WidgetKit — required on iOS 17+ for system widgets.
                .containerBackground(.fill.tertiary, for: .widget)
                // widgetURL: tapping the widget opens the app and deep-links to this word.
                .widgetURL(URL(string: "vocabwidget://word/\(entry.word.id)"))
        }
        .configurationDisplayName("Word of the Day")
        .description("A new vocabulary word every day on your lock screen.")
        .supportedFamilies([
            .systemMedium,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular
        ])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// You can preview each widget family side-by-side in Xcode's canvas.
// ─────────────────────────────────────────────────────────────────────────────
#Preview(as: .accessoryRectangular) {
    VocabLockScreenWidget()
} timeline: {
    VocabEntry(date: .now, word: VocabularyStore.wordOfTheDay)
    VocabEntry(date: .now, word: VocabularyStore.featuredWord(forDayOffset: 1))
}
