//
//  CodexPlanTier.swift
//  PlanTracker
//

import Foundation

enum CodexPlanTier: String, Codable, Sendable {
    case free = "free"
    case pro = "pro"
    case max = "max"
    case team = "team"
    case enterprise = "enterprise"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        case .max: "Max"
        case .team: "Team"
        case .enterprise: "Enterprise"
        case .unknown: "Unknown"
        }
    }
}
