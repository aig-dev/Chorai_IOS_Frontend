import Combine
import Foundation

@MainActor
public final class BlockNoteEditorController: ObservableObject {
    private typealias SnapshotContinuation = CheckedContinuation<BlockNoteSnapshot, Error>

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

    func attach(commandHandler: @escaping (BlockNoteEditorCommand) -> Void) {
        if self.commandHandler != nil {
            failAllSnapshots(with: .tornDown)
        }
        self.commandHandler = commandHandler
    }

    func detach(with failure: BlockNoteEditorFailure = .tornDown) {
        commandHandler = nil
        failAllSnapshots(with: failure)
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
    public typealias UIViewType = WKWebView
    public typealias Coordinator = BlockNoteEditorCoordinator

    private let document: BlockNoteInitialDocument
    private let editable: Bool
    private let controller: BlockNoteEditorController
    private let onEvent: @MainActor (BlockNoteEditorEvent) -> Void

    public init(
        document: BlockNoteInitialDocument,
        editable: Bool,
        controller: BlockNoteEditorController,
        onEvent: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        self.document = document
        self.editable = editable
        self.controller = controller
        self.onEvent = onEvent
    }

    public func makeCoordinator() -> BlockNoteEditorCoordinator {
        BlockNoteEditorCoordinator(
            document: document,
            editable: editable,
            controller: controller,
            onEvent: onEvent
        )
    }

    public func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateEventHandler(onEvent)
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}
#endif
