import XCTest
import UIKit
@testable import CoreFlow
@testable import ArcNote

@MainActor
final class LocalNoteThumbnailReaderTests: XCTestCase {
    func testLargePublishedBodyBurstSharesOnePipelineAndCancellationStaysLocal() async throws {
        let fixture = try await ThumbnailFixture(bodyPadding: String(repeating: "large immutable body ", count: 25_000))
        defer { fixture.removeFiles() }
        let entered = expectation(description: "shared preparation")
        let gate = DispatchSemaphore(value: 0)
        let probe = ThumbnailProbe()
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, load: { identity in
            probe.loaded(); return try await fixture.library.thumbnailData(for: identity)
        }, prepare: { data, size in
            probe.begin(); defer { probe.end() }; entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
            return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let requests = (0..<40).map { _ in Task { try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) } }
        await fulfillment(of: [entered], timeout: 3)
        await settle()
        for request in requests.prefix(20) { request.cancel() }
        for request in requests.prefix(20) {
            do { _ = try await request.value; XCTFail("Canceled reader received a result") } catch is CancellationError {} catch { XCTFail("\(error)") }
        }
        gate.signal()
        for request in requests.suffix(20) { _ = try await request.value }
        XCTAssertEqual(probe.loads, 1); XCTAssertEqual(probe.preparations, 1); XCTAssertEqual(probe.peak, 1)
        await fixture.close()
    }
    func testConcurrentReadersShareVerifiedLoadAndPreparationAndOneMayCancel() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let entered = expectation(description: "preparing")
        let gate = DispatchSemaphore(value: 0)
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, load: { identity in
            probe.loaded(); return try await fixture.library.thumbnailData(for: identity)
        }, prepare: { data, size in
            probe.begin(); defer { probe.end() }
            entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
            return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let one = Task { try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) }
        let two = Task { try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) }
        await fulfillment(of: [entered], timeout: 3)
        await settle()
        one.cancel()
        do { _ = try await one.value; XCTFail("Cancelled consumer received image") } catch is CancellationError {} catch { XCTFail("\(error)") }
        gate.signal()
        let image = try await two.value
        let warm = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64)
        XCTAssertTrue(image === warm)
        XCTAssertEqual(probe.loads, 1)
        XCTAssertEqual(probe.preparations, 1)
        XCTAssertFalse(probe.onMain)
        XCTAssertEqual(image.cgImage?.width, 64)
        XCTAssertEqual(image.cgImage?.height, 32)
        await fixture.close()
    }

    func testSizeRevisionScopeAndMemoryWarningInvalidateReuse() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let notifications = NotificationCenter()
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.library.scope }, notifications: notifications,
            prepare: { data, size in probe.begin(); defer { probe.end() }; return UIImage(data: data)?.preparingThumbnail(of: size) })
        _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64)
        let smaller = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 32)
        XCTAssertEqual(smaller.cgImage?.width, 32)
        XCTAssertEqual(probe.preparations, 2)
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64)
        XCTAssertEqual(probe.preparations, 3)
        _ = try await fixture.library.save(identifier: "local-note:one", createID: "one", body: .init(content: "removed"), scope: fixture.scope)
        do { _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64); XCTFail("Stale body used cache") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .staleGeneration) }
        await fixture.library.configure(scope: .init(actorID: "bob", environmentID: "local"), cloudEnabled: false)
        do { _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64); XCTFail("Retired scope used cache") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidScope) }
        XCTAssertEqual(probe.preparations, 3)
        await fixture.close()
    }

    func testCancelledRunningWorkRetainsItsConcurrencySlot() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let entered = expectation(description: "two actual preparations"); entered.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, prepare: { data, size in
            let call = probe.begin(); defer { probe.end() }
            if call <= 2 { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let jobs = (64...67).map { size in Task { try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: size) } }
        await fulfillment(of: [entered], timeout: 3)
        jobs[0].cancel(); jobs[1].cancel()
        await settle()
        XCTAssertEqual(probe.preparations, 2, "Cancellation cannot free a still-running synchronous slot")
        gate.signal(); gate.signal()
        for job in jobs { _ = await job.result }
        XCTAssertLessThanOrEqual(probe.peak, 2)
        await fixture.close()
    }

    func testDecodedByteBudgetDoesNotRetainOversizedImageAndFailuresCanRetry() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, byteLimit: 1,
            prepare: { data, size in probe.begin(); defer { probe.end() }; return UIImage(data: data)?.preparingThumbnail(of: size) })
        for _ in 0..<2 { _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) }
        XCTAssertEqual(probe.preparations, 2)
        let broken = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, prepare: { _, _ in
            probe.begin(); defer { probe.end() }; return nil
        })
        for _ in 0..<2 {
            do { _ = try await broken.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64); XCTFail("Decode failure accepted") }
            catch { XCTAssertEqual(error as? NoteLocalStoreError, .invalidAttachment) }
        }
        XCTAssertEqual(probe.preparations, 4)
        await fixture.close()
    }

    func testLatePreparationCannotDisplayRemovedImageAndDiskIntegrityIsStillChecked() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "preparing")
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, prepare: { data, size in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
            return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let pending = Task { try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) }
        await fulfillment(of: [entered], timeout: 3)
        try await fixture.library.setLifecycle(identifier: "local-note:one", lifecycle: .trashed, scope: fixture.scope)
        gate.signal()
        do { _ = try await pending.value; XCTFail("Trashed image published late") } catch {}
        try await fixture.library.setLifecycle(identifier: "local-note:one", lifecycle: .active, scope: fixture.scope)
        let attachment = try XCTUnwrap(fixture.library.notes.first?.attachments.first)
        let directory = try NoteLocalStore.directory(rootURL: fixture.root, scope: fixture.scope)
        try Data([0]).write(to: directory.appendingPathComponent("attachments").appendingPathComponent(attachment.relativePath))
        do { _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64); XCTFail("Corrupt bytes accepted") }
        catch { XCTAssertEqual(error as? NoteLocalStoreError, .attachmentMismatch) }
        await fixture.close()
    }

    func testEntryLimitUsesRecencyAndRetiredAccountCannotPublishLateImage() async throws {
        let fixture = try await ThumbnailFixture()
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.library.scope }, entryLimit: 2,
            prepare: { data, size in probe.begin(); defer { probe.end() }; return UIImage(data: data)?.preparingThumbnail(of: size) })
        for size in [64, 32, 64, 16, 64, 32] {
            _ = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: size)
        }
        XCTAssertEqual(probe.preparations, 4, "The recently used 64px entry survives; the 32px entry is evicted")
        let entered = expectation(description: "preparing before logout")
        let gate = DispatchSemaphore(value: 0)
        let pendingReader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.library.scope }, prepare: { data, size in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
            return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let pending = Task { try await pendingReader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 64) }
        await fulfillment(of: [entered], timeout: 3)
        await fixture.library.configure(scope: .init(actorID: "bob", environmentID: "local"), cloudEnabled: false)
        gate.signal()
        do { _ = try await pending.value; XCTFail("Retired account published an image") } catch {}
        await fixture.close()
    }

    func testLargeImageColdAndWarmPreparationWork() async throws {
        let fixture = try await ThumbnailFixture(size: CGSize(width: 4000, height: 3000))
        defer { fixture.removeFiles() }
        let probe = ThumbnailProbe()
        let reader = LocalNoteThumbnailReader(library: fixture.library, currentScope: { fixture.scope }, load: { identity in
            probe.loaded(); return try await fixture.library.thumbnailData(for: identity)
        }, prepare: { data, size in
            probe.begin(); defer { probe.end() }; return UIImage(data: data)?.preparingThumbnail(of: size)
        })
        let start = CACurrentMediaTime()
        let cold = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 1024)
        let coldMS = (CACurrentMediaTime() - start) * 1000
        let warmStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let warm = try await reader.image(source: fixture.source, cardID: "local-note:one", scope: fixture.scope, bodyRevision: fixture.revision, pixelSize: 1024)
            XCTAssertTrue(warm === cold)
        }
        let warmMS = (CACurrentMediaTime() - warmStart) * 1000 / 10
        let bitmap = try XCTUnwrap(cold.cgImage)
        XCTAssertEqual(probe.loads, 1); XCTAssertEqual(probe.preparations, 1); XCTAssertFalse(probe.onMain)
        XCTAssertEqual(bitmap.width, 1024); XCTAssertEqual(bitmap.height, 768)
        print("EXECUTION_METRIC local_thumbnail source_pixels=12000000 cold_ms=\(coldMS) warm_mean_ms=\(warmMS) reads=\(probe.loads) preparations=\(probe.preparations) decoded_bytes=\(bitmap.bytesPerRow * bitmap.height)")
        await fixture.close()
    }

    private func settle() async {
        let turn = expectation(description: "consumer scheduling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { turn.fulfill() }
        await fulfillment(of: [turn], timeout: 1)
    }
}

@MainActor
private final class ThumbnailFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let scope = NoteStoreScope(actorID: "alice", environmentID: "local")
    let library: NoteLibraryStore
    let source: NoteThumbnailSource
    let revision: Int64
    init(size: CGSize = CGSize(width: 200, height: 100), bodyPadding: String = "") async throws {
        library = NoteLibraryStore(rootURL: root, service: { HomeOfflineTransport(scope: $0) })
        await library.configure(scope: scope, cloudEnabled: false)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.85))
        let photo = try await library.retainImage(.init(data: data, filename: "image.jpg", mimeType: "image/jpeg"), identifier: nil, createID: "one", scope: scope)
        let body = OfflineNoteBody(content: "Photo" + bodyPadding, contentJSON: #"[{"id":"photo","type":"image","props":{"url":"\#(photo.url.absoluteString)"}}]"#)
        let note = try await library.save(identifier: nil, createID: "one", body: body, scope: scope)
        revision = note.bodyRevision; source = .reference(photo.mediaRef)
    }
    func close() async { await library.configure(scope: nil, cloudEnabled: false) }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private final class ThumbnailProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var loadCount = 0, preparationCount = 0, active = 0, peakCount = 0
    private var main = false
    func loaded() { lock.lock(); defer { lock.unlock() }; loadCount += 1 }
    @discardableResult func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        preparationCount += 1; active += 1; peakCount = max(peakCount, active); main = main || Thread.isMainThread
        return preparationCount
    }
    func end() { lock.lock(); defer { lock.unlock() }; active -= 1 }
    var loads: Int { lock.lock(); defer { lock.unlock() }; return loadCount }
    var preparations: Int { lock.lock(); defer { lock.unlock() }; return preparationCount }
    var peak: Int { lock.lock(); defer { lock.unlock() }; return peakCount }
    var onMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
}
