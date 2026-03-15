import SwiftUI

struct WorldClockView: View {
    @StateObject private var viewModel = WorldClockViewModel()
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            // Map Background
            WorldMapView()
                .ignoresSafeArea()
            
            // City markers layer
            GeometryReader { geometry in
                ForEach(viewModel.filteredCities) { city in
                    CityMarkerView(city: city, currentTime: viewModel.currentTime)
                        .position(
                            x: city.coordinate.x * geometry.size.width,
                            y: city.coordinate.y * geometry.size.height
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.selectedCity = city
                            }
                        }
                }
            }
            
            // Selected city detail overlay
            if let selected = viewModel.selectedCity {
                VStack {
                    HStack {
                        CityDetailCard(city: selected, currentTime: viewModel.currentTime)
                            .environmentObject(appState)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // Top controls
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    SearchBar(text: $viewModel.searchText)
                        .frame(maxWidth: 280)
                    
                    Spacer()
                    
                    // Current time display
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.currentTimeString)
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .monospacedDigit()
                        
                        Text(viewModel.currentTimeZoneString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                
                Spacer()
            }
        }
        .navigationTitle("World Clock")
    }
}

struct WorldMapView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient - dark blue ocean
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.05, green: 0.08, blue: 0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // World map continents
                WorldMapShape()
                    .fill(Color(red: 0.18, green: 0.35, blue: 0.24))
                    .overlay(
                        WorldMapShape()
                            .stroke(Color(red: 0.25, green: 0.48, blue: 0.35), lineWidth: 0.8)
                    )
                    .frame(width: geometry.size.width * 0.95, height: geometry.size.height * 0.85)
                
                // Day/night overlay
                DayNightTerminator()
                    .opacity(0.25)
                    .blendMode(.multiply)
                
                // Grid lines
                MapGridLines()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        }
    }
}

struct WorldMapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // North America
        path.move(to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.15),
                      control1: CGPoint(x: rect.width * 0.15, y: rect.height * 0.10),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.12))
        path.addCurve(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.42),
                      control1: CGPoint(x: rect.width * 0.30, y: rect.height * 0.25),
                      control2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.35))
        path.addCurve(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.52),
                      control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.48),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.50))
        path.addCurve(to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.38),
                      control1: CGPoint(x: rect.width * 0.12, y: rect.height * 0.48),
                      control2: CGPoint(x: rect.width * 0.06, y: rect.height * 0.45))
        path.closeSubpath()
        
        // South America
        path.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.55))
        path.addCurve(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.55),
                      control1: CGPoint(x: rect.width * 0.26, y: rect.height * 0.52),
                      control2: CGPoint(x: rect.width * 0.30, y: rect.height * 0.52))
        path.addCurve(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.88),
                      control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.70),
                      control2: CGPoint(x: rect.width * 0.36, y: rect.height * 0.82))
        path.addCurve(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.92),
                      control1: CGPoint(x: rect.width * 0.30, y: rect.height * 0.90),
                      control2: CGPoint(x: rect.width * 0.27, y: rect.height * 0.92))
        path.addCurve(to: CGPoint(x: rect.width * 0.20, y: rect.height * 0.65),
                      control1: CGPoint(x: rect.width * 0.20, y: rect.height * 0.85),
                      control2: CGPoint(x: rect.width * 0.18, y: rect.height * 0.75))
        path.closeSubpath()
        
        // Europe
        path.move(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.15),
                      control1: CGPoint(x: rect.width * 0.47, y: rect.height * 0.16),
                      control2: CGPoint(x: rect.width * 0.50, y: rect.height * 0.14))
        path.addCurve(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.32),
                      control1: CGPoint(x: rect.width * 0.55, y: rect.height * 0.22),
                      control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.28))
        path.addCurve(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.38),
                      control1: CGPoint(x: rect.width * 0.54, y: rect.height * 0.36),
                      control2: CGPoint(x: rect.width * 0.51, y: rect.height * 0.38))
        path.addCurve(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.28),
                      control1: CGPoint(x: rect.width * 0.45, y: rect.height * 0.35),
                      control2: CGPoint(x: rect.width * 0.43, y: rect.height * 0.32))
        path.closeSubpath()
        
        // Africa
        path.move(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.40))
        path.addCurve(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.38),
                      control1: CGPoint(x: rect.width * 0.50, y: rect.height * 0.38),
                      control2: CGPoint(x: rect.width * 0.54, y: rect.height * 0.37))
        path.addCurve(to: CGPoint(x: rect.width * 0.54, y: rect.height * 0.78),
                      control1: CGPoint(x: rect.width * 0.60, y: rect.height * 0.55),
                      control2: CGPoint(x: rect.width * 0.58, y: rect.height * 0.70))
        path.addCurve(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.82),
                      control1: CGPoint(x: rect.width * 0.52, y: rect.height * 0.80),
                      control2: CGPoint(x: rect.width * 0.50, y: rect.height * 0.82))
        path.addCurve(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.55),
                      control1: CGPoint(x: rect.width * 0.44, y: rect.height * 0.75),
                      control2: CGPoint(x: rect.width * 0.42, y: rect.height * 0.65))
        path.closeSubpath()
        
        // Asia
        path.move(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.12))
        path.addCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.10),
                      control1: CGPoint(x: rect.width * 0.70, y: rect.height * 0.08),
                      control2: CGPoint(x: rect.width * 0.80, y: rect.height * 0.08))
        path.addCurve(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.48),
                      control1: CGPoint(x: rect.width * 0.95, y: rect.height * 0.28),
                      control2: CGPoint(x: rect.width * 0.96, y: rect.height * 0.40))
        path.addCurve(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.55),
                      control1: CGPoint(x: rect.width * 0.86, y: rect.height * 0.55),
                      control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.58))
        path.addCurve(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.45),
                      control1: CGPoint(x: rect.width * 0.68, y: rect.height * 0.52),
                      control2: CGPoint(x: rect.width * 0.64, y: rect.height * 0.48))
        path.addCurve(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.28),
                      control1: CGPoint(x: rect.width * 0.58, y: rect.height * 0.40),
                      control2: CGPoint(x: rect.width * 0.56, y: rect.height * 0.35))
        path.closeSubpath()
        
        // Australia
        path.move(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.68))
        path.addCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.65),
                      control1: CGPoint(x: rect.width * 0.82, y: rect.height * 0.65),
                      control2: CGPoint(x: rect.width * 0.86, y: rect.height * 0.64))
        path.addCurve(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.85),
                      control1: CGPoint(x: rect.width * 0.90, y: rect.height * 0.75),
                      control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.82))
        path.addCurve(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.85),
                      control1: CGPoint(x: rect.width * 0.84, y: rect.height * 0.86),
                      control2: CGPoint(x: rect.width * 0.80, y: rect.height * 0.86))
        path.closeSubpath()
        
        return path
    }
}

struct DayNightTerminator: View {
    var body: some View {
        GeometryReader { geometry in
            // Calculate day/night based on current time
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let totalMinutes = hour * 60 + minute
            
            // Simplified: sun position moves across the map
            let sunPosition = CGFloat(totalMinutes) / (24 * 60) // 0.0 to 1.0
            let xOffset = geometry.size.width * (sunPosition - 0.5)
            
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.6)
            .offset(x: xOffset)
        }
    }
}

struct MapGridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Horizontal lines
        for i in 1..<5 {
            let y = rect.height * CGFloat(i) / 5
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        // Vertical lines
        for i in 1..<10 {
            let x = rect.width * CGFloat(i) / 10
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        return path
    }
}

struct CityMarkerView: View {
    let city: City
    let currentTime: Date
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                .frame(width: isHovered ? 28 : 20, height: isHovered ? 28 : 20)
                .blur(radius: 2)
            
            // Glow effect
            Circle()
                .fill(Color.cyan.opacity(isHovered ? 0.4 : 0.25))
                .frame(width: isHovered ? 24 : 16, height: isHovered ? 24 : 16)
                .blur(radius: 3)
            
            // Inner glow
            Circle()
                .fill(Color.cyan.opacity(0.6))
                .frame(width: isHovered ? 12 : 8, height: isHovered ? 12 : 8)
                .shadow(color: .cyan.opacity(0.8), radius: isHovered ? 6 : 4)
            
            // Core
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: isHovered ? 6 : 4, height: isHovered ? 6 : 4)
            
            // Time label (shown on hover or for major cities)
            if isHovered || city.isMajor {
                VStack(spacing: 2) {
                    Text(city.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(cityTimeString)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                )
                .offset(y: -40)
                .shadow(color: .black.opacity(0.3), radius: 8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var cityTimeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
}

struct CityDetailCard: View {
    let city: City
    let currentTime: Date
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(city.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(city.country)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Large time display
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 42, weight: .light, design: .monospaced))
                        .monospacedDigit()
                    
                    Text(dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Time zone info
            HStack(spacing: 20) {
                InfoItem(title: "Time Zone", value: city.timeZone.identifier)
                InfoItem(title: "UTC Offset", value: city.utcOffsetString)
                InfoItem(title: "GMT", value: gmtString)
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    appState.currentTimeZone = city.timeZone
                    appState.selectedTab = .calendar
                    dismiss()
                } label: {
                    Label("Set as Default", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    appState.selectedTab = .calendar
                    dismiss()
                } label: {
                    Label("View Calendar", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 20)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: currentTime)
    }
    
    private var gmtString: String {
        let offset = city.timeZone.secondsFromGMT() / 3600
        return "GMT\(offset >= 0 ? "+" : "")\(offset)"
    }
}

struct InfoItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search city...", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

// MARK: - Models

struct City: Identifiable {
    let id = UUID()
    let name: String
    let country: String
    let timeZone: TimeZone
    let coordinate: (x: Double, y: Double) // Normalized 0-1 coordinates
    let isMajor: Bool
    
    var utcOffsetString: String {
        let seconds = timeZone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        if minutes == 0 {
            return "UTC\(hours >= 0 ? "+" : "")\(hours)"
        }
        return "UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes))"
    }
}

// MARK: - ViewModel

class WorldClockViewModel: ObservableObject {
    @Published var currentTime = Date()
    @Published var selectedCity: City?
    @Published var searchText = ""
    
    let cities: [City] = [
        City(name: "Beijing", country: "China", timeZone: TimeZone(identifier: "Asia/Shanghai")!, coordinate: (x: 0.78, y: 0.32), isMajor: true),
        City(name: "Tokyo", country: "Japan", timeZone: TimeZone(identifier: "Asia/Tokyo")!, coordinate: (x: 0.88, y: 0.33), isMajor: true),
        City(name: "London", country: "UK", timeZone: TimeZone(identifier: "Europe/London")!, coordinate: (x: 0.46, y: 0.26), isMajor: true),
        City(name: "New York", country: "USA", timeZone: TimeZone(identifier: "America/New_York")!, coordinate: (x: 0.26, y: 0.30), isMajor: true),
        City(name: "Paris", country: "France", timeZone: TimeZone(identifier: "Europe/Paris")!, coordinate: (x: 0.48, y: 0.28), isMajor: true),
        City(name: "Sydney", country: "Australia", timeZone: TimeZone(identifier: "Australia/Sydney")!, coordinate: (x: 0.90, y: 0.72), isMajor: true),
        City(name: "Dubai", country: "UAE", timeZone: TimeZone(identifier: "Asia/Dubai")!, coordinate: (x: 0.62, y: 0.38), isMajor: true),
        City(name: "Singapore", country: "Singapore", timeZone: TimeZone(identifier: "Asia/Singapore")!, coordinate: (x: 0.76, y: 0.52), isMajor: true),
        City(name: "Los Angeles", country: "USA", timeZone: TimeZone(identifier: "America/Los_Angeles")!, coordinate: (x: 0.15, y: 0.34), isMajor: true),
        City(name: "Moscow", country: "Russia", timeZone: TimeZone(identifier: "Europe/Moscow")!, coordinate: (x: 0.58, y: 0.22), isMajor: false),
        City(name: "Berlin", country: "Germany", timeZone: TimeZone(identifier: "Europe/Berlin")!, coordinate: (x: 0.51, y: 0.26), isMajor: false),
        City(name: "Hong Kong", country: "China", timeZone: TimeZone(identifier: "Asia/Hong_Kong")!, coordinate: (x: 0.79, y: 0.42), isMajor: false),
        City(name: "Seoul", country: "South Korea", timeZone: TimeZone(identifier: "Asia/Seoul")!, coordinate: (x: 0.85, y: 0.32), isMajor: false),
        City(name: "Mumbai", country: "India", timeZone: TimeZone(identifier: "Asia/Kolkata")!, coordinate: (x: 0.68, y: 0.45), isMajor: false),
        City(name: "Cairo", country: "Egypt", timeZone: TimeZone(identifier: "Africa/Cairo")!, coordinate: (x: 0.55, y: 0.38), isMajor: false),
        City(name: "Rio de Janeiro", country: "Brazil", timeZone: TimeZone(identifier: "America/Sao_Paulo")!, coordinate: (x: 0.32, y: 0.70), isMajor: false),
        City(name: "Vancouver", country: "Canada", timeZone: TimeZone(identifier: "America/Vancouver")!, coordinate: (x: 0.12, y: 0.26), isMajor: false),
        City(name: "Auckland", country: "New Zealand", timeZone: TimeZone(identifier: "Pacific/Auckland")!, coordinate: (x: 0.95, y: 0.80), isMajor: false),
    ]
    
    var filteredCities: [City] {
        if searchText.isEmpty {
            return cities
        }
        return cities.filter { city in
            city.name.localizedCaseInsensitiveContains(searchText) ||
            city.country.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
    
    var currentTimeZoneString: String {
        let tz = TimeZone.current
        let offset = tz.secondsFromGMT() / 3600
        return "\(tz.identifier) (GMT\(offset >= 0 ? "+" : "")\(offset))"
    }
    
    private var timer: Timer?
    
    init() {
        // Update time every 100ms for millisecond precision
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = Date()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
