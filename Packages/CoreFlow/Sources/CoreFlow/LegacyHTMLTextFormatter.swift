import Foundation

/// The existing HTMLTextRenderer dialect, intentionally distinct from rich-card
/// Markdown/HTML previews. Call through the preview cache's background queue.
public enum LegacyHTMLTextFormatter {
    private static let tags = try! NSRegularExpression(pattern: "<[^>]+>")
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)

    public static func presentation(_ html: String) -> LibraryCardPresentation {
        var text = html
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>"] {
            text = text.replacingOccurrences(of: tag, with: "\n")
        }
        text = tags.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        // Order is observable: &amp;nbsp; stays &nbsp;, while &amp;lt; becomes <.
        for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = whitespace.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LibraryCardPresentation(
            preview: LibraryCardPreviewContent(text: text, imageSource: nil, imageAlternativeText: nil),
            blocks: [], plainText: text, gridSummary: "", accessibilityExcerpt: ""
        )
    }
}
