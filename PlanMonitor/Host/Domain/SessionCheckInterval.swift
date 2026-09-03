//
//  SessionCheckInterval.swift
//  PlanTracker
//

import Foundation

enum SessionCheckInterval: Int, CaseIterable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case thirty = 30

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var displayName: String { String(localized: "\(rawValue) min") }
}
