import SwiftUI
import WebKit
import CoreLocation

// MARK: - Web World Clock View

struct WebWorldClockView: View {
    @ObservedObject var viewModel: WorldClockViewModel
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            WorldClockWebView(
                cities: viewModel.cities,
                selectedCity: viewModel.currentCity,
                onCitySelected: { cityName in
                    if let city = viewModel.cities.first(where: { $0.name == cityName }) {
                        viewModel.currentCity = city
                    }
                },
                onFullscreen: {
                    // 全屏处理由父视图处理
                }
            )
            .opacity(isLoading ? 0 : 1)
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isLoading = false
            }
        }
    }
}

// MARK: - World Clock Web View (WKWebView Wrapper)

struct WorldClockWebView: NSViewRepresentable {
    let cities: [WorldCity]
    let selectedCity: WorldCity
    let onCitySelected: (String) -> Void
    let onFullscreen: () -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 启用JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // 设置消息处理器
        configuration.userContentController.add(context.coordinator, name: "citySelectedHandler")
        configuration.userContentController.add(context.coordinator, name: "fullscreenHandler")
        
        // 创建WebView
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        
        // 加载HTML
        loadHTML(in: webView)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // 更新选中的城市
        let escapedName = selectedCity.name.replacingOccurrences(of: "'", with: "\\'")
        let script = "if (typeof setSelectedCity === 'function') { setSelectedCity('\(escapedName)'); }"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCitySelected: onCitySelected,
            onFullscreen: onFullscreen
        )
    }
    
    private func loadHTML(in webView: WKWebView) {
        // Swift Package中必须使用Bundle.module
        let bundle = Bundle.module
        
        if let htmlURL = bundle.url(forResource: "worldclock", withExtension: "html") {
            // allowingReadAccessTo 设置为 bundle 根目录，让 JS 可以 fetch 同目录下的 JSON 文件
            let baseURL = bundle.bundleURL
            webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
        } else {
            print("ERROR: Failed to load worldclock.html from bundle")
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onCitySelected: (String) -> Void
        let onFullscreen: () -> Void
        
        init(onCitySelected: @escaping (String) -> Void, onFullscreen: @escaping () -> Void) {
            self.onCitySelected = onCitySelected
            self.onFullscreen = onFullscreen
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "citySelectedHandler":
                if let cityName = message.body as? String {
                    onCitySelected(cityName)
                }
            case "fullscreenHandler":
                onFullscreen()
            default:
                break
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading worldclock.html")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error)")
        }
    }
}
