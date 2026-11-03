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
    var excerpt: String { body.components(separatedBy: "\n\n").first ?? body }
}

struct PrototypeState {
    var notes: [SampleNote] = [
        SampleNote(id: UUID(), body: "Some ideas need a little room.\n\nI used to think a good note was a finished thought. Now I think it is a place to return to. A sentence, a question, something noticed on the way home.\n\nWhat if we leave the edges open? Give an idea enough space to meet another one. Let the connection arrive before the conclusion.\n\nToday, I’m keeping the unfinished things.", author: "You", tags: ["Writing", "Ideas"], isOwned: true, isPublic: false, date: "Today"),
        SampleNote(id: UUID(), body: "A small ritual for noticing.\n\nBefore opening another tab, write down the question you are carrying. One line is enough.\n\nIt changes how you read. You begin to find your own thread through other people’s thinking.", author: "You", tags: ["Ideas"], isOwned: true, isPublic: false, date: "Yesterday"),
        SampleNote(id: UUID(), body: "Attention is a kind of generosity.\n\nThere is a different way to move through the world: a little slower, with a little more curiosity.\n\nA shadow crossing a page. A conversation that stays with you. An idea that only becomes clear when you share it.\n\nThe things we notice become the things we care about.", author: "Mira Chen", tags: ["Culture", "Attention"], isOwned: false, isPublic: true, date: "2 days ago"),
        SampleNote(id: UUID(), body: "A garden is never quite finished.\n\nPerhaps knowledge works the same way. We keep what is growing, make room for what is next, and learn to see a path where there wasn’t one before.\n\nThinking together is a way of tending it.", author: "Leo Park", tags: ["Design", "Connections"], isOwned: false, isPublic: true, date: "Last week"),
        SampleNote(id: UUID(), body: "Leave a question in the margin.\n\nThe best part of a book is sometimes the thought it interrupts. A sentence sends you back to something you had almost forgotten.\n\nWrite that down before you turn the page. Your response belongs beside the words that started it.", author: "Nia Bell", tags: ["Reading", "Ideas"], isOwned: false, isPublic: true, date: "Yesterday"),
        SampleNote(id: UUID(), body: "A walk can be a way of thinking.\n\nTake the longer street. Notice where the light lands. A problem that felt fixed at your desk can change shape when the scenery moves.\n\nYou do not have to solve it before you return. Bringing back a better question is enough.", author: "Alex Rivers", tags: ["Attention", "Everyday"], isOwned: false, isPublic: true, date: "3 days ago"),
        SampleNote(id: UUID(), body: "Good conversations leave room.\n\nSomeone offers half an idea. Someone else hears the part that is missing. Neither could have arrived there alone.\n\nPerhaps sharing unfinished work is a small act of trust. It lets another person help you see.", author: "Sofia Lane", tags: ["Connections", "Writing"], isOwned: false, isPublic: true, date: "4 days ago"),
        SampleNote(id: UUID(), body: "Keep the things that make you look twice.\n\nA drawing, a phrase, a pattern in an ordinary afternoon. Their meaning may arrive later, when another piece finds its place.\n\nA collection can be a record of attention before it becomes a map of ideas.", author: "Rowan Lee", tags: ["Design", "Culture"], isOwned: false, isPublic: true, date: "Last week")
    ]
    var query = ""
    var submittedQuery: String?
    var filter: NoteFilter = .all
    var collected: Set<UUID> = []
    init() { collected = Set(notes.filter { $0.author == "Leo Park" }.map(\.id)) }
    var searchResults: [SampleNote] {
        guard let query = submittedQuery, !query.isEmpty else { return [] }
        return notes.filter { ($0.body + " " + $0.author + " " + $0.tags.joined(separator: " ")).localizedCaseInsensitiveContains(query) }
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
