import Combine
import Foundation

/// A fixed attachment's acceptance boundary and applied-event watermark.
/// Retaining this handle never redirects a pending drain to a replacement view.
@MainActor
public final class BlockNoteEditorAttachment {
    public let id = UUID()
    public private(set) var isClosing = false
    private let drain: @MainActor () async -> Void
    private let pendingEvents: @MainActor () -> Bool
    private let close: @MainActor (BlockNoteEditorAttachment) -> Void

    init(drain: @escaping @MainActor () async -> Void,
         pendingEvents: @escaping @MainActor () -> Bool,
         close: @escaping @MainActor (BlockNoteEditorAttachment) -> Void) {
        self.drain = drain
        self.pendingEvents = pendingEvents
        self.close = close
    }

    public func drainAcceptedEvents() async { await drain() }

    /// Check synchronously after draining before replacing a live editor. A
    /// fixed watermark may finish while more events entered its mailbox.
    public var hasPendingAcceptedEvents: Bool { pendingEvents() }

    public func beginClosing() {
        guard !isClosing else { return }
        isClosing = true
        close(self)
    }
}

@MainActor
public final class BlockNoteEditorController: ObservableObject {
    private typealias SnapshotContinuation = CheckedContinuation<BlockNoteSnapshot, Error>

    public private(set) var attachment: BlockNoteEditorAttachment?
    public var onAttachmentWillClose: (@MainActor (BlockNoteEditorAttachment) -> Void)?

    private var commandHandler: ((BlockNoteEditorCommand) -> Void)?
    private var pendingSnapshots: [String: SnapshotContinuation] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    public init() {}

    public func applyFormat(_ format: BlockNoteFormat) {
        send(.applyFormat(format))
    }

    public func setBlockType(_ blockType: BlockNoteBlockType) {
        send(.setBlockType(blockType))
    }

    public func toggleList(_ listType: BlockNoteListType) {
        send(.toggleList(listType))
    }

    public func insertLink(url: String, text: String) {
        send(.insertLink(url: url, text: text))
    }

    public func insertImage(url: String, alt: String) {
        send(.insertImage(url: url, alt: alt))
    }

    public func undo() {
        send(.undo)
    }

    public func redo() {
        send(.redo)
    }

    public func focus() {
        send(.focus)
    }

    public func blur() {
        send(.blur)
    }

    public func requestSnapshot(
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws -> BlockNoteSnapshot {
        guard commandHandler != nil else {
            throw BlockNoteEditorFailure.notAttached
        }

        let requestID = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingSnapshots[requestID] = continuation
                timeoutTasks[requestID] = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    self?.finishSnapshot(
                        requestID: requestID,
                        result: .failure(.snapshotTimedOut(requestID: requestID))
                    )
                }
                commandHandler?(.requestSnapshot(requestID: requestID))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishSnapshot(
                    requestID: requestID,
                    result: .failure(.requestCancelled(requestID: requestID))
                )
            }
        }
    }

    func attach(
        drainAcceptedEvents: @escaping @MainActor () async -> Void = {},
        hasPendingAcceptedEvents: @escaping @MainActor () -> Bool = { false },
        beginClosing: @escaping @MainActor () -> Void = {},
        commandHandler: @escaping (BlockNoteEditorCommand) -> Void
    ) {
        attachment?.beginClosing()
        failAllSnapshots(with: .tornDown)
        attachment = BlockNoteEditorAttachment(drain: drainAcceptedEvents,
            pendingEvents: hasPendingAcceptedEvents) { [weak self] binding in
            if self?.attachment?.id == binding.id {
                self?.commandHandler = nil
                self?.failAllSnapshots(with: .tornDown)
            }
            beginClosing()
            self?.onAttachmentWillClose?(binding)
        }
        self.commandHandler = commandHandler
    }

    public func beginClosing() {
        attachment?.beginClosing()
    }

    public func drainAcceptedEvents() async {
        let binding = attachment
        await binding?.drainAcceptedEvents()
    }

    func detach(with failure: BlockNoteEditorFailure = .tornDown) {
        commandHandler = nil
        failAllSnapshots(with: failure)
        attachment?.beginClosing()
        // Keep the fixed handle until a new attachment replaces it. Accepted
        // events still belong to this lifetime after WK has been dismantled.
    }

    @discardableResult
    func complete(snapshot: BlockNoteSnapshot) -> Bool {
        finishSnapshot(requestID: snapshot.requestID, result: .success(snapshot))
    }

    func failAllSnapshots(with failure: BlockNoteEditorFailure) {
        for requestID in Array(pendingSnapshots.keys) {
            finishSnapshot(requestID: requestID, result: .failure(failure))
        }
    }

    func failSnapshot(requestID: String, with failure: BlockNoteEditorFailure) {
        finishSnapshot(requestID: requestID, result: .failure(failure))
    }

    var pendingSnapshotCount: Int {
        pendingSnapshots.count
    }

    private func send(_ command: BlockNoteEditorCommand) {
        commandHandler?(command)
    }

    @discardableResult
    private func finishSnapshot(
        requestID: String,
        result: Result<BlockNoteSnapshot, BlockNoteEditorFailure>
    ) -> Bool {
        guard let continuation = pendingSnapshots.removeValue(forKey: requestID) else {
            return false
        }
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        continuation.resume(with: result.mapError { $0 as Error })
        return true
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

public struct BlockNoteEditorView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    public typealias UIViewType = WKWebView
    public typealias Coordinator = BlockNoteEditorCoordinator

    private let document: BlockNoteInitialDocument
    private let editable: Bool
    private let fontScale: Double
    private let minimumWritingHeight: Double
    private let controller: BlockNoteEditorController
    private let localImageSource: BlockNoteLocalImageSource?
    private let onEvent: @MainActor (BlockNoteEditorEvent) -> Void

    public init(
        document: BlockNoteInitialDocument,
        editable: Bool,
        fontScale: Double = 23.0 / 17.0,
        minimumWritingHeight: Double = 0,
        controller: BlockNoteEditorController,
        localImageSource: BlockNoteLocalImageSource? = nil,
        onEvent: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        self.document = document
        self.editable = editable
        self.fontScale = fontScale
        self.minimumWritingHeight = minimumWritingHeight
        self.controller = controller
        self.localImageSource = localImageSource
        self.onEvent = onEvent
    }

    public func makeCoordinator() -> BlockNoteEditorCoordinator {
        BlockNoteEditorCoordinator(
            document: document,
            editable: editable,
            controller: controller,
            localImageSource: localImageSource,
            onEvent: onEvent
        )
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.makeWebView(
            fontScale: fontScale,
            minimumWritingHeight: minimumWritingHeight
        )
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateEventHandler(onEvent)
        context.coordinator.updateMinimumWritingHeight(minimumWritingHeight)
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}
#endif
