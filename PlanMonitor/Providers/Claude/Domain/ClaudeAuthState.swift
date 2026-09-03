//
//  ClaudeAuthState.swift
//  PlanTracker
//

import Foundation

enum ClaudeAuthState: Sendable, Equatable {
    case unknown
    case unauthenticated
    case authenticating
    case restoring(email: String?)
    case authenticated(email: String)

    var isAuthenticated: Bool {
        switch self {
        case .restoring, .authenticated:
            return true
        default:
            return false
        }
    }

    var email: String? {
        switch self {
        case .restoring(let email):
            return email
        case .authenticated(let email):
            return email
        default:
            return nil
        }
    }
}
