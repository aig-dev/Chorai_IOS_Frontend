import SwiftUI
import UIKit

/// A browse-first companion to the swipe deck. State and scrolling remain with Explore.
struct ExploreGridContent: View {
    let notes: [SampleNote]
    let collected: Set<UUID>
    let palette: Palette
    let onOpen: (SampleNote) -> Void
    let onCollect: (SampleNote) -> Void
    let onAction: (SampleNote, String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ExploreMasonryLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, spacing: 12) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                ExploreGridTile(note: note, isCollected: collected.contains(note.id), palette: palette,
                                onOpen: { onOpen(note) }, onCollect: { onCollect(note) },
                                onAction: { onAction(note, $0) })
                    .accessibilitySortPriority(Double(notes.count - index))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.grid")
    }
}

/// Places each subsequent note into the shortest column without rearranging the view hierarchy.
/// VoiceOver and keyboard navigation therefore retain the original content order.
private struct ExploreMasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private func placements(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], heights: [CGFloat], columnWidth: CGFloat) {
        let count = max(1, columns)
        let columnWidth = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var heights = Array(repeating: CGFloat.zero, count: count)
        var points: [CGPoint] = []
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            points.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            heights[column] += size.height + spacing
        }
        return (points, heights, columnWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let result = placements(width: width, subviews: subviews)
        return CGSize(width: width, height: max(0, (result.heights.max() ?? 0) - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = placements(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: result.columnWidth, height: nil))
        }
    }
}

private struct ExploreGridTile: View {
    let note: SampleNote
    let isCollected: Bool
    let palette: Palette
    let onOpen: () -> Void
    let onCollect: () -> Void
    let onAction: (String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var bodySize = 13.0
    @ScaledMetric(relativeTo: .title3) private var titleSize = 20.0
    @ScaledMetric(relativeTo: .title2) private var quoteSize = 23.0
    @ScaledMetric(relativeTo: .footnote) private var codeSize = 11.0
    @ScaledMetric(relativeTo: .caption) private var captionSize = 11.0

    private var key: String { note.sampleKey.isEmpty ? note.id.uuidString : note.sampleKey }
    private var paragraphs: [String] { note.body.components(separatedBy: "\n\n") }
    private var summary: String { paragraphs.dropFirst().first ?? "" }
    private var secondaryInk: Color { palette.ink.opacity(0.76) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                content
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .background(tileSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.rule.opacity(0.65), lineWidth: 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(ExploreTilePressStyle())
            .accessibilityLabel("\(note.contentKind.label), \(note.excerpt), by \(note.author)")
            .accessibilityHint("Opens the full note")
            .accessibilityIdentifier("prototype.grid.\(key)")
            .contextMenu { actions }

            HStack(spacing: 2) {
                Text(note.author)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCollect) {
                    Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isCollected ? palette.ink : secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollected ? "Remove \(note.excerpt) from collection" : "Collect \(note.excerpt)")
                .accessibilityValue(isCollected ? "Collected" : "Not collected")
                .accessibilityIdentifier("prototype.grid.collect.\(key)")
            }
            .padding(.leading, 3)
            .padding(.trailing, -6)
        }
        .foregroundStyle(palette.ink)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        Button("Spark", systemImage: "sparkles") { onAction("Spark") }
        Button(note.isOwned ? "Edit" : "View", systemImage: note.isOwned ? "square.and.pencil" : "doc.text") {
            if note.isOwned { onAction("Edit") } else { onOpen() }
        }
        Button(isCollected ? "Remove from collection" : "Collect", systemImage: isCollected ? "bookmark.slash" : "bookmark") { onCollect() }
        Button("Link", systemImage: "link") { onAction("Link") }
        if note.isOwned {
            Button("Share", systemImage: "square.and.arrow.up") { onAction("Share") }
        } else {
            Button("Report", systemImage: "flag") { onAction("Report") }
        }
    }

    private var tileSurface: Color {
        switch note.richContent {
        case .quote, .short: palette.accent.opacity(palette.dark ? 0.11 : 0.08)
        case .code: palette.ink.opacity(palette.dark ? 0.07 : 0.045)
        default: palette.surface
        }
    }

    @ViewBuilder private var content: some View {
        switch note.richContent {
        case .photo(let photo): photoContent(photo)
        case .essay:
            VStack(alignment: .leading, spacing: 12) {
                formatLabel("LONG READ", icon: "text.alignleft")
                title
                Text(summary)
                    .font(.system(size: bodySize, design: .serif))
                    .lineSpacing(4)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 10)
                Rectangle().fill(palette.rule).frame(width: 25, height: 1).accessibilityHidden(true)
                Text(paragraphs.dropFirst(2).first ?? "")
                    .font(.system(size: bodySize, design: .serif).italic())
                    .foregroundStyle(secondaryInk)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            }.padding(15)
        case .quote(let quote):
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "quote.opening").font(.system(size: 22)).foregroundStyle(palette.accent).accessibilityHidden(true)
                Text(quote.text)
                    .font(.system(size: quoteSize, design: .serif))
                    .tracking(-0.4)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Original sample writing").font(.system(size: captionSize)).foregroundStyle(secondaryInk)
            }.padding(16).padding(.vertical, 7)
        case .checklist(let checklist):
            VStack(alignment: .leading, spacing: 13) {
                formatLabel("FIELD NOTES", icon: "checklist")
                title
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(checklist.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.completed ? palette.accent : secondaryInk)
                                .padding(.top, 1)
                            Text(item.text).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: bodySize))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.completed ? "Recorded" : "Not recorded"): \(item.text)")
                    }
                }
                Text("Author’s checklist · \(checklist.items.filter(\.completed).count) / \(checklist.items.count)").font(.system(size: captionSize)).foregroundStyle(secondaryInk)
            }.padding(14)
        case .code(let code):
            VStack(alignment: .leading, spacing: 12) {
                formatLabel(code.language.uppercased(), icon: "chevron.left.forwardslash.chevron.right")
                title
                Rectangle().fill(palette.rule).frame(height: 0.5).accessibilityHidden(true)
                Text(code.source)
                    .font(.system(size: codeSize, design: .monospaced))
                    .lineSpacing(3)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 10)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A small code sketch").font(.system(size: captionSize)).foregroundStyle(secondaryInk)
            }.padding(14)
        case .reference(let reference):
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "text.book.closed").font(.system(size: 22)).foregroundStyle(palette.accent).accessibilityHidden(true)
                Text(reference.publication).font(.system(size: bodySize, weight: .semibold))
                Text(reference.excerpt)
                    .font(.system(size: titleSize - 2, design: .serif))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference.location)
                    Text("Fictional sample source")
                }.font(.system(size: captionSize)).foregroundStyle(secondaryInk)
            }.padding(15)
        case .comparison(let comparison):
            VStack(alignment: .leading, spacing: 13) {
                formatLabel("SIDE BY SIDE", icon: "rectangle.split.2x1")
                title
                comparisonRows(comparison)
            }.padding(14)
        case .short:
            VStack(alignment: .leading, spacing: 18) {
                Text(note.excerpt)
                    .font(.system(size: quoteSize + 1, design: .serif))
                    .tracking(-0.45)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(palette.accent).frame(width: 24, height: 1).accessibilityHidden(true)
                Text(summary).font(.system(size: bodySize)).lineSpacing(3).foregroundStyle(secondaryInk)
            }.padding(17).padding(.vertical, 9)
        case nil:
            VStack(alignment: .leading, spacing: 12) {
                title
                Text(summary).font(.system(size: bodySize)).lineSpacing(4).lineLimit(typeSize.isAccessibilitySize ? nil : 8)
            }.padding(15)
        }
    }

    private var title: some View {
        Text(note.excerpt)
            .font(.system(size: titleSize, design: .serif))
            .tracking(-0.3)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func formatLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: captionSize - 1, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(palette.accent)
    }

    private func photoContent(_ photo: RichPhoto) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                Group {
                    if let path = Bundle.main.path(forResource: photo.assetName, ofType: "png"), let image = UIImage(contentsOfFile: path) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .accessibilityLabel(photo.alternativeText)
                    } else {
                        Rectangle().fill(palette.accent.opacity(0.1))
                            .overlay(Image(systemName: "leaf").font(.largeTitle).foregroundStyle(palette.accent))
                            .accessibilityLabel(photo.alternativeText)
                    }
                }
                .frame(width: geometry.size.width, height: typeSize.isAccessibilitySize ? 230 : 185)
                .clipped()
            }
            .frame(height: typeSize.isAccessibilitySize ? 230 : 185)
            VStack(alignment: .leading, spacing: 8) {
                Text(note.excerpt)
                    .font(.system(size: titleSize - 2, design: .serif))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Generated sample image")
                    .font(.system(size: captionSize))
                    .foregroundStyle(secondaryInk)
            }.padding(12)
        }
    }

    private func comparisonRows(_ comparison: RichComparison) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Text(comparison.firstHeading).frame(maxWidth: .infinity, alignment: .leading)
                Text(comparison.secondHeading).foregroundStyle(palette.accent).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: bodySize, weight: .semibold))
            ForEach(Array(comparison.rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(palette.rule).frame(height: 0.5).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.topic).font(.system(size: captionSize)).foregroundStyle(secondaryInk)
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.first).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.second).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: bodySize))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExploreTilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.83 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
