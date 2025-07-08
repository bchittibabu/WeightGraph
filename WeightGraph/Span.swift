import Foundation

/// A chart time-span.
public enum Span: CaseIterable, Hashable, Sendable {
    case week, month, year

    /// Calendar component width for this span.
    var component: Calendar.Component {
        switch self {
        case .week:  return .weekOfYear
        case .month: return .month
        case .year:  return .year
        }
    }

    /// The time interval (seconds) that fits in one visible chart screen.
    var visibleLength: TimeInterval {
        switch self {
        case .week:
            return 7 * 24 * 60 * 60 // 1 week
        case .month:
            return 30 * 24 * 60 * 60 // Approx 1 month
        case .year:
            return 365 * 24 * 60 * 60 // Approx 1 year
        }
    }

    /// An extended domain interval used while querying/prefetching (±factor of visible length).
    func extendedDomain(around date: Date, factor: Double = 3) -> ClosedRange<Date> {
        let half = visibleLength * factor
        return (date.addingTimeInterval(-half))...(date.addingTimeInterval(half))
    }

    /// DateComponents for valueAligned scroll target behavior.
    var dateComponents: DateComponents {
        switch self {
        case .week:  return DateComponents(weekOfYear: 1)
        case .month: return DateComponents(month: 1)
        case .year:  return DateComponents(year: 1)
        }
    }
} 