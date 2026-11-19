import CoreFlow
import Foundation
import UIKit

/// One encoder for native image entry points. UIImage is captured as an immutable
/// value; no UIKit view or mutable store crosses this execution boundary.
final class CardImagePreparation: Sendable {
    enum PreparationError: Error { case encodingFailed }
    static let shared = CardImagePreparation()
    private let queue: OperationQueue
    private let encode: @Sendable (UIImage, CGFloat) -> Data?

    init(encode: @escaping @Sendable (UIImage, CGFloat) -> Data? = { $0.jpegData(compressionQuality: $1) }) {
        self.encode = encode
        queue = OperationQueue()
        queue.name = "app.chorai.image-preparation"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
    }

    func jpeg(_ image: UIImage, quality: CGFloat, filename: String) async throws -> CardEditingImage {
        try Task.checkCancellation()
        let operation = JPEGOperation(image: image, quality: quality, filename: filename, encode: encode)
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.install(continuation)
                queue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}

/// Operation supplies the synchronous running-slot lifetime. All shared payload
/// and continuation state is protected by the lock; running encoding owns a local
/// image reference until it actually returns, even if its consumer is canceled.
private final class JPEGOperation: Operation, @unchecked Sendable {
    private let stateLock = NSLock()
    private var image: UIImage?
    private var continuation: CheckedContinuation<CardEditingImage, Error>?
    private let quality: CGFloat
    private let filename: String
    private let encode: @Sendable (UIImage, CGFloat) -> Data?

    init(image: UIImage, quality: CGFloat, filename: String, encode: @escaping @Sendable (UIImage, CGFloat) -> Data?) {
        self.image = image
        self.quality = quality
        self.filename = filename
        self.encode = encode
    }

    func install(_ continuation: CheckedContinuation<CardEditingImage, Error>) {
        stateLock.lock()
        let canceled = isCancelled
        if !canceled { self.continuation = continuation }
        stateLock.unlock()
        if canceled { continuation.resume(throwing: CancellationError()) }
    }

    override func cancel() {
        super.cancel()
        stateLock.lock()
        image = nil
        let completion = continuation
        continuation = nil
        stateLock.unlock()
        completion?.resume(throwing: CancellationError())
    }

    override func main() {
        stateLock.lock()
        let source = image
        image = nil
        stateLock.unlock()
        guard !isCancelled, let source else { return }
        let result: Result<CardEditingImage, Error> = autoreleasepool {
            guard let data = encode(source, quality) else {
                return .failure(CardImagePreparation.PreparationError.encodingFailed)
            }
            return .success(CardEditingImage(data: data, filename: filename, mimeType: "image/jpeg"))
        }
        stateLock.lock()
        let completion = continuation
        continuation = nil
        stateLock.unlock()
        completion?.resume(with: result)
    }
}
