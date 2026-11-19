import Foundation
import WebKit

enum BlockNoteBridgeBootstrap {
    @MainActor static let contentWorld = WKContentWorld.page

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

    @MainActor static func install(in userContentController: WKUserContentController) {
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

/// Retained by an attachment's mailbox until its accepted events are applied.
/// WebKit callbacks stay weak; body delivery survives coordinator dismantling.
@MainActor
private final class BlockNoteBridgeDelivery {
    private weak var controller: BlockNoteEditorController?
    var eventHandler: @MainActor (BlockNoteEditorEvent) -> Void
    var submitCommand: (BlockNotePreparedCommand) -> Void = { _ in }
    var updateSummary: (BlockNotePreparedOutput) -> Void = { _ in }
    var isCurrentFocusProbe: (Int) -> Bool = { _ in false }

    init(controller: BlockNoteEditorController, eventHandler: @escaping @MainActor (BlockNoteEditorEvent) -> Void) {
        self.controller = controller
        self.eventHandler = eventHandler
    }

    func dispatch(_ prepared: BlockNotePreparedOutput) {
        if let revision = prepared.focusProbeRevision, !isCurrentFocusProbe(revision) { return }
        updateSummary(prepared)
        for command in prepared.commands { submitCommand(command) }
        let output = prepared.output
        if let snapshot = output.snapshot { _ = controller?.complete(snapshot: snapshot) }
        if let failure = output.snapshotRequestFailure { controller?.failSnapshot(requestID: failure.requestID, with: failure.failure) }
        if let failure = output.snapshotFailure { controller?.failAllSnapshots(with: failure) }
        for event in output.events { eventHandler(event) }
    }
}

@MainActor
public final class BlockNoteEditorCoordinator: NSObject {
    private let controller: BlockNoteEditorController
    private let localImageHandler: BlockNoteLocalImageHandler?
    private let delivery: BlockNoteBridgeDelivery
    private var mailbox: BlockNoteBridgeMailbox?
    private var mutationAllowed = false
    private weak var webView: WKWebView?
    private var navigationGate: BlockNoteNavigationGate?
    private var isTornDown = false
    private var focusObservationRevision = 0
    private var minimumWritingHeight: Double = 0
    private var hasFinishedNavigation = false
    private let resourceValidator: BlockNoteResourceValidator
    private var resourceValidationTask: Task<Void, Never>?
    private var resourceAttachmentID = UUID()

    init(
        document: BlockNoteInitialDocument,
        editable: Bool,
        controller: BlockNoteEditorController,
        localImageSource: BlockNoteLocalImageSource? = nil,
        resourceValidator: BlockNoteResourceValidator = .shared,
        onEvent: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        self.controller = controller
        self.resourceValidator = resourceValidator
        localImageHandler = localImageSource.map { BlockNoteLocalImageHandler(source: $0) }
        delivery = BlockNoteBridgeDelivery(controller: controller, eventHandler: onEvent)
        super.init()
        delivery.submitCommand = { [weak self] in self?.evaluate($0) }
        delivery.updateSummary = { [weak self] in self?.mutationAllowed = $0.mutationAllowed }
        delivery.isCurrentFocusProbe = { [weak self] revision in
            guard let self else { return false }
            return !self.isTornDown && revision == self.focusObservationRevision
        }
        let delivery = self.delivery
        mailbox = BlockNoteBridgeMailbox(worker: BlockNoteBridgeWorker(document: document, editable: editable)) {
            delivery.dispatch($0)
        }
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

        let mailbox = self.mailbox
        controller.attach(
            drainAcceptedEvents: { await mailbox?.drainAcceptedEvents() },
            hasPendingAcceptedEvents: { (mailbox?.pendingCount ?? 0) > 0 },
            beginClosing: { [weak self] in self?.teardown() }
        ) { [weak self] command in
            self?.submit(.command(command))
        }

        let attachment = UUID()
        resourceAttachmentID = attachment
        resourceValidationTask?.cancel()
        let validator = resourceValidator
        resourceValidationTask = Task { [weak self, weak webView] in
            do {
                _ = try await validator.validateBundledResources()
                guard !Task.isCancelled, let self, let webView,
                      !self.isTornDown, self.resourceAttachmentID == attachment,
                      self.webView === webView else { return }
                let directory = try BlockNoteEditorResources.resourceDirectory()
                let indexURL = try BlockNoteEditorResources.indexURL()
                self.navigationGate = BlockNoteNavigationGate(resourceDirectory: directory, indexURL: indexURL)
                let navigation = webView.loadFileURL(indexURL, allowingReadAccessTo: directory)
                self.navigationGate?.bindBootstrapNavigation(navigation)
            } catch is CancellationError {
            } catch {
                guard let self, !self.isTornDown,
                      self.resourceAttachmentID == attachment else { return }
                self.submit(.bridgeFailure("resource_validation_failed"))
            }
        }

        return webView
    }

    func updateEventHandler(
        _ handler: @escaping @MainActor (BlockNoteEditorEvent) -> Void
    ) {
        delivery.eventHandler = handler
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
        resourceAttachmentID = UUID()
        resourceValidationTask?.cancel()
        resourceValidationTask = nil
        localImageHandler?.close()

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: BlockNoteEditorProtocol.webKitHandlerName
        )
        mailbox?.close()
        controller.detach(with: .tornDown)
        webView = nil
    }

    private func submit(_ input: BlockNoteBridgeInput) {
        mailbox?.enqueue(input)
    }

    private func evaluate(_ prepared: BlockNotePreparedCommand) {
        let command = prepared.command
        guard !isTornDown, let webView else {
            if let requestID = command.snapshotRequestID {
                controller.failSnapshot(requestID: requestID, with: .tornDown)
            }
            return
        }
        let focusRevision: Int?
        switch command {
        case .focus, .blur:
            focusObservationRevision += 1
            focusRevision = focusObservationRevision
            submit(.focusObservation(focusObservationRevision))
        default: focusRevision = nil
        }
        webView.evaluateJavaScript(prepared.script) { [weak self] _, error in
            Task { @MainActor in
                guard let self, !self.isTornDown else { return }
                guard error == nil else {
                    self.submit(.bridgeFailure("javascript_evaluation_failed"))
                    return
                }
                if let focusRevision { self.reconcileBodyFocus(ifCurrent: focusRevision) }
            }
        }
    }

    private func reconcileBodyFocus(ifCurrent revision: Int) {
        guard !isTornDown,
              revision == focusObservationRevision,
              mutationAllowed,
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
                      self.mutationAllowed,
                      error == nil,
                      let isFocused = result as? Bool else { return }
                self.submit(.focusProbe(isFocused: isFocused, revision: revision))
            }
        }
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

        let envelope = BlockNoteBridgeEnvelope.capture(message.body)
        var revision: Int?
        if envelope.mayContainNaturalFocus {
            // Do not consult a stale main-thread readiness snapshot. The worker
            // observes ready and focus in the same FIFO as all other inputs.
            focusObservationRevision += 1
            revision = focusObservationRevision
        }
        submit(.message(envelope, focusRevision: revision))
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
        submit(.navigationFinished)
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isTornDown else { return }
        submit(.bridgeFailure("navigation_failed"))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isTornDown else { return }
        submit(.bridgeFailure("navigation_failed"))
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
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
