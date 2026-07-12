import CoreFlow
import SwiftUI
import UIKit

struct ChoraIdentitySection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String

    @State private var selectedImage: UIImage?
    @State private var showsImagePicker = false

    var body: some View {
        ChoraSectionSurface(
            title: "Identity",
            identifier: "chora.identity.section"
        ) {
            switch store.phase {
            case .idle, .loading:
                ChoraLoadingRow(
                    text: "Loading Chora identity…",
                    identifier: "chora.identity.loading"
                )
            case .failed:
                ChoraInlineError(
                    text: "Chora’s identity couldn’t be loaded.",
                    identifier: "chora.identity.error"
                ) {
                    Task { await store.load(humanActorID: humanActorID) }
                }
            case .ready:
                identityForm
            }
        }
        .sheet(isPresented: $showsImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { image in
            guard let image,
                  let data = image.jpegData(compressionQuality: 0.88) else {
                return
            }
            store.setAvatarDraft(
                ChoraAvatarDraft(
                    data: data,
                    filename: "chora-avatar.jpg",
                    mimeType: "image/jpeg"
                )
            )
        }
    }

    private var identityForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Button {
                    showsImagePicker = true
                } label: {
                    avatar
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                Color.white.opacity(0.22),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chora avatar. Choose a photo")
                .accessibilityIdentifier("chora.identity.avatar")

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.identity?.displayName ?? "Chora")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your bound companion")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.58))
                }
                Spacer(minLength: 0)
            }

            ChoraField(
                label: "Display name",
                placeholder: "Chora",
                text: Binding(
                    get: { store.displayNameDraft },
                    set: store.setDisplayNameDraft
                ),
                identifier: "chora.identity.displayName"
            )

            ChoraField(
                label: "Preferred address",
                placeholder: "How Chora addresses you",
                text: Binding(
                    get: { store.preferredAddressDraft ?? "" },
                    set: { value in
                        store.setPreferredAddressDraft(
                            value.isEmpty ? nil : value
                        )
                    }
                ),
                identifier: "chora.identity.preferredAddress"
            )

            ForEach(identityErrors, id: \.0) { field, message in
                Text(message)
                    .font(.footnote)
                    .foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "chora.identity.error.\(field)"
                    )
            }

            Button {
                store.save()
            } label: {
                HStack(spacing: 8) {
                    if store.isSaving {
                        ProgressView().tint(.white)
                    }
                    Text(store.isSaving ? "Saving…" : "Save")
                        .font(.body.weight(.medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isSaving || store.changedFields.isEmpty)
            .opacity(
                store.isSaving || store.changedFields.isEmpty ? 0.55 : 1
            )
            .accessibilityIdentifier("chora.identity.save")
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let avatarURL = store.identity?.avatarURL,
                  !avatarURL.isEmpty,
                  let url = URL(
                    string: APIConfiguration.resourceURLString(avatarURL)
                  ) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image("bot").resizable().aspectRatio(contentMode: .fill)
                }
            }
        } else {
            Image("bot")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private var identityErrors: [(String, String)] {
        var values: [(String, String)] = []
        if store.fieldErrors[.displayName] != nil {
            values.append(("displayName", "Display name wasn’t saved."))
        }
        if store.fieldErrors[.preferredAddress] != nil {
            values.append(("preferredAddress", "Preferred address wasn’t saved."))
        }
        if store.fieldErrors[.avatar] != nil {
            values.append(("avatar", "Avatar wasn’t saved."))
        }
        return values
    }
}

struct ChoraGrowthSection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String

    var body: some View {
        ChoraSectionSurface(
            title: "Growth",
            identifier: "chora.growth.section"
        ) {
            switch store.growthPhase {
            case .idle, .loading:
                ChoraLoadingRow(
                    text: "Loading Growth…",
                    identifier: "chora.growth.loading"
                )
            case .unavailable:
                ChoraInlineError(
                    text: "Growth is unavailable right now.",
                    identifier: "chora.growth.unavailable"
                ) {
                    Task { await store.load(humanActorID: humanActorID) }
                }
            case .ready:
                growthContent
            }
        }
    }

    private var growthContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stage")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(stageName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.growth.stage")
            }

            VStack(spacing: 12) {
                ForEach(
                    ChoraGrowthDimension.canonicalRenderOrder,
                    id: \.rawValue
                ) { dimension in
                    ChoraGrowthBar(
                        dimension: dimension,
                        value: value(for: dimension)
                    )
                }
            }
        }
    }

    private var stageName: String {
        store.growth?.committedStage.displayName ?? "Unavailable"
    }

    private func value(for dimension: ChoraGrowthDimension) -> Double? {
        store.growth?.dimensions.first {
            $0.dimension == dimension
        }?.displayValue
    }
}

struct ChoraSoulSourcesSection: View {
    @ObservedObject var noteImportStore: NoteImportStore
    @ObservedObject var notionStore: NotionSourceStore

    @State private var localNotesExpanded = false
    @State private var notionExpanded = false

    var body: some View {
        ChoraSectionSurface(title: "Soul Sources") {
            VStack(spacing: 0) {
                ChoraDisclosureRow(
                    imageName: "notes",
                    title: "Local Notes",
                    summary: localNotesSummary,
                    isExpanded: localNotesExpanded,
                    identifier: "chora.sources.localNotes"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localNotesExpanded.toggle()
                    }
                }

                localNotesStatusMarker

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
                    identifier: "chora.sources.notion"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notionExpanded.toggle()
                    }
                    if !notionExpanded,
                       notionStore.status?.state == .connected,
                       notionStore.pages.isEmpty {
                        notionStore.searchPages(query: nil)
                    }
                }

                notionStatusMarker

                if notionExpanded {
                    NotionExpandedContent(store: notionStore)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var localNotesSummary: String {
        if let detail = noteImportStore.detail {
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

    @ViewBuilder
    private var localNotesStatusMarker: some View {
        if let detail = noteImportStore.detail {
            if detail.status == .failed {
                ChoraStatusMarker(identifier: "chora.sources.localNotes.failure")
            } else if detail.isSettled {
                ChoraStatusMarker(identifier: "chora.sources.localNotes.done")
            } else {
                ChoraStatusMarker(identifier: "chora.sources.localNotes.active")
            }
        } else if case .failed = noteImportStore.phase {
            ChoraStatusMarker(identifier: "chora.sources.localNotes.error")
        }
    }

    private var notionSummary: String {
        if notionStore.isConnecting { return "Connecting…" }
        if notionStore.isDisconnecting { return "Disconnecting…" }
        if notionStore.statusPhase == .loading { return "Checking connection" }
        if notionStore.inlineError != nil { return "Connection needs attention" }
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

    @ViewBuilder
    private var notionStatusMarker: some View {
        if notionStore.inlineError != nil {
            ChoraStatusMarker(identifier: "chora.sources.notion.error")
        } else if notionStore.status?.state == .connected {
            ChoraStatusMarker(identifier: "chora.sources.notion.connected")
        } else if notionStore.status?.state == .disconnected {
            ChoraStatusMarker(identifier: "chora.sources.notion.disconnected")
        }
    }
}

struct ChoraChatHistorySection: View {
    let humanActorID: String
    let visibility: ChatHistoryVisibility
    let now: @Sendable () -> Date

    @State private var showsConfirmation = false
    @State private var didClear = false

    var body: some View {
        ChoraSectionSurface(title: "Chat History") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Previous messages are hidden on this device.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    showsConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image("trash")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                        Text(didClear ? "Chat History Hidden" : "Clear Chat History")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .foregroundColor(Color(red: 1, green: 0.46, blue: 0.5))
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chora.chat.clear")
            }
        }
        .alert("Clear Chat History?", isPresented: $showsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Previous Messages", role: .destructive) {
                visibility.clear(actorID: humanActorID, at: now())
                didClear = true
            }
        } message: {
            Text("Previous messages will be hidden on this device. They are not deleted from Chorai.")
        }
    }
}

private struct LocalNotesExpandedContent: View {
    @ObservedObject var store: NoteImportStore
    @State private var showsCancelConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            if canCancel {
                ChoraOutlineButton(title: "Cancel Import", destructive: true) {
                    showsCancelConfirmation = true
                }
                .accessibilityIdentifier("chora.sources.localNotes.cancel")
            } else if canRetry {
                ChoraOutlineButton(title: "Retry") { store.retry() }
                    .accessibilityIdentifier("chora.sources.localNotes.retry")
            } else if !store.selectedFiles.isEmpty {
                ChoraOutlineButton(title: "Start Import") { store.start() }
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
    }

    private var canCancel: Bool {
        switch store.phase {
        case .submitting, .reconciling, .polling: true
        default: false
        }
    }

    private var canRetry: Bool {
        switch store.phase {
        case .ambiguous, .failed: true
        default: false
        }
    }

    private var localErrorText: String? {
        if let message = store.detail?.errorMessage, !message.isEmpty {
            return message
        }
        switch store.phase {
        case .ambiguous:
            return "The import outcome is unclear. Retry to reconcile it."
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
            Text(item.status.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.originalFilename)
        .accessibilityValue(item.status.rawValue)
        .accessibilityIdentifier(
            "chora.sources.localNotes.file.\(item.sourceKey)"
        )
    }
}

private struct NotionExpandedContent: View {
    @ObservedObject var store: NotionSourceStore
    @State private var showsDisconnectConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.inlineError {
                Text(errorText(error))
                    .font(.footnote)
                    .foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.sources.notion.inlineError")
            }

            if store.status?.state == .connected {
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
                                Image(systemName: store.selectedPageIDs.contains(page.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                Text(page.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chora.sources.notion.page.\(page.id)")
                    }
                }

                if !store.selectedPageIDs.isEmpty {
                    ChoraOutlineButton(
                        title: store.isImporting ? "Importing…" : "Import Selected"
                    ) {
                        store.startImport()
                    }
                    .disabled(store.isImporting)
                    .accessibilityIdentifier("chora.sources.notion.import")
                }

                ChoraOutlineButton(title: "Disconnect", destructive: true) {
                    showsDisconnectConfirmation = true
                }
                .disabled(store.isDisconnecting)
                .accessibilityIdentifier("chora.sources.notion.disconnect")
            } else {
                ChoraOutlineButton(
                    title: store.isConnecting ? "Connecting…" : "Connect Notion"
                ) {
                    store.connect()
                }
                .disabled(store.isConnecting)
                .accessibilityIdentifier("chora.sources.notion.connect")

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

    private func errorText(_ error: NotionSourceError) -> String {
        switch error {
        case .invalidActor: "Notion is unavailable for this account."
        case .noPagesSelected: "Select at least one Notion page."
        case .authorizationFailed: "Notion authorization wasn’t completed."
        case .requestFailed: "Notion couldn’t be refreshed. Try again."
        }
    }
}

private struct ChoraField: View {
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
                .accessibilityIdentifier(identifier)
        }
    }
}

private struct ChoraGrowthBar: View {
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

private struct ChoraSectionSurface<Content: View>: View {
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

private struct ChoraLoadingRow: View {
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

private struct ChoraInlineError: View {
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
            ChoraOutlineButton(title: "Retry", action: retry)
        }
    }
}

private struct ChoraDisclosureRow: View {
    let imageName: String
    let title: String
    let summary: String
    let isExpanded: Bool
    let identifier: String
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
        .accessibilityValue(summary)
        .accessibilityIdentifier(identifier)
    }
}

private struct ChoraOutlineButton: View {
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(
                    destructive
                        ? Color(red: 1, green: 0.5, blue: 0.54)
                        : .white
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ChoraStatusMarker: View {
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(identifier)
            .accessibilityIdentifier(identifier)
    }
}
