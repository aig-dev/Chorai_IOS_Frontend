import Foundation

public struct LibraryCardPreviewContent: Equatable, Sendable {
    public let text: String
    public let imageSource: String?
    public let imageAlternativeText: String?
    public let imageMediaRef: String?

    public init(
        text: String,
        imageSource: String?,
        imageAlternativeText: String?,
        imageMediaRef: String? = nil
    ) {
        self.text = text
        self.imageSource = imageSource
        self.imageAlternativeText = imageAlternativeText
        self.imageMediaRef = imageMediaRef
    }
}

public struct LibraryCardPreviewBlock: Equatable, Sendable {
    public let kind: String
    public let text: String
    public let checked: Bool
}

public struct LibraryCardPresentation: Equatable, Sendable {
    public let preview: LibraryCardPreviewContent
    public let blocks: [LibraryCardPreviewBlock]
    public let plainText: String
    public let gridSummary: String
    public let accessibilityExcerpt: String

    var estimatedBytes: Int {
        let textBytes = preview.text.utf8.count + plainText.utf8.count + gridSummary.utf8.count + accessibilityExcerpt.utf8.count
        let imageBytes = [preview.imageSource, preview.imageAlternativeText, preview.imageMediaRef]
            .compactMap { $0 }.reduce(0) { $0 + $1.utf8.count }
        let blockBytes = blocks.reduce(0) { $0 + $1.kind.utf8.count + $1.text.utf8.count }
        return textBytes + imageBytes + blockBytes
    }
}

public enum LibraryCardPreviewParser {
    private static let markdownImageExpression = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(\s*(?:<([^>\r\n]+)>|([^\s\)]+))(?:\s+(?:\"[^\"]*\"|'[^']*'|\([^\)]*\)))?\s*\)"#
    )
    private static let imageTagExpression = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let imageSourceAttributeExpression = try! NSRegularExpression(
        pattern: #"\bsrc\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )
    private static let imageAltAttributeExpression = try! NSRegularExpression(
        pattern: #"\balt\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )
    private static let breakTagExpression = try! NSRegularExpression(
        pattern: #"(?i)<br\s*/?>"#
    )
    private static let closingBlockTagExpression = try! NSRegularExpression(
        pattern: #"(?i)</(?:p|div|li|h[1-6]|blockquote)>"#
    )
    private static let htmlTagExpression = try! NSRegularExpression(
        pattern: #"<[^>]+>"#
    )
    private static let horizontalWhitespaceExpression = try! NSRegularExpression(
        pattern: #"[\t ]+"#
    )

    public static func parse(
        content: String,
        contentJSON: String? = nil,
        allowsLocalImages: Bool = false
    ) -> LibraryCardPreviewContent {
        read(content: content, contentJSON: contentJSON, allowsLocalImages: allowsLocalImages, includeBlocks: false).preview
    }

    public static func presentation(
        content: String,
        contentJSON: String? = nil,
        allowsLocalImages: Bool = false
    ) -> LibraryCardPresentation {
        let (preview, blocks) = read(
            content: content, contentJSON: contentJSON, allowsLocalImages: allowsLocalImages, includeBlocks: true
        )
        let excerpt = preview.text.split(maxSplits: 100, whereSeparator: \.isWhitespace)
            .prefix(100).joined(separator: " ").prefix(100)
        return LibraryCardPresentation(
            preview: preview,
            blocks: blocks,
            plainText: makePlainText(content),
            gridSummary: blocks.map(\.text).joined(separator: "\n\n"),
            accessibilityExcerpt: String(excerpt)
        )
    }

    private static func makePlainText(_ source: String) -> String {
        let decoded = source
            .replacingOccurrences(
                of: "(?is)<(script|style)[^>]*>.*?</\\1>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)<br\\s*/?>|</p\\s*>|</div\\s*>|</li\\s*>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")

        let preview = decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview
    }

    private static func read(
        content: String,
        contentJSON: String?,
        allowsLocalImages: Bool,
        includeBlocks: Bool
    ) -> (preview: LibraryCardPreviewContent, blocks: [LibraryCardPreviewBlock]) {
        if let blocks = structuredBlocks(from: contentJSON), !blocks.isEmpty {
            let flattened = flatten(blocks)
            let image = firstStructuredImage(in: flattened, allowsLocalImages: allowsLocalImages)
            var textByBlock: [String] = []
            var displayBlocks: [LibraryCardPreviewBlock] = []
            for block in flattened {
                let kind = (block["type"] as? String ?? "paragraph").lowercased()
                guard let rawText = structuredText(from: block, kind: kind) else { continue }
                textByBlock.append(rawText)

                if includeBlocks {
                    let text = normalizedPlainText(rawText)
                    if !text.isEmpty {
                        let checked = (block["props"] as? [String: Any])?["checked"] as? Bool ?? false
                        displayBlocks.append(LibraryCardPreviewBlock(kind: kind, text: text, checked: checked))
                    }
                }
            }
            let text = normalizedPlainText(textByBlock.joined(separator: "\n"))

            if image != nil || !text.isEmpty {
                let preview = LibraryCardPreviewContent(
                    text: text,
                    imageSource: image?.source,
                    imageAlternativeText: image?.alternativeText,
                    imageMediaRef: image?.mediaRef
                )
                return (preview, resolvedBlocks(displayBlocks, fallback: text, includeBlocks: includeBlocks))
            }
        }

        let preview = fallbackPreview(from: content)
        return (preview, resolvedBlocks([], fallback: preview.text, includeBlocks: includeBlocks))
    }

    private static func resolvedBlocks(
        _ blocks: [LibraryCardPreviewBlock],
        fallback text: String,
        includeBlocks: Bool
    ) -> [LibraryCardPreviewBlock] {
        guard includeBlocks, blocks.isEmpty, !text.isEmpty else { return blocks }
        return [LibraryCardPreviewBlock(kind: "paragraph", text: text, checked: false)]
    }

    private struct ImageCandidate {
        let location: Int
        let source: String?
        let alternativeText: String?
        var mediaRef: String? = nil
    }

    private static func structuredBlocks(from value: String?) -> [[String: Any]]? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var parsed: Any = value
        for _ in 0..<2 {
            guard let encoded = parsed as? String else { break }
            guard let data = encoded.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(
                      with: data,
                      options: [.fragmentsAllowed]
                  ) else {
                return nil
            }
            parsed = decoded
        }

        let values: [Any]
        if let array = parsed as? [Any] {
            values = array
        } else if let envelope = parsed as? [String: Any],
                  let blocks = envelope["blocks"] as? [Any] {
            values = blocks
        } else {
            return nil
        }

        return values.compactMap { $0 as? [String: Any] }
    }

    private static func flatten(
        _ blocks: [[String: Any]]
    ) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for block in blocks {
            result.append(block)
            if let children = block["children"] as? [Any] {
                result.append(
                    contentsOf: flatten(
                        children.compactMap { $0 as? [String: Any] }
                    )
                )
            }
        }
        return result
    }

    private static func firstStructuredImage(
        in blocks: [[String: Any]],
        allowsLocalImages: Bool
    ) -> ImageCandidate? {
        for (index, block) in blocks.enumerated() {
            guard (block["type"] as? String)?.lowercased() == "image",
                  let props = block["props"] as? [String: Any] else {
                continue
            }

            let sources = [props["url"], props["src"]]
                .compactMap { $0 as? String }
            let source = sources.first { value in
                if isAllowedImageSource(value) { return true }
                guard allowsLocalImages, let url = URL(string: value),
                      url.scheme == NoteAttachmentFiles.previewScheme else { return false }
                return (try? NoteAttachmentFiles.previewUploadID(url)) != nil
            }
            let mediaRef = allowsLocalImages
                ? (props["mediaRef"] as? String ?? props["media_ref"] as? String)?.trimmedNonEmpty
                : nil
            guard source != nil || mediaRef != nil else {
                continue
            }

            let alternativeText = [
                props["caption"], props["name"], props["alt"]
            ]
                .compactMap { ($0 as? String)?.trimmedNonEmpty }
                .first

            return ImageCandidate(
                location: index,
                source: source?.trimmingCharacters(in: .whitespacesAndNewlines),
                alternativeText: alternativeText,
                mediaRef: mediaRef
            )
        }
        return nil
    }

    private static func structuredText(
        from block: [String: Any],
        kind: String
    ) -> String? {
        guard kind != "image" else { return nil }

        if kind == "mindmap",
           let props = block["props"] as? [String: Any],
           let fallback = (props["fallbackText"] as? String)?.trimmedNonEmpty {
            return fallback
        }

        return inlineText(from: block["content"])?.trimmedNonEmpty
    }

    private static func inlineText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let values = value as? [Any] {
            let text = values.compactMap(inlineText).joined()
            return text.isEmpty ? nil : text
        }
        guard let object = value as? [String: Any] else { return nil }
        if let text = object["text"] as? String {
            return text
        }
        return inlineText(from: object["content"])
    }

    private static func fallbackPreview(
        from content: String
    ) -> LibraryCardPreviewContent {
        let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
        var candidates: [ImageCandidate] = []

        for match in markdownImageExpression.matches(
            in: content,
            range: fullRange
        ) {
            guard let source = firstCapture(
                in: content,
                match: match,
                groups: [2, 3]
            ), isAllowedImageSource(source) else {
                continue
            }
            candidates.append(
                ImageCandidate(
                    location: match.range.location,
                    source: source.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    alternativeText: firstCapture(
                        in: content,
                        match: match,
                        groups: [1]
                    )?.trimmedNonEmpty
                )
            )
        }

        for match in imageTagExpression.matches(in: content, range: fullRange) {
            guard let tagRange = Range(match.range, in: content) else {
                continue
            }
            let tag = String(content[tagRange])
            guard let source = htmlAttribute("src", in: tag),
                  isAllowedImageSource(source) else {
                continue
            }
            candidates.append(
                ImageCandidate(
                    location: match.range.location,
                    source: source.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    alternativeText: htmlAttribute("alt", in: tag)?
                        .trimmedNonEmpty
                )
            )
        }

        var text = markdownImageExpression.stringByReplacingMatches(
            in: content,
            range: NSRange(content.startIndex..<content.endIndex, in: content),
            withTemplate: ""
        )
        text = imageTagExpression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        )

        let image = candidates.min { $0.location < $1.location }
        return LibraryCardPreviewContent(
            text: normalizedPlainText(text),
            imageSource: image?.source,
            imageAlternativeText: image?.alternativeText
        )
    }

    private static func firstCapture(
        in value: String,
        match: NSTextCheckingResult,
        groups: [Int]
    ) -> String? {
        for group in groups where group < match.numberOfRanges {
            let capture = match.range(at: group)
            guard capture.location != NSNotFound,
                  let range = Range(capture, in: value) else {
                continue
            }
            return String(value[range])
        }
        return nil
    }

    private static func htmlAttribute(
        _ name: String,
        in tag: String
    ) -> String? {
        let expression = name == "src"
            ? imageSourceAttributeExpression
            : imageAltAttributeExpression
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range) else {
            return nil
        }
        return firstCapture(in: tag, match: match, groups: [1, 2, 3])
    }

    private static func isAllowedImageSource(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains(where: { $0.isNewline || $0.isASCIIControl }) else {
            return false
        }
        if value.hasPrefix("/") {
            return !value.hasPrefix("//")
        }
        if value.hasPrefix("chorai-assets/") {
            return true
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return true
    }

    private static func normalizedPlainText(_ rawValue: String) -> String {
        var value = rawValue
        value = replacing(
            breakTagExpression,
            in: value,
            with: "\n"
        )
        value = replacing(
            closingBlockTagExpression,
            in: value,
            with: "\n"
        )
        value = replacing(htmlTagExpression, in: value, with: "")
        value = decodeHTMLEntities(value)

        return value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                replacing(
                    horizontalWhitespaceExpression,
                    in: String(line),
                    with: " "
                )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                !$0.isEmpty
                    && !$0.matchesArtifactLine
                    && !$0.matchesInternalDocumentReference
            }
            .joined(separator: "\n")
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
        ].reduce(value) { result, pair in
            result.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private static func replacing(
        _ expression: NSRegularExpression,
        in value: String,
        with replacement: String
    ) -> String {
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }

}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var matchesArtifactLine: Bool {
        lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init) == ["default", "left", "default"]
    }

    var matchesInternalDocumentReference: Bool {
        lowercased().hasPrefix("doc://note/hash/")
    }
}
