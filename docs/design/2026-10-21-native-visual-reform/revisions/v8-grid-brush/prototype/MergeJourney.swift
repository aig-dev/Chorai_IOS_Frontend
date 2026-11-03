import SwiftUI

private enum MergeJourneyStep: String, CaseIterable {
    case selection, selected, progress, background, ready
    case syncError = "sync-error"
    case conflict, saved, failed, cancelled

    var label: String {
        switch self {
        case .selection: "Choose sources"
        case .selected: "Sources selected"
        case .progress: "In progress"
        case .background: "Background task"
        case .ready: "Insight ready"
        case .syncError: "Sync issue"
        case .conflict: "Version conflict"
        case .saved: "Saved"
        case .failed: "Generation failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// Session memory deliberately survives presentation dismissal. It is separate from source notes.
/// No network job, generated result, or server persistence is represented by this sample store.
@MainActor
private final class MergeJourneySession: ObservableObject {
    private static var retained: [UUID: MergeJourneySession] = [:]

    @Published var step: MergeJourneyStep
    @Published var selectedIDs: Set<UUID>
    @Published var body: String
    @Published var tags = ["Ideas", "Connections"]
    @Published var savedNoteID: UUID?
    @Published var statusMessage = "Draft kept in this app session"
    @Published var wasDiscarded = false
    let anchorID: UUID

    static let preparedBody = "Some ideas grow better together.\n\nA note gives an unfinished thought a place to rest. A garden gives it room to change. Both become more useful when we return with something new to notice.\n\nKeeping a question beside an observation creates a small path between them. Sharing that path lets someone else see a connection we might have missed.\n\nLeave room for a pause, a different perspective, and the next conversation."
    static let otherVersion = "Some ideas grow better together.\n\nA note gives an unfinished thought a place to rest. A garden gives it room to change. Both become more useful when we return with something new to notice.\n\nThis alternate sample draft keeps the question open: what changes when another person adds a new perspective?\n\nA connection is a beginning, not a finished explanation."

    static func session(source: SampleNote, candidates: [SampleNote], initialStep: String) -> MergeJourneySession {
        if let existing = retained[source.id] { return existing }
        let session = MergeJourneySession(anchorID: source.id, candidates: candidates, initialStep: initialStep)
        retained[source.id] = session
        return session
    }

    private init(anchorID: UUID, candidates: [SampleNote], initialStep: String) {
        self.anchorID = anchorID
        step = MergeJourneyStep(rawValue: initialStep) ?? .selection
        selectedIDs = [anchorID]
        body = Self.preparedBody
        if step != .selection, let first = candidates.first { selectedIDs.insert(first.id) }
        if step == .conflict { body += "\n\nMy local addition: leave the edges open." }
    }

    func preview(_ step: MergeJourneyStep, candidates: [SampleNote]) {
        if step == .selection { selectedIDs = [anchorID] }
        else if selectedIDs.count < 2, let first = candidates.first { selectedIDs.insert(first.id) }
        if body.isEmpty { body = Self.preparedBody }
        if step == .conflict, !body.contains("My local addition:") {
            body += "\n\nMy local addition: leave the edges open."
        }
        self.step = step
    }

    func restart() {
        selectedIDs = [anchorID]
        body = Self.preparedBody
        tags = ["Ideas", "Connections"]
        savedNoteID = nil
        statusMessage = "Draft kept in this app session"
        wasDiscarded = false
        step = .selection
    }
}

/// A titleless, editable Merge journey using prepared local content and native controls.
@MainActor
struct MergeJourney: View {
    @Binding var state: PrototypeState
    let source: SampleNote
    @StateObject private var session: MergeJourneySession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.prototypeTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var tagInput = ""
    @State private var confirmDiscard = false
    @State private var confirmCancel = false
    @FocusState private var editorFocused: Bool
    @FocusState private var tagFocused: Bool

    init(state: Binding<PrototypeState>, source: SampleNote, initialStep: String = "selection") {
        _state = state
        self.source = source
        let candidates = state.wrappedValue.notes.filter {
            $0.id != source.id && ($0.isOwned || state.wrappedValue.collected.contains($0.id))
        }
        _session = StateObject(wrappedValue: MergeJourneySession.session(source: source, candidates: candidates, initialStep: initialStep))
    }

    private var palette: Palette { Palette(dark: colorScheme == .dark, theme: theme) }
    private var candidates: [SampleNote] {
        state.notes.filter { $0.id != source.id && ($0.isOwned || state.collected.contains($0.id)) }
    }
    private var selectedNotes: [SampleNote] { [source] + candidates.filter { session.selectedIDs.contains($0.id) } }
    private var sourceCount: Int { selectedNotes.count }
    private var savedBody: String {
        if let id = session.savedNoteID, let saved = state.notes.first(where: { $0.id == id }) { return saved.body }
        return session.body
    }
    private var isSelecting: Bool { session.step == .selection || session.step == .selected }
    private var isArtifact: Bool { [.ready, .syncError, .conflict].contains(session.step) }
    private var canCreate: Bool { (2...8).contains(sourceCount) }
    private var canAccept: Bool {
        session.step == .ready && session.savedNoteID == nil && canCreate && !session.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    sampleBadge
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(isArtifact ? "New Insight" : "Merge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Close Merge")
                        .accessibilityIdentifier("journey.merge.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(MergeJourneyStep.allCases, id: \.rawValue) { step in
                            Button(step.label) {
                                editorFocused = false
                                session.preview(step, candidates: candidates)
                            }
                        }
                    } label: { Label("Preview states", systemImage: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("journey.merge.preview")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false; tagFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
            .confirmationDialog("Discard this Merge?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Merge", role: .destructive) { discard() }
                    .accessibilityIdentifier("journey.merge.discard-confirm")
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Only this sample task and its draft are removed. Your source notes stay unchanged.") }
            .confirmationDialog("Cancel this Merge?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel Merge", role: .destructive) { discard() }
                Button("Keep Merge", role: .cancel) {}
            } message: { Text("Closing the screen keeps this task. Cancel removes only this sample task and draft.") }
            .tint(palette.ink)
        }
        .presentationDragIndicator(.visible)
    }

    private var sampleBadge: some View {
        Label("Local workflow sample", systemImage: "iphone")
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(palette.accent.opacity(0.08), in: Capsule())
            .accessibilityIdentifier("journey.merge.sample")
    }

    @ViewBuilder private var content: some View {
        if isSelecting { selectionContent }
        else if isArtifact { artifactContent }
        else {
            switch session.step {
            case .progress: progressContent
            case .background: backgroundContent
            case .failed: failedContent
            case .saved: savedContent
            case .cancelled: cancelledContent
            default: EmptyView()
            }
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Bring a few ideas together.", detail: "Choose from your notes and Collect. Your original notes remain intact.")
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("STARTING NOTE")
                sourceRow(source, fixed: true, selected: true)
                    .accessibilityIdentifier("journey.merge.anchor")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.ink.opacity(0.7))
                TextField("Search notes and Collect", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("journey.merge.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Clear source search")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("ADD SOURCES")
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, note in
                    if query.isEmpty || note.searchableText.localizedCaseInsensitiveContains(query) {
                        let selected = session.selectedIDs.contains(note.id)
                        Button {
                            if selected { session.selectedIDs.remove(note.id) }
                            else if sourceCount < 8 { session.selectedIDs.insert(note.id) }
                        } label: { sourceRow(note, fixed: false, selected: selected) }
                        .buttonStyle(.plain)
                        .disabled(!selected && sourceCount >= 8)
                        .accessibilityLabel("\(note.excerpt), by \(note.author)")
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityIdentifier("journey.merge.candidate.\(index)")
                    }
                }
                if !candidates.contains(where: { query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query) }) {
                    ContentUnavailableView.search(text: query)
                }
            }
            Text("This review uses 2–8 sources, including your starting note.")
                .font(.footnote).foregroundStyle(palette.ink.opacity(0.72))
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            heading("Weaving ideas", detail: "Review the in-progress state before opening the prepared insight.")
            VStack(spacing: 22) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 54, weight: .light)).foregroundStyle(palette.accent)
                    .padding(.top, 8).accessibilityHidden(true)
                Text("\(sourceCount) sources, one new perspective.")
                    .font(.title3).multilineTextAlignment(.center)
                ProgressView(value: 0.55).tint(palette.accent)
                    .accessibilityLabel("Simulated progress")
                    .accessibilityValue("Preview only")
                Text("Prepared content · no AI request is running")
                    .font(.caption).foregroundStyle(palette.ink.opacity(0.72))
            }
            .padding(24).frame(maxWidth: .infinity)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 24))
            sourcesDisclosure
            Text("You can leave this screen and return to the same sample task.")
                .font(.subheadline).foregroundStyle(palette.ink.opacity(0.76))
        }
        .accessibilityIdentifier("journey.merge.progress")
    }

    private var backgroundContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Pick it up when you’re ready.", detail: "This task stays in the local session when you close Merge.")
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "rectangle.stack.badge.clock").font(.title2).foregroundStyle(palette.accent)
                    Spacer()
                    Text("SAMPLE TASK").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(palette.ink.opacity(0.7))
                }
                Text(source.excerpt).font(.system(.title3, design: .serif))
                Label("\(sourceCount) sources · progress preview", systemImage: "circle.dotted")
                    .font(.subheadline).foregroundStyle(palette.ink.opacity(0.76))
                Button { session.step = .progress } label: {
                    Label("Resume Merge", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.glassProminent).tint(palette.ink)
                    .accessibilityIdentifier("journey.merge.resume")
            }
            .padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 24))
            Text("Reopen Merge from the same note to resume. Background processing and notifications are not connected in this sample.")
                .font(.footnote).foregroundStyle(palette.ink.opacity(0.72))
        }
    }

    private var artifactContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A new thought, ready for your voice.")
                .font(.system(.title2, design: .serif)).foregroundStyle(palette.ink)
            Text(session.savedNoteID == nil ? "Prepared sample insight · edit the body and tags, then Accept to keep a private note." : "This task was already accepted. Previewing its states does not change the saved note.")
                .font(.footnote).foregroundStyle(palette.ink.opacity(0.74))
            syncStatus
            TextEditor(text: $session.body)
                .font(.system(.body, design: .serif)).lineSpacing(5)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(12)
                .frame(minHeight: typeSize.isAccessibilitySize ? 420 : 320)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.rule, lineWidth: 0.7))
                .accessibilityLabel("Merge insight body")
                .accessibilityIdentifier("journey.merge.body")
            tagEditor
            sourcesDisclosure
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.tags, id: \.self) { tag in
                        Button { session.tags.removeAll { $0 == tag } } label: {
                            HStack(spacing: 7) { Text(tag); Image(systemName: "xmark").font(.caption2) }
                                .font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44)
                        }.buttonStyle(.glass)
                            .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a tag", text: $tagInput)
                    .textInputAutocapitalization(.words).submitLabel(.done)
                    .focused($tagFocused).onSubmit(addTag)
                    .accessibilityIdentifier("journey.merge.tag")
                Button(action: addTag) {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add tag")
            }
            .padding(.leading, 12)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var syncStatus: some View {
        if session.step == .syncError {
            statusPanel(title: "Sync issue — sample", icon: "exclamationmark.icloud", detail: "Your edits remain in this local session. Retry previews recovery without contacting a server.") {
                Button { session.statusMessage = "Recovery preview complete · draft kept locally"; session.step = .ready } label: {
                    Text("Retry sample sync").frame(minHeight: 44)
                }.buttonStyle(.glass)
                    .accessibilityIdentifier("journey.merge.retry")
            }
        } else if session.step == .conflict {
            statusPanel(title: "Two versions — sample", icon: "arrow.triangle.2.circlepath", detail: "Another prepared draft differs from this one. Reload replaces this local body and tags; Keep retains your edits.") {
                VStack(spacing: 10) {
                    Button {
                        session.body = MergeJourneySession.otherVersion
                        session.tags = ["Ideas", "Connections"]
                        session.statusMessage = "Alternate sample version loaded locally"
                        session.step = .ready
                    } label: { Text("Reload server version").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glass)
                        .accessibilityIdentifier("journey.merge.reload")
                    Button { session.statusMessage = "Your version retained in this sample"; session.step = .ready } label: {
                        Text("Keep my version").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glass)
                        .accessibilityIdentifier("journey.merge.keep")
                }
            }
        } else {
            Label(session.statusMessage, systemImage: "checkmark.circle")
                .font(.footnote).foregroundStyle(palette.ink.opacity(0.76))
                .accessibilityIdentifier("journey.merge.sync-status")
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 44, weight: .light)).foregroundStyle(palette.accent).accessibilityHidden(true)
            heading("Couldn’t weave", detail: "This is a recoverable failure preview. Your selected sources and local draft are still here.")
            sourcesDisclosure
            Button { session.step = .progress } label: {
                Label("Retry Merge", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.glassProminent).tint(palette.ink)
                .accessibilityIdentifier("journey.merge.retry")
            Button { session.step = .selected } label: { Text("Review selected sources").frame(minHeight: 44) }
                .buttonStyle(.glass)
        }
    }

    private var savedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "checkmark.circle").font(.system(size: 48, weight: .light)).foregroundStyle(palette.accent).accessibilityHidden(true)
            heading(session.savedNoteID == nil ? "Saved state preview" : "Saved to your notes", detail: session.savedNoteID == nil ? "This preview has not created a note. Return to the insight and choose Accept to save it locally." : "Your new note is private and available in Home. Its source notes are unchanged.")
            Text(savedBody).font(.system(.body, design: .serif)).lineSpacing(5).lineLimit(7)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
            Label("Private · this app session", systemImage: "lock")
                .font(.footnote).foregroundStyle(palette.ink.opacity(0.76))
            if session.savedNoteID == nil {
                Button { session.step = .ready } label: { Text("Return to insight").frame(minHeight: 44) }
                    .buttonStyle(.glass)
            }
        }
        .accessibilityIdentifier("journey.merge.saved")
    }

    private var cancelledContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "xmark.circle").font(.system(size: 48, weight: .light)).foregroundStyle(palette.ink.opacity(0.7)).accessibilityHidden(true)
            heading(session.wasDiscarded ? "Merge discarded" : "Cancelled state preview", detail: "Your source notes remain unchanged. No new note is created until you choose Accept.")
            Button { session.restart() } label: { Text("Start a new Merge").frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(.glassProminent).tint(palette.ink)
        }
    }

    private var sourcesDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.excerpt).font(.subheadline)
                        Text(note.author).font(.caption).foregroundStyle(palette.ink.opacity(0.7))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 12)
        } label: { Label("\(sourceCount) source notes", systemImage: "square.stack") }
        .font(.subheadline).padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var actionDock: some View {
        if isSelecting {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(sourceCount) selected").font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("journey.merge.count")
                    Text("2–8 sources").font(.caption).foregroundStyle(palette.ink.opacity(0.72))
                }
                Spacer()
                Button { editorFocused = false; session.step = .progress } label: {
                    Label("Create Merge", systemImage: "sparkles").frame(minHeight: 48)
                }.buttonStyle(.glassProminent).tint(palette.ink).disabled(!canCreate)
                    .accessibilityIdentifier("journey.merge.create")
            }.padding(18).background(.regularMaterial)
        } else if isArtifact {
            HStack(spacing: 12) {
                Button { editorFocused = false; confirmDiscard = true } label: {
                    Text("Discard").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.glass)
                    .accessibilityIdentifier("journey.merge.discard")
                Button(action: accept) {
                    Label("Accept", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.glassProminent).tint(palette.ink).disabled(!canAccept)
                    .accessibilityIdentifier("journey.merge.accept")
            }.padding(18).background(.regularMaterial)
        } else if session.step == .progress {
            VStack(spacing: 10) {
                Button { session.step = .ready } label: {
                    Text("Review sample insight").frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.glassProminent).tint(palette.ink)
                    .accessibilityIdentifier("journey.merge.continue")
                HStack {
                    Button { session.step = .background } label: {
                        Text("Leave in background").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glass)
                        .accessibilityIdentifier("journey.merge.background")
                    Button { confirmCancel = true } label: { Text("Cancel").frame(minWidth: 64, minHeight: 44) }
                }
            }.padding(18).background(.regularMaterial)
        } else if session.step == .saved || session.step == .background || session.step == .cancelled {
            Button { close() } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(.glassProminent).tint(palette.ink).padding(18).background(.regularMaterial)
        } else if session.step == .failed {
            Button { confirmCancel = true } label: { Text("Cancel Merge").frame(minHeight: 44) }.padding(14)
        }
    }

    private func sourceRow(_ note: SampleNote, fixed: Bool, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: fixed ? "lock.fill" : selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(selected ? palette.ink : palette.ink.opacity(0.55))
                .frame(width: 24).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(note.excerpt).font(.system(.body, design: .serif)).lineLimit(3)
                Text(fixed ? "Fixed source · \(note.author)" : "\(note.author) · \(note.isOwned ? "My note" : "Collect")")
                    .font(.caption).foregroundStyle(palette.ink.opacity(0.72))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(selected ? palette.ink.opacity(0.06) : palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? palette.ink.opacity(0.32) : palette.rule, lineWidth: selected ? 1 : 0.6))
        .foregroundStyle(palette.ink)
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.largeTitle, design: .serif)).tracking(-0.5).foregroundStyle(palette.ink)
            Text(detail).font(.subheadline).lineSpacing(3).foregroundStyle(palette.ink.opacity(0.76))
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(palette.ink.opacity(0.72))
    }

    private func statusPanel<Actions: View>(title: String, icon: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).lineSpacing(3).foregroundStyle(palette.ink.opacity(0.8))
            actions()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        if !session.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { session.tags.append(tag) }
        tagInput = ""
        tagFocused = false
    }

    private func accept() {
        guard canAccept else { return }
        editorFocused = false
        tagFocused = false
        if session.savedNoteID == nil {
            let note = SampleNote(id: UUID(), body: session.body, author: "You", tags: session.tags,
                                  isOwned: true, isPublic: false, date: "Just now", sampleKey: "merge-result")
            state.notes.insert(note, at: 0)
            session.savedNoteID = note.id
        }
        session.step = .saved
    }

    private func discard() {
        session.body = ""
        session.tags = []
        session.wasDiscarded = true
        session.step = .cancelled
    }

    private func close() {
        editorFocused = false
        tagFocused = false
        // Dismissal is presentation-only; retained session data is not cancelled or discarded.
        dismiss()
    }
}
