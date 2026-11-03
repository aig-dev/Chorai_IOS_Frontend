import CoreFlow
import SwiftUI
struct ChoraSoulSourcesSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var noteImportStore: NoteImportStore
    @ObservedObject var notionStore: NotionSourceStore
    let notionOAuthCoordinator: any NotionOAuthCoordinating

    @State private var localNotesExpanded = false
    @State private var notionExpanded = false
    @State private var lastAuthorizationResult: NotionAuthorizationResult?

    var body: some View {
        ChoraSectionSurface(
            title: "Soul Sources",
            identifier: "chora.sources.section",
            openLayout: true
        ) {
            VStack(spacing: 0) {
                ChoraDisclosureRow(
                    imageName: "notes",
                    title: "Local Notes",
                    summary: localNotesSummary,
                    isExpanded: localNotesExpanded,
                    identifier: "chora.sources.localNotes",
                    statusIdentifier: localNotesStatusIdentifier
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        localNotesExpanded.toggle()
                    }
                }

                if localNotesExpanded {
                    LocalNotesExpandedContent(store: noteImportStore)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .overlay(ChoraiTheme.separator)
                    .padding(.vertical, 8)

                ChoraDisclosureRow(
                    imageName: "syn",
                    title: "Notion",
                    summary: notionSummary,
                    isExpanded: notionExpanded,
                    identifier: "chora.sources.notion",
                    statusIdentifier: notionStatusIdentifier
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        notionExpanded.toggle()
                    }
                    if notionExpanded,
                       notionStore.status?.state == .connected,
                       notionStore.pages.isEmpty {
                        notionStore.searchPages(query: nil)
                    }
                }

                if notionExpanded {
                    NotionExpandedContent(store: notionStore)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onChange(of: notionStore.authorizationRequest) { request in
            guard let request else { return }
            notionOAuthCoordinator.authorize(request: request) { id, result in
                lastAuthorizationResult = result
                notionStore.authorizationCompleted(id: id, result: result)
            }
        }
        .overlay(alignment: .topLeading) {
            if let lastAuthorizationResult {
                Text(authorizationResultText(lastAuthorizationResult))
                    .font(.system(size: 1))
                    .foregroundColor(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier(
                        "chora.sources.notion.oauth.\(authorizationResultText(lastAuthorizationResult))"
                    )
            }
        }
    }

    private var localNotesSummary: String {
        if let detail = noteImportStore.detail {
            if !isKnownJobStatus(detail.status) {
                return "Unavailable"
            }
            if detail.status == .cancelled {
                return "Cancelled"
            }
            if detail.status == .failed {
                return "Import needs attention"
            }
            if detail.isSettled {
                return "\(detail.importedCount) imported · \(detail.updatedCount) updated"
            }
            return "Importing \(detail.totalFiles) files"
        }
        switch noteImportStore.phase {
        case .loading: return "Checking recent imports"
        case .failed, .ambiguous: return "Couldn’t load imports"
        default: return "Markdown and HTML"
        }
    }

    private var localNotesStatusIdentifier: String? {
        if let detail = noteImportStore.detail {
            if !isKnownJobStatus(detail.status) {
                return "chora.sources.localNotes.unknown"
            } else if detail.status == .cancelled {
                return "chora.sources.localNotes.cancelled"
            } else if detail.status == .failed {
                return "chora.sources.localNotes.failure"
            } else if detail.isSettled {
                return "chora.sources.localNotes.done"
            } else {
                return "chora.sources.localNotes.active"
            }
        } else if case .failed = noteImportStore.phase {
            return "chora.sources.localNotes.error"
        }
        return nil
    }

    private var notionSummary: String {
        if notionStore.isConnecting { return "Connecting…" }
        if notionStore.isDisconnecting { return "Disconnecting…" }
        if notionStore.statusPhase == .loading { return "Checking connection" }
        if notionStore.status == nil, notionStore.inlineError != nil {
            return "Unavailable"
        }
        guard let status = notionStore.status else { return "Unavailable" }
        switch status.state.knownValue {
        case .connected:
            return status.workspaceName ?? "Connected"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Not connected"
        case nil:
            return "Unavailable"
        }
    }

    private var notionStatusIdentifier: String? {
        if notionStore.status?.state == .connected {
            return "chora.sources.notion.connected"
        }
        if notionStore.status?.state == .disconnected {
            return "chora.sources.notion.disconnected"
        }
        if notionStore.status?.state == .connecting {
            return "chora.sources.notion.connecting"
        }
        if notionStore.status != nil,
           notionStore.status?.state.knownValue == nil {
            return "chora.sources.notion.unavailable"
        }
        if notionStore.inlineError != nil {
            return "chora.sources.notion.unavailable"
        }
        return nil
    }

    private func isKnownJobStatus(_ status: NoteImportJobStatus) -> Bool {
        status == .queued || status == .running || status == .done
            || status == .failed || status == .cancelled
    }

    private func authorizationResultText(
        _ result: NotionAuthorizationResult
    ) -> String {
        switch result {
        case .success: "success"
        case .cancelled: "cancelled"
        case .failed: "failed"
        }
    }
}

private struct LocalNotesExpandedContent: View {
    @ObservedObject var store: NoteImportStore
    @State private var showsCancelConfirmation = false
    @State private var showsDocumentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChoraActionButton(title: "Choose Files") {
                showsDocumentPicker = true
            }
            .disabled(store.phase == .submitting || store.phase == .reconciling)
            .accessibilityIdentifier("chora.sources.localNotes.chooseFiles")

            ForEach(store.selectedFiles, id: \.id) { file in
                HStack {
                    Text(file.filename)
                        .font(.subheadline)
                        .foregroundColor(ChoraiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(file.byteCount == 0 ? "Empty" : formatText(file.format))
                        .font(.caption)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(
                    "chora.sources.localNotes.selection.\(file.id)"
                )
            }

            if let detail = store.detail {
                VStack(alignment: .leading, spacing: 8) {
                    countRow("Imported", value: detail.importedCount)
                    countRow("Updated", value: detail.updatedCount)
                    countRow("Skipped", value: detail.skippedCount)
                    countRow("Failed", value: detail.failedCount)
                }
                .accessibilityElement(children: .contain)

                ForEach(detail.items, id: \.sourceKey) { item in
                    if let assetID = item.assetID {
                        NavigationLink {
                            DetailView(cardId: assetID)
                        } label: {
                            fileRow(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        fileRow(item)
                    }
                }
            }

            if let error = localErrorText {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.localNotes.inlineError")
            }

            if store.canCancelCurrentJob {
                ChoraActionButton(title: "Cancel Import", foregroundColor: .red) {
                    showsCancelConfirmation = true
                }
                .accessibilityIdentifier("chora.sources.localNotes.cancel")
            } else if store.phase == .cancelling {
                Text("Cancelling import…")
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .accessibilityIdentifier("chora.sources.localNotes.cancelling")
            } else if store.canRetrySubmission {
                ChoraActionButton(title: "Retry") { store.retry() }
                    .accessibilityIdentifier("chora.sources.localNotes.retry")
            } else if store.phase == .failed(
                .preflight(code: "file_metadata_unavailable")
            ) {
                Text("Choose the file again to retry.")
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "chora.sources.localNotes.reselect"
                    )
            } else if store.canReload, let actorID = store.actorID {
                ChoraActionButton(title: "Retry Loading") {
                    Task { await store.load(actorID: actorID) }
                }
                .accessibilityIdentifier("chora.sources.localNotes.reload")
            } else if store.needsFileReselectionForRetry {
                Text("Choose the original files again to reconcile this import.")
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.localNotes.reselect")
            } else if store.phase == .submitting || store.phase == .reconciling {
                Text("Submitting files…")
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .accessibilityIdentifier("chora.sources.localNotes.submitting")
            } else if !store.selectedFiles.isEmpty {
                ChoraActionButton(title: "Start Import") { store.start() }
                    .accessibilityIdentifier("chora.sources.localNotes.start")
            } else {
                Text("Choose Markdown or HTML files to start a local import.")
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Cancel Import?", isPresented: $showsCancelConfirmation) {
            Button("Keep Importing", role: .cancel) {}
            Button("Cancel Import", role: .destructive) { store.cancel() }
        } message: {
            Text("Files already processed will remain in Chorai.")
        }
        .sheet(isPresented: $showsDocumentPicker) {
            NoteImportDocumentPicker { files in
                store.select(files)
                showsDocumentPicker = false
            }
        }
    }

    private var localErrorText: String? {
        if let message = store.detail?.errorMessage, !message.isEmpty {
            return message
        }
        switch store.phase {
        case .ambiguous:
            return "The import outcome is unclear. Retry to reconcile it."
        case .failed(.preflight(code: "file_metadata_unavailable")):
            return "Couldn’t read file details. Choose the file again."
        case .failed:
            return "Local Notes couldn’t be refreshed. Try again."
        case .invalidSelection(.noFiles):
            return "Choose at least one supported file."
        case let .invalidSelection(.unsupportedFormat(filename)):
            return "\(filename) isn’t Markdown or HTML."
        case let .invalidSelection(.emptyFile(filename)):
            return "\(filename) is empty."
        default:
            return nil
        }
    }

    private func countRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title).foregroundColor(ChoraiTheme.secondaryInk)
            Spacer()
            Text("\(value)").foregroundColor(ChoraiTheme.ink)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }

    private func fileRow(_ item: NoteImportJobItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.originalFilename)
                .font(.subheadline)
                .foregroundColor(ChoraiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
                        Text(itemStatusText(item.status))
                .font(.caption)
                .foregroundColor(ChoraiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.originalFilename)
        .accessibilityValue(itemStatusText(item.status))
        .accessibilityIdentifier(
            "chora.sources.localNotes.file.\(item.sourceKey)"
        )
    }

    private func itemStatusText(_ status: NoteImportItemStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .imported: "Imported"
        case .updated: "Updated"
        case .skipped: "Skipped"
        case .failed: "Failed"
        default: "Unknown"
        }
    }

    private func formatText(_ format: NoteImportFormat) -> String {
        switch format {
        case .markdown: "Markdown"
        case .html: "HTML"
        default: "Unsupported"
        }
    }
}

private struct NotionExpandedContent: View {
    @ObservedObject var store: NotionSourceStore
    @State private var showsDisconnectConfirmation = false
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.inlineError {
                Text(errorText(error))
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.notion.error")
            }

            if store.status?.state == .connected {
                HStack(spacing: 10) {
                    TextField("Search pages", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundColor(ChoraiTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ChoraiTheme.surface)
                        )
                        .accessibilityIdentifier("chora.sources.notion.search")
                    Button("Search") {
                        store.searchPages(query: query.isEmpty ? nil : query)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .choraiGlassButton()
                    .accessibilityIdentifier("chora.sources.notion.search.submit")
                }

                if store.pagesPhase == .loading {
                    ProgressView("Loading pages…")
                        .tint(ChoraiTheme.ink)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                } else {
                    ForEach(store.pages) { page in
                        Button {
                            var selection = store.selectedPageIDs
                            if selection.contains(page.id) {
                                selection.removeAll { $0 == page.id }
                            } else {
                                selection.append(page.id)
                            }
                            store.setSelectedPageIDs(selection)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(store.selectedPageIDs.contains(page.id)
                                     ? "Selected"
                                     : "Select")
                                    .font(.caption)
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                Text(page.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline)
                            .foregroundColor(ChoraiTheme.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chora.sources.notion.page.\(page.id)")
                        .accessibilityAddTraits(
                            store.selectedPageIDs.contains(page.id)
                                ? .isSelected
                                : []
                        )
                    }
                }

                ForEach(store.status?.pageStatuses ?? [], id: \.pageID) { status in
                    HStack {
                        Text(status.pageID).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(pageSyncText(status.status))
                    }
                    .font(.caption)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Notion page \(status.pageID)")
                    .accessibilityValue(pageSyncText(status.status))
                    .accessibilityIdentifier("chora.sources.notion.sync.\(status.pageID)")
                }

                if !store.selectedPageIDs.isEmpty {
                    ChoraActionButton(
                        title: store.isImporting ? "Importing…" : "Import Selected"
                    ) {
                        store.startImport()
                    }
                    .disabled(store.isImporting)
                    .accessibilityIdentifier("chora.sources.notion.import")
                }

                ChoraActionButton(title: "Disconnect", foregroundColor: .red) {
                    showsDisconnectConfirmation = true
                }
                .disabled(store.isDisconnecting)
                .accessibilityIdentifier("chora.sources.notion.disconnect")
                notionImportState
            } else {
                switch store.status?.state.knownValue {
                case .disconnected:
                    ChoraActionButton(title: "Connect Notion") {
                        store.connect()
                    }
                    .accessibilityIdentifier("chora.sources.notion.connect")
                case .connecting:
                    Text("Connecting…")
                        .font(.subheadline)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                        .accessibilityIdentifier("chora.sources.notion.connecting")
                case .connected:
                    EmptyView()
                case nil:
                    ChoraActionButton(title: "Retry") { store.reloadStatus() }
                        .accessibilityIdentifier("chora.sources.notion.retryStatus")
                }

                if store.authorizationRequest != nil {
                    Text("Continue in the secure Notion sign-in window.")
                        .font(.footnote)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chora.sources.notion.authorizationReady")
                }
            }
        }
        .alert("Disconnect Notion?", isPresented: $showsDisconnectConfirmation) {
            Button("Keep Connected", role: .cancel) {}
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } message: {
            Text("Imported notes remain in Chorai.")
        }
    }

    @ViewBuilder
    private var notionImportState: some View {
        if let receipt = store.importReceipt {
            Text("Job \(receipt.jobID)")
                .font(.footnote)
                .foregroundColor(ChoraiTheme.secondaryInk)
                .accessibilityLabel("Notion import receipt")
                .accessibilityValue(receipt.jobID)
                .accessibilityIdentifier("chora.sources.notion.import.receipt")
        }
        if let job = store.importJob {
            Text(importStatusText(job.status))
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.ink)
                .accessibilityIdentifier("chora.sources.notion.import.\(job.status.knownValue == nil ? "unknown" : job.status.rawValue)")
            notionCount("Imported", value: job.imported, id: "imported")
            notionCount("Updated", value: job.updated, id: "updated")
            notionCount("Skipped", value: job.skipped, id: "skipped")
            ForEach(job.failures, id: \.pageID) { failure in
                Text("\(failure.pageID): \(failure.reason)")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Notion page \(failure.pageID) failed")
                    .accessibilityValue(failure.reason)
                    .accessibilityIdentifier("chora.sources.notion.import.failure.\(failure.pageID)")
            }
        }
    }

    private func notionCount(_ title: String, value: Int, id: String) -> some View {
        HStack { Text(title); Spacer(); Text("\(value)") }
            .font(.footnote)
            .foregroundColor(ChoraiTheme.secondaryInk)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(value)")
            .accessibilityIdentifier("chora.sources.notion.import.\(id)")
    }

    private func pageSyncText(_ status: NotionPageSyncState) -> String {
        status.knownValue.map { String(describing: $0).capitalized } ?? "Unknown"
    }

    private func importStatusText(_ status: NotionImportJobStatus) -> String {
        status.knownValue.map { String(describing: $0).capitalized } ?? "Unknown"
    }

    private func errorText(_ error: NotionSourceError) -> String {
        switch error {
        case .invalidActor: "Notion is unavailable for this account."
        case .noPagesSelected: "Select at least one Notion page."
        case .authorizationFailed: "Notion authorization wasn’t completed."
        case .requestFailed: "Notion couldn’t be refreshed. Try again."
        }
    }
}

struct ChoraField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.ink)
            TextField(placeholder, text: $text)
                .font(.body)
                .foregroundColor(ChoraiTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ChoraiTheme.surface)
                )
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct ChoraGrowthBar: View {
    let dimension: ChoraGrowthDimension
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dimension.displayName ?? "Unavailable")
                Spacer()
                Text(valueText)
                    .foregroundColor(ChoraiTheme.secondaryInk)
            }
            .font(.subheadline)
            .foregroundColor(ChoraiTheme.ink)

            ProgressView(value: min(12, max(0, value ?? 0)), total: 12)
                .progressViewStyle(.linear)
                .tint(ChoraiTheme.gold)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dimension.displayName ?? "Growth dimension")
        .accessibilityValue(value.map { "\(formatted($0)) out of 12" } ?? "Unavailable")
        .accessibilityIdentifier("chora.growth.\(dimension.rawValue)")
    }

    private var valueText: String {
        value.map { "\(formatted($0)) / 12" } ?? "Unavailable"
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct ChoraSectionSurface<Content: View>: View {
    let title: String
    let identifier: String?
    let openLayout: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        identifier: String? = nil,
        openLayout: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.identifier = identifier
        self.openLayout = openLayout
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(openLayout ? .system(.title2, design: .serif).weight(.semibold) : .title3.weight(.semibold))
                .foregroundColor(ChoraiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier ?? "chora.section.\(title)")
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(openLayout ? 0 : 20)
        .background {
            if !openLayout {
                RoundedRectangle(cornerRadius: 16)
                    .fill(ChoraiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(ChoraiTheme.separator, lineWidth: 1)
                    )
                    .cardHighlightEffect()
            }
        }
    }
}

struct ChoraLoadingRow: View {
    let text: String
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(ChoraiTheme.ink)
            Text(text)
                .font(.subheadline)
                .foregroundColor(ChoraiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

struct ChoraInlineError: View {
    let text: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            SettingsOutlineButton(title: "Retry", action: retry)
                .accessibilityIdentifier("\(identifier).retry")
        }
    }
}

private struct ChoraDisclosureRow: View {
    let imageName: String
    let title: String
    let summary: String
    let isExpanded: Bool
    let identifier: String
    let statusIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if imageName == "notes" {
                        Image(systemName: "doc.text").font(.title3)
                    } else {
                        Image(imageName).renderingMode(.template).resizable().scaledToFit()
                    }
                }
                .frame(width: 24, height: 24)
                .foregroundStyle(ChoraiTheme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(ChoraiTheme.ink)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            statusIdentifier ?? "\(identifier).summary"
                        )
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(isExpanded ? "Expanded" : "Collapsed"), \(summary)")
        .accessibilityIdentifier(identifier)
    }
}

/// Chora-only presentation of existing actions; data and mutation callbacks stay in the stores.
struct ChoraActionButton: View {
    let title: String
    var foregroundColor: Color = ChoraiTheme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .foregroundStyle(foregroundColor)
        .choraiGlassButton()
    }
}
