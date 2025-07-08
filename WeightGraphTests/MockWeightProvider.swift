import Foundation
@testable import WeightGraph

struct MockWeightProvider: WeightStatisticsProviding {
    private let store: [Span: [Bin]]
    private let bmiStore: [Span: [Bin]]

    init(store: [Span: [Bin]], bmiStore: [Span: [Bin]] = [:]) {
        self.store = store
        self.bmiStore = bmiStore
    }

    func bins(for span: Span) async throws -> [Bin] {
        let count: Int = span == .week ? 7 : span == .month ? 30 : 365
        return (0..<count).compactMap { idx in
            // Skip some days to create missing data
            if idx % 6 == 0 || idx % 9 == 0 {
                return nil // Missing data
            }
            
            // Create some larger gaps every 2 weeks
            if idx % 14 >= 3 && idx % 14 <= 5 {
                return nil // Missing data gap
            }
            
            return Bin(date: Date().addingTimeInterval(Double(-idx) * 86_400), value: 70 + Double(idx).truncatingRemainder(dividingBy: 10))
        }.sorted { $0.date < $1.date }
    }
    
    func bmiBins(for span: Span) async throws -> [Bin] {
        let count: Int = span == .week ? 7 : span == .month ? 30 : 365
        return (0..<count).compactMap { idx in
            // Different missing pattern for BMI
            if idx % 5 == 0 {
                return nil // Missing BMI data
            }
            
            // Create some larger gaps every 3 weeks
            if idx % 21 >= 2 && idx % 21 <= 4 {
                return nil // Missing BMI data gap
            }
            
            return Bin(date: Date().addingTimeInterval(Double(-idx) * 86_400), value: 22 + Double(idx).truncatingRemainder(dividingBy: 5))
        }.sorted { $0.date < $1.date }
    }
} 