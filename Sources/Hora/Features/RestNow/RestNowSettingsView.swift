import SwiftUI

// MARK: - Shared Duration Picker Component

/// 纯 UI 组件：工作/休息时长选择器
/// 通过 Binding 双向绑定数据，选项列表由调用方传入，适配不同上下文
struct RestNowDurationPicker: View {
    @Binding var workMinutes: Int
    @Binding var restMinutes: Int

    let workOptions: [Int]
    let restOptions: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("工作时长")
                    .font(.headline)
                Picker("工作时长", selection: $workMinutes) {
                    ForEach(workOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("休息时长")
                    .font(.headline)
                Picker("休息时长", selection: $restMinutes) {
                    ForEach(restOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

// MARK: - Settings Panel View

/// 定时休息配置面板视图
/// 组合：Toggle + RestNowDurationPicker + 颜色设置 + 关闭按钮
struct RestNowSettingsView: View {
    @ObservedObject var session = RestNowSession.shared
    @AppStorage("hora.restNow.workDuration") private var workDurationSeconds = 1200
    @AppStorage("hora.restNow.restDuration") private var restDurationSeconds = 300

    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("定时休息设置")
                .font(.title.bold())

            Toggle("开启定时休息", isOn: $session.isEnabled)
                .font(.headline)

            RestNowDurationPicker(
                workMinutes: workMinutesBinding,
                restMinutes: restMinutesBinding,
                workOptions: [20, 30, 45, 60],
                restOptions: [1, 3, 5, 10]
            )

            RestNowColorSettingsView()

            Spacer()

            Button("关闭") {
                onDismiss?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .frame(width: 460, height: 460)
        .onChange(of: workDurationSeconds) {
            if session.isEnabled { session.resetCycle() }
        }
        .onChange(of: restDurationSeconds) {
            if session.isEnabled { session.resetCycle() }
        }
    }

    // MARK: - Binding Converters (seconds ↔ minutes)

    private var workMinutesBinding: Binding<Int> {
        Binding(
            get: { max(workDurationSeconds / 60, 1) },
            set: { workDurationSeconds = $0 * 60 }
        )
    }

    private var restMinutesBinding: Binding<Int> {
        Binding(
            get: { max(restDurationSeconds / 60, 1) },
            set: { restDurationSeconds = $0 * 60 }
        )
    }
}
