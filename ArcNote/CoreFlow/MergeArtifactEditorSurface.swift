import CoreFlow
import SwiftUI

@MainActor
struct MergeArtifactEditorSurface: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var controller: MergeArtifactDraftController
    let onBack: () -> Void

    @FocusState private var isTagInputFocused: Bool
    @State private var restingViewportSlots: [RestingViewportSlot] = []
    @State private var viewportWidthsNeedingStableObservation: [CGFloat] = []
    @State private var restingViewportObservationGeneration = 0

    private struct RestingViewportSlot {
        let width: CGFloat
        let height: CGFloat
    }

    private enum ScrollTarget: Hashable {
        case editor
    }

    private static let restingViewportWidthTolerance: CGFloat = 1
    private static let maximumRestingViewportSlotCount = 2
    private static let restingViewportSettleNanoseconds: UInt64 = 500_000_000

    private let shape = RoundedRectangle(
        cornerRadius: 28,
        style: .continuous
    )

    var body: some View {
        GeometryReader { geometry in
            let viewportHeight = geometry.size.height
            let restingViewportHeight = restingViewportHeight(
                for: geometry.size
            )
            let layoutViewportHeight = controller.bodyModel.isBodyFocused
                ? restingViewportHeight
                : viewportHeight
            let surfaceVerticalInset: CGFloat = dynamicTypeSize.isAccessibilitySize
                ? 0
                : 52
            let surfaceHeight = max(
                0,
                layoutViewportHeight - surfaceVerticalInset
            )
            let actionAreaHeight: CGFloat = 78
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            backAction

                            Text("New Insight")
                                .font(.title3.weight(.medium))
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)

                            levelPill
                                .padding(.top, 12)

                            editor(
                                height: editorHeight(in: restingViewportHeight)
                            )
                            .padding(.top, 16)
                            .id(ScrollTarget.editor)

                            tagRow
                                .padding(.top, 10)

                            syncState
                                .padding(.top, 6)

                            if controller.isConflict {
                                conflictActions
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: controller.bodyModel.isBodyFocused) {
                        isFocused in
                        guard isFocused,
                              geometry.size.width > geometry.size.height else {
                            return
                        }
                        Task { @MainActor in
                            await Task.yield()
                            guard controller.bodyModel.isBodyFocused else {
                                return
                            }
                            proxy.scrollTo(ScrollTarget.editor, anchor: .top)
                        }
                    }
                }
                .frame(height: max(0, surfaceHeight - actionAreaHeight))

                mutationActions
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .frame(height: actionAreaHeight, alignment: .top)
            }
            .frame(
                width: min(geometry.size.width, 680),
                height: surfaceHeight,
                alignment: .top
            )
            .background {
                CardLevelMaterial(
                    style: controller.levelStyle,
                    shape: shape
                )
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .frame(height: layoutViewportHeight, alignment: .center)
            .onAppear {
                seedInitialRestingViewport(geometry.size)
            }
            .onChange(of: geometry.size) { size in
                observeRestingViewport(size)
            }
            .onChange(of: controller.bodyModel.isBodyFocused) { _ in
                observeRestingViewport(geometry.size)
            }
            .onChange(of: isTagInputFocused) { _ in
                observeRestingViewport(geometry.size)
            }
            .onDisappear {
                restingViewportObservationGeneration += 1
            }
        }
        .foregroundStyle(.white)
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Merge artifact")
                .accessibilityIdentifier("screen.merge.artifact")
        }
        .confirmationDialog(
            "Discard Merge?",
            isPresented: $controller.isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                controller.discard()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This removes only this Merge task and its draft.")
        }
    }

    private func editorHeight(in viewportHeight: CGFloat) -> CGFloat {
        min(360, max(180, viewportHeight - 430))
    }

    private func restingViewportHeight(for currentSize: CGSize) -> CGFloat {
        restingViewportSlot(for: currentSize.width)?.height
            ?? currentSize.height
    }

    private func seedInitialRestingViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard !isEditorInputFocused else {
            markViewportWidthAsNeedingStableObservation(size.width)
            observeRestingViewport(size)
            return
        }
        recordRestingViewportSlotIfNeeded(size)
    }

    private func observeRestingViewport(_ size: CGSize) {
        restingViewportObservationGeneration += 1
        let generation = restingViewportObservationGeneration
        guard size.width > 0, size.height > 0,
              restingViewportSlot(for: size.width) == nil else { return }

        if isEditorInputFocused {
            markViewportWidthAsNeedingStableObservation(size.width)
            return
        }

        guard viewportWidthNeedsStableObservation(size.width) else {
            recordRestingViewportSlotIfNeeded(size)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: Self.restingViewportSettleNanoseconds
            )
            guard generation == restingViewportObservationGeneration,
                  !isEditorInputFocused else { return }
            recordRestingViewportSlotIfNeeded(size)
        }
    }

    private func recordRestingViewportSlotIfNeeded(_ size: CGSize) {
        guard restingViewportSlot(for: size.width) == nil,
              restingViewportSlots.count
                < Self.maximumRestingViewportSlotCount else { return }
        restingViewportSlots.append(
            RestingViewportSlot(width: size.width, height: size.height)
        )
        viewportWidthsNeedingStableObservation.removeAll {
            abs($0 - size.width) <= Self.restingViewportWidthTolerance
        }
    }

    private func restingViewportSlot(
        for width: CGFloat
    ) -> RestingViewportSlot? {
        restingViewportSlots.first {
            abs($0.width - width)
                <= Self.restingViewportWidthTolerance
        }
    }

    private var isEditorInputFocused: Bool {
        controller.bodyModel.isBodyFocused || isTagInputFocused
    }

    private func markViewportWidthAsNeedingStableObservation(
        _ width: CGFloat
    ) {
        guard !viewportWidthNeedsStableObservation(width),
              viewportWidthsNeedingStableObservation.count
                < Self.maximumRestingViewportSlotCount else { return }
        viewportWidthsNeedingStableObservation.append(width)
    }

    private func viewportWidthNeedsStableObservation(
        _ width: CGFloat
    ) -> Bool {
        viewportWidthsNeedingStableObservation.contains {
            abs($0 - width) <= Self.restingViewportWidthTolerance
        }
    }

    private var backAction: some View {
        HStack {
            Button {
                controller.back(onMinimize: onBack)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityHint("Minimizes this Merge without discarding edits")
            .accessibilityIdentifier("merge.artifact.back")

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var levelPill: some View {
        Text(controller.levelStyle.label)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 24)
            .frame(minWidth: 180, minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.13))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                controller.levelStyle.materialAccentColor?
                                    .opacity(0.72)
                                    ?? Color.white.opacity(0.28),
                                lineWidth: 1
                            )
                    }
            }
            .accessibilityLabel(controller.levelStyle.label)
            .accessibilityIdentifier("merge.artifact.level")
    }

    private func editor(height: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                BlockNoteCardEditor(
                    model: controller.bodyModel,
                    minimumHeight: 180
                )

                if !controller.unresolvedMediaReferences.isEmpty {
                    Label(
                        "Attachment preserved. A secure preview isn’t available yet.",
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.18))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { value in
                guard controller.bodyModel.isBodyFocused,
                      abs(value.translation.height) >= 24,
                      abs(value.translation.height)
                        > abs(value.translation.width) else {
                    return
                }
                controller.bodyModel.dismissKeyboard()
            }
        )
        .frame(height: height, alignment: .top)
        .background(Color.black.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(
            controller.canEdit
                ? (controller.bodyModel.isBodyFocused ? "Editing" : "Preview")
                : "Locked"
        )
        .accessibilityIdentifier("merge.artifact.editor")
        .allowsHitTesting(controller.canEdit)
    }

    private var tagRow: some View {
        CardEditorTagRow(
            tags: controller.tags,
            isEditable: controller.canEdit,
            isAddingTag: controller.isAddingTag,
            prefersKeyboardTagAction: false,
            tagInput: $controller.tagInput,
            isTagInputFocused: $isTagInputFocused,
            semantics: CardEditorTagSemantics(
                tagIdentifierPrefix: "merge.artifact.tag.",
                addTagIdentifier: "merge.artifact.add-tag",
                inputIdentifier: "merge.artifact.tag-input"
            ),
            onBeginTag: controller.beginTag,
            onCompleteTag: controller.completeTag,
            onInteraction: controller.completeTag,
            onRemove: controller.removeTag
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merge.artifact.tags")
    }

    private var syncState: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if controller.store.artifactDraftSyncState == .saving
                    || controller.isPreparingAccept
                    || controller.isRetryingArtifactDraft {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.78))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: syncSymbol)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(controller.syncMessage)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controller.syncMessage)
            .accessibilityIdentifier("merge.artifact.sync-state")

            if controller.canRetryArtifactDraft {
                Button("Retry") {
                    controller.retryArtifactDraft()
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 64, minHeight: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule(style: .continuous))
                .accessibilityHint("Retries the same saved Merge draft")
                .accessibilityIdentifier("merge.artifact.retry-sync")
            }
        }
        .foregroundStyle(syncColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var syncSymbol: String {
        if controller.isConflict {
            return "arrow.triangle.2.circlepath"
        }
        if controller.validationMessage != nil
            || controller.store.artifactActionError != nil {
            return "exclamationmark.triangle"
        }
        switch controller.store.artifactDraftSyncState {
        case .clean:
            return "checkmark.circle"
        case .dirty:
            return "clock"
        case .saving:
            return "arrow.triangle.2.circlepath"
        case .unsynced(.offline):
            return "wifi.slash"
        case .unsynced:
            return "exclamationmark.icloud"
        case .conflict:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var syncColor: Color {
        if controller.isConflict
            || controller.validationMessage != nil
            || controller.store.artifactActionError != nil {
            return Color(red: 1, green: 0.76, blue: 0.66)
        }
        return .white.opacity(0.72)
    }

    private var conflictActions: some View {
        HStack(spacing: 10) {
            Button("Reload server version") {
                controller.resolveConflict(.reloadServer)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule(style: .continuous))

            Button("Keep my version") {
                controller.resolveConflict(.keepMine)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule(style: .continuous))
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .contain)
    }

    private var mutationActions: some View {
        HStack(spacing: 12) {
            MergeArtifactMutationButton(
                title: controller.store.phase == .cancelling
                    ? "Discarding…"
                    : "Discard",
                systemImage: "xmark",
                isFilled: false,
                isBusy: controller.store.phase == .cancelling,
                isEnabled: controller.canDiscard,
                identifier: "merge.artifact.discard"
            ) {
                controller.requestDiscardConfirmation()
            }

            MergeArtifactMutationButton(
                title: controller.store.phase == .committing
                    || controller.isPreparingAccept
                    ? "Accepting…"
                    : "Accept",
                systemImage: "checkmark",
                isFilled: true,
                isBusy: controller.store.phase == .committing
                    || controller.isPreparingAccept,
                isEnabled: controller.canAccept,
                identifier: "merge.artifact.accept"
            ) {
                controller.accept()
            }
        }
    }
}

private struct MergeArtifactMutationButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    let isFilled: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(isEnabled || isBusy ? 0.96 : 0.42))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isFilled
                            ? Color.white.opacity(isEnabled ? 0.19 : 0.08)
                            : Color.black.opacity(0.08)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                Color.white.opacity(isEnabled ? 0.28 : 0.12),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
