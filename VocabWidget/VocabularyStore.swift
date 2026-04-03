// VocabularyStore.swift
// Shared between the main app target AND the widget extension target.
// In Xcode: select this file → File Inspector → check both targets under "Target Membership".
//
// LEARNING NOTE:
// We pick the word of the day using the day-of-year as an index into the word list.
// Because both the app and the widget run this same code independently, they always
// agree on which word is "today's word" — no data sharing (App Groups) needed!

import Foundation

struct VocabularyStore {

    // ---------------------------------------------------------
    // MARK: - Word List
    // Add more words here to grow your deck. The app cycles
    // through them day by day and wraps around automatically.
    // ---------------------------------------------------------
    static let words: [VocabularyWord] = [
        VocabularyWord(id: 0,
                       word: "Ephemeral",
                       partOfSpeech: "adjective",
                       definition: "Lasting for a very short time.",
                       example: "The ephemeral beauty of cherry blossoms makes them all the more precious."),

        VocabularyWord(id: 1,
                       word: "Luminous",
                       partOfSpeech: "adjective",
                       definition: "Full of or shedding light; bright or shining.",
                       example: "The luminous moon cast long shadows across the quiet street."),

        VocabularyWord(id: 2,
                       word: "Serendipity",
                       partOfSpeech: "noun",
                       definition: "The occurrence of events by chance in a happy or beneficial way.",
                       example: "Finding that old photograph was pure serendipity."),

        VocabularyWord(id: 3,
                       word: "Melancholy",
                       partOfSpeech: "noun",
                       definition: "A feeling of pensive sadness, typically with no obvious cause.",
                       example: "A deep melancholy settled over him as autumn arrived."),

        VocabularyWord(id: 4,
                       word: "Eloquent",
                       partOfSpeech: "adjective",
                       definition: "Fluent or persuasive in speaking or writing.",
                       example: "Her eloquent speech moved the audience to tears."),

        VocabularyWord(id: 5,
                       word: "Tenacious",
                       partOfSpeech: "adjective",
                       definition: "Tending to keep a firm hold of something; persisting.",
                       example: "His tenacious spirit kept him going through the hardest years."),

        VocabularyWord(id: 6,
                       word: "Ambiguous",
                       partOfSpeech: "adjective",
                       definition: "Open to more than one interpretation; not having one obvious meaning.",
                       example: "The contract contained several ambiguous clauses that confused both parties."),

        VocabularyWord(id: 7,
                       word: "Pragmatic",
                       partOfSpeech: "adjective",
                       definition: "Dealing with things sensibly and realistically, based on practical considerations.",
                       example: "A pragmatic approach to the problem saved the team hours of debate."),

        VocabularyWord(id: 8,
                       word: "Resilient",
                       partOfSpeech: "adjective",
                       definition: "Able to recover quickly from difficulties; tough.",
                       example: "The resilient community rebuilt within a year after the flood."),

        VocabularyWord(id: 9,
                       word: "Laconic",
                       partOfSpeech: "adjective",
                       definition: "Using very few words to express a lot.",
                       example: "His laconic reply — 'Fine.' — told me everything I needed to know."),

        VocabularyWord(id: 10,
                       word: "Ubiquitous",
                       partOfSpeech: "adjective",
                       definition: "Present, appearing, or found everywhere.",
                       example: "Smartphones have become ubiquitous in modern life."),

        VocabularyWord(id: 11,
                       word: "Voracious",
                       partOfSpeech: "adjective",
                       definition: "Having or showing an insatiable appetite for an activity or pursuit.",
                       example: "She was a voracious reader, finishing two novels a week."),

        VocabularyWord(id: 12,
                       word: "Equanimity",
                       partOfSpeech: "noun",
                       definition: "Mental calmness and composure, especially in a difficult situation.",
                       example: "He faced the diagnosis with remarkable equanimity."),

        VocabularyWord(id: 13,
                       word: "Pernicious",
                       partOfSpeech: "adjective",
                       definition: "Having a harmful effect, especially in a gradual or subtle way.",
                       example: "The pernicious influence of misinformation spreads slowly."),

        VocabularyWord(id: 14,
                       word: "Magnanimous",
                       partOfSpeech: "adjective",
                       definition: "Very generous or forgiving, especially toward a rival.",
                       example: "The champion was magnanimous in victory, praising her opponent."),

        VocabularyWord(id: 15,
                       word: "Erudite",
                       partOfSpeech: "adjective",
                       definition: "Having or showing great knowledge or learning.",
                       example: "The erudite professor could speak fluently on almost any topic."),

        VocabularyWord(id: 16,
                       word: "Sanguine",
                       partOfSpeech: "adjective",
                       definition: "Optimistic or positive, especially in a difficult situation.",
                       example: "Despite the setbacks, she remained sanguine about the project's future."),

        VocabularyWord(id: 17,
                       word: "Fastidious",
                       partOfSpeech: "adjective",
                       definition: "Very attentive to accuracy and detail; difficult to please.",
                       example: "A fastidious editor, she caught every misplaced comma."),

        VocabularyWord(id: 18,
                       word: "Querulous",
                       partOfSpeech: "adjective",
                       definition: "Complaining in a rather petulant or whining manner.",
                       example: "The querulous customer complained about every tiny detail."),

        VocabularyWord(id: 19,
                       word: "Vicarious",
                       partOfSpeech: "adjective",
                       definition: "Experienced in the imagination through the feelings of another person.",
                       example: "He lived vicariously through his adventurous sister's travel stories."),

        VocabularyWord(id: 20,
                       word: "Arduous",
                       partOfSpeech: "adjective",
                       definition: "Involving or requiring strenuous effort; difficult and tiring.",
                       example: "The arduous hike to the summit took twelve hours."),

        VocabularyWord(id: 21,
                       word: "Pensive",
                       partOfSpeech: "adjective",
                       definition: "Engaged in, involving, or reflecting deep or serious thought.",
                       example: "She sat by the window with a pensive expression, lost in memories."),

        VocabularyWord(id: 22,
                       word: "Obfuscate",
                       partOfSpeech: "verb",
                       definition: "To render obscure, unclear, or unintelligible.",
                       example: "The politician's answer seemed designed to obfuscate rather than explain."),

        VocabularyWord(id: 23,
                       word: "Perspicacious",
                       partOfSpeech: "adjective",
                       definition: "Having a ready insight into and understanding of things.",
                       example: "A perspicacious investor, she spotted the trend before anyone else."),

        VocabularyWord(id: 24,
                       word: "Recalcitrant",
                       partOfSpeech: "adjective",
                       definition: "Having an obstinately uncooperative attitude.",
                       example: "The recalcitrant student refused to follow any classroom rules."),

        VocabularyWord(id: 25,
                       word: "Truculent",
                       partOfSpeech: "adjective",
                       definition: "Eager or quick to argue or fight; aggressively defiant.",
                       example: "His truculent manner made negotiations very difficult."),

        VocabularyWord(id: 26,
                       word: "Zealous",
                       partOfSpeech: "adjective",
                       definition: "Having or showing great energy or enthusiasm in pursuit of a cause.",
                       example: "She was a zealous advocate for environmental reform."),

        VocabularyWord(id: 27,
                       word: "Insipid",
                       partOfSpeech: "adjective",
                       definition: "Lacking flavor, vigor, or interest; dull.",
                       example: "The film had an insipid plot that left the audience unmoved."),

        VocabularyWord(id: 28,
                       word: "Verbose",
                       partOfSpeech: "adjective",
                       definition: "Using or expressed in more words than are needed.",
                       example: "His verbose emails could have been condensed into a single sentence."),

        VocabularyWord(id: 29,
                       word: "Sycophant",
                       partOfSpeech: "noun",
                       definition: "A person who acts obsequiously toward someone important in order to gain advantage.",
                       example: "Every meeting, the sycophant praised the boss's most mediocre ideas."),

        VocabularyWord(id: 30,
                       word: "Pontificate",
                       partOfSpeech: "verb",
                       definition: "To express one's opinions in a pompous and dogmatic way.",
                       example: "He loved to pontificate about topics he barely understood.")
    ]

    // ---------------------------------------------------------
    // MARK: - Word of the Day
    // Uses the day-of-year (1–365) as an index, wrapping around
    // if the word list is shorter than 365 entries.
    // ---------------------------------------------------------
    static var wordOfTheDay: VocabularyWord {
        let calendar = Calendar.current
        // ordinality(of:in:for:) returns nil only for invalid combos — default to 1.
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % words.count
        return words[index]
    }
}
