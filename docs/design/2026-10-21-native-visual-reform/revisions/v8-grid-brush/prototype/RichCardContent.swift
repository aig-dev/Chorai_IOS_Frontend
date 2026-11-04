import SwiftUI
import UIKit

/// The card and reader share the same offline content; only the amount of prose changes.
/// Gestures and navigation belong to the enclosing Explore card.
struct RichCardContent: View {
    let note: SampleNote
    let palette: Palette
    var full: Bool = false

    @ScaledMetric(relativeTo: .title2) private var headlineSize = 24.0
    @ScaledMetric(relativeTo: .body) private var readingSize = 20.0
    @ScaledMetric(relativeTo: .body) private var compactSize = 15.0
    @ScaledMetric(relativeTo: .title) private var statementSize = 33.0
    @ScaledMetric(relativeTo: .footnote) private var codeSize = 13.0

    private var paragraphs: [String] { note.body.components(separatedBy: "\n\n") }
    private var title: String { paragraphs.first ?? "" }
    private var remainingParagraphs: [String] { Array(paragraphs.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: full ? 22 : 14) {
            switch note.richContent {
            case .photo(let photo):
                photoBlock(photo)
                heading
                proseTail(previewLines: 2)
            case .essay:
                heading
                if full {
                    proseTail()
                } else {
                    Text(remainingParagraphs.prefix(2).joined(separator: "\n\n"))
                        .font(.system(size: readingSize, design: .serif))
                        .lineSpacing(5)
                        .lineLimit(9)
                        .foregroundStyle(palette.ink.opacity(0.88))
                    Label("A longer read", systemImage: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
                }
            case .quote(let quote):
                quoteBlock(quote)
                if full { heading }
                proseTail(previewLines: 3)
            case .checklist(let checklist):
                heading
                checklistBlock(checklist)
                proseTail(previewLines: 2)
            case .code(let code):
                heading
                codeBlock(code)
                proseTail(previewLines: 2)
            case .reference(let reference):
                referenceBlock(reference)
                if full { heading }
                proseTail(previewLines: 3)
            case .comparison(let comparison):
                heading
                comparisonBlock(comparison)
                proseTail(previewLines: 3)
            case .short:
                Text(title)
                    .font(.system(size: statementSize, design: .serif))
                    .tracking(-0.6)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, full ? 4 : 20)
                Rectangle().fill(palette.accent.opacity(0.7)).frame(width: 32, height: 2)
                    .accessibilityHidden(true)
                proseTail(previewLines: 4)
            case nil:
                if full {
                    heading
                    proseTail()
                } else {
                    Text(note.body)
                        .font(.system(size: readingSize, design: .serif))
                        .lineSpacing(4)
                        .lineLimit(12)
                }
            }
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        Text(title)
            .font(.system(size: full ? headlineSize * 1.18 : headlineSize, design: .serif))
            .tracking(-0.35)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func proseTail(previewLines: Int = 3) -> some View {
        if full {
            ForEach(Array(remainingParagraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: readingSize, design: .serif))
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let paragraph = remainingParagraphs.first {
            Text(paragraph)
                .font(.system(size: compactSize))
                .lineSpacing(3)
                .foregroundStyle(palette.ink.opacity(0.78))
                .lineLimit(previewLines)
        }
    }

    private func photoBlock(_ photo: RichPhoto) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let path = Bundle.main.path(forResource: photo.assetName, ofType: "png"),
                   let image = UIImage(contentsOfFile: path) {
                    // The flexible container owns width. Aspect-fill pixels must
                    // not make a narrow card wider than its proposed content area.
                    Color.clear
                        .frame(height: full ? 230 : 146)
                        .overlay {
                            GeometryReader { geometry in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(photo.alternativeText)
                        .accessibilityAddTraits(.isImage)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "leaf").font(.title2)
                        Text(photo.alternativeText).font(.caption).multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .frame(height: full ? 230 : 146)
                    .background(palette.accent.opacity(0.09))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(photo.caption)
                .font(.caption2)
                .foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
        }
    }

    private func quoteBlock(_ quote: RichQuote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(quote.text)
                .font(.system(size: statementSize, design: .serif))
                .tracking(-0.65)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(quote.attribution)
                .font(.caption)
                .foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
        }
        .padding(.vertical, full ? 6 : 8)
    }

    private func checklistBlock(_ checklist: RichChecklist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checklist.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.completed ? palette.accent : palette.ink.opacity(0.3))
                        .font(.system(size: 18, weight: .regular))
                        .accessibilityHidden(true)
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(item.completed ? palette.ink.opacity(0.64) : palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.completed ? "Recorded" : "Not recorded"): \(item.text)")
                if index < checklist.items.count - 1 {
                    Rectangle().fill(palette.rule).frame(height: 0.5).padding(.leading, 28)
                        .accessibilityHidden(true)
                }
            }
            Text(checklist.footnote)
                .font(.caption2)
                .foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
                .padding(.top, 9)
        }
    }

    private func codeBlock(_ code: RichCode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(code.language)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent)
            Text(code.source)
                .font(.system(size: full ? codeSize * 1.12 : codeSize, design: .monospaced))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if full {
                Text(code.caption).font(.caption).foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.ink.opacity(palette.dark ? 0.055 : 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.rule, lineWidth: 0.6))
    }

    private func referenceBlock(_ reference: RichReference) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "text.book.closed").font(.title3).foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference.publication).font(.subheadline.weight(.medium))
                    Text(reference.location).font(.caption).foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
                }
            }
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 2).fill(palette.accent.opacity(0.7)).frame(width: 3)
                    .accessibilityHidden(true)
                Text(reference.excerpt)
                    .font(.system(size: full ? headlineSize : readingSize + 1, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(reference.attribution)
                .font(.caption2)
                .foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
        }
    }

    private func comparisonBlock(_ comparison: RichComparison) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text(" ").accessibilityHidden(true)
                Text(comparison.firstHeading).foregroundStyle(palette.ink)
                Text(comparison.secondHeading).foregroundStyle(palette.accent)
            }
            .font(.subheadline.weight(.semibold))
            ForEach(Array(comparison.rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(palette.rule).frame(height: 0.5).gridCellColumns(3).accessibilityHidden(true)
                GridRow(alignment: .top) {
                    Text(row.topic).font(.caption).foregroundStyle(palette.ink.opacity(palette.dark ? 0.72 : 0.90))
                    Text(row.first).font(.subheadline)
                    Text(row.second).font(.subheadline)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
