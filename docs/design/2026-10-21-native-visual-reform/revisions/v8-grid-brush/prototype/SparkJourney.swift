import SwiftUI

/// A deterministic, offline walk through the existing Spark journey.
/// Collections use the prototype's in-memory state; no service or persistence is used.
struct SparkJourney: View {
    @Binding var state: PrototypeState
    let source: SampleNote
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @State private var nodes: [SparkJourneyNode]
    @State private var activeNode: Int
    @State private var phase: SparkJourneyPhase
    @State private var hasResults: Bool
    @State private var pending: SparkJourneyPending = .initial
    @State private var path: [SparkJourneyReaderRoute]
    @State private var liked: Set<UUID> = []
    @State private var author: SampleNote?
    @State private var statusMessage: String?
    @State private var initialCollectionApplied = false
    private let startsCollected: Bool

    init(state: Binding<PrototypeState>, source: SampleNote, initialStep: String = "results") {
        _state = state
        self.source = source
        let first = SparkJourneyNode(id: 0, source: source,
                                     results: Self.sampleResults(in: state.wrappedValue.notes, excluding: source.id))
        var initialNodes = [first]
        if initialStep == "deeper", let nextSource = first.results.first {
            initialNodes.append(SparkJourneyNode(id: 1, source: nextSource,
                results: Self.sampleResults(in: state.wrappedValue.notes, excluding: nextSource.id, offset: 1)))
        }
        _nodes = State(initialValue: initialNodes)
        _activeNode = State(initialValue: initialNodes.count - 1)
        _phase = State(initialValue: SparkJourneyPhase(rawValue: initialStep) ?? .results)
        _hasResults = State(initialValue: initialStep != "loading" && initialStep != "empty")
        _path = State(initialValue: initialStep == "reader" ? first.results.prefix(1).map {
            SparkJourneyReaderRoute(note: $0, isSource: false)
        } : [])
        startsCollected = initialStep == "collected"
    }

    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    private var currentNode: SparkJourneyNode { nodes[activeNode] }
    private var result: SampleNote? {
        currentNode.results.indices.contains(currentNode.selectedIndex)
            ? currentNode.results[currentNode.selectedIndex] : nil
    }
    private var canDeepen: Bool { (phase == .results || phase == .error) && result != nil }
    private var secondaryInk: Color { palette.ink.opacity(palette.dark ? 0.75 : 0.78) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chainRail
                    sourceStrip
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles").foregroundStyle(palette.accent)
                        Text("Sample results · no AI request")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryInk)
                    .accessibilityIdentifier("journey.spark.demo")

                    if phase == .loading { loadingPanel }
                    if phase == .error { errorNotice }
                    if phase == .limit { limitNotice }

                    if hasResults, let result {
                        resultsHeader
                        resultCard(result)
                        resultNavigation
                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(secondaryInk)
                                .accessibilityIdentifier("journey.spark.feedback")
                        }
                    } else if phase == .empty {
                        emptyPanel
                    } else if phase == .loading {
                        skeleton
                    }

                    Text("Collections stay in this prototype session. Nothing is sent to your account.")
                        .font(.caption)
                        .foregroundStyle(secondaryInk)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.ink)
            .safeAreaInset(edge: .bottom) {
                if hasResults, let result { continueBar(result) }
            }
            .navigationTitle("Spark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("journey.spark.close")
                }
                ToolbarItem(placement: .topBarTrailing) { previewMenu }
            }
            .navigationDestination(for: SparkJourneyReaderRoute.self) { route in
                reader(route)
            }
        }
        .tint(palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $author) { note in authorSheet(note) }
        .onAppear {
            guard !initialCollectionApplied else { return }
            initialCollectionApplied = true
            if startsCollected, let result, !result.isOwned {
                state.collected.insert(result.id)
                statusMessage = "Collected in this sample session."
            }
        }
    }

    private var previewMenu: some View {
        Menu {
            Section("Preview state · offline samples") {
                Button("Results", systemImage: "rectangle.stack") { preview("results") }
                Button("Loading", systemImage: "hourglass") { preview("loading") }
                Button("Deeper Spark", systemImage: "sparkles") { preview("deeper") }
                Button("More results failed", systemImage: "wifi.exclamationmark") { preview("error") }
                Button("Empty result", systemImage: "tray") { preview("empty") }
                Button("Depth limit", systemImage: "hand.raised") { preview("limit") }
                Button("Read result", systemImage: "book") { preview("reader") }
                Button("Collected", systemImage: "bookmark.fill") { preview("collected") }
            }
        } label: {
            Label("Preview state", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.medium))
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Preview state")
        .accessibilityIdentifier("journey.spark.state")
    }

    private var chainRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button {
                    openReader(source, isSource: true)
                } label: {
                    Image(systemName: "doc.text")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Read original source")
                .accessibilityIdentifier("journey.spark.original")

                ForEach(nodes) { node in
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryInk)
                        .accessibilityHidden(true)
                    Button {
                        selectNode(node.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(node.id + 1)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Text(node.id == 0 ? "First Spark" : "Deeper")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .foregroundStyle(activeNode == node.id ? palette.onTint : palette.ink)
                        .background(activeNode == node.id ? palette.ink : palette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(phase == .loading)
                    .accessibilityLabel("Spark \(node.id + 1), \(node.source.excerpt)")
                    .accessibilityValue(activeNode == node.id ? "Current step" : "Previous result")
                    .accessibilityIdentifier("journey.spark.node.\(node.id + 1)")
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityIdentifier("journey.spark.chain")
    }

    private var sourceStrip: some View {
        Button {
            openReader(currentNode.source, isSource: true)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.accent)
                    .frame(width: 3, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("FROM \(currentNode.source.isOwned ? "YOUR NOTE" : currentNode.source.author.uppercased())")
                        .font(.caption2.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(secondaryInk)
                    Text(currentNode.source.excerpt)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read source note, \(currentNode.source.excerpt)")
        .accessibilityIdentifier("journey.spark.source")
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(activeNode == 0 ? "Related ideas" : "A little further")
                .font(.title3.weight(.semibold))
            Spacer()
            Text("\(currentNode.selectedIndex + 1) of \(currentNode.results.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondaryInk)
        }
        .accessibilityIdentifier("journey.spark.results")
    }

    private func resultCard(_ note: SampleNote) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { author = note } label: {
                    HStack(spacing: 10) {
                        avatar(note.author, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.author).font(.subheadline.weight(.semibold))
                            Text(note.isOwned ? "Your note · local sample" : "Sample author · \(note.date)")
                                .font(.caption).foregroundStyle(secondaryInk)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View sample author, \(note.author)")
                Spacer(minLength: 8)
                Text(bucketLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(palette.accent.opacity(0.09), in: Capsule())
            }

            Text(note.body)
                .font(.system(.title3, design: .serif))
                .lineSpacing(5)
                .lineLimit(9)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openReader(note, isSource: false)
            } label: {
                Label("Read full note", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(phase == .loading)
            .accessibilityIdentifier("journey.spark.reader")

            Divider().overlay(palette.rule)
            HStack(spacing: 12) {
                if !note.isOwned { collectButton(note) }
                else {
                    Label("Your note", systemImage: "person.crop.circle")
                        .font(.subheadline).foregroundStyle(secondaryInk)
                        .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
                Button { toggleLike(note) } label: {
                    Label("\(18 + (liked.contains(note.id) ? 1 : 0))", systemImage: liked.contains(note.id) ? "heart.fill" : "heart")
                        .font(.subheadline)
                        .frame(minWidth: 52, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(phase == .loading)
                .accessibilityLabel(liked.contains(note.id) ? "Unlike sample note" : "Like sample note")
                .accessibilityIdentifier("journey.spark.like")
            }

        }
        .padding(20)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(palette.rule, lineWidth: 1))
        .shadow(color: .black.opacity(palette.dark ? 0.12 : 0.035), radius: 16, x: 0, y: 8)
        .accessibilityIdentifier("journey.spark.card")
    }

    private func continueBar(_ note: SampleNote) -> some View {
        Button {
            beginDeeper(note)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                Text("Continue Spark").fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(palette.onTint)
        }
        .buttonStyle(.glassProminent)
        .tint(palette.ink)
        .disabled(!canDeepen)
        .accessibilityHint("Shows a local loading sample, then a sample deeper result. No AI request.")
        .accessibilityIdentifier("journey.spark.deepen")
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var bucketLabel: String {
        switch currentNode.selectedIndex % 3 {
        case 1: "Another angle"
        case 2: "Keyword"
        default: "Related"
        }
    }

    private var resultNavigation: some View {
        HStack(spacing: 12) {
            Button {
                nodes[activeNode].selectedIndex -= 1
                statusMessage = nil
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .disabled(currentNode.selectedIndex == 0 || phase == .loading)
            .accessibilityIdentifier("journey.spark.previous")
            Spacer()
            Button {
                nodes[activeNode].selectedIndex += 1
                statusMessage = nil
            } label: {
                Label("Next idea", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 44)
            }
            .disabled(currentNode.selectedIndex + 1 >= currentNode.results.count || phase == .loading)
            .accessibilityIdentifier("journey.spark.next")
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.plain)
    }

    private var loadingPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(pending == .deeper ? "Following this thread" : "Finding related ideas", systemImage: "sparkles")
                .font(.headline).foregroundStyle(palette.accent)
            Text("Loading-state sample. No AI request is running.")
                .font(.footnote).foregroundStyle(secondaryInk)
            Button {
                showSampleResult()
            } label: {
                Label("Show sample result", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("journey.spark.show-result")
            if hasResults {
                Button("Keep current results") { phase = .results; pending = .initial }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("journey.spark.keep-results")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("journey.spark.loading")
    }

    private var errorNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("More results paused", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text("The sample request failed. Your current ideas are still here.")
                .font(.footnote).foregroundStyle(secondaryInk)
            Button {
                pending = .more
                phase = .loading
            } label: {
                Label("Retry sample", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("journey.spark.retry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("journey.spark.error")
    }

    private var limitNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("This Spark has reached its limit.", systemImage: "hand.raised")
                .font(.headline)
            Text("You can still read, collect, or return to an earlier step. This is a sample limit state.")
                .font(.footnote).foregroundStyle(secondaryInk)
            if activeNode > 0 {
                Button("Return to previous Spark") { selectNode(activeNode - 1) }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("journey.spark.limit")
    }

    private var emptyPanel: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 38, weight: .light)).foregroundStyle(palette.accent)
            Text("No new thread").font(.system(.title2, design: .serif))
            Text("There are no results in this sample. Your source note is still here.")
                .font(.body).foregroundStyle(secondaryInk).multilineTextAlignment(.center)
            Button { openReader(currentNode.source, isSource: true) } label: {
                Label("Return to source", systemImage: "doc.text")
                    .frame(minHeight: 44).padding(.horizontal, 12)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 18).padding(.vertical, 45)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("journey.spark.empty")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Circle().fill(palette.rule).frame(width: 36, height: 36)
                RoundedRectangle(cornerRadius: 5).fill(palette.rule).frame(width: 120, height: 12)
            }
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 5).fill(palette.rule)
                    .frame(maxWidth: index == 3 ? 160 : .infinity).frame(height: 14)
            }
            Spacer(minLength: 22)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 26))
        .accessibilityHidden(true)
    }

    private func collectButton(_ note: SampleNote) -> some View {
        Button { toggleCollect(note) } label: {
            Label(state.collected.contains(note.id) ? "Collected" : "Collect",
                  systemImage: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(phase == .loading)
        .accessibilityValue(state.collected.contains(note.id) ? "Collected in prototype session" : "Not collected")
        .accessibilityIdentifier("journey.spark.collect")
    }

    private func reader(_ route: SparkJourneyReaderRoute) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(route.isSource ? "SOURCE NOTE" : "SPARK RESULT")
                    .font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(palette.accent)
                HStack(spacing: 12) {
                    avatar(route.note.author, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.note.author).font(.headline)
                        Text(route.note.isOwned ? "Your note · local sample" : "Sample author · \(route.note.date)")
                            .font(.caption).foregroundStyle(secondaryInk)
                    }
                }
                Text(route.note.body)
                    .font(.system(.title3, design: .serif)).lineSpacing(8)
                    .textSelection(.enabled)
                if let rich = route.note.richContent {
                    Text(rich.searchableText)
                        .font(.system(.body, design: .serif)).lineSpacing(6)
                        .foregroundStyle(secondaryInk).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    ForEach(route.note.tags, id: \.self) { tag in
                        Text(tag).font(.caption).foregroundStyle(secondaryInk)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(palette.rule.opacity(0.5), in: Capsule())
                    }
                }
                Divider()
                if !route.note.isOwned { collectButton(route.note) }
                Text("Sample results · no AI request. Collection changes last for this prototype session.")
                    .font(.caption).foregroundStyle(secondaryInk)
            }
            .padding(26)
        }
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .navigationTitle(route.isSource ? "Source note" : "Read")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("journey.spark.reader.screen")
    }

    private func avatar(_ name: String, size: CGFloat) -> some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .frame(width: size, height: size)
            .background(palette.ink.opacity(0.09), in: Circle())
            .accessibilityHidden(true)
    }

    private func authorSheet(_ note: SampleNote) -> some View {
        NavigationStack {
            VStack(spacing: 18) {
                avatar(note.author, size: 70)
                Text(note.author).font(.title2.weight(.semibold))
                Text(note.isOwned ? "Your local sample notes" : "Collecting questions, noticing connections.")
                    .font(.system(.body, design: .serif)).multilineTextAlignment(.center)
                Text("Sample author · no live profile or follow request")
                    .font(.footnote).foregroundStyle(secondaryInk).multilineTextAlignment(.center)
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background).foregroundStyle(palette.ink)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { author = nil } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func toggleCollect(_ note: SampleNote) {
        guard !note.isOwned else { return }
        if state.collected.contains(note.id) {
            state.collected.remove(note.id)
            statusMessage = "Removed from this sample collection."
        } else {
            state.collected.insert(note.id)
            statusMessage = "Collected in this sample session."
        }
    }

    private func toggleLike(_ note: SampleNote) {
        if liked.contains(note.id) { liked.remove(note.id) } else { liked.insert(note.id) }
        statusMessage = "Like changed in this journey only. No request was sent."
    }

    private func openReader(_ note: SampleNote, isSource: Bool) {
        path.append(SparkJourneyReaderRoute(note: note, isSource: isSource))
    }

    private func beginDeeper(_ note: SampleNote) {
        guard canDeepen else { return }
        pending = .deeper
        phase = .loading
        statusMessage = nil
    }

    private func showSampleResult() {
        if pending == .deeper, let result {
            let node = SparkJourneyNode(id: nodes.count, source: result,
                results: Self.sampleResults(in: state.notes, excluding: result.id, offset: nodes.count))
            nodes.append(node)
            activeNode = node.id
        } else if pending == .more {
            let extras = state.notes.filter { note in
                note.id != currentNode.source.id && !currentNode.results.contains(where: { $0.id == note.id })
            }
            nodes[activeNode].results.append(contentsOf: extras.prefix(2))
            statusMessage = "More sample ideas added. Your current card stayed in place."
        }
        hasResults = true
        phase = .results
        pending = .initial
    }

    private func selectNode(_ index: Int) {
        guard nodes.indices.contains(index), phase != .loading else { return }
        activeNode = index
        phase = .results
        hasResults = true
        pending = .initial
        statusMessage = nil
    }

    private func preview(_ step: String) {
        path.removeAll()
        statusMessage = nil
        phase = SparkJourneyPhase(rawValue: step) ?? .results
        hasResults = step != "loading" && step != "empty"
        pending = .initial
        if step == "deeper", let result {
            let node = SparkJourneyNode(id: nodes.count, source: result,
                results: Self.sampleResults(in: state.notes, excluding: result.id, offset: nodes.count))
            nodes.append(node)
            activeNode = node.id
        } else if step == "reader", let result {
            openReader(result, isSource: false)
        } else if step == "collected", let result, !result.isOwned {
            state.collected.insert(result.id)
            statusMessage = "Collected in this sample session."
        }
    }

    private static func sampleResults(in notes: [SampleNote], excluding sourceID: UUID, offset: Int = 0) -> [SampleNote] {
        let keys = ["quote", "comparison", "reference", "essay", "short", "checklist", "code", "photo"]
        let ordered = keys.compactMap { key in notes.first { $0.sampleKey == key && $0.id != sourceID } }
        guard !ordered.isEmpty else { return notes.filter { $0.id != sourceID } }
        let rotation = offset % ordered.count
        var selected = Array((Array(ordered.dropFirst(rotation)) + Array(ordered.prefix(rotation))).prefix(3))
        if let own = notes.first(where: { $0.isOwned && $0.id != sourceID }) { selected.append(own) }
        return selected
    }
}

private enum SparkJourneyPhase: String { case results, loading, error, empty, limit }
private enum SparkJourneyPending { case initial, deeper, more }
private struct SparkJourneyNode: Identifiable {
    let id: Int
    let source: SampleNote
    var results: [SampleNote]
    var selectedIndex = 0
}
private struct SparkJourneyReaderRoute: Hashable {
    let note: SampleNote
    let isSource: Bool
}
