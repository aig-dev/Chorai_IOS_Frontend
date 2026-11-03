import SwiftUI
import CoreFlow

/// The store remains the only selection owner. Layout never changes a choice.
struct ChooseInterestsView: View {
    @State private var showTabBar = false
    @StateObject private var store: InterestSelectionStore
    private let actorID: String?
    private let onComplete: (() -> Void)?

    init(
        service: any CoreInterestSelectionServing = NetworkCoreInterestSelectionService(),
        actorID: String? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        _store = StateObject(wrappedValue: InterestSelectionStore(service: service))
        self.actorID = actorID
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("Follow your curiosity")
                        .font(.headline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose up to \(InterestSelectionStore.maximumSelectionCount) starting points. You can skip this.")
                        .font(.subheadline)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

                if store.phase == .idle || store.phase == .loading {
                    ProgressView("Loading interests…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let error = loadErrorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Couldn’t load interests", systemImage: "wifi.exclamationmark")
                            .font(.headline)
                        Text(error).foregroundStyle(ChoraiTheme.secondaryInk)
                        Button("Retry", action: loadInterests)
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("interests.retry")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("interests.load-error")
                } else {
                    InterestPillLayout(spacing: 8) {
                        ForEach(Array(store.options.enumerated()), id: \.element.value) { index, option in
                            Button {
                                store.toggle(option.value)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(option.value)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Image(systemName: option.isSelected ? "checkmark" : "plus")
                                        .font(.caption.weight(.semibold))
                                        .accessibilityHidden(true)
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(option.isSelected ? ChoraiTheme.onAccent : ChoraiTheme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(option.isSelected ? ChoraiTheme.accent : ChoraiTheme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(ChoraiTheme.separator, lineWidth: option.isSelected ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSaving || (!option.isSelected && selectionLimitReached))
                            .accessibilityIdentifier("interests.option.\(index)")
                            .accessibilityValue(option.isSelected ? "selected" : "not selected")
                            .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.top, 14)
                }

                if let error = saveErrorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("interests.save-error")
                }
            }
            .adaptiveContentGutter()
            .padding(.vertical, 20)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button("Skip", action: store.skip)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("interests.skip")
            }
            .overlay {
                Text("chorai")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .adaptiveContentGutter()
            .background(ChoraiTheme.background)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack {
                    Button("Reset", action: store.reset)
                        .font(.subheadline.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(store.isSaving || store.selectedDomains.isEmpty)
                        .accessibilityIdentifier("interests.reset")
                    Spacer()
                    Text(selectionSummary)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                }
                AuthPrimaryButton(
                    title: "Continue",
                    isLoading: store.isSaving,
                    enabled: store.canSave,
                    identifier: "interests.next",
                    action: store.save
                )
            }
            .adaptiveContentGutter()
            .padding(.bottom, 12)
            .background(ChoraiTheme.background)
        }
        .authEntryPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.interests")
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showTabBar) { TabBarView() }
        .onAppear(perform: loadInterests)
        .onChange(of: store.phase) { phase in
            guard phase == .saved || phase == .skipped else { return }
            if let onComplete {
                onComplete()
            } else {
                showTabBar = true
            }
        }
    }

    private var selectionLimitReached: Bool {
        store.selectedDomains.count >= InterestSelectionStore.maximumSelectionCount
    }

    private var selectionSummary: String {
        let count = store.selectedDomains.count
        return count == 0 ? "Choose up to \(InterestSelectionStore.maximumSelectionCount)" : "\(count) selected"
    }

    private func loadInterests() {
        store.load(actorID: actorID ?? AuthManager.shared.currentUser?.id ?? "")
    }

    private var loadErrorMessage: String? {
        guard case .failed(.load, let error) = store.phase else { return nil }
        return message(for: error)
    }

    private var saveErrorMessage: String? {
        guard case .failed(.save, let error) = store.phase else { return nil }
        return "Couldn’t save interests. \(message(for: error))"
    }

    private func message(for error: InterestSelectionError) -> String {
        switch error {
        case .invalidActor: return "Your session is missing. Please sign in again."
        case .transport: return "Check your connection and try again."
        }
    }
}

private struct InterestPillLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var rows: [[CGSize]] = []
        var row: [CGSize] = []
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width <= width
                ? ideal
                : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !row.isEmpty, rowWidth + spacing + size.width > width {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            rowWidth += (row.isEmpty ? 0 : spacing) + size.width
            row.append(size)
        }
        if !row.isEmpty { rows.append(row) }

        var frames: [CGRect] = []
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.width } + CGFloat(row.count - 1) * spacing
            let rowHeight = row.map(\.height).max() ?? 0
            var x = width.isFinite ? max(0, (width - rowWidth) / 2) : 0
            for size in row {
                frames.append(CGRect(origin: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), size: size))
                x += size.width + spacing
            }
            usedWidth = max(usedWidth, rowWidth)
            y += rowHeight + spacing
        }

        return (frames, CGSize(width: width.isFinite ? width : usedWidth, height: max(0, y - spacing)))
    }
}
