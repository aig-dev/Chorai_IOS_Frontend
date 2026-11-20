import Foundation
import Alamofire
import os

/// URLSession owns the immutable request/client association. The recursive lock
/// serializes response delivery with cancellation, including reentrant client calls.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Handler: Sendable {
        let start: @Sendable (StubURLProtocol) -> Void
        let stop: @Sendable () -> Void
    }
    private static let handlers = OSAllocatedUnfairLock(initialState: [String: Handler]())
    private let stateLock = NSRecursiveLock()
    private var stopped = false
    private var completed = false

    static func register(host: String, handler: Handler) {
        handlers.withLock { $0[host] = handler }
    }
    static func remove(host: String) {
        _ = handlers.withLock { $0.removeValue(forKey: host) }
    }
    private var handler: Handler? {
        Self.handlers.withLock { $0[request.url?.host ?? ""] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        handler.start(self)
    }
    override func stopLoading() {
        stateLock.lock()
        let first = !stopped && !completed
        stopped = true
        stateLock.unlock()
        if first { handler?.stop() }
    }
    func respond(status: Int = 200, body: Data, contentType: String = "application/json") {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !stopped, let url = request.url else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        completed = true
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class HTTPFixture: Sendable {
    let host = UUID().uuidString.lowercased() + ".invalid"
    let session: Session
    private let requests = OSAllocatedUnfairLock(initialState: [StubURLProtocol]())
    var baseURL: String { "https://" + host }
    var count: Int { requests.withLock { $0.count } }

    init(onStart: @escaping @Sendable () -> Void = {}, onStop: @escaping @Sendable () -> Void = {}) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        session = Session(configuration: configuration)
        StubURLProtocol.register(host: host, handler: .init(start: { [weak self] request in
            guard let self else { return }
            requests.withLock { $0.append(request) }
            onStart()
        }, stop: onStop))
    }
    func respond(_ body: String, status: Int = 200, at index: Int = 0, contentType: String = "application/json") {
        let request = requests.withLock { $0[index] }
        request.respond(status: status, body: Data(body.utf8), contentType: contentType)
    }
    deinit { StubURLProtocol.remove(host: host); session.cancelAllRequests() }

    static let detail = #"{"success":true,"data":{"id":"card","content":"body","content_hash":"v1","is_public":true,"tags":[],"created_at":"now","updated_at":"now","like_count":0,"is_liked":false,"is_pinned":false,"is_favorited":false,"favorite_count":0,"comment_count":0,"rate":1,"author":{"author_id":"actor","author_name":"Author"}}}"#
}
