import SwiftUI

enum SidebarGroup: CaseIterable, Identifiable {
    case none, cleanup, protection, performance, applications, files

    var id: Self { self }

    var title: LocalizedStringKey? {
        switch self {
        case .none: nil
        case .cleanup: "Cleanup"
        case .protection: "Protection"
        case .performance: "Performance"
        case .applications: "Applications"
        case .files: "Files"
        }
    }

    var sections: [SidebarSection] {
        SidebarSection.allCases.filter { $0.group == self }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case smartSweep, systemJunk, protection, optimization, maintenance
    case uninstaller, updater, telescope, largeFiles, duplicates

    var id: String { rawValue }

    var group: SidebarGroup {
        switch self {
        case .smartSweep: .none
        case .systemJunk: .cleanup
        case .protection: .protection
        case .optimization, .maintenance: .performance
        case .uninstaller, .updater: .applications
        case .telescope, .largeFiles, .duplicates: .files
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .smartSweep: "Smart Sweep"
        case .systemJunk: "System Junk"
        case .protection: "Protection"
        case .optimization: "Optimization"
        case .maintenance: "Maintenance"
        case .uninstaller: "Uninstaller"
        case .updater: "Updater"
        case .telescope: "Telescope"
        case .largeFiles: "Large & Old Files"
        case .duplicates: "Duplicates"
        }
    }

    var tint: ModuleTint {
        switch self {
        case .smartSweep: .sweep
        case .systemJunk: .junk
        case .protection: .protection
        case .optimization: .optimization
        case .maintenance: .maintenance
        case .uninstaller: .uninstaller
        case .updater: .updater
        case .telescope: .telescope
        case .largeFiles: .largeFiles
        case .duplicates: .duplicates
        }
    }

    var symbol: String {
        switch self {
        case .smartSweep: "sparkles"
        case .systemJunk: "trash"
        case .protection: "shield.lefthalf.filled"
        case .optimization: "gauge.with.dots.needle.67percent"
        case .maintenance: "wrench.and.screwdriver"
        case .uninstaller: "xmark.app"
        case .updater: "arrow.down.app"
        case .telescope: "scope"
        case .largeFiles: "doc.text.magnifyingglass"
        case .duplicates: "square.on.square"
        }
    }
}
