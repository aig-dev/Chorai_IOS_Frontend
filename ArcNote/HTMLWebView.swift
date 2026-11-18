import SwiftUI
import WebKit

struct AdaptiveHTMLWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let htmlContent: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let webView = ChoraiHTMLAppearance.makeWebView()
        webView.navigationDelegate = context.coordinator
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        guard context.coordinator.loadedContent != htmlContent else { return }
        context.coordinator.loadedContent = htmlContent
        webView.loadHTMLString(
            ChoraiHTMLAppearance.document(content: htmlContent),
            baseURL: nil
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AdaptiveHTMLWebView
        var loadedContent: String?
        private var contentSizeObservation: NSKeyValueObservation?

        init(_ parent: AdaptiveHTMLWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
            // Images may finish after navigation. Observe rendered size rather
            // than reloading the document each time SwiftUI measures its height.
            contentSizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak webView] _, _ in
                guard let webView else { return }
                self?.updateHeight(webView)
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("Math.ceil(Math.max(document.body.scrollHeight, document.body.getBoundingClientRect().height))") { [weak self] result, _ in
                guard let self, let value = result as? NSNumber else { return }
                let measured = max(CGFloat(value.doubleValue), 50)
                guard abs(self.parent.height - measured) > 0.5 else { return }
                DispatchQueue.main.async { [weak self] in self?.parent.height = measured }
            }
        }
    }
}

private enum ChoraiHTMLAppearance {
    static func makeWebView() -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    static func document(content: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root { color-scheme: light dark; --ink:#153b37; --muted:#586d64; --surface:#f0f0ea; --edge:#d9dfd7; --gold:#846838; }
        @media (prefers-color-scheme: dark) {
            :root { --ink:#bfdbcf; --muted:#a2b5ac; --surface:#35363b; --edge:#4c514f; --gold:#d6b378; }
        }
        html, body { margin:0; padding:0; background:transparent; width:100%; }
        /* Contain heading/paragraph margins so the measured body includes the
           last line. Collapsed margins can otherwise fall outside scrollHeight. */
        body { display:flow-root; }
        body { font:-apple-system-body; line-height:1.65; color:CanvasText; overflow-wrap:anywhere; -webkit-text-size-adjust:100%; }
        html { font:-apple-system-body; } body { font-family:ui-serif,'New York','Songti SC',Georgia,serif; font-size:1.235294rem; line-height:1.6; } p { margin-bottom:24px; }
        p { margin:0 0 16px; padding:0; }
        ul, ol { margin:12px 0; padding-left:24px; }
        li { margin:5px 0; }
        h1, h2, h3, h4, h5, h6 { margin:22px 0 12px; color:inherit; font-family:ui-serif,Georgia,serif; line-height:1.25; }
        h1 { font-size:1.75em; } h2 { font-size:1.45em; } h3 { font-size:1.2em; }
        blockquote { margin:16px 0; padding:8px 16px; border-left:3px solid var(--gold); color:var(--muted); }
        code { background:var(--surface); border-radius:4px; padding:2px 4px; font-family:ui-monospace,monospace; font-size:0.88em; }
        pre { box-sizing:border-box; max-width:100%; overflow-x:auto; padding:16px; border-radius:12px; background:var(--surface); }
        pre code { padding:0; background:transparent; }
        a { color:var(--ink); text-decoration:underline; }
        img, video { display:block; max-width:100%; height:auto; border-radius:12px; margin:16px 0; }
        table { display:block; overflow-x:auto; max-width:100%; border-collapse:collapse; margin:16px 0; }
        th, td { border:1px solid var(--edge); padding:8px; text-align:left; }
        th { background:var(--surface); }
        hr { border:0; border-top:1px solid var(--edge); margin:20px 0; }
        p { margin-bottom:24px; } body > :first-child { margin-top:0; }
        </style></head><body>\(content)</body></html>
        """
    }
}
