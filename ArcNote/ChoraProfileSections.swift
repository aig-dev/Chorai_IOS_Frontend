import CoreFlow
import SwiftUI
struct ChoraSoulSourcesSection: View {
    @ObservedObject var noteImportStore: NoteImportStore
    @ObservedObject var notionStore: NotionSourceStore
    let notionOAuthCoordinator: any NotionOAuthCoordinating

    @State private var localNotesExpanded = false
    @State private var notionExpanded = false
    @State private var lastAuthorizationResult: NotionAuthorizationResult?

    var body: some View {
        ChoraSectionSurface(
            title: "Soul Sources",
            identifier: "chora.sources.section"
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localNotesExpanded.toggle()
                    }
                }

                if localNotesExpanded {
                    LocalNotesExpandedContent(store: noteImportStore)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .background(Color.white.opacity(0.16))
                    .padding(.vertical, 8)

                ChoraDisclosureRow(
                    imageName: "syn",
                    title: "Notion",
                    summary: notionSummary,
                    isExpanded: notionExpanded,
                    identifier: "chora.sources.notion",
                    statusIdentifier: notionStatusIdentifier
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
            SettingsOutlineButton(title: "Choose Files") {
                showsDocumentPicker = true
            }
            .disabled(store.phase == .submitting || store.phase == .reconciling)
            .accessibilityIdentifier("chora.sources.localNotes.chooseFiles")

            ForEach(store.selectedFiles, id: \.id) { file in
                HStack {
                    Text(file.filename)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(file.byteCount == 0 ? "Empty" : formatText(file.format))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.58))
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
                    .foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.localNotes.inlineError")
            }

            if store.canCancelCurrentJob {
                SettingsOutlineButton(title: "Cancel Import", foregroundColor: Color(red: 1, green: 0.5, blue: 0.54)) {
                    showsCancelConfirmation = true
                }
                .accessibilityIdentifier("chora.sources.localNotes.cancel")
            } else if store.phase == .cancelling {
                Text("Cancelling import…")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
                    .accessibilityIdentifier("chora.sources.localNotes.cancelling")
            } else if store.canRetrySubmission {
                SettingsOutlineButton(title: "Retry") { store.retry() }
                    .accessibilityIdentifier("chora.sources.localNotes.retry")
            } else if store.phase == .failed(
                .preflight(code: "file_metadata_unavailable")
            ) {
                Text("Choose the file again to retry.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "chora.sources.localNotes.reselect"
                    )
            } else if store.canReload, let actorID = store.actorID {
                SettingsOutlineButton(title: "Retry Loading") {
                    Task { await store.load(actorID: actorID) }
                }
                .accessibilityIdentifier("chora.sources.localNotes.reload")
            } else if store.needsFileReselectionForRetry {
                Text("Choose the original files again to reconcile this import.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.localNotes.reselect")
            } else if store.phase == .submitting || store.phase == .reconciling {
                Text("Submitting files…")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
                    .accessibilityIdentifier("chora.sources.localNotes.submitting")
            } else if !store.selectedFiles.isEmpty {
                SettingsOutlineButton(title: "Start Import") { store.start() }
                    .accessibilityIdentifier("chora.sources.localNotes.start")
            } else {
                Text("Choose Markdown or HTML files to start a local import.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.55))
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
            Text(title).foregroundColor(.white.opacity(0.62))
            Spacer()
            Text("\(value)").foregroundColor(.white)
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
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
                        Text(itemStatusText(item.status))
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
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
                    .foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.notion.error")
            }

            if store.status?.state == .connected {
                HStack(spacing: 10) {
                    TextField("Search pages", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        )
                        .accessibilityIdentifier("chora.sources.notion.search")
                    Button("Search") {
                        store.searchPages(query: query.isEmpty ? nil : query)
                    }
                    .foregroundColor(.white)
                    .accessibilityIdentifier("chora.sources.notion.search.submit")
                }

                if store.pagesPhase == .loading {
                    ProgressView("Loading pages…")
                        .tint(.white)
                        .foregroundColor(.white.opacity(0.65))
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
                                    .foregroundColor(.white.opacity(0.6))
                                Text(page.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
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
                    .foregroundColor(.white.opacity(0.62))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Notion page \(status.pageID)")
                    .accessibilityValue(pageSyncText(status.status))
                    .accessibilityIdentifier("chora.sources.notion.sync.\(status.pageID)")
                }

                if !store.selectedPageIDs.isEmpty {
                    SettingsOutlineButton(
                        title: store.isImporting ? "Importing…" : "Import Selected"
                    ) {
                        store.startImport()
                    }
                    .disabled(store.isImporting)
                    .accessibilityIdentifier("chora.sources.notion.import")
                }

                SettingsOutlineButton(title: "Disconnect", foregroundColor: Color(red: 1, green: 0.5, blue: 0.54)) {
                    showsDisconnectConfirmation = true
                }
                .disabled(store.isDisconnecting)
                .accessibilityIdentifier("chora.sources.notion.disconnect")
                notionImportState
            } else {
                switch store.status?.state.knownValue {
                case .disconnected:
                    SettingsOutlineButton(title: "Connect Notion") {
                        store.connect()
                    }
                    .accessibilityIdentifier("chora.sources.notion.connect")
                case .connecting:
                    Text("Connecting…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                        .accessibilityIdentifier("chora.sources.notion.connecting")
                case .connected:
                    EmptyView()
                case nil:
                    SettingsOutlineButton(title: "Retry") { store.reloadStatus() }
                        .accessibilityIdentifier("chora.sources.notion.retryStatus")
                }

                if store.authorizationRequest != nil {
                    Text("Continue in the secure Notion sign-in window.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))
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
                .foregroundColor(.white.opacity(0.65))
                .accessibilityLabel("Notion import receipt")
                .accessibilityValue(receipt.jobID)
                .accessibilityIdentifier("chora.sources.notion.import.receipt")
        }
        if let job = store.importJob {
            Text(importStatusText(job.status))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .accessibilityIdentifier("chora.sources.notion.import.\(job.status.knownValue == nil ? "unknown" : job.status.rawValue)")
            notionCount("Imported", value: job.imported, id: "imported")
            notionCount("Updated", value: job.updated, id: "updated")
            notionCount("Skipped", value: job.skipped, id: "skipped")
            ForEach(job.failures, id: \.pageID) { failure in
                Text("\(failure.pageID): \(failure.reason)")
                    .font(.footnote)
                    .foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
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
            .foregroundColor(.white.opacity(0.72))
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
                .foregroundColor(.white)
            TextField(placeholder, text: $text)
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .cardHighlightEffect()
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
                    .foregroundColor(.white.opacity(0.62))
            }
            .font(.subheadline)
            .foregroundColor(.white)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    if let value {
                        Capsule()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: proxy.size.width * value / 12)
                    }
                }
            }
            .frame(height: 6)
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
    @ViewBuilder let content: Content

    init(
        title: String,
        identifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier ?? "chora.section.\(title)")
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .cardHighlightEffect()
        )
    }
}

struct ChoraLoadingRow: View {
    let text: String
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
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
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
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
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            statusIdentifier ?? "\(identifier).summary"
                        )
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(isExpanded ? "Expanded" : "Collapsed"), \(summary)")
        .accessibilityIdentifier(identifier)
    }
}
