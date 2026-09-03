//
//  AppLanguage.swift
//  PlanTracker
//

import Foundation

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: String(localized: "English")
        case .spanish: String(localized: "Spanish")
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        }
    }
}
