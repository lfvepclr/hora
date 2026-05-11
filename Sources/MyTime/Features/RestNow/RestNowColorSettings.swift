import SwiftUI
import Cocoa

/// 定时休息颜色配置管理
@MainActor
final class RestNowColorSettings: ObservableObject {
    static let shared = RestNowColorSettings()

    @Published var workColor: NSColor {
        didSet { saveColor(workColor, forKey: "mytime.restNow.workCircleColor") }
    }
    @Published var restColor: NSColor {
        didSet { saveColor(restColor, forKey: "mytime.restNow.restCircleColor") }
    }

    private init() {
        workColor = Self.loadColor(forKey: "mytime.restNow.workCircleColor") ?? NSColor.systemTeal
        restColor = Self.loadColor(forKey: "mytime.restNow.restCircleColor") ?? NSColor.systemOrange
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
}

// MARK: - Color Settings View

struct RestNowColorSettingsView: View {
    @ObservedObject var settings = RestNowColorSettings.shared

    private let presetColors: [NSColor] = [
        .systemTeal, .systemBlue, .systemGreen, .systemIndigo,
        .systemOrange, .systemPink, .systemRed, .systemYellow,
        .systemPurple, .systemMint
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圆圈颜色设置")
                .font(.headline)

            // 工作圆圈颜色
            VStack(alignment: .leading, spacing: 8) {
                Text("工作圆圈")
                    .font(.subheadline)
                HStack(spacing: 6) {
                    ForEach(presetColors, id: \.self) { color in
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Group {
                                    if settings.workColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            )
                            .onTapGesture { settings.workColor = color }
                    }
                    ColorPicker("", selection: workColorBinding)
                        .labelsHidden()
                }
            }

            // 休息圆圈颜色
            VStack(alignment: .leading, spacing: 8) {
                Text("休息圆圈")
                    .font(.subheadline)
                HStack(spacing: 6) {
                    ForEach(presetColors, id: \.self) { color in
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Group {
                                    if settings.restColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            )
                            .onTapGesture { settings.restColor = color }
                    }
                    ColorPicker("", selection: restColorBinding)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var workColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.workColor) },
            set: { settings.workColor = NSColor($0) }
        )
    }

    private var restColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.restColor) },
            set: { settings.restColor = NSColor($0) }
        )
    }
}

