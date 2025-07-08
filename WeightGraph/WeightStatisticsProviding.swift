import Foundation

/// Abstraction over HealthKit statistics collection so it can be mocked in tests.
public protocol WeightStatisticsProviding: Sendable {
    /// Returns aggregated bins for the requested span.
    func bins(for span: Span) async throws -> [Bin]
    /// Returns aggregated BMI bins for the requested span.
    func bmiBins(for span: Span) async throws -> [Bin]
} 