import Foundation

/// 应用元数据集中管理
enum AppInfo {
    static let name = "Hora"
    static let version = "7.0.2"
    static let build = "2"
    static let bundleIdentifier = "com.hora.app"
    static let githubURL = "https://github.com/lfvepclr/hora"
    static let license = "MIT"
    static let minimumSystemVersion = "14.0"

    static func resourceBundle(in bundle: Bundle = .main) -> Bundle {
        if let url = bundle.url(forResource: "Hora_Hora", withExtension: "bundle"),
           let resources = Bundle(url: url) {
            return resources
        }
        return Bundle.module
    }
}
