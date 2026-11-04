import SwiftUI
import UIKit

private struct ReadingFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22
    init(_ size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .body) }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: .regular, design: .serif)) }
}
private extension View {
    func readingFont(_ size: CGFloat = 22) -> some View { modifier(ReadingFont(size)) }
}
private struct DemoBadge: View {
    var body: some View {
        Text("LOCAL DEMO").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.3)
            .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .accessibilityLabel("Local prototype. Sample changes reset when the app relaunches.")
    }
}

@main struct ChoraiPrototypeApp: App {
    var body: some Scene { WindowGroup { JourneyEntryPoint() } }
}
struct PrototypeRoot: View {
    @Binding var state: PrototypeState
    @State private var selectedTab: Int
    @State private var appearance: String
    @State private var theme: PrototypeTheme
    private let initialEditor: Bool
    init(state: Binding<PrototypeState>) {
        _state = state
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }; return args[index + 1] }
        let screen = value("--screen") ?? "explore"
        _selectedTab = State(initialValue: screen == "explore" ? 0 : 1)
        _appearance = State(initialValue: value("--appearance") ?? "system")
        _theme = State(initialValue: PrototypeTheme(rawValue: value("--palette") ?? "forest-gold") ?? .forestGold)
        initialEditor = screen == "editor"
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Explore", systemImage: "safari", value: 0) {
                ExplorePrototype(state: $state, appearance: $appearance)
            }
            Tab("Home", systemImage: "square.stack", value: 1) {
                HomePrototype(state: $state, appearance: $appearance, opensEditor: initialEditor)
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: 2) {
                ChatPrototype(appearance: $appearance)
            }
        }
        .tint(theme.dynamicTint)
        .environment(\.prototypeTheme, theme)
        .environment(\.prototypeThemeSelection, $theme)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}

private struct ExplorePrototype: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var state: PrototypeState
    @Binding var appearance: String
    @State private var browsing = ExploreDeckState()
    @State private var gridMode = ProcessInfo.processInfo.arguments.contains("--grid")
    @State private var actionRequest: NoteActionRequest?
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: Bool?
    @State private var isDismissing = false
    @State private var swipeFeedback = 0
    @State private var searchMode = false
    @State private var searchIndex = 0
    @State private var reader: SampleNote?
    @State private var settings = false
    @State private var service: DemoService?
    @State private var author: SampleNote?
    @State private var liked: Set<UUID> = []
    @FocusState private var searchFocused: Bool
    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    init(state: Binding<PrototypeState>, appearance: Binding<String>) {
        _state = state; _appearance = appearance
        let args = ProcessInfo.processInfo.arguments
        var initial = ExploreDeckState()
        if let argument = args.firstIndex(of: "--card"), args.indices.contains(argument + 1),
           let index = state.wrappedValue.notes.filter({ !$0.isOwned }).firstIndex(where: { $0.sampleKey == args[argument + 1] }) {
            for _ in 0..<index { initial.skip(total: state.wrappedValue.notes.filter { !$0.isOwned }.count) }
        }
        _browsing = State(initialValue: initial)
    }
    private var deck: [SampleNote] { state.notes.filter { !$0.isOwned } }
    private var currentNote: SampleNote? { browsing.currentIndex(total: deck.count).map { deck[$0] } }
    private var results: [SampleNote] { state.searchResults }
    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
            ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if searchMode {
                        searchField
                        if state.submittedQuery == nil {
                            ContentUnavailableView("Follow a question", systemImage: "magnifyingglass", description: Text("Search notes and ideas. Tap Search on the keyboard to begin."))
                                .padding(.top, 65)
                        } else if results.isEmpty {
                            ContentUnavailableView.search(text: state.submittedQuery ?? "").padding(.top, 65)
                        } else {
                            Text("\(results.count) NOTES").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                            let result = results[min(searchIndex, results.count - 1)]
                            VStack(alignment: .leading, spacing: 20) {
                                Button { reader = result } label: {
                                    VStack(alignment: .leading, spacing: 20) {
                                        Text(result.author).font(.subheadline.weight(.semibold)).foregroundStyle(palette.ink)
                                        Text(result.body.replacingOccurrences(of: "\n\n", with: "\n")).readingFont(21).lineSpacing(4).lineLimit(7).foregroundStyle(.primary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                                }.buttonStyle(.plain)
                                HStack {
                                    Button { searchIndex = max(0, searchIndex - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(searchIndex == 0).accessibilityLabel("Previous result")
                                    Spacer()
                                    Text("\(searchIndex + 1) / \(results.count)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { searchIndex = min(results.count - 1, searchIndex + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(searchIndex == results.count - 1).accessibilityLabel("Next result")
                                }.buttonStyle(.glass)
                            }.padding(23).background(palette.surface, in: RoundedRectangle(cornerRadius: 28))
                                .gesture(DragGesture(minimumDistance: 45).onEnded { value in
                                    if value.translation.width < -70 { searchIndex = min(results.count - 1, searchIndex + 1) }
                                    else if value.translation.width > 70 { searchIndex = max(0, searchIndex - 1) }
                                })
                        }
                    } else {
                        HStack {
                            if browsing.isRevisiting {
                                Label("Browsing history", systemImage: "clock.arrow.circlepath")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
                                    .accessibilityIdentifier("prototype.explore.history")
                            } else {
                                Label("For you", systemImage: "sparkle").font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
                            }
                            Spacer()
                            Text("\(min(browsing.cursor + 1, deck.count)) / \(deck.count)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityIdentifier("prototype.explore.position")
                        }
                        if let note = currentNote {
                            swipeStack(note, minimumHeight: max(440, viewport.size.height - 112))
                        } else {
                            ContentUnavailableView("You’re all caught up", systemImage: "checkmark.circle", description: Text("Your recent cards are still here. Go back whenever you like."))
                                .frame(minHeight: 330).accessibilityIdentifier("prototype.explore.end")
                        }
                        HStack(spacing: 8) {
                            Button {
                                browsing.previous()
                            } label: {
                                Label("Previous", systemImage: "arrow.uturn.backward").font(.subheadline).frame(minHeight: 44)
                            }.disabled(!browsing.canGoBack || isDismissing)
                                .accessibilityIdentifier("prototype.explore.previous")
                            Spacer(minLength: 6)
                            if browsing.isRevisiting {
                                Button { browsing.resume() } label: {
                                    Label("Continue exploring", systemImage: "arrow.right").font(.subheadline).frame(minHeight: 44)
                                }.disabled(isDismissing).accessibilityIdentifier("prototype.explore.resume")
                            } else if currentNote != nil {
                                Text(browsing.cursor == 0 ? "← Skip · Collect →" : "Tap the note to read").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.horizontal, searchMode ? 24 : 14).padding(.top, 8).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(gridMode && !searchMode ? 0 : 1)
            .allowsHitTesting(!gridMode || searchMode)
            .accessibilityHidden(gridMode && !searchMode)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("For you").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("8 NOTES").font(.caption2).tracking(1.2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 2)
                    ExploreGridContent(notes: deck, collected: state.collected, palette: palette,
                        onOpen: { reader = $0 }, onCollect: { toggleCollect($0) },
                        onAction: { note, action in actionRequest = NoteActionRequest(note: note, action: action) })
                    Text("You’re all caught up").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 20)
            }
            .accessibilityIdentifier("prototype.grid.scroll")
            .opacity(gridMode && !searchMode ? 1 : 0)
            .allowsHitTesting(gridMode && !searchMode)
            .accessibilityHidden(!gridMode || searchMode)
            }
            }

            .background(palette.background.ignoresSafeArea())
            .navigationTitle(searchMode ? "Search" : "Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if searchMode { Button { searchMode = false; state.cancelSearch(); searchFocused = false } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Cancel search") }
                    else { Button { settings = true } label: { Image(systemName: "line.3.horizontal") }.accessibilityLabel("Open menu") }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(searchMode ? "Search" : "Explore").font(.headline)
                        Text("LOCAL DEMO").font(.system(size: 8, weight: .medium)).tracking(1.1).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if searchMode { Button("Cancel") { searchMode = false; state.cancelSearch(); searchFocused = false } }
                    else {
                        HStack(spacing: 12) {
                            Button { browsing.dismissUndo(); gridMode.toggle() } label: {
                                Image(systemName: gridMode ? "rectangle.portrait" : "square.grid.2x2")
                            }.accessibilityLabel(gridMode ? "Switch to swipe mode" : "Switch to grid mode")
                                .accessibilityIdentifier("prototype.explore.mode")
                            Button { searchMode = true; searchFocused = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search notes")
                        }
                    }
                }
            }
            .navigationDestination(item: $reader) { note in
                if note.isOwned { EditorPrototype(state: $state, note: note) } else { ReaderPrototype(state: $state, note: note) }
            }
            .sheet(isPresented: $settings) { MenuPrototype(appearance: $appearance) }
            .sheet(item: $actionRequest) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
            .overlay(alignment: .top) {
                if browsing.undoCollectionID != nil && !searchMode && !gridMode {
                    HStack(spacing: 12) {
                        Label("Collected to sample", systemImage: "bookmark.fill").font(.subheadline)
                        Spacer(minLength: 6)
                        Button("Undo") { browsing.undoCollection(collected: &state.collected) }
                            .font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Undo collection").accessibilityIdentifier("prototype.explore.undo")
                    }.padding(.horizontal, 16).padding(.vertical, 4)
                        .background(palette.surface, in: Capsule())
                        .glassEffect(.regular, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                        .padding(.horizontal, 24).padding(.top, 6)
                }
            }
            .task(id: browsing.undoCollectionID) {
                guard browsing.undoCollectionID != nil else { return }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                browsing.dismissUndo()
            }
            .onChange(of: reader) { _, note in
                if note != nil { browsing.dismissUndo() }
            }
            .sensoryFeedback(.selection, trigger: swipeFeedback)
            .sheet(item: $service) { item in ServiceSheet(item: item) }
            .sheet(item: $author) { note in AuthorSheet(note: note) }
        }
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes and ideas", text: $state.query).focused($searchFocused).submitLabel(.search).accessibilityIdentifier("prototype.explore.search")
                .onSubmit { state.submitSearch(); searchIndex = 0; searchFocused = false }
            if !state.query.isEmpty { Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear query") }
        }.padding(14).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
    private func readingCard(_ note: SampleNote, minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Button { author = note } label: {
                    HStack(spacing: 10) {
                        Avatar(name: note.author, color: palette.ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.author).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(note.date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer()
                Button { actionRequest = NoteActionRequest(note: note, action: "Spark") } label: {
                    Label("Spark", systemImage: "sparkles").font(.caption.weight(.semibold)).padding(.horizontal, 4).frame(minHeight: 36)
                }.buttonStyle(.glass).tint(palette.accent)
                Menu {
                    Button("Spark", systemImage: "sparkles") { actionRequest = NoteActionRequest(note: note, action: "Spark") }
                    Button(note.isOwned ? "Share" : "Report", systemImage: note.isOwned ? "square.and.arrow.up" : "flag") { actionRequest = NoteActionRequest(note: note, action: note.isOwned ? "Share" : "Report") }
                    Button("Link", systemImage: "link") { actionRequest = NoteActionRequest(note: note, action: "Link") }
                    Button(note.isOwned ? "Edit" : "View", systemImage: "doc.text") { reader = note }
                    Divider()
                    Button(state.collected.contains(note.id) ? "Remove from collection" : "Collect sample", systemImage: "bookmark") { toggleCollect(note) }
                    Button("Skip note", systemImage: "arrow.left") { commitSwipe(collect: false) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(.secondary) }
                    .accessibilityLabel("Note actions").accessibilityIdentifier("prototype.explore.more")
            }
            RichCardContent(note: note, palette: palette)
                .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).exclusively(before: TapGesture())
                        .onEnded { gesture in
                            if case .second = gesture, !isDismissing { reader = note }
                        }
                )
                .accessibilityElement(children: .combine)
            .accessibilityLabel(note.searchableText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { reader = note }
                .accessibilityIdentifier("prototype.explore.read")
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                ForEach(note.tags, id: \.self) { tag in Text(tag).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5).background(palette.background, in: Capsule()) }
                Spacer()
            }
            HStack(spacing: 16) {
                if state.collected.contains(note.id) {
                    Label("Collected", systemImage: "bookmark.fill").font(.caption).foregroundStyle(palette.ink)
                        .accessibilityIdentifier("prototype.explore.collected")
                }
                Spacer()
                Button {
                    if liked.contains(note.id) { liked.remove(note.id) } else { liked.insert(note.id) }
                } label: { Label(liked.contains(note.id) ? "1" : "0", systemImage: liked.contains(note.id) ? "heart.fill" : "heart").font(.caption).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).foregroundStyle(liked.contains(note.id) ? palette.ink : .secondary).accessibilityLabel("Like local sample")
                Button { service = DemoService(title: "Comments", icon: "bubble.right", detail: "No comments in this local sample. Reading live comments or posting a reply requires the connected service.") } label: { Label("0", systemImage: "bubble.right").font(.caption).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Comments")
            }
        }
        .padding(24).frame(minHeight: minimumHeight, alignment: .topLeading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(palette.rule, lineWidth: 0.7) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.1 : 0.025), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.explore.card")
        .accessibilityAction(named: "Skip note") { commitSwipe(collect: false) }
        .accessibilityAction(named: "Collect note") { commitSwipe(collect: true) }
    }
    private func swipeStack(_ note: SampleNote, minimumHeight: CGFloat) -> some View {
        ZStack {
            if browsing.cursor + 1 < deck.count {
                RoundedRectangle(cornerRadius: 28)
                    .fill(palette.surface.opacity(reduceTransparency ? 1 : 0.7))
                    .overlay { RoundedRectangle(cornerRadius: 28).stroke(palette.rule, lineWidth: 1) }
                    .padding(.horizontal, 12).offset(y: 12)
                    .scaleEffect(reduceMotion ? 1 : 1 + min(abs(dragOffset) / 8000, 0.02))
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: 28)
                    .fill(palette.surface)
                    .overlay { RoundedRectangle(cornerRadius: 28).stroke(palette.rule, lineWidth: 1) }
                    .padding(.horizontal, 6).offset(y: 6)
                    .accessibilityHidden(true)
            }
            readingCard(note, minimumHeight: minimumHeight)
                .overlay(alignment: dragOffset >= 0 ? .topLeading : .topTrailing) {
                    if abs(dragOffset) > 18 {
                        Label(dragOffset > 0 ? "COLLECT" : "SKIP", systemImage: dragOffset > 0 ? "bookmark.fill" : "arrow.left")
                            .font(.subheadline.weight(.bold)).tracking(1)
                            .foregroundStyle(dragOffset > 0 ? palette.ink : Color.primary)
                            .padding(.horizontal, 15).padding(.vertical, 12)
                            .background(palette.surface, in: Capsule())
                            .overlay { Capsule().stroke(dragOffset > 0 ? palette.ink : Color.secondary, lineWidth: 1.5) }
                            .opacity(min(abs(dragOffset) / 85, 1)).padding(20)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .offset(x: reduceMotion ? 0 : dragOffset, y: reduceMotion ? 0 : abs(dragOffset) * 0.025)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragOffset / 35)))
                .opacity(reduceMotion && isDismissing ? 0 : 1)
                .simultaneousGesture(DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard !isDismissing else { return }
                        if dragAxis == nil {
                            dragAxis = abs(value.translation.width) > abs(value.translation.height) * 1.2
                        }
                        guard dragAxis == true else { return }
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let horizontal = dragAxis == true
                        dragAxis = nil
                        guard horizontal && !isDismissing else { return }
                        let travel = value.translation.width
                        // Velocity must not turn a tiny exploratory drag into a decision.
                        if abs(travel) > 82 || (abs(travel) > 44 && abs(value.predictedEndTranslation.width) > 150) {
                            commitSwipe(collect: travel > 0)
                        } else {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                        }
                    })
                .allowsHitTesting(!isDismissing)
        }.padding(.bottom, 12)
    }
    private func commitSwipe(collect: Bool) {
        guard let note = currentNote, !isDismissing else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22), completionCriteria: .logicallyComplete) {
            isDismissing = true
            dragOffset = collect ? 520 : -520
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if collect { browsing.collect(noteID: note.id, collected: &state.collected, total: deck.count) }
                else { browsing.skip(total: deck.count) }
                dragOffset = 0
                dragAxis = nil
                isDismissing = false
                swipeFeedback += 1
            }
        }
    }
    private func toggleCollect(_ note: SampleNote) {
        browsing.dismissUndo()
        if state.collected.contains(note.id) { state.collected.remove(note.id) } else { state.collected.insert(note.id) }
    }
}

private struct HomePrototype: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Binding var state: PrototypeState
    @Binding var appearance: String
    let opensEditor: Bool
    @State private var scope: HomeScope = .notes
    @State private var actionRequest: NoteActionRequest?
    @State private var selected: SampleNote?
    @State private var settings = false
    @State private var searchMode = false
    @State private var query = ""
    @State private var submitted: String?
    @State private var openedInitial = false
    @FocusState private var focused: Bool
    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    private var notes: [SampleNote] {
        let scoped = state.visibleHomeNotes(scope: scope)
        guard searchMode, let submitted, !submitted.isEmpty else { return searchMode ? [] : scoped }
        return scoped.filter { $0.body.localizedCaseInsensitiveContains(submitted) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Library", selection: $scope) { ForEach(HomeScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    if searchMode {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search \(scope.rawValue.lowercased())", text: $query).focused($focused).submitLabel(.search)
                                .onSubmit { submitted = query.trimmingCharacters(in: .whitespacesAndNewlines); focused = false }
                            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear query") }
                        }.padding(14).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    }
                    HStack {
                        Text(scope == .notes ? "Your thinking, in progress." : "Ideas worth returning to.").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Picker("Filter", selection: $state.filter) { ForEach(NoteFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Filter notes")
                    }
                    if state.filter != .all { Text(state.filter.rawValue).font(.caption.weight(.medium)).foregroundStyle(palette.ink) }
                    if searchMode && submitted == nil {
                        ContentUnavailableView("Search your \(scope.rawValue.lowercased())", systemImage: "magnifyingglass", description: Text("Submit a question or a phrase to find a note."))
                    } else if notes.isEmpty {
                        ContentUnavailableView("No notes here", systemImage: "doc.text.magnifyingglass", description: Text("Try another filter or search."))
                    } else {
                        ForEach(notes) { note in
                            Button { selected = note } label: { NoteRow(note: note, palette: palette) }.buttonStyle(.plain).accessibilityIdentifier(note.isOwned ? "prototype.note.owned" : "prototype.note.collected")
                                .contextMenu {
                                    Button(note.isOwned ? "Edit" : "View", systemImage: "doc.text") { selected = note }
                                    Button("Spark", systemImage: "sparkles") { actionRequest = NoteActionRequest(note: note, action: "Spark") }
                                    if note.isOwned { Button("Merge", systemImage: "arrow.triangle.merge") { actionRequest = NoteActionRequest(note: note, action: "Merge") } }
                                    Button("Share", systemImage: "square.and.arrow.up") { actionRequest = NoteActionRequest(note: note, action: "Share") }
                                    Button("Link", systemImage: "link") { actionRequest = NoteActionRequest(note: note, action: "Link") }
                                    if !note.isOwned { Button("Report", systemImage: "flag") { actionRequest = NoteActionRequest(note: note, action: "Report") } }
                                }
                            Divider().overlay(palette.rule)
                        }
                    }
                    if !searchMode {
                        HStack(spacing: 7) { Image(systemName: "lock").font(.caption2); Text("New notes start private.").font(.caption) }.foregroundStyle(.tertiary).padding(.top, 8)
                    }
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 100)
            }.scrollDismissesKeyboard(.interactively)
            .background(palette.background.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                Button { selected = state.createNote() } label: {
                    Label("New note", systemImage: "square.and.pencil")
                        .foregroundStyle(palette.onTint)
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(height: 52)
                }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier("prototype.note.new")
                    .padding(.trailing, 24).padding(.bottom, 18)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "line.3.horizontal") }.accessibilityLabel("Open menu") }
                ToolbarItem(placement: .principal) { DemoBadge() }
                ToolbarItem(placement: .topBarTrailing) {
                    if searchMode { Button("Cancel") { searchMode = false; submitted = nil; query = ""; focused = false } }
                    else { Button { searchMode = true; focused = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search library") }
                }
            }
            .navigationDestination(item: $selected) { note in
                if note.isOwned { EditorPrototype(state: $state, note: note) } else { ReaderPrototype(state: $state, note: note) }
            }
            .sheet(isPresented: $settings) { MenuPrototype(appearance: $appearance) }
            .sheet(item: $actionRequest) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
            .task { if opensEditor && !openedInitial { openedInitial = true; selected = state.notes.first { $0.isOwned } } }
        }
    }
}

private struct NoteRow: View {
    let note: SampleNote
    let palette: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(note.date.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                if !note.isOwned { Text("·"); Text(note.author).font(.caption) }
                Spacer()
                Image(systemName: note.isPublic ? "globe" : "lock").font(.caption2)
            }.foregroundStyle(.secondary)
            Text(note.body.isEmpty ? "Start with a sentence, a question, or a small observation." : note.body.replacingOccurrences(of: "\n\n", with: "\n"))
                .readingFont(21).lineSpacing(4).foregroundStyle(.primary).lineLimit(4).multilineTextAlignment(.leading)
            HStack {
                ForEach(note.tags, id: \.self) { Text("#\($0)").font(.caption).foregroundStyle(palette.ink.opacity(0.8)) }
                Spacer()
                Image(systemName: note.isOwned ? "arrow.up.right" : "bookmark").font(.caption).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
    }
}

private struct EditorPrototype: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Binding var state: PrototypeState
    let note: SampleNote
    @State private var bodyText: String
    @State private var isPublic: Bool
    @State private var baselineBody: String
    @State private var baselinePublic: Bool
    @State private var confirmClose = false
    @State private var saved = false
    @State private var info: DemoService?
    @State private var actionRequest: NoteActionRequest?
    @FocusState private var focused: Bool
    init(state: Binding<PrototypeState>, note: SampleNote) {
        _state = state; self.note = note
        _bodyText = State(initialValue: note.body)
        _isPublic = State(initialValue: note.isPublic)
        _baselineBody = State(initialValue: note.body)
        _baselinePublic = State(initialValue: note.isPublic)
    }
    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    private var dirty: Bool { bodyText != baselineBody || isPublic != baselinePublic }
    private var words: Int { bodyText.split { $0.isWhitespace || $0.isNewline }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(palette.ink.opacity(0.55)).frame(width: 5, height: 5)
                Text(dirty ? "Unsaved sample changes" : saved ? "Saved to this sample" : "\(note.date) · Local sample")
                Spacer()
                Text("\(words) words").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 27).padding(.top, 20).padding(.bottom, 14)
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("Give a thought some room.").readingFont(24).foregroundStyle(.tertiary).padding(.horizontal, 29).padding(.top, 12).allowsHitTesting(false)
                }
                TextEditor(text: $bodyText)
                    .readingFont(23).lineSpacing(8)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 23).focused($focused)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityLabel("Note body")
                    .accessibilityIdentifier("prototype.editor.body")
            }
            VStack(alignment: .leading, spacing: 14) {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "number").foregroundStyle(.tertiary)
                    Text(note.tags.isEmpty ? "Add tags" : note.tags.joined(separator: "    ")).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button { info = DemoService(title: "Note details", icon: "number", detail: "This sample has \(note.tags.count) tags and no links. Tag and source editing are outside these three visual prototypes.") } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Note details")
                }
                Text("Sample changes stay in this app session. Nothing is published or synced.").font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 27).padding(.bottom, 20)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if dirty {
                        state.save(id: note.id, body: bodyText, isPublic: isPublic)
                        baselineBody = bodyText; baselinePublic = isPublic; saved = true
                    } else { state.discardEmptyDraft(id: note.id); dismiss() }
                } label: {
                    Label(dirty ? "Save" : "Back", systemImage: dirty ? "checkmark" : "chevron.left")
                }
                .accessibilityLabel(dirty ? "Save sample changes" : "Back")
                .accessibilityIdentifier("prototype.editor.leading")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Visibility of sample", selection: $isPublic) {
                        Label("Private", systemImage: "lock").tag(false)
                        Label("Public", systemImage: "globe").tag(true)
                    }
                    Text("Preview only. No publishing.")
                } label: { Image(systemName: isPublic ? "globe" : "lock").frame(minWidth: 32, minHeight: 44) }.accessibilityLabel("Note privacy")
                Menu {
                    Button("Spark", systemImage: "sparkles") { openPersistedAction("Spark") }
                    Button("Merge", systemImage: "arrow.triangle.merge") { openPersistedAction("Merge") }
                    Button("Share", systemImage: "square.and.arrow.up") { openPersistedAction("Share") }
                    Divider()
                    Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                    Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
                    Divider()
                    Button("Note details", systemImage: "info.circle") { info = DemoService(title: "Local writing sample", icon: "doc.text", detail: "A single body field with native text selection, copy and paste, keyboard, and undo. The production BlockNote editor is unchanged.") }
                    Button("Discard changes", systemImage: "arrow.uturn.backward", role: .destructive) { confirmClose = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 32, minHeight: 44) }.accessibilityLabel("More note actions")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("Undo")
                Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("Redo")
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .confirmationDialog("Discard local changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard and close", role: .destructive) { state.discardEmptyDraft(id: note.id); focused = false; dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Only unsaved changes in this prototype will be discarded.") }
        .sheet(item: $info) { ServiceSheet(item: $0) }
        .sheet(item: $actionRequest) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
    }
    private func openPersistedAction(_ action: String) {
        focused = false
        state.save(id: note.id, body: bodyText, isPublic: isPublic)
        baselineBody = bodyText; baselinePublic = isPublic; saved = true
        guard let persisted = state.notes.first(where: { $0.id == note.id }) else { return }
        actionRequest = NoteActionRequest(note: persisted, action: action)
    }
}

private struct ReaderPrototype: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Binding var state: PrototypeState
    let note: SampleNote
    @State private var author = false
    @State private var actionRequest: NoteActionRequest?
    @State private var service: DemoService?
    private var palette: Palette { Palette(dark: scheme == .dark, theme: theme) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Button { author = true } label: {
                    HStack(spacing: 12) { Avatar(name: note.author, color: palette.ink); VStack(alignment: .leading, spacing: 4) { Text(note.author).font(.subheadline.weight(.semibold)); Text(note.date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                }.buttonStyle(.plain)
                RichCardContent(note: note, palette: palette, full: true)
                    .textSelection(.enabled)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("prototype.reader.rich")
                HStack { ForEach(note.tags, id: \.self) { Text("#\($0)").font(.caption).foregroundStyle(palette.ink) } }
                Divider()
                Text("A read-only sample by another author.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(palette.background.ignoresSafeArea())
        .navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { if state.collected.contains(note.id) { state.collected.remove(note.id) } else { state.collected.insert(note.id) } } label: { Image(systemName: state.collected.contains(note.id) ? "bookmark.fill" : "bookmark") }.accessibilityLabel("Toggle local collection")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Spark", systemImage: "sparkles") { actionRequest = NoteActionRequest(note: note, action: "Spark") }
                    Button("Report", systemImage: "flag") { actionRequest = NoteActionRequest(note: note, action: "Report") }
                    Button("Link", systemImage: "link") { actionRequest = NoteActionRequest(note: note, action: "Link") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Note actions")
            }
            ToolbarItem(placement: .bottomBar) {
                Button { actionRequest = NoteActionRequest(note: note, action: "Spark") } label: { Label("Spark", systemImage: "sparkles").foregroundStyle(palette.onTint) }.buttonStyle(.glassProminent)
            }
        }
        .sheet(item: $actionRequest) { request in JourneyActionSheet(request: request, state: $state, palette: palette) }
        .sheet(isPresented: $author) { AuthorSheet(note: note) }
        .sheet(item: $service) { ServiceSheet(item: $0) }
    }
}

private struct Avatar: View {
    let name: String
    let color: Color
    var body: some View {
        Text(name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.08), in: Circle())
    }
}
private struct DemoService: Identifiable { var id: String { title }; let title: String; let icon: String; let detail: String }
private struct ServiceSheet: View {
    let item: DemoService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: item.icon).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                Text(item.title).font(.title2.weight(.semibold))
                Text(item.detail).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                Label("Local prototype · no service request", systemImage: "iphone").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }.padding(28).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
private struct AuthorSheet: View {
    let note: SampleNote
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Avatar(name: note.author, color: Color(red: 0.25, green: 0.45, blue: 0.39)).scaleEffect(1.8).frame(height: 75)
                Text(note.author).font(.title2.weight(.semibold))
                Text("Collecting small observations.\nMaking room for new connections.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Text("Sample author · no live profile").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }.padding(35).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}
private struct MenuPrototype: View {
    @Environment(\.prototypeThemeSelection) private var themeSelection
    @Binding var appearance: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 13) { Avatar(name: "Local Sample", color: .secondary); VStack(alignment: .leading, spacing: 4) { Text("Your space").font(.headline); Text("Chorai native prototype").font(.caption).foregroundStyle(.secondary) } }
                }
                Section("Visual direction") {
                    Label("Warm white · Forest · Gold", systemImage: "circle.lefthalf.filled")
                    Text("Warm paper, forest ink, a small touch of college gold.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Prototype appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Follow System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.inline)
                }
                Section {
                    Label("All content is a local sample", systemImage: "iphone")
                    Label("No account or network connection", systemImage: "network.slash")
                } footer: { Text("Sample edits and collection changes last for this app session. AI, publishing and sync are not connected. This is a visual review prototype, separate from Chorai.") }
            }.navigationTitle("Your space").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
}
private struct ChatPrototype: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.prototypeTheme) private var theme
    @Binding var appearance: String
    @State private var settings = false
    @State private var service: DemoService?
    var body: some View {
        NavigationStack {
            VStack(spacing: 23) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 49, weight: .ultraLight)).foregroundStyle(.secondary)
                Text("A thought can start a conversation.").readingFont(28).multilineTextAlignment(.center)
                Text("Your conversations will live here.\nChat is not connected in this prototype.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Button { service = DemoService(title: "Conversations", icon: "bubble.left.and.bubble.right", detail: "The Chat tab and its native navigation are available for review. Real conversations, sending, and AI replies require the connected service.") } label: { Label("About this sample", systemImage: "info.circle").padding(.horizontal, 15).padding(.vertical, 5) }.buttonStyle(.glass)
                Spacer(); Spacer()
            }.padding(30).frame(maxWidth: .infinity).background(Palette(dark: scheme == .dark, theme: theme).background.ignoresSafeArea())
                .navigationTitle("Chat")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "line.3.horizontal") }.accessibilityLabel("Open menu") }
                    ToolbarItem(placement: .principal) { DemoBadge() }
                }
                .sheet(isPresented: $settings) { MenuPrototype(appearance: $appearance) }
                .sheet(item: $service) { ServiceSheet(item: $0) }
        }
    }
}
