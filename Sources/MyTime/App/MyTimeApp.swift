import SwiftUI

@main
struct MyTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // 禁用窗口标签页功能（消除 WindowTab 警告）
        // 对于菜单栏应用，不需要窗口标签页
        UserDefaults.standard.register(defaults: ["NSWindowTabbingDisabled": true])
    }
    
    var body: some Scene {
        // 菜单栏应用，不显示主窗口
        Settings {
            SettingsView()
                .frame(width: 500, height: 400)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var selectedTab: Tab = .calendar
    @Published var currentTimeZone: TimeZone = .current
    
    enum Tab {
        case calendar
        case worldClock
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200)
        } detail: {
            switch appState.selectedTab {
            case .calendar:
                CalendarContainerView()
            case .worldClock:
                WorldClockView()
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            Section("Navigation") {
                Label("Calendar", systemImage: "calendar")
                    .tag(AppState.Tab.calendar)
                
                Label("World Clock", systemImage: "globe")
                    .tag(AppState.Tab.worldClock)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MyTime")
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("General Settings")
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
    }
}
