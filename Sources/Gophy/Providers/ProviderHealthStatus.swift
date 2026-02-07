import Foundation

public enum ProviderHealthStatus: Sendable {
    case healthy
    case degraded(String)
    case unavailable(String)
}

public protocol HealthCheckable: Sendable {
    func healthCheck() async -> ProviderHealthStatus
}
