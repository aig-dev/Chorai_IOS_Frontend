import XCTest
import UIKit
import SwiftUI
import CoreFlow
@testable import ArcNote

@MainActor
final class CardImagePreparationTests: XCTestCase {
    private func image(size: CGSize = CGSize(width: 64, height: 32)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testProfilePickerBindingRejectsReplacementWhileCapturedImageEncodes() async throws {
        let original = image()
        let replacement = image(size: CGSize(width: 32, height: 64))
        var selected: UIImage? = original
        var saving = true
        let binding = EditProfileView.imageSelectionBinding(
            Binding(get: { selected }, set: { selected = $0 }), isSaving: { saving })
        let entered = expectation(description: "captured profile image encoding")
        let gate = DispatchSemaphore(value: 0)
        let preparation = CardImagePreparation { image, quality in
            entered.fulfill(); _ = gate.wait(timeout: .now() + 3)
            return image.jpegData(compressionQuality: quality)
        }
        let pending = Task { try await preparation.jpeg(original, quality: 0.82, filename: "profile.jpg") }
        await fulfillment(of: [entered], timeout: 2)
        binding.wrappedValue = replacement
        XCTAssertTrue(selected === original, "A stale picker callback must not replace the captured selection")
        gate.signal()
        let encoded = try await pending.value
        XCTAssertEqual(encoded.data, original.jpegData(compressionQuality: 0.82))
        saving = false
        binding.wrappedValue = replacement
        XCTAssertTrue(selected === replacement, "Selection becomes editable again after save finishes")
    }

    func testJPEGEncodingRunsOffMainAndForwardsOriginalQualities() async throws {
        let preparation = CardImagePreparation { image, quality in
            XCTAssertFalse(Thread.isMainThread)
            return image.jpegData(compressionQuality: quality)
        }
        let original = image()
        for quality: CGFloat in [0.82, 0.88, 0.9] {
            let result = try await preparation.jpeg(original, quality: quality, filename: "fixture.jpg")
            XCTAssertEqual(result.data, original.jpegData(compressionQuality: quality))
            XCTAssertEqual(result.mimeType, "image/jpeg")
            XCTAssertEqual(result.filename, "fixture.jpg")
            XCTAssertTrue(Thread.isMainThread)
        }
    }

    func testOrientationAndDimensionsMatchExistingEncoding() async throws {
        let original = UIImage(cgImage: try XCTUnwrap(image().cgImage), scale: 2, orientation: .left)
        let before = try XCTUnwrap(original.jpegData(compressionQuality: 0.9))
        let result = try await CardImagePreparation.shared.jpeg(original, quality: 0.9, filename: "camera.jpg")
        XCTAssertEqual(result.data, before)
        let beforeImage = try XCTUnwrap(UIImage(data: before))
        let after = try XCTUnwrap(UIImage(data: result.data))
        XCTAssertEqual(after.size, beforeImage.size)
        XCTAssertEqual(after.imageOrientation, beforeImage.imageOrientation)
    }

    func testCancelledRunningPreparationDoesNotUploadOrFreeItsSerialSlot() async throws {
        let started = expectation(description: "first started")
        let secondStarted = expectation(description: "second started")
        let gate = DispatchSemaphore(value: 0)
        let counter = ImageEncodingCounter()
        let preparation = CardImagePreparation { image, quality in
            let index = counter.begin()
            defer { counter.end() }
            if index == 1 { started.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            else { secondStarted.fulfill() }
            return image.jpegData(compressionQuality: quality)
        }
        let image = image()
        var uploads = [String]()
        let first = Task {
            let value = try await preparation.jpeg(image, quality: 0.9, filename: "old.jpg")
            uploads.append(value.filename)
        }
        await fulfillment(of: [started], timeout: 3)
        first.cancel()
        let second = Task {
            let value = try await preparation.jpeg(image, quality: 0.9, filename: "new.jpg")
            uploads.append(value.filename)
        }
        do { try await first.value; XCTFail("Cancellation not delivered") } catch is CancellationError {} catch { XCTFail("\(error)") }
        gate.signal()
        try await second.value
        await fulfillment(of: [secondStarted], timeout: 3)
        XCTAssertEqual(uploads, ["new.jpg"])
        XCTAssertEqual(counter.peak, 1)
    }

    func testQueuedCancellationSkipsEncodingAndReleasesImage() async throws {
        let started = expectation(description: "started")
        let gate = DispatchSemaphore(value: 0)
        let counter = ImageEncodingCounter()
        let preparation = CardImagePreparation { image, quality in
            let index = counter.begin()
            defer { counter.end() }
            if index == 1 { started.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            return image.jpegData(compressionQuality: quality)
        }
        let first = Task { try await preparation.jpeg(image(), quality: 0.9, filename: "one.jpg") }
        await fulfillment(of: [started], timeout: 3)
        var pendingImage: UIImage? = image()
        weak var weakImage = pendingImage
        let pending = Task { [captured = pendingImage!] in
            try await preparation.jpeg(captured, quality: 0.9, filename: "cancel.jpg")
        }
        pendingImage = nil
        pending.cancel()
        _ = await pending.result
        gate.signal()
        _ = try await first.value
        XCTAssertEqual(counter.calls, 1)
        // The canceled queue entry must not retain the large image.
        XCTAssertNil(weakImage)
    }

    func testEncodingFailureIsReported() async {
        let preparation = CardImagePreparation { _, _ in nil }
        do { _ = try await preparation.jpeg(image(), quality: 0.9, filename: "bad.jpg"); XCTFail() }
        catch CardImagePreparation.PreparationError.encodingFailed {}
        catch { XCTFail("\(error)") }
    }

    func testSyntheticTwelveMegapixelBaseline() async throws {
        let source = image(size: CGSize(width: 4000, height: 3000))
        var samples = [Double]()
        for iteration in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
            XCTAssertGreaterThan(data.count, 0)
            if iteration >= 5 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        ExecutionFixtures.report("12MP_direct_jpeg_q90", samples: samples)
        samples.removeAll()
        for iteration in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            let value = try await CardImagePreparation.shared.jpeg(source, quality: 0.9, filename: "12mp.jpg")
            XCTAssertGreaterThan(value.data.count, 0)
            if iteration >= 5 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        ExecutionFixtures.report("12MP_worker_jpeg_q90", samples: samples)

    }
}

/// Every mutable field is accessed under the same lock.
private final class ImageEncodingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var total = 0
    private var maximum = 0
    var peak: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return total }
    func begin() -> Int { lock.lock(); defer { lock.unlock() }; active += 1; total += 1; maximum = max(maximum, active); return total }
    func end() { lock.lock(); defer { lock.unlock() }; active -= 1 }
}
