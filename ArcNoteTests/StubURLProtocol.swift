import Foundation
import Alamofire

final class StubURLProtocol: URLProtocol {
    struct Handler {
        let start: (StubURLProtocol) -> Void
        let stop: () -> Void
    }
    private static let registryLock = NSLock()
    private static var handlers: [String: Handler] = [:]
    private let stateLock = NSRecursiveLock()
    private var stopped = false
    private var completed = false

    static func register(host: String, handler: Handler) {
        registryLock.lock(); defer { registryLock.unlock() }
        handlers[host] = handler
    }
    static func remove(host: String) {
        registryLock.lock(); defer { registryLock.unlock() }
        handlers.removeValue(forKey: host)
    }
    private var handler: Handler? {
        Self.registryLock.lock(); defer { Self.registryLock.unlock() }
        return Self.handlers[request.url?.host ?? ""]
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
    func respond(status: Int = 200, body: Data) {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !stopped, let url = request.url else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        completed = true
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class HTTPFixture {
    let host = UUID().uuidString.lowercased() + ".invalid"
    let session: Session
    private let lock = NSLock()
    private var requests: [StubURLProtocol] = []
    var baseURL: String { "https://" + host }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    init(onStart: @escaping () -> Void = {}, onStop: @escaping () -> Void = {}) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        session = Session(configuration: configuration)
        StubURLProtocol.register(host: host, handler: .init(start: { [weak self] request in
            guard let self else { return }
            lock.lock(); requests.append(request); lock.unlock()
            onStart()
        }, stop: onStop))
    }
    func respond(_ body: String, status: Int = 200, at index: Int = 0) {
        lock.lock(); let request = requests[index]; lock.unlock()
        request.respond(status: status, body: Data(body.utf8))
    }
    deinit { StubURLProtocol.remove(host: host); session.cancelAllRequests() }

    static let detail = #"{"success":true,"data":{"id":"card","content":"body","content_hash":"v1","is_public":true,"tags":[],"created_at":"now","updated_at":"now","like_count":0,"is_liked":false,"is_pinned":false,"is_favorited":false,"favorite_count":0,"comment_count":0,"rate":1,"author":{"author_id":"actor","author_name":"Author"}}}"#
}
