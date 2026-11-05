import Foundation
import WebKit

enum BlockNoteBridgeBootstrap {
    static let contentWorld = WKContentWorld.page

    static var source: String {
        """
        (() => {
          const bridgeWindow = window;
          const bridgeName = "\(BlockNoteEditorProtocol.javaScriptBridgeName)";
          const queueName = "\(BlockNoteEditorProtocol.javaScriptQueueName)";
          const existingQueue = bridgeWindow[queueName];
          if (
            existingQueue &&
            bridgeWindow[bridgeName] === existingQueue.receiver &&
            Array.isArray(existingQueue.pending)
          ) return;

          const previous = bridgeWindow[bridgeName];
          const pending = [];
          const receiver = {
            receiveCommand(command) { pending.push(command); }
          };
          bridgeWindow[queueName] = { receiver, pending, previous };
          bridgeWindow[bridgeName] = receiver;
        })();
        """
    }

    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: contentWorld
        ))
    }
}

enum BlockNoteBodyFocusObservation {
    static var source: String {
        """
        (() => {
          const report = () => {
            const root = document.querySelector('.ios-editor-root');
            const active = document.activeElement;
            const isFocused = Boolean(root && active && root.contains(active) && active.isContentEditable);
            window.webkit.messageHandlers.\(BlockNoteEditorProtocol.webKitHandlerName).postMessage({
              type: 'bodyFocusChanged', isFocused
            });
          };
          const schedule = () => queueMicrotask(report);
          document.addEventListener('focusin', schedule, true);
          document.addEventListener('focusout', schedule, true);
        })();
        """
    }
}

enum BlockNoteNavigationDecision: Equatable {
    case allow
    case cancel
}

struct BlockNoteNavigationGate {
    private let canonicalResourceDirectory: URL
    private let canonicalIndexURL: URL
    private let exactIndexURL: String
    private var bootstrapNavigation: AnyObject?
    private var didAuthorizeBootstrap = false
    private var didCompleteBootstrap = false

    init(resourceDirectory: URL, indexURL: URL) {
        canonicalResourceDirectory = resourceDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        canonicalIndexURL = indexURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        exactIndexURL = indexURL.absoluteString
    }

    mutating func bindBootstrapNavigation(_ navigation: AnyObject?) {
        guard bootstrapNavigation == nil, let navigation else { return }
        bootstrapNavigation = navigation
    }

    mutating func decision(
        for url: URL?,
        isMainFrame: Bool
    ) -> BlockNoteNavigationDecision {
        guard let url,
              Self.hasLocalFileAuthority(url) else {
            return .cancel
        }

        let root = canonicalResourceDirectory.path
        let candidate = url
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate == root || candidate.hasPrefix(rootPrefix) else {
            return .cancel
        }

        if isMainFrame {
            guard !didAuthorizeBootstrap,
                  !didCompleteBootstrap,
                  url.absoluteString == exactIndexURL,
                  candidate == canonicalIndexURL.path else {
                return .cancel
            }
            didAuthorizeBootstrap = true
        }
        return .allow
    }

    mutating func completeBootstrapNavigation(
        _ navigation: AnyObject?,
        to url: URL?
    ) -> Bool {
        guard didAuthorizeBootstrap,
              !didCompleteBootstrap,
              let navigation,
              let bootstrapNavigation,
              navigation === bootstrapNavigation,
              let url,
              Self.hasLocalFileAuthority(url),
              url.absoluteString == exactIndexURL,
              url.resolvingSymlinksInPath().standardizedFileURL.path == canonicalIndexURL.path else {
            return false
        }
        didCompleteBootstrap = true
        return true
    }

    private static func hasLocalFileAuthority(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.user == nil,
              url.password == nil,
              url.port == nil else {
            return false
        }
        guard let host = url.host, !host.isEmpty else {
            return true
        }
        return host.caseInsensitiveCompare("localhost") == .orderedSame
    }
}

@MainActor
public final class BlockNoteEditorCoordinator: NSObject {
    private let controller: BlockNoteEditorController
    private let localImageHandler: BlockNoteLocalImageHandler?
    private var eventHandler: @MainActor (BlockNoteEditorEvent) -> Void
    private var session: BlockNoteEditorBridgeSession
    private weak var webView: WKWebView?
    private var navigationGate: BlockNoteNavigationGate?
    private var isTornDown = false
    private var focusObservationRevision = 0
    private var minimumWritingHeight: Double = 0
    private var hasFinishedNavigation = false

    init(
        document: BlockNoteInitialDocument,
        editable: Bool,
        controller: BlockNoteEditorController,
        localImageSource: BlockNoteLocalImageSource? = nil,
        onEvent: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        self.controller = controller
        localImageHandler = localImageSource.map { BlockNoteLocalImageHandler(source: $0) }
        eventHandler = onEvent
        session = BlockNoteEditorBridgeSession(document: document, editable: editable)
        super.init()
    }

    func makeWebView(
        fontScale: Double = 23.0 / 17.0,
        minimumWritingHeight: Double = 0
    ) -> WKWebView {
        self.minimumWritingHeight = BlockNoteEditorAppearance.normalizedMinimumWritingHeight(minimumWritingHeight)
        let userContentController = WKUserContentController()
        BlockNoteBridgeBootstrap.install(in: userContentController)
        userContentController.addUserScript(WKUserScript(
            source: BlockNoteBodyFocusObservation.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: BlockNoteBridgeBootstrap.contentWorld
        ))
        userContentController.addUserScript(WKUserScript(
            source: BlockNoteEditorAppearance.installationScript(
                fontScale: fontScale,
                minimumWritingHeight: self.minimumWritingHeight
            ),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.add(self, name: BlockNoteEditorProtocol.webKitHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .nonPersistent()
        if let localImageHandler {
            configuration.setURLSchemeHandler(localImageHandler, forURLScheme: localImageHandler.scheme)
        }

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
            let navigation = webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: directory
            )
            navigationGate?.bindBootstrapNavigation(navigation)
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

    func updateMinimumWritingHeight(_ height: Double) {
        let height = BlockNoteEditorAppearance.normalizedMinimumWritingHeight(height)
        guard minimumWritingHeight != height else { return }
        minimumWritingHeight = height
        applyMinimumWritingHeight()
    }

    private func applyMinimumWritingHeight() {
        guard !isTornDown, hasFinishedNavigation, let webView else { return }
        // This floor comes from SwiftUI's available page, never from the
        // WebView's content-dependent height. Removing text can shrink again.
        webView.evaluateJavaScript(
            BlockNoteEditorAppearance.minimumWritingHeightScript(minimumWritingHeight)
        )
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        localImageHandler?.close()

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
        BlockNoteBridgeOutputDispatcher(
            submitCommand: { [weak self] command in
                self?.evaluate(command)
            },
            emitEvent: { [weak self] event in
                self?.eventHandler(event)
            },
            completeSnapshot: { [weak controller] snapshot in
                _ = controller?.complete(snapshot: snapshot)
            },
            failSnapshot: { [weak controller] failure in
                controller?.failSnapshot(
                    requestID: failure.requestID,
                    with: failure.failure
                )
            },
            failSnapshots: { [weak controller] failure in
                controller?.failAllSnapshots(with: failure)
            }
        ).dispatch(output)
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
            let focusRevision: Int?
            switch command {
            case .focus, .blur:
                focusObservationRevision += 1
                focusRevision = focusObservationRevision
            default:
                focusRevision = nil
            }
            webView.evaluateJavaScript(script) { [weak self] _, error in
                Task { @MainActor in
                    guard let self, !self.isTornDown else { return }
                    guard error == nil else {
                        self.apply(self.session.bridgeFailure(code: "javascript_evaluation_failed"))
                        return
                    }
                    if let focusRevision {
                        self.reconcileBodyFocus(ifCurrent: focusRevision)
                    }
                }
            }
        } catch {
            apply(session.bridgeFailure(code: "command_encoding_failed"))
        }
    }

    private func reconcileBodyFocus(ifCurrent revision: Int) {
        guard !isTornDown,
              revision == focusObservationRevision,
              session.state.mutationAllowed,
              let webView else { return }
        // Hydration can focus the DOM before the React bridge observes focus.
        // Repeating focus() then produces no event. Read the real DOM state after
        // explicit focus/blur instead of treating the command as confirmation.
        let script = """
        (() => {
          const root = document.querySelector('.ios-editor-root');
          const active = document.activeElement;
          return Boolean(root && active && root.contains(active) && active.isContentEditable);
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.isTornDown,
                      revision == self.focusObservationRevision,
                      self.session.state.mutationAllowed,
                      error == nil,
                      let isFocused = result as? Bool else { return }
                self.apply(self.session.receive(.bodyFocusChanged(isFocused: isFocused)))
            }
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
            let decoded = try decodeMessageBody(message.body)
            if case .bodyFocusChanged = decoded {
                // DOM focus can change while the document is still hydrating.
                guard session.state.isBridgeReady else { return }
                // A genuine newer event takes precedence over an outstanding
                // command acknowledgement, even if that query finishes later.
                focusObservationRevision += 1
            }
            apply(session.receive(decoded))
        } catch {
            apply(session.malformedMessage())
        }
    }
}

extension BlockNoteEditorCoordinator: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isTornDown,
              navigationGate?.completeBootstrapNavigation(
                  navigation,
                  to: webView.url
              ) == true else {
            return
        }
        hasFinishedNavigation = true
        applyMinimumWritingHeight()
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
        guard !isTornDown,
              let decision = navigationGate?.decision(
                  for: navigationAction.request.url,
                  isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true
              ) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(decision == .allow ? .allow : .cancel)
    }
}

private enum BlockNoteMessageBodyError: Error {
    case invalidJSONObject
}
