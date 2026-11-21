#if DEBUG
import Combine
import CoreFlow
import Foundation
import os
import XCTest
@testable import ArcNote

@MainActor
final class NetworkNoteImportBridgeTests: XCTestCase {
    func testSynchronousReceiptAfterTransportAlreadyTerminated() async {
        let run = start { handle in
            handle.finish()
            handle.finish()
            return Just(Self.response)
                .setFailureType(to: NetworkError.self).eraseToAnyPublisher()
        }
        await verify(run, outcome: .receipt(Self.receipt))
        XCTAssertEqual(run.handle.cancelThreads, [])
    }

    func testSynchronousFailureWaitsForTransportAndRetainsError() async throws {
        let run = start { _ in Fail(error: .timeout).eraseToAnyPublisher() }

        try await assertWaiting(run)
        run.handle.finish()
        await verify(run, outcome: .failure(.ambiguous(.timeout)))
    }

    func testSynchronousEmptyCompletionWaitsForTransport() async throws {
        let run = start { _ in Empty().eraseToAnyPublisher() }

        try await assertWaiting(run)
        run.handle.finish()
        await verify(run, outcome: .failure(.contract(code: "empty_response")))
    }

    func testSynchronousUndecodableResponseRetainsAmbiguityThroughTermination() async throws {
        let run = start { _ in
            Just(.undecodableSuccess(statusCode: 202))
                .setFailureType(to: NetworkError.self).eraseToAnyPublisher()
        }

        try await assertWaiting(run)
        run.handle.finish()
        await verify(run, outcome: .failure(.ambiguous(.undecodableSuccess(statusCode: 202))))
    }

    func testAcceptedValueWinsOffMainCancellationBeforePublisherCompletion() async throws {
        let subject = PassthroughSubject<NoteImportUploadTransportResult, NetworkError>()
        let run = start { _ in subject.eraseToAnyPublisher() }
        await fulfillment(of: [run.subscribed], timeout: 5)

        subject.send(Self.response)
        // Keep MainActor occupied until off-main cancellation reaches the
        // active handler. Otherwise the winner may already have returned.
        let cancelled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            run.task.cancel()
            cancelled.signal()
        }
        XCTAssertEqual(cancelled.wait(timeout: .now() + 5), .success)
        subject.send(.undecodableSuccess(statusCode: 202))
        subject.send(completion: .failure(.timeout))

        try await assertWaiting(run)
        XCTAssertEqual(run.handle.cancelThreads, [])
        run.handle.finish()
        run.handle.finish()
        await verify(run, outcome: .receipt(Self.receipt))
    }

    func testOffMainCancellationOfInstalledSubscriptionWaitsForTransport() async throws {
        let subject = PassthroughSubject<NoteImportUploadTransportResult, NetworkError>()
        let run = start { _ in subject.eraseToAnyPublisher() }
        await fulfillment(of: [run.subscribed], timeout: 5)

        await Task.detached {
            run.task.cancel()
            run.task.cancel()
        }.value
        subject.send(Self.response)
        subject.send(completion: .failure(.timeout))

        try await assertWaiting(run)
        XCTAssertEqual(run.handle.cancelThreads, [false])
        run.handle.finish()
        await verify(run, outcome: .cancelled)
    }

    func testOffMainCancellationBeforeRegistrationBeatsSynchronousResult() async throws {
        let entered = DispatchSemaphore(value: 0)
        let cancelled = DispatchSemaphore(value: 0)
        let run = start { _ in
            // This factory runs inside sink(), before it can register its AnyCancellable.
            entered.signal()
            XCTAssertEqual(cancelled.wait(timeout: .now() + 5), .success)
            // Publish a value synchronously after cancellation won. Leave
            // completion pending so late registration must cancel the transport.
            return Just(Self.response)
                .setFailureType(to: NetworkError.self)
                .append(Empty(completeImmediately: false))
                .eraseToAnyPublisher()
        }
        DispatchQueue.global().async {
            let arrived = entered.wait(timeout: .now() + 5)
            XCTAssertEqual(arrived, .success)
            defer { cancelled.signal() }
            run.task.cancel()
        }

        try await assertWaiting(run)
        XCTAssertEqual(run.handle.cancelThreads, [true])
        run.handle.finish()
        await verify(run, outcome: .cancelled)
    }

    func testTerminationResumesAllRegisteredAndLaterWaitersOnce() async {
        let termination = NoteImportUploadTermination()
        let first = expectation(description: "first registered waiter resumed")
        let second = expectation(description: "second registered waiter resumed")
        let late = expectation(description: "late waiter resumed")
        for expectation in [first, second, late] {
            expectation.assertForOverFulfill = true
        }

        Task.detached { await termination.wait(); first.fulfill() }
        Task.detached { await termination.wait(); second.fulfill() }
        await waitUntil { termination.testWaiterCount == 2 }
        XCTAssertEqual(termination.testWaiterCount, 2)

        await Task.detached { termination.signal(); termination.signal() }.value
        Task.detached { await termination.wait(); late.fulfill() }
        await fulfillment(of: [first, second, late], timeout: 5)
        XCTAssertEqual(termination.testWaiterCount, 0)
    }

    private enum Outcome: Equatable, Sendable {
        case receipt(NoteImportReceipt)
        case failure(NoteImportServiceError)
        case cancelled
        case unexpected(String)
    }

    private struct Run: Sendable {
        let scopes: ScopeRecorder
        let handle: UploadHandle
        let uploader: Uploader
        let subscribed: XCTestExpectation
        let completed: XCTestExpectation
        let outcome: OSAllocatedUnfairLock<Outcome?>
        let task: Task<Void, Never>
    }

    private func start(
        publisher: @escaping @MainActor (UploadHandle) -> AnyPublisher<
            NoteImportUploadTransportResult, NetworkError
        >
    ) -> Run {
        let scopes = ScopeRecorder()
        let handle = UploadHandle(scopes: scopes)
        let subscribed = XCTestExpectation(description: "publisher installed its subscription")
        let completed = expectation(description: "enqueue completed after releasing its URLs")
        completed.assertForOverFulfill = true
        let outcome = OSAllocatedUnfairLock<Outcome?>(initialState: nil)
        let uploader = Uploader(handle: handle, subscribed: subscribed, publisher: publisher)
        let service = NetworkNoteImportService(resourceAccessor: scopes, uploader: uploader)
        let urls = [URL(fileURLWithPath: "/tmp/import-first.md"), URL(fileURLWithPath: "/tmp/import-second.md")]
        let files = [urls[0], urls[1], urls[0]].enumerated().map { index, url in
            NoteImportFile(
                id: "file-\(index)", sourceKey: "source-\(index)", url: url,
                filename: url.lastPathComponent, label: "Note \(index)", format: .markdown, byteCount: 10
            )
        }
        let task = Task {
            let value: Outcome
            do {
                value = .receipt(try await service.enqueue(files: files, clientRequestID: "bridge-request"))
            } catch is CancellationError {
                value = .cancelled
            } catch let error as NoteImportServiceError {
                value = .failure(error)
            } catch {
                value = .unexpected(String(describing: error))
            }
            outcome.withLock { $0 = value }
            completed.fulfill()
        }
        return Run(
            scopes: scopes, handle: handle, uploader: uploader, subscribed: subscribed,
            completed: completed, outcome: outcome, task: task
        )
    }

    private func assertWaiting(_ run: Run) async throws {
        await waitUntil { run.uploader.termination != nil || run.outcome.withLock { $0 != nil } }
        let termination = try XCTUnwrap(run.uploader.termination)
        await waitUntil { termination.testWaiterCount == 1 || run.outcome.withLock { $0 != nil } }
        XCTAssertEqual(termination.testWaiterCount, 1, "Enqueue must wait for the multipart request")
        XCTAssertNil(run.outcome.withLock { $0 })
        XCTAssertEqual(run.scopes.events, Self.acquired)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    private func verify(_ run: Run, outcome: Outcome) async {
        await fulfillment(of: [run.completed], timeout: 5)
        XCTAssertEqual(run.outcome.withLock { $0 }, outcome)
        XCTAssertEqual(
            run.scopes.events,
            Self.acquired + ["transport terminated", "release:import-second.md", "release:import-first.md"]
        )
        XCTAssertEqual(run.uploader.requestID, "bridge-request")
        XCTAssertEqual(run.uploader.sourceKeys, ["source-0", "source-1", "source-2"])
    }

    private static let acquired = ["acquire:import-first.md", "acquire:import-second.md"]
    private static let receipt = NoteImportReceipt(
        jobID: "bridge-job", clientRequestID: "bridge-request", status: .init(rawValue: "queued"),
        totalFiles: 3, acceptedFiles: 3, rejectedFiles: 0
    )
    private static let response: NoteImportUploadTransportResult = .response(.init(
        jobID: "bridge-job", clientRequestID: "bridge-request", status: "queued",
        totalFiles: 3, acceptedFiles: 3, rejectedFiles: 0
    ))
}

private final class ScopeRecorder: SecurityScopedResourceAccessing {
    private let log = OSAllocatedUnfairLock(initialState: [String]())

    var events: [String] { log.withLock { $0 } }

    func startAccessing(_ url: URL) -> Bool {
        log.withLock { $0.append("acquire:\(url.lastPathComponent)") }
        return true
    }

    func stopAccessing(_ url: URL) {
        log.withLock { $0.append("release:\(url.lastPathComponent)") }
    }

    func markTerminated() {
        log.withLock { $0.append("transport terminated") }
    }
}

private final class UploadHandle: MultipartUploadHandling {
    private struct State: Sendable {
        var cancelledOnMain: [Bool] = []
        var callback: (@Sendable () -> Void)?
        var finished = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let scopes: ScopeRecorder

    init(scopes: ScopeRecorder) { self.scopes = scopes }

    var cancelThreads: [Bool] { state.withLock { $0.cancelledOnMain } }

    func cancel() {
        state.withLock { $0.cancelledOnMain.append(Thread.isMainThread) }
    }

    func observeTermination(_ callback: @escaping @Sendable () -> Void) {
        state.withLock { $0.callback = callback }
    }

    func finish() {
        let callback = state.withLock {
            if !$0.finished {
                scopes.markTerminated()
                $0.finished = true
            }
            return $0.callback
        }
        callback?()
    }
}

@MainActor
private final class Uploader: NoteImportUploading {
    let handle: UploadHandle
    let subscribed: XCTestExpectation
    let publisher: @MainActor (UploadHandle) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError>

    private(set) var termination: NoteImportUploadTermination?
    private(set) var requestID: String?
    private(set) var sourceKeys: [String]?

    init(
        handle: UploadHandle,
        subscribed: XCTestExpectation,
        publisher: @escaping @MainActor (UploadHandle) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError>
    ) {
        self.handle = handle
        self.subscribed = subscribed
        self.publisher = publisher
    }

    func enqueue(
        parts: [NoteImportUploadPart],
        clientRequestID: String,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError> {
        self.termination = termination
        requestID = clientRequestID
        sourceKeys = parts.map(\.sourceKey)

        // Real bridge construction observes the transport before subscribing.
        // The upstream is deferred so tests can enter the subscription itself.
        return MultipartUploadPublisherBuilder.publisher(
            handle: handle,
            upstream: Deferred { self.publisher(self.handle) }
                .handleEvents(receiveSubscription: { [subscribed] _ in subscribed.fulfill() })
                .eraseToAnyPublisher(),
            termination: termination
        )
    }
}
#endif
