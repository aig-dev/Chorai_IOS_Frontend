import SwiftUI
import UIKit

/// Isolated V9 design study. All changes stay in this in-memory sample session.
struct ReviewV9Root: View {
    @State private var state = PrototypeState()
    @State private var appearance: String
    @State private var theme = PrototypeTheme.forestGold
    @State private var tab = 0
    @State private var legacy = false
    private let initialEditor: Bool

    init() {
        let screen = ReviewV9Launch.value("--screen") ?? "explore"
        _appearance = State(initialValue: ReviewV9Launch.value("--appearance") ?? "system")
        _tab = State(initialValue: screen == "home" || screen == "editor" ? 1 : 0)
        initialEditor = screen == "editor"
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Explore", systemImage: "safari", value: 0) {
                ReviewV9Explore(state: $state, appearance: $appearance, openLegacy: { legacy = true })
            }
            Tab("Home", systemImage: "square.stack", value: 1) {
                HomePrototype(state: $state, appearance: $appearance, opensEditor: initialEditor)
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: 2) {
                NavigationStack {
                    ContentUnavailableView("Local design sample", systemImage: "bubble.left.and.bubble.right", description: Text("No conversations or messages are sent from this prototype."))
                        .navigationTitle("Chat").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .tint(theme.dynamicTint)
        .environment(\.prototypeTheme, theme)
        .environment(\.prototypeThemeSelection, $theme)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .sheet(isPresented: $legacy) { JourneyEntryPoint() }
    }
}

private enum ReviewV9Launch {
    static func value(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

private struct ReviewV9Explore: View {
    @Binding var state: PrototypeState
    @Binding var appearance: String
    let openLegacy: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var cursor = 0
    @State private var frontier = 0
    @State private var drag: CGFloat = 0
    @State private var crossedThreshold = false
    @State private var dismissing = false
    @State private var feedback = 0
    @State private var history = false
    @State private var reader: SampleNote?
    @State private var action: NoteActionRequest?
    @State private var author: SampleNote?
    @State private var grid = false
    @State private var search = false
    @State private var searchQuery = ""
    @State private var searchSelection: SampleNote?
    @State private var launched = false
    @State private var frozen = ReviewV9Launch.value("--state") ?? "rest"
    @State private var lastCollected: UUID?
    @State private var liked: Set<UUID> = []
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var notes: [SampleNote] { state.notes.filter { !$0.isOwned } }
    private var current: SampleNote? { notes.indices.contains(cursor) ? notes[cursor] : nil }
    private var revisiting: Bool { cursor < frontier }
    private var visualDrag: CGFloat { frozen == "skip" ? -88 : frozen == "collect" ? 88 : drag }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                VStack(spacing: 4) {
                    contextRow
                    if grid {
                        ScrollView {
                            ExploreGridContent(notes: notes, collected: state.collected, palette: palette,
                                onOpen: { reader = $0 }, onCollect: toggleCollection,
                                onAction: { action = NoteActionRequest(note: $0, action: $1) })
                        }.accessibilityIdentifier("v9.grid")
                    } else if let note = current {
                        deck(note, height: max(260, viewport.size.height - 60))
                    } else {
                        ContentUnavailableView {
                            Label("All caught up", systemImage: "checkmark.circle")
                        } description: { Text("Your recent cards are still in history.") }
                        actions: { Button("View recent cards") { history = true } }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 10)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { reviewMenu }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Explore").font(.headline)
                        Text("LOCAL DEMO · V9").font(.system(size: 8, weight: .medium)).tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { grid.toggle() } label: { Image(systemName: grid ? "rectangle.portrait" : "square.grid.2x2") }
                        .accessibilityLabel(grid ? "Show swipe cards" : "Show Grid").accessibilityIdentifier("v9.mode")
                    Button { search = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search notes").accessibilityIdentifier("v9.search.open")
                }
            }
            .navigationDestination(item: $reader) { note in
                ReviewV9Reader(note: note, level: level(note), state: $state)
                    .toolbar(.hidden, for: .tabBar)
            }
            .sheet(isPresented: $history) { historySheet }
            .sheet(isPresented: $search, onDismiss: {
                if let searchSelection { reader = searchSelection; self.searchSelection = nil }
            }) { searchSheet }
            .sheet(item: $action) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
            .sheet(item: $author) { note in ReviewV9Author(note: note) }
            .sensoryFeedback(.selection, trigger: feedback)
            .task {
                guard !launched else { return }; launched = true
                if let key = ReviewV9Launch.value("--card"), let index = notes.firstIndex(where: { $0.sampleKey == key }) { cursor = index; frontier = index }
                if ReviewV9Launch.value("--screen") == "reader", let current { reader = current }
                if frozen == "history" { frontier = max(frontier, min(3, notes.count)); cursor = min(frontier, notes.count - 1); history = true }
            }
        }
    }

    private var contextRow: some View {
        HStack(spacing: 6) {
            Label(revisiting ? "Recently viewed" : "For you", systemImage: revisiting ? "clock.arrow.circlepath" : "sparkle")
                .font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
            Spacer(minLength: 4)
            if revisiting {
                Button { cursor = frontier; frozen = "rest" } label: { Image(systemName: "arrow.right.to.line").frame(width: 44, height: 44) }
                    .accessibilityLabel("Continue exploring").accessibilityIdentifier("v9.resume")
            }
            Text("\(min(cursor + 1, notes.count)) / \(notes.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityIdentifier("v9.explore.position")
            Button { history = true } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }
                .accessibilityLabel("Recently viewed cards").accessibilityIdentifier("v9.explore.history")
        }.frame(height: 44)
    }

    private func deck(_ note: SampleNote, height: CGFloat) -> some View {
        ZStack {
            if cursor + 1 < notes.count {
                RoundedRectangle(cornerRadius: 28).fill(palette.surface)
                    .overlay { RoundedRectangle(cornerRadius: 28).stroke(palette.rule, lineWidth: 1) }
                    .padding(.horizontal, 7).offset(y: 6).allowsHitTesting(false).accessibilityHidden(true)
            }
            ZStack {
                cardContent(note)
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(level(note)?.color.opacity(0.55) ?? palette.rule, lineWidth: 1).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) { if let level = level(note) { ReviewV9Brush(level: level).allowsHitTesting(false) } }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(alignment: visualDrag >= 0 ? .topLeading : .topTrailing) {
                if abs(visualDrag) > 18 {
                    Label(visualDrag > 0 ? "COLLECT" : "SKIP", systemImage: visualDrag > 0 ? "bookmark.fill" : "arrow.left")
                        .font(.subheadline.weight(.bold)).tracking(1)
                        .foregroundStyle(visualDrag > 0 ? palette.ink : Color.primary).padding(.horizontal, 16).padding(.vertical, 11)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke((visualDrag > 0 ? palette.ink : Color.primary).opacity(0.8), lineWidth: 1.5) }
                        .rotationEffect(.degrees(visualDrag > 0 ? -8 : 8))
                        .padding(.horizontal, 24).padding(.top, 130)
                        .opacity(min(abs(visualDrag) / 82, 1)).allowsHitTesting(false)
                        .accessibilityIdentifier("v9.swipe.feedback")
                }
            }
            .offset(x: reduceMotion ? 0 : visualDrag, y: reduceMotion ? 0 : abs(visualDrag) * 0.025)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(visualDrag / 35)))
            .accessibilityElement(children: .contain).accessibilityIdentifier("v9.explore.card")
            .accessibilityAction(named: "Skip note") { commit(collect: false) }
            .accessibilityAction(named: "Collect note") { commit(collect: true) }
        }.frame(height: height).disabled(dismissing)
    }

    private func cardContent(_ note: SampleNote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button { author = note } label: {
                    HStack(spacing: 8) {
                        ReviewV9Avatar(name: note.author, ink: palette.ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.author).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                            Text(note.date).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open author, \(note.author)")
                Spacer(minLength: 0)
                Button { action = NoteActionRequest(note: note, action: "Spark") } label: {
                    if typeSize.isAccessibilitySize { Image(systemName: "sparkles").frame(width: 44, height: 44) }
                    else { Label("Spark", systemImage: "sparkles").font(.caption.weight(.semibold)).frame(minHeight: 44) }
                }.buttonStyle(.glass).tint(palette.accent).accessibilityLabel("Spark sample")
                noteMenu(note).accessibilityIdentifier("v9.card.menu")
            }
            ReviewV9Grade(level: level(note), dark: palette.dark)
            GeometryReader { space in
                ReviewV9Content(note: note, palette: palette, full: false, availableHeight: space.size.height)
                    .frame(width: space.size.width, height: space.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    // A recognized drag keeps ownership even when it snaps back.
                    .gesture(
                        swipeGesture(width: space.size.width + 40)
                            .exclusively(before: TapGesture().onEnded {
                                guard !dismissing else { return }
                                reader = note
                            })
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Read full note. \(note.searchableText)")
                    .accessibilityAction { reader = note }
                    .accessibilityIdentifier("v9.explore.summary")
            }
            HStack(spacing: 10) {
                Text(note.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            HStack {
                Button { toggleCollection(note) } label: {
                    Image(systemName: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(state.collected.contains(note.id) ? "Remove sample collection" : "Collect sample")
                    .accessibilityIdentifier("v9.card.collect")
                Spacer()
                Button { if !liked.insert(note.id).inserted { liked.remove(note.id) } } label: {
                    Label(liked.contains(note.id) ? "1" : "0", systemImage: liked.contains(note.id) ? "heart.fill" : "heart").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("Like sample")
                Button { action = NoteActionRequest(note: note, action: "Comments") } label: {
                    Label("0", systemImage: "bubble.right").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("Comments sample")
            }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard frozen == "rest", !dismissing, abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                drag = value.translation.width
                let crossed = abs(drag) >= max(72, width * 0.22)
                if crossed && !crossedThreshold { feedback += 1 }
                crossedThreshold = crossed
            }
            .onEnded { value in
                guard frozen == "rest", !dismissing else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                if horizontal && (abs(drag) >= max(72, width * 0.22) || (abs(drag) > 44 && abs(value.predictedEndTranslation.width) > 150)) {
                    commit(collect: drag > 0)
                } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { drag = 0 }; crossedThreshold = false }
            }
    }

    private func commit(collect: Bool) {
        guard let note = current, !dismissing else { return }
        frozen = "rest"; dismissing = true
        if collect, state.collected.insert(note.id).inserted { lastCollected = note.id }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
            drag = collect ? 520 : -520
        } completion: {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { cursor += 1; frontier = max(frontier, cursor); drag = 0; dismissing = false; crossedThreshold = false }
        }
    }

    private func toggleCollection(_ note: SampleNote) {
        if !state.collected.insert(note.id).inserted { state.collected.remove(note.id) }
    }
    private func level(_ note: SampleNote) -> NativeCardLevel? {
        switch note.sampleKey {
        case "photo": .basic; case "essay": .notable; case "quote": .valuable
        case "checklist": .significant; case "code": .exceptional; case "reference": .definitive
        default: nil
        }
    }
    private func noteMenu(_ note: SampleNote) -> some View {
        Menu {
            Button("Read full note", systemImage: "doc.text") { reader = note }
            Button("Spark", systemImage: "sparkles") { action = NoteActionRequest(note: note, action: "Spark") }
            Button("Link", systemImage: "link") { action = NoteActionRequest(note: note, action: "Link") }
            Button("Share sample", systemImage: "square.and.arrow.up") { action = NoteActionRequest(note: note, action: "Share") }
            if !note.isOwned { Button("Report", systemImage: "flag") { action = NoteActionRequest(note: note, action: "Report") } }
            Divider()
            Button("Skip note", systemImage: "arrow.left") { commit(collect: false) }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.buttonStyle(.plain)
            .accessibilityLabel("Note actions")
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(notes.prefix(min(frontier + 1, notes.count)).enumerated().reversed()), id: \.element.id) { entry in
                        Button {
                            cursor = entry.offset; drag = 0; frozen = "rest"; history = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(entry.element.author).font(.caption).foregroundStyle(.secondary); Spacer(); if state.collected.contains(entry.element.id) { Image(systemName: "bookmark.fill").font(.caption) } }
                                Text(entry.element.body).font(.system(.body, design: .serif)).lineLimit(2).foregroundStyle(.primary)
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("v9.history.item.\(entry.element.sampleKey)")
                    }
                } footer: { Text("Revisiting a card does not remove its collection. This history belongs to the current sample session.") }
                if let lastCollected {
                    Section { Button("Undo last sample collection") { state.collected.remove(lastCollected); self.lastCollected = nil } }
                }
            }
            .navigationTitle("Recently viewed").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { history = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private var searchSheet: some View {
        NavigationStack {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = state.notes.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
            Group {
                if query.isEmpty {
                    ContentUnavailableView("Follow a question", systemImage: "magnifyingglass", description: Text("Search the notes, authors, and tags in this local sample."))
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(matches) { note in
                        Button {
                            searchSelection = note
                            search = false
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(note.author).font(.caption).foregroundStyle(.secondary)
                                Text(note.body).font(.system(.body, design: .serif)).foregroundStyle(.primary).lineLimit(3)
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("v9.search.result.\(note.sampleKey)")
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search notes and ideas")
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { search = false } } }
        }.presentationDragIndicator(.visible)
    }

    private var reviewMenu: some View {
        Menu {
            Section("V9 · offline design study") {
                Button("Swipe cards") { grid = false; frozen = "rest" }
                Button("Read current note") { reader = current }
                Button("Recently viewed") { history = true }
                Button("Continue exploring") { cursor = frontier; frozen = "rest" }
            }
            Section("Sample content") {
                ForEach(Array(notes.enumerated()), id: \.element.id) { entry in
                    Button(entry.element.contentKind.label) { cursor = entry.offset; frontier = max(frontier, cursor); frozen = "rest"; grid = false }
                }
            }
            Section("Capture states · no action is performed") {
                Button("Rest") { frozen = "rest"; drag = 0 }
                Button("Skip gesture") { frozen = "skip" }
                Button("Collect gesture") { frozen = "collect" }
            }
            Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            Button("Open preserved V8 flows", action: openLegacy)
        } label: { Image(systemName: "slider.horizontal.3") }
        .accessibilityLabel("Design study options").accessibilityIdentifier("v9.review-menu")
    }
}

private struct ReviewV9Reader: View {
    let note: SampleNote
    let level: NativeCardLevel?
    @Binding var state: PrototypeState
    @Environment(\.colorScheme) private var scheme
    @State private var action: NoteActionRequest?
    @State private var author = false
    @State private var socialExplanation = false
    @State private var liked = false
    private var palette: Palette { Palette(dark: scheme == .dark) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ReviewV9Grade(level: level, dark: palette.dark, compact: true)
                        Spacer()
                        if let level {
                            ZStack(alignment: .trailing) {
                                ReviewV9Brush(level: level)
                                    .frame(width: 190, height: 98)
                                    .scaleEffect(0.46, anchor: .topTrailing)
                                    .frame(width: 92, height: 40 * 64 / 56, alignment: .topTrailing)
                                    .opacity(0.82)
                                ReviewV9Chora(level: level, size: 40).padding(.trailing, 4)
                            }
                            .frame(width: 92, height: 40 * 64 / 56)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    HStack(spacing: 8) {
                        Button { author = true } label: {
                            HStack(spacing: 8) {
                                ReviewV9Avatar(name: note.author, ink: palette.ink)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.author).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text(note.date).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Open author, \(note.author)")
                        Spacer(minLength: 0)
                        Button { socialExplanation = true } label: {
                            Image(systemName: "bubble.left").frame(width: 44, height: 44).contentShape(Rectangle())
                        }.accessibilityLabel("Message").accessibilityIdentifier("v9.reader.message")
                        Button { socialExplanation = true } label: {
                            Text("Follow").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("v9.reader.follow")
                    }.font(.subheadline).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                ReviewV9Content(note: note, palette: palette, full: true, availableHeight: 0)
                Text(note.tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    Button { liked.toggle() } label: { Label(liked ? "1" : "0", systemImage: liked ? "heart.fill" : "heart").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Like sample").accessibilityIdentifier("v9.reader.like")
                    Button { action = NoteActionRequest(note: note, action: "Comments") } label: { Label("0", systemImage: "bubble.right").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Comments sample")
                }.font(.subheadline).buttonStyle(.plain).foregroundStyle(.secondary)
                Text("Local sample · no live account or service").font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 36)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Read note").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if !state.collected.insert(note.id).inserted { state.collected.remove(note.id) }
                } label: { Image(systemName: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark") }
                    .accessibilityLabel(state.collected.contains(note.id) ? "Remove sample collection" : "Collect sample")
                    .accessibilityIdentifier("v9.reader.collect")
                Button { action = NoteActionRequest(note: note, action: "Spark") } label: { Image(systemName: "sparkles") }.tint(palette.accent).accessibilityLabel("Spark sample")
                Menu {
                    Button("Link", systemImage: "link") { action = NoteActionRequest(note: note, action: "Link") }
                    Button("Share sample", systemImage: "square.and.arrow.up") { action = NoteActionRequest(note: note, action: "Share") }
                    if !note.isOwned { Button("Report", systemImage: "flag") { action = NoteActionRequest(note: note, action: "Report") } }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Note actions")
                    .accessibilityIdentifier("v9.reader.more")
            }
        }
        .alert("Local design sample", isPresented: $socialExplanation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Following and messaging require a connected account. No follow or message request was sent.")
        }
        .sheet(item: $action) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
        .sheet(isPresented: $author) { ReviewV9Author(note: note) }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("v9.reader")
    }
}

/// A bounded excerpt in the deck; the full reader never promotes the first paragraph into a title.
private struct ReviewV9Content: View {
    let note: SampleNote
    let palette: Palette
    let full: Bool
    let availableHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var readerSize = 22.0
    @ScaledMetric(relativeTo: .body) private var summarySize = 20.0
    private var paragraphs: [String] { note.body.components(separatedBy: "\n\n") }
    private var lineBudget: Int { max(1, Int(availableHeight / (summarySize * 1.45))) }
    private var richHeight: CGFloat { max(0, min(172, availableHeight * 0.44)) }

    var body: some View {
        VStack(alignment: .leading, spacing: full ? 22 : 14) {
            if !typeSize.isAccessibilitySize || full { richBlock }
            if full {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.system(size: readerSize, design: .serif)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(note.body).font(.system(size: summarySize, design: .serif)).lineSpacing(4)
                    .lineLimit(summaryLines).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLines: Int {
        if typeSize.isAccessibilitySize { return lineBudget }
        switch note.richContent {
        case .photo, .quote, .checklist, .code, .reference, .comparison: return max(1, Int((availableHeight - richHeight - 36) / (summarySize * 1.45)))
        default: return lineBudget
        }
    }

    @ViewBuilder private var richBlock: some View {
        switch note.richContent {
        case .photo(let photo):
            VStack(alignment: .leading, spacing: 7) {
                if let path = Bundle.main.path(forResource: photo.assetName, ofType: "png"), let image = UIImage(contentsOfFile: path) {
                    Rectangle().fill(palette.rule).frame(height: full ? 240 : richHeight)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(photo.alternativeText)
                }
                if full { Text(photo.caption).font(.caption).foregroundStyle(.secondary) }
            }
        case .quote(let quote):
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "quote.opening").foregroundStyle(palette.accent).font(.title3)
                Text(quote.text).font(.system(size: full ? readerSize : summarySize, design: .serif)).italic().lineSpacing(4).lineLimit(full ? nil : 3)
                if full { Text(quote.attribution).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxHeight: full ? nil : richHeight, alignment: .topLeading)
        case .checklist(let list):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(list.items.prefix(full ? list.items.count : 3).enumerated()), id: \.offset) { _, item in
                    Label(item.text, systemImage: item.completed ? "checkmark.circle.fill" : "circle")
                        .font(full ? .body : .subheadline).lineLimit(full ? nil : 1)
                }
                if full { Text(list.footnote).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxHeight: full ? nil : richHeight, alignment: .topLeading)
        case .code(let code):
            VStack(alignment: .leading, spacing: 7) {
                Text(code.language).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(full ? code.source : code.source.components(separatedBy: "\n").prefix(5).joined(separator: "\n"))
                    .font(.system(size: full ? 15 : 12, design: .monospaced)).lineLimit(full ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if full { Text(code.caption).font(.caption).foregroundStyle(.secondary) }
            }.padding(12).background(palette.rule.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: full ? nil : richHeight, alignment: .topLeading)
        case .reference(let reference):
            VStack(alignment: .leading, spacing: 8) {
                Text(reference.publication).font(.subheadline.weight(.semibold))
                Text(reference.excerpt).font(.system(size: full ? readerSize : summarySize, design: .serif)).italic().lineLimit(full ? nil : 3)
                if full { Text(reference.location + " · " + reference.attribution).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxHeight: full ? nil : richHeight, alignment: .topLeading)
        case .comparison(let comparison):
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(comparison.firstHeading); Spacer(); Text(comparison.secondHeading) }.font(.subheadline.weight(.semibold))
                ForEach(Array(comparison.rows.prefix(full ? comparison.rows.count : 2).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) { Text(row.first).frame(maxWidth: .infinity, alignment: .leading); Text(row.second).frame(maxWidth: .infinity, alignment: .leading) }.font(full ? .body : .subheadline)
                    if full { Text(row.topic).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(12).background(palette.rule.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxHeight: full ? nil : richHeight, alignment: .topLeading)
        default: EmptyView()
        }
    }
}

private struct ReviewV9Grade: View {
    let level: NativeCardLevel?
    let dark: Bool
    var compact = false
    var body: some View {
        if let level {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(level.roman).font(.system(size: compact ? 17 : 24, weight: .medium, design: .serif))
                Text(level.name).font(compact ? .caption : .subheadline)
            }.foregroundStyle(level.ink(dark: dark)).accessibilityElement(children: .combine)
        }
    }
}
private struct ReviewV9Avatar: View {
    let name: String
    let ink: Color
    var body: some View {
        Text(name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(ink.opacity(0.8))
            .frame(width: 34, height: 34).background(ink.opacity(0.08), in: Circle()).accessibilityHidden(true)
    }
}
private struct ReviewV9Brush: View {
    let level: NativeCardLevel
    var body: some View {
        GeometryReader { proxy in
            if let path = Bundle.main.path(forResource: "rim-brush", ofType: "png"), let image = UIImage(contentsOfFile: path) {
                level.color.frame(width: 190, height: 98)
                    .mask(alignment: .topLeading) { Image(uiImage: image).resizable().frame(width: 231, height: 231).offset(x: -18, y: -74) }
                    .opacity(0.72).position(x: proxy.size.width - 95, y: 49)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct ReviewV9Chora: View {
    let level: NativeCardLevel
    var size: CGFloat = 56
    var body: some View {
        Group {
            let asset = level == .exceptional ? "exceptional-green-gold" : "perches"
            if let path = Bundle.main.path(forResource: asset, ofType: "png"), let atlas = UIImage(contentsOfFile: path)?.cgImage, let crop = atlas.cropping(to: level.crop) {
                Image(uiImage: UIImage(cgImage: crop)).resizable().scaledToFit()
            }
        }.frame(width: size, height: size * 64 / 56).accessibilityHidden(true)
    }
}
private struct ReviewV9Author: View {
    let note: SampleNote
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ReviewV9Avatar(name: note.author, ink: .primary)
                Text(note.author).font(.title2)
                Text("Sample author · no live profile").font(.subheadline).foregroundStyle(.secondary)
                Text("Following and messaging require a connected account. This preview does not send a request.")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Spacer()
            }.padding(32).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}
