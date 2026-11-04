import Foundation

/// Offline editorial formats. These describe content, never additional actions.
enum RichNoteKind: String, CaseIterable, Hashable {
    case plain, photo, essay, quote, checklist, code, reference, comparison, short

    var label: String {
        switch self {
        case .plain: "Note"
        case .photo: "Image note"
        case .essay: "Long read"
        case .quote: "A thought"
        case .checklist: "Field checklist"
        case .code: "Code note"
        case .reference: "Source excerpt"
        case .comparison: "Side by side"
        case .short: "Quick thought"
        }
    }
}

struct RichPhoto: Hashable {
    var assetName: String
    var alternativeText: String
    var caption: String
}
struct RichQuote: Hashable {
    var text: String
    var attribution: String
}
struct RichChecklistItem: Hashable {
    var text: String
    var completed: Bool
}
struct RichChecklist: Hashable {
    var items: [RichChecklistItem]
    var footnote: String
}
struct RichCode: Hashable {
    var language: String
    var source: String
    var caption: String
}
struct RichReference: Hashable {
    var publication: String
    var location: String
    var excerpt: String
    var attribution: String
}
struct RichComparisonRow: Hashable {
    var topic: String
    var first: String
    var second: String
}
struct RichComparison: Hashable {
    var firstHeading: String
    var secondHeading: String
    var rows: [RichComparisonRow]
}

enum RichNoteContent: Hashable {
    case photo(RichPhoto)
    case essay
    case quote(RichQuote)
    case checklist(RichChecklist)
    case code(RichCode)
    case reference(RichReference)
    case comparison(RichComparison)
    case short

    var kind: RichNoteKind {
        switch self {
        case .photo: .photo
        case .essay: .essay
        case .quote: .quote
        case .checklist: .checklist
        case .code: .code
        case .reference: .reference
        case .comparison: .comparison
        case .short: .short
        }
    }

    /// Includes structured content in the same local search as prose notes.
    var searchableText: String {
        switch self {
        case .photo(let photo): [photo.alternativeText, photo.caption].joined(separator: " ")
        case .essay, .short: ""
        case .quote(let quote): [quote.text, quote.attribution].joined(separator: " ")
        case .checklist(let checklist): (checklist.items.map(\.text) + [checklist.footnote]).joined(separator: " ")
        case .code(let code): [code.language, code.source, code.caption].joined(separator: " ")
        case .reference(let source): [source.publication, source.location, source.excerpt, source.attribution].joined(separator: " ")
        case .comparison(let comparison): ([comparison.firstHeading, comparison.secondHeading] + comparison.rows.map { [$0.topic, $0.first, $0.second].joined(separator: " ") }).joined(separator: " ")
        }
    }
}
