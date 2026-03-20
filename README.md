# MyTime

A macOS menu bar application for time, calendar, and world clock management.

## Features

### Menu Bar Integration
- Displays current date in `MM月DD日` format in the macOS menu bar
- Tooltip shows full date and lunar calendar information
- Left-click opens the calendar popover
- Right-click shows context menu with quit option

### Calendar View
- **Month View**: Grid display showing all days of the current month
- **Year View**: Overview of all 12 months in a single view
- **Navigation**: Previous/next month buttons and "Today" quick navigation
- **Lunar Calendar**: Displays Chinese lunar date for each day
- **Holiday Indicators**: 
  - Red badge with "休" for legal holidays
  - Gray badge with "班" for weekend makeup workdays
- **Festival Display**: 
  - Red text for lunar and solar festivals
  - Green text for solar terms (节气)
- **Day Selection**: Click to select a date with visual highlighting
- **Today Highlight**: Blue border around current date

### World Clock
- **Interactive Map**: MapKit-based world map with city markers
- **Real-time Updates**: Clock updates every second
- **City Time Display**: Shows time for multiple major cities worldwide
- **Current Location**: Automatically detects and highlights your current timezone
- **Hover/Click Interactions**: View city details on hover or tap
- **Fullscreen Mode**: Toggle fullscreen for an immersive view
- **Timezone Information**: Displays UTC offset and DST status

### Almanac (黄历)
- **Daily Summary**: Shows Yi (宜 - suitable activities) and Ji (忌 - avoid activities)
- **Detailed View**: Comprehensive almanac information including:
  - **Wu Xing** (五行): Five elements
  - **Chong Sha** (冲煞): Clash and harm
  - **Peng Zu** (彭祖): Daily taboo characters
  - **Ji Shen/Xiong Shen** (吉神/凶神): Auspicious/inauspicious deities
  - **Xing Xiu** (星宿): Lunar mansion
- **Shi Chen** (时辰): 12 two-hour periods with lucky/unlucky indicators
- **Yi/Ji Grid**: Visual grid display of suitable and activities

### Internationalization
- Supports multiple languages: English, Chinese (Simplified), Japanese, Korean
- All UI strings are localized

## Technology Stack

- **Framework**: SwiftUI + AppKit (hybrid approach)
- **Language**: Swift 5.9+
- **Minimum macOS**: macOS 14.0+
- **Dependencies**:
  - [SwiftDate](https://github.com/malcommac/SwiftDate): Date/time utilities
  - [lunar-swift](https://github.com/6tail/lunar-swift): Chinese lunar calendar calculations

## Project Structure

```
Sources/MyTime/
├── App/
│   ├── AppDelegate.swift      # Menu bar management
│   └── MyTimeApp.swift         # Main app entry point
├── Core/
│   ├── Models/
│   │   └── WorldCity.swift     # City data model
│   ├── Services/
│   │   ├── CityDataService.swift      # City/timezone management
│   │   ├── HolidayService.swift       # Holiday data (2001-2026)
│   │   └── LunarCalendarService.swift # Lunar calendar calculations
│   └── Utils/
├── Features/
│   ├── Almanac/
│   │   ├── AlmanacDetailPopup.swift   # Popup component
│   │   └── AlmanacDetailView.swift    # Full detail view
│   ├── Calendar/
│   │   ├── CalendarContainerView.swift # Main calendar container
│   │   ├── CalendarGridView.swift     # Calendar grid
│   │   └── CalendarPopoverView.swift  # Popover variant
│   └── WorldClock/
│       ├── WorldClockMapView.swift    # Map component
│       └── WorldClockPopupView.swift  # Popup with controls
└── Resources/
    ├── Cities.json            # World city data
    └── Localizable.xcstrings  # Localized strings
```

## Building

```bash
# Resolve dependencies
swift package resolve

# Build
swift build

# Run
swift run
```

Or open the project in Xcode and build from there.

## Usage

1. **Launch**: The app runs as a menu bar application (no dock icon)
2. **View Calendar**: Click the date in the menu bar
3. **Navigate**: Use arrows to change months, click "Today" to return
4. **View World Clock**: Select "World Clock" from the sidebar
5. **Check Almanac**: Select a date in calendar to see almanac summary
6. **Quit**: Right-click the menu bar icon and select "Quit MyTime"

## License

MIT License
