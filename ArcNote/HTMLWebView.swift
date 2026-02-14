import SwiftUI
import WebKit

struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let height: CGFloat
    
    init(htmlContent: String, height: CGFloat = 200) {
        self.htmlContent = htmlContent
        self.height = height
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let htmlString = createStyledHTML(from: htmlContent)
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLWebView
        
        init(_ parent: HTMLWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 获取内容高度并调整 WebView 高度
            webView.evaluateJavaScript("document.body.scrollHeight") { (result, error) in
                if let _ = result as? CGFloat {
                    DispatchQueue.main.async {
                        // 这里可以通知父视图更新高度
                        // 由于 SwiftUI 的限制，我们使用固定高度
                    }
                }
            }
        }
    }
    
    private func createStyledHTML(from content: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 16px;
                    line-height: 1.4;
                    color: rgba(255, 255, 255, 0.9);
                    background-color: transparent;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    max-height: 4.2em;
                    overflow: hidden;
                    position: relative;
                }
                
              
                
                p {
                    margin: 0 0 8px 0;
                    padding: 0;
                }
                
                ul, ol {
                    margin: 8px 0;
                    padding-left: 20px;
                }
                
                li {
                    margin: 4px 0;
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin: 12px 0 8px 0;
                    font-weight: 600;
                    color: rgba(255, 255, 255, 0.95);
                }
                
                h1 { font-size: 20px; }
                h2 { font-size: 18px; }
                h3 { font-size: 17px; }
                
                blockquote {
                    margin: 8px 0;
                    padding: 8px 12px;
                    border-left: 3px solid rgba(255, 255, 255, 0.3);
                    background-color: rgba(255, 255, 255, 0.05);
                    font-style: italic;
                }
                
                code {
                    background-color: rgba(255, 255, 255, 0.1);
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
                    font-size: 14px;
                }
                
                pre {
                    background-color: rgba(255, 255, 255, 0.1);
                    padding: 8px 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 8px 0;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                
                a {
                    color: rgba(255, 255, 255, 0.8);
                    text-decoration: underline;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                    margin: 8px 0;
                }
                
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin: 8px 0;
                }
                
                th, td {
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    padding: 6px 8px;
                    text-align: left;
                }
                
                th {
                    background-color: rgba(255, 255, 255, 0.1);
                    font-weight: 600;
                }
                
                hr {
                    border: none;
                    border-top: 1px solid rgba(255, 255, 255, 0.2);
                    margin: 12px 0;
                }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}

// MARK: - 自适应高度的 HTML WebView
struct AdaptiveHTMLWebView: UIViewRepresentable {
    let htmlContent: String
    @Binding var height: CGFloat
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let htmlString = createStyledHTML(from: htmlContent)
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AdaptiveHTMLWebView
        
        init(_ parent: AdaptiveHTMLWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 获取内容高度并更新绑定
            webView.evaluateJavaScript("document.body.scrollHeight") { (result, error) in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.height = max(height, 50) // 最小高度 50
                    }
                }
            }
        }
    }
    
    private func createStyledHTML(from content: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 16px;
                    line-height: 1.4;
                    color: rgba(255, 255, 255, 0.9);
                    background-color: transparent;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    max-height: 4.2em;
                    overflow: hidden;
                    position: relative;
                }
                
                p {
                    margin: 0 0 8px 0;
                    padding: 0;
                }
                
                ul, ol {
                    margin: 8px 0;
                    padding-left: 20px;
                }
                
                li {
                    margin: 4px 0;
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin: 12px 0 8px 0;
                    font-weight: 600;
                    color: rgba(255, 255, 255, 0.95);
                }
                
                h1 { font-size: 20px; }
                h2 { font-size: 18px; }
                h3 { font-size: 17px; }
                
                blockquote {
                    margin: 8px 0;
                    padding: 8px 12px;
                    border-left: 3px solid rgba(255, 255, 255, 0.3);
                    background-color: rgba(255, 255, 255, 0.05);
                    font-style: italic;
                }
                
                code {
                    background-color: rgba(255, 255, 255, 0.1);
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
                    font-size: 14px;
                }
                
                pre {
                    background-color: rgba(255, 255, 255, 0.1);
                    padding: 8px 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 8px 0;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                }
                
                a {
                    color: rgba(255, 255, 255, 0.8);
                    text-decoration: underline;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                    margin: 8px 0;
                }
                
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin: 8px 0;
                }
                
                th, td {
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    padding: 6px 8px;
                    text-align: left;
                }
                
                th {
                    background-color: rgba(255, 255, 255, 0.1);
                    font-weight: 600;
                }
                
                hr {
                    border: none;
                    border-top: 1px solid rgba(255, 255, 255, 0.2);
                    margin: 12px 0;
                }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}
