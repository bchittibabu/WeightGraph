import Foundation
import Combine

/// Repository responsible for retrieving and caching weight data from HealthKit (or another provider).
@MainActor
public final class WeightStore: ObservableObject {
    @Published public private(set) var binsBySpan: [Span: [Bin]] = [:]
    @Published public private(set) var bmiBinsBySpan: [Span: [Bin]] = [:]

    private let provider: WeightStatisticsProviding
    private var refreshTask: Task<Void, Never>?

    public init(provider: WeightStatisticsProviding) {
        self.provider = provider
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Refresh the cache for all spans. Existing values remain until new data arrives.
    public func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            // Run all span requests concurrently.
            async let week = provider.bins(for: .week)
            async let month = provider.bins(for: .month)
            async let year = provider.bins(for: .year)
            
            async let weekBMI = provider.bmiBins(for: .week)
            async let monthBMI = provider.bmiBins(for: .month)
            async let yearBMI = provider.bmiBins(for: .year)

            do {
                let (weekBins, monthBins, yearBins) = try await (week, month, year)
                let (weekBMIBins, monthBMIBins, yearBMIBins) = try await (weekBMI, monthBMI, yearBMI)
                
                self.binsBySpan[.week] = weekBins
                self.binsBySpan[.month] = monthBins
                self.binsBySpan[.year] = yearBins
                
                self.bmiBinsBySpan[.week] = weekBMIBins
                self.bmiBinsBySpan[.month] = monthBMIBins
                self.bmiBinsBySpan[.year] = yearBMIBins
            } catch {
                debugPrint("WeightStore refresh error:", error)
            }
        }
    }
} 