import Foundation
import WebKit

enum BlockNoteNavigationDecision: Equatable {
    case allow
    case cancel
}

struct BlockNoteNavigationGate {
    private let resourceDirectory: URL
    private let indexURL: URL
    private var didCompleteBootstrap = false

    init(resourceDirectory: URL, indexURL: URL) {
        self.resourceDirectory = resourceDirectory.standardizedFileURL
        self.indexURL = indexURL.standardizedFileURL
    }

    func decision(
        for url: URL?,
        isMainFrame: Bool
    ) -> BlockNoteNavigationDecision {
        guard let url, url.isFileURL else {
            return .cancel
        }

        let root = resourceDirectory.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate == root || candidate.hasPrefix(rootPrefix) else {
            return .cancel
        }

        if isMainFrame {
            guard !didCompleteBootstrap,
                  candidate == indexURL.standardizedFileURL.path else {
                return .cancel
            }
        }
        return .allow
    }

    mutating func completeBootstrapNavigation(to url: URL?) -> Bool {
        guard !didCompleteBootstrap,
              let url,
              url.isFileURL,
              url.standardizedFileURL.path == indexURL.standardizedFileURL.path else {
            return false
        }
        didCompleteBootstrap = true
        return true
    }
}

@MainActor
public final class BlockNoteEditorCoordinator: NSObject {
    private let controller: BlockNoteEditorController
    private var eventHandler: @MainActor (BlockNoteEditorEvent) -> Void
    private var session: BlockNoteEditorBridgeSession
    private weak var webView: WKWebView?
    private var navigationGate: BlockNoteNavigationGate?
    private var isTornDown = false

    init(
        document: BlockNoteInitialDocument,
        editable: Bool,
        controller: BlockNoteEditorController,
        onEvent: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        self.controller = controller
        eventHandler = onEvent
        session = BlockNoteEditorBridgeSession(document: document, editable: editable)
        super.init()
    }

    func makeWebView() -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(self, name: BlockNoteEditorProtocol.webKitHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.alwaysBounceVertical = false
        #endif

        controller.attach { [weak self] command in
            guard let self else { return }
            self.apply(self.session.request(command))
        }

        do {
            _ = try BlockNoteEditorResources.validateBundledResources()
            let directory = try BlockNoteEditorResources.resourceDirectory()
            let indexURL = try BlockNoteEditorResources.indexURL()
            navigationGate = BlockNoteNavigationGate(
                resourceDirectory: directory,
                indexURL: indexURL
            )
            webView.loadFileURL(indexURL, allowingReadAccessTo: directory)
        } catch {
            apply(session.bridgeFailure(code: "resource_validation_failed"))
        }

        return webView
    }

    func updateEventHandler(
        _ handler: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        eventHandler = handler
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: BlockNoteEditorProtocol.webKitHandlerName
        )
        apply(session.teardown())
        controller.detach(with: .tornDown)
        webView = nil
    }

    private func apply(_ output: BlockNoteBridgeSessionOutput) {
        for event in output.events {
            eventHandler(event)
        }
        if let snapshot = output.snapshot {
            _ = controller.complete(snapshot: snapshot)
        }
        if let failure = output.snapshotFailure {
            controller.failAllSnapshots(with: failure)
        }
        for command in output.commands {
            evaluate(command)
        }
    }

    private func evaluate(_ command: BlockNoteEditorCommand) {
        guard !isTornDown, let webView else {
            if let requestID = command.snapshotRequestID {
                controller.failSnapshot(requestID: requestID, with: .tornDown)
            }
            return
        }

        do {
            let data = try JSONEncoder().encode(command)
            let json = String(decoding: data, as: UTF8.self)
            let script = "window.\(BlockNoteEditorProtocol.javaScriptBridgeName).receiveCommand(\(json));"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error != nil else { return }
                Task { @MainActor in
                    guard let self, !self.isTornDown else { return }
                    self.apply(self.session.bridgeFailure(code: "javascript_evaluation_failed"))
                }
            }
        } catch {
            apply(session.bridgeFailure(code: "command_encoding_failed"))
        }
    }

    private func decodeMessageBody(_ body: Any) throws -> BlockNoteEditorMessage {
        let data: Data
        if let string = body as? String {
            data = Data(string.utf8)
        } else {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw BlockNoteMessageBodyError.invalidJSONObject
            }
            data = try JSONSerialization.data(withJSONObject: body)
        }
        return try JSONDecoder().decode(BlockNoteEditorMessage.self, from: data)
    }
}

extension BlockNoteEditorCoordinator: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard !isTornDown,
              message.name == BlockNoteEditorProtocol.webKitHandlerName,
              message.frameInfo.isMainFrame else {
            return
        }

        do {
            apply(session.receive(try decodeMessageBody(message.body)))
        } catch {
            apply(session.malformedMessage())
        }
    }
}

extension BlockNoteEditorCoordinator: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isTornDown,
              navigationGate?.completeBootstrapNavigation(to: webView.url) == true else {
            return
        }
        apply(session.navigationFinished())
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isTornDown else { return }
        apply(session.bridgeFailure(code: "navigation_failed"))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isTornDown else { return }
        apply(session.bridgeFailure(code: "navigation_failed"))
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard !isTornDown, let navigationGate else {
            decisionHandler(.cancel)
            return
        }

        let decision = navigationGate.decision(
            for: navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true
        )
        decisionHandler(decision == .allow ? .allow : .cancel)
    }
}

private enum BlockNoteMessageBodyError: Error {
    case invalidJSONObject
}
