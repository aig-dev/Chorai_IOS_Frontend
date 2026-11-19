import SwiftUI

struct TrashView: View {
    @StateObject private var trashManager = TrashManager.shared
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: TrashCard?
    @State private var busyCardID: String?
    @State private var actionError: String?
    @State private var actionErrorCardID: String?

    var body: some View {
        List {
            Section {
                Label {
                    Text("Notes are kept here while offline. Cloud Trash retains synced deletions for 30 days.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .listRowBackground(Color.clear)
            }

            if trashManager.isLoading && trashManager.trashCards.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading trash...")
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityIdentifier("trash.loading")
                }
                .listRowBackground(ChoraiTheme.surface)
            } else if let error = trashManager.error, trashManager.trashCards.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            trashManager.loadTrashCards(refresh: true)
                        }
                        .frame(minWidth: 88, minHeight: 44)
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .accessibilityIdentifier("trash.load.error")
                }
                .listRowBackground(ChoraiTheme.surface)
            } else if trashManager.trashCards.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.largeTitle)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        Text("Trash is empty")
                            .font(.headline)
                        Text("Deleted notes will appear here")
                            .font(.subheadline)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .accessibilityIdentifier("trash.empty")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(trashManager.trashCards) { card in
                        TrashCardView(
                            card: card,
                            isBusy: busyCardID == card.id,
                            actionError: actionErrorCardID == card.id && !showDeleteConfirmation
                                ? actionError
                                : nil,
                            onRestore: { restore(card) },
                            onPermanentlyDelete: {
                                guard busyCardID == nil else { return }
                                actionError = nil
                                actionErrorCardID = nil
                                cardToDelete = card
                                showDeleteConfirmation = true
                            }
                        )
                        .listRowBackground(ChoraiTheme.surface)
                    }
                }

                if trashManager.hasMoreData && !trashManager.isLoading {
                    Button("Load More") {
                        trashManager.loadMoreTrashCards()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("trash.load-more")
                }

                if trashManager.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .choraiPageBackground()
        .foregroundStyle(ChoraiTheme.ink)
        .navigationTitle("Trash Can")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("screen.trash")
        .refreshable {
            trashManager.refreshTrashCards()
        }
        .onAppear {
            trashManager.loadTrashCards(refresh: true)
        }
        .sheet(isPresented: $showDeleteConfirmation, onDismiss: clearDeleteSelection) {
            deleteConfirmation
        }
    }

    private var deleteConfirmation: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Confirm delete this note?")
                        .font(.body)
                        .foregroundStyle(ChoraiTheme.ink)
                    if let actionError {
                        Text(actionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("trash.delete.error")
                    }
                }
                .listRowBackground(ChoraiTheme.surface)

                Section {
                    Button(role: .destructive, action: permanentlyDeleteSelectedCard) {
                        HStack(spacing: 12) {
                            Text("Permanently Delete")
                            Spacer()
                            if busyCardID != nil {
                                ProgressView()
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(busyCardID != nil)
                    .accessibilityIdentifier("trash.delete.confirm")

                    Button("Cancel", role: .cancel, action: closeDeleteConfirmation)
                        .frame(minHeight: 44)
                        .disabled(busyCardID != nil)
                        .accessibilityIdentifier("trash.delete.cancel")
                }
                .listRowBackground(ChoraiTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .choraiPageBackground()
            .navigationTitle("Delete Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: closeDeleteConfirmation) {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(busyCardID != nil)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("trash.delete.close")
                }
            }
            .accessibilityIdentifier("trash.delete.confirmation")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busyCardID != nil)
    }

    private func restore(_ card: TrashCard) {
        guard busyCardID == nil else { return }
        busyCardID = card.id
        actionError = nil
        actionErrorCardID = nil
        trashManager.restoreCard(cardId: card.id) { result in
            busyCardID = nil
            switch result {
            case .success:
                break
            case .failure:
                actionError = "Couldn’t restore this note. Please try again."
                actionErrorCardID = card.id
            }
        }
    }

    private func clearDeleteSelection() {
        cardToDelete = nil
        actionError = nil
        actionErrorCardID = nil
    }

    private func closeDeleteConfirmation() {
        guard busyCardID == nil else { return }
        showDeleteConfirmation = false
        clearDeleteSelection()
    }

    private func permanentlyDeleteSelectedCard() {
        guard let card = cardToDelete, busyCardID == nil else { return }
        busyCardID = card.id
        actionError = nil
        actionErrorCardID = nil
        trashManager.permanentlyDeleteCard(cardId: card.id) { result in
            busyCardID = nil
            switch result {
            case .success:
                closeDeleteConfirmation()
            case .failure:
                actionError = "Couldn’t permanently delete this note. Please try again."
                actionErrorCardID = card.id
            }
        }
    }
}

struct TrashCardView: View {
    let card: TrashCard
    let isBusy: Bool
    let actionError: String?
    let onRestore: () -> Void
    let onPermanentlyDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deleted on: \(formatTrashDate(card.deletedAt))")
                .font(.caption)
                .foregroundStyle(ChoraiTheme.secondaryInk)

            HTMLTextRenderer(cardID: card.id, htmlContent: card.content, maxLines: 3)

            if !card.tags.isEmpty {
                Text(card.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Cloud Trash retains synced deletions for 30 days.")
                .font(.caption)
                .foregroundStyle(ChoraiTheme.gold)

            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trash.card.error.\(card.id)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    restoreButton
                    Spacer(minLength: 12)
                    deleteButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    restoreButton
                    deleteButton
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trash.card.\(card.id)")
    }

    private var restoreButton: some View {
        Button(action: onRestore) {
            HStack(spacing: 8) {
                if isBusy { ProgressView() }
                Text("Restore")
            }
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
        .accessibilityIdentifier("trash.card.restore.\(card.id)")
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onPermanentlyDelete) {
            Text("Permanently Delete")
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
        .accessibilityIdentifier("trash.card.delete.\(card.id)")
    }

    // MARK: 格式化删除日期
    private func formatTrashDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)

        if let date {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM dd, yyyy"
            return displayFormatter.string(from: date)
        }

        return "Unknown date"
    }
}

#Preview {
    NavigationStack { TrashView() }
}
