//
//  WebView.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        // 在创建时立即加载页面
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 不在这里加载页面，避免重复加载
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, showError: $showError, errorMessage: $errorMessage)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var showError: Bool
        @Binding var errorMessage: String
        
        init(isLoading: Binding<Bool>, showError: Binding<Bool>, errorMessage: Binding<String>) {
            self._isLoading = isLoading
            self._showError = showError
            self._errorMessage = errorMessage
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            showError = false
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            showError = false
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // 忽略用户取消操作 (-999) 和其他常见的非致命错误
            if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled {
                return
            }
            
            isLoading = false
            showError = true
            errorMessage = error.localizedDescription
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 忽略用户取消操作 (-999) 和其他常见的非致命错误
            if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled {
                return
            }
            
            isLoading = false
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: WebView 页面
struct WebViewPage: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            WebView(
                url: url,
                isLoading: $isLoading,
                showError: $showError,
                errorMessage: $errorMessage
            )
            .opacity(isLoading ? 0 : 1)
            
        }
        .ignoresSafeArea(.all)
        .background(Color.black)
        .onAppear {
            print("URL: \(url.absoluteString)")
        }
    }
}

#Preview {
    WebViewPage(
        url: URL(string: "https://knowleopard.top/terms")!,
        title: "Terms of Service"
    )
}
