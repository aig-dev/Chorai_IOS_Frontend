import Foundation
import XCTest
@testable import BlockNoteEditor

final class BlockNoteResourceValidatorTests: XCTestCase {
    private let manifest = BlockNoteEditorResourceManifest(protocolVersion: 3, schemaVersion: 1, blockNoteVersion: "fixture", hashes: .init(editorCSS: "", editorJS: "", indexHTML: ""))

    @MainActor
    func testConcurrentWaitersShareNonMainValidationAndSuccessfulResultIsReused() async throws {
        let started = expectation(description: "started")
        let gate = DispatchSemaphore(value: 0)
        let probe = ValidationProbe()
        let expected = manifest
        let validator = BlockNoteResourceValidator(validate: {
            XCTAssertFalse(Thread.isMainThread)
            probe.increment()
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return expected
        })
        let first = Task { try await validator.validateBundledResources() }
        let second = Task { try await validator.validateBundledResources() }
        await fulfillment(of: [started], timeout: 3)
        first.cancel()
        gate.signal()
        let result = try await second.value
        XCTAssertEqual(result, manifest)
        do { _ = try await first.value; XCTFail("Canceled consumer returned") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let cached = try await validator.validateBundledResources()
        XCTAssertEqual(cached, manifest)
        XCTAssertEqual(probe.count, 1)
    }

    func testFailureIsNotCachedAndIndependentInstancesDoNotShare() async throws {
        let probe = ValidationProbe()
        let expected = manifest
        let retryable = BlockNoteResourceValidator(validate: {
            let attempt = probe.increment()
            if attempt == 1 { throw BlockNoteEditorResourceError.hashMismatch(file: "editor.js") }
            return expected
        })
        do { _ = try await retryable.validateBundledResources(); XCTFail("Bad hash accepted") }
        catch BlockNoteEditorResourceError.hashMismatch(file: "editor.js") {} catch { XCTFail("\(error)") }
        let recovered = try await retryable.validateBundledResources()
        XCTAssertEqual(recovered, manifest)
        let isolated = BlockNoteResourceValidator(validate: { probe.increment(); return expected })
        _ = try await isolated.validateBundledResources()
        XCTAssertEqual(probe.count, 3)
    }

    @MainActor
    func testClosedCoordinatorDoesNotLoadAfterValidation() async throws {
        let started = expectation(description: "validation started")
        let gate = DispatchSemaphore(value: 0)
        let expected = manifest
        let validator = BlockNoteResourceValidator(validate: {
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return expected
        })
        let coordinator = BlockNoteEditorCoordinator(document: .init(contentJSON: nil, fallbackMarkdown: ""), editable: true, controller: BlockNoteEditorController(), resourceValidator: validator, onEvent: { _ in })
        let webView = coordinator.makeWebView()
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNil(webView.url)
        coordinator.teardown()
        gate.signal()
        _ = try await validator.validateBundledResources()
        XCTAssertNil(webView.url)
        XCTAssertFalse(webView.isLoading)
    }

    @MainActor
    func testInvalidResourcesFailWithoutLoadingWebView() async {
        let failed = expectation(description: "resource failure")
        let validator = BlockNoteResourceValidator(validate: {
            throw BlockNoteEditorResourceError.hashMismatch(file: "editor.js")
        })
        let coordinator = BlockNoteEditorCoordinator(document: .init(contentJSON: nil, fallbackMarkdown: ""), editable: true, controller: BlockNoteEditorController(), resourceValidator: validator) {
            if case .bridgeError(code: "resource_validation_failed") = $0 { failed.fulfill() }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertNil(webView.url)
    }

    func testBundledValidationPreservesManifestAndHashes() async throws {
        let validator = BlockNoteResourceValidator()
        let result = try await validator.validateBundledResources()
        XCTAssertEqual(result.protocolVersion, BlockNoteEditorProtocol.version)
        XCTAssertEqual(result, try BlockNoteEditorResources.validateBundledResources())
    }
}

private final class ValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
