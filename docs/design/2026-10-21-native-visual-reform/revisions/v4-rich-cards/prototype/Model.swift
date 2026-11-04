import Foundation

struct ExploreDeckState {
    private(set) var cursor = 0
    private(set) var frontier = 0
    private(set) var undoCollectionID: UUID?
    var canGoBack: Bool { cursor > 0 }
    var isRevisiting: Bool { cursor < frontier }
    func currentIndex(total: Int) -> Int? { cursor >= 0 && cursor < total ? cursor : nil }
    mutating func skip(total: Int) {
        guard currentIndex(total: total) != nil else { return }
        cursor += 1
        frontier = max(frontier, cursor)
    }
    mutating func collect(noteID: UUID, collected: inout Set<UUID>, total: Int) {
        guard currentIndex(total: total) != nil else { return }
        undoCollectionID = collected.insert(noteID).inserted ? noteID : nil
        skip(total: total)
    }
    mutating func previous() { cursor = max(0, cursor - 1) }
    mutating func resume() { cursor = frontier }
    mutating func undoCollection(collected: inout Set<UUID>) {
        guard let id = undoCollectionID else { return }
        collected.remove(id)
        undoCollectionID = nil
    }
    mutating func dismissUndo() { undoCollectionID = nil }
}

enum HomeScope: String, CaseIterable { case notes = "Notes", collect = "Collect" }
enum NoteFilter: String, CaseIterable { case all = "All notes", writing = "Writing", ideas = "Ideas" }
struct SampleNote: Identifiable, Hashable {
    var id: UUID
    var body: String
    var author: String
    var tags: [String]
    var isOwned: Bool
    var isPublic: Bool
    var date: String
    var sampleKey: String = ""
    var richContent: RichNoteContent? = nil
    var contentKind: RichNoteKind { richContent?.kind ?? .plain }
    var searchableText: String { [body, author, tags.joined(separator: " "), richContent?.searchableText ?? ""].joined(separator: " ") }
    var excerpt: String { body.components(separatedBy: "\n\n").first ?? body }
}

struct PrototypeState {
    var notes: [SampleNote] = [
        SampleNote(id: UUID(), body: "Some ideas need a little room.\n\nI used to think a good note was a finished thought. Now I think it is a place to return to. A sentence, a question, something noticed on the way home.\n\nWhat if we leave the edges open? Give an idea enough space to meet another one. Let the connection arrive before the conclusion.\n\nToday, I’m keeping the unfinished things.", author: "You", tags: ["Writing", "Ideas"], isOwned: true, isPublic: false, date: "Today"),
        SampleNote(id: UUID(), body: "A small ritual for noticing.\n\nBefore opening another tab, write down the question you are carrying. One line is enough.\n\nIt changes how you read. You begin to find your own thread through other people’s thinking.", author: "You", tags: ["Ideas"], isOwned: true, isPublic: false, date: "Yesterday"),
        SampleNote(id: UUID(), body: "Attention is a kind of generosity.\n\nThere is a different way to move through the world: a little slower, with a little more curiosity.\n\nA shadow crossing a page. A conversation that stays with you. An idea that only becomes clear when you share it.\n\nThe things we notice become the things we care about.", author: "Mira Chen", tags: ["Culture", "Attention"], isOwned: false, isPublic: true, date: "2 days ago", sampleKey: "photo", richContent: .photo(RichPhoto(assetName: "reading-garden", alternativeText: "An open book on a sunlit wooden table beside a window, surrounded by green plants.", caption: "A slower afternoon · Generated sample image"))),
        SampleNote(id: UUID(), body: "A garden is never quite finished.\n\nPerhaps knowledge works the same way. We keep what is growing, make room for what is next, and learn to see a path where there wasn’t one before.\n\nThinking together is a way of tending it.\n\nLast winter I stopped sorting every note into a perfect folder. I began leaving small paths instead: a question beside an observation, a passage beside a drawing. The connections were uneven, but they were mine.\n\nA useful garden has more than one pace. There are places to pause and places to pass through. Some ideas need a season before they become useful; others give something back the day you put them in the ground.\n\nWhen a friend adds a different view, the whole arrangement changes. What looked like a dead end becomes a place to sit. A familiar sentence opens onto another person’s experience.\n\nI still make lists. I still pull weeds. But I no longer mistake a tidy system for a living one. The point is to keep something growing.", author: "Leo Park", tags: ["Design", "Connections"], isOwned: false, isPublic: true, date: "Last week", sampleKey: "essay", richContent: .essay),
        SampleNote(id: UUID(), body: "Leave a little unfinished.\n\nA line from my notebook after a long conversation. Sharing an idea before it is polished can give someone else a place to begin.", author: "Nia Bell", tags: ["Writing", "Ideas"], isOwned: false, isPublic: true, date: "Yesterday", sampleKey: "quote", richContent: .quote(RichQuote(text: "An unfinished thought is an invitation to think together.", attribution: "Nia Bell · Original sample writing"))),
        SampleNote(id: UUID(), body: "A walk without a destination.\n\nA small field guide for an ordinary afternoon. These are the observations I brought home.", author: "Alex Rivers", tags: ["Attention", "Everyday"], isOwned: false, isPublic: true, date: "3 days ago", sampleKey: "checklist", richContent: .checklist(RichChecklist(items: [RichChecklistItem(text: "Take the quieter street", completed: true), RichChecklistItem(text: "Notice one changing shadow", completed: true), RichChecklistItem(text: "Write down a sound", completed: false), RichChecklistItem(text: "Bring back a better question", completed: false)], footnote: "An author’s checklist · 2 of 4 recorded"))),
        SampleNote(id: UUID(), body: "Small code. A little more calm.\n\nA tiny reminder to keep one deliberate pause between noticing something and turning it into a task.", author: "Sofia Lane", tags: ["Code", "Ideas"], isOwned: false, isPublic: true, date: "4 days ago", sampleKey: "code", richContent: .code(RichCode(language: "Swift", source: "struct SmallRitual {\n    let question: String\n\n    var nextStep: String {\n        \"Notice one thing.\"\n    }\n}", caption: "A small Swift sketch, saved as a note"))),
        SampleNote(id: UUID(), body: "Keep the question beside the source.\n\nMy margin note: a useful reference tells me where an idea began, and leaves enough room for my own response.", author: "Rowan Lee", tags: ["Reading", "Sources"], isOwned: false, isPublic: true, date: "Last week", sampleKey: "reference", richContent: .reference(RichReference(publication: "The Margin Notebook", location: "Issue 03 · p. 12", excerpt: "A collection begins with what catches our attention. It becomes understanding when we ask why these things belong together.", attribution: "Fictional publication · Original sample excerpt"))),
        SampleNote(id: UUID(), body: "Two ways to keep an idea.\n\nNeither is the better system. I use the first when I need to find something, and the second when I want to discover something.", author: "Jules Avery", tags: ["Design", "Ideas"], isOwned: false, isPublic: true, date: "Yesterday", sampleKey: "comparison", richContent: .comparison(RichComparison(firstHeading: "A folder", secondHeading: "A garden", rows: [RichComparisonRow(topic: "Start with", first: "A category", second: "A question"), RichComparisonRow(topic: "Make room for", first: "A clear place", second: "A new connection"), RichComparisonRow(topic: "Come back to", first: "Find it again", second: "See it differently")]))),
        SampleNote(id: UUID(), body: "Maybe the detour was the point.\n\nA thought from the walk home. Keeping it here before I explain it away.", author: "Emi Santos", tags: ["Everyday", "Writing"], isOwned: false, isPublic: true, date: "Just now", sampleKey: "short", richContent: .short)
    ]
    var query = ""
    var submittedQuery: String?
    var filter: NoteFilter = .all
    var collected: Set<UUID> = []
    init() { collected = Set(notes.filter { $0.author == "Leo Park" }.map(\.id)) }
    var searchResults: [SampleNote] {
        guard let query = submittedQuery, !query.isEmpty else { return [] }
        return notes.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }
    mutating func submitSearch() { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }
    mutating func cancelSearch() { query = ""; submittedQuery = nil }
    func visibleHomeNotes(scope: HomeScope) -> [SampleNote] {
        notes.filter { note in
            (scope == .notes ? note.isOwned : collected.contains(note.id))
                && (filter == .all || note.tags.contains(filter == .writing ? "Writing" : "Ideas"))
        }
    }
    mutating func save(id: UUID, body: String, isPublic: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.isOwned }) else { return }
        notes[index].body = body
        notes[index].isPublic = isPublic
    }
    mutating func createNote() -> SampleNote {
        let note = SampleNote(id: UUID(), body: "", author: "You", tags: [], isOwned: true, isPublic: false, date: "Just now")
        notes.insert(note, at: 0)
        return note
    }
    mutating func discardEmptyDraft(id: UUID) {
        notes.removeAll { $0.id == id && $0.isOwned && $0.body.isEmpty }
    }

}
