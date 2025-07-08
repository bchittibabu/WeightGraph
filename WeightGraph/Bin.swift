import Foundation

/// A discrete weight sample aggregated into a time bucket.
/// `id` is identical to `date`, enabling SwiftUI diffing by bucket start.
public struct Bin: Identifiable, Equatable {
    /// Unique identifier that corresponds to the start date of the bucket.
    public let id: Date
    /// The start date of the bucket interval.
    public let date: Date
    /// Average mass value recorded for the bucket (in kilograms).
    public let value: Double

    public init(date: Date, value: Double) {
        self.id = date
        self.date = date
        self.value = value
    }
} 
