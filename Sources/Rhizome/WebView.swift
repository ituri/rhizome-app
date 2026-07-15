#if os(iOS)
import SwiftUI
import WebKit

/// A WKWebView wrapper around the Rhizome PWA. Uses the default (persistent) data
/// store so the login session, cookies and the app's IndexedDB offline cache all
/// survive relaunches — the web app already handles offline boot and sync, so the
/// native shell just has to keep its storage around.
struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persist cookies + IndexedDB across launches
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        weak var webView: WKWebView?
        init(_ parent: WebView) { self.parent = parent }

        @objc func reload(_ sender: UIRefreshControl) { webView?.reload() }

        // Keep in-app navigation on our own host; open outside links (share cards,
        // OAuth, external references) in the system browser.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else { return decisionHandler(.allow) }
            let sameHost = target.host == Config.serverURL.host
            if navigationAction.navigationType == .linkActivated && !sameHost {
                UIApplication.shared.open(target)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(webView)
        }

        private func finish(_ webView: WKWebView) {
            parent.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
    }
}
#endif
