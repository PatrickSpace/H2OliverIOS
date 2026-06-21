//
//  AppAppearance.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "Sistema"
        case .light:
            "Claro"
        case .dark:
            "Oscuro"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            "iphone"
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
