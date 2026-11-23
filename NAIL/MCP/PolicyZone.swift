import Foundation

enum PolicyZone: String, Codable, CaseIterable, Sendable {
    case green
    case yellow
    case red
}

struct PolicyDecision: Equatable, Sendable {
    var allowed: Bool
    var zone: PolicyZone
    var reason: String
}
