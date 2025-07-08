import Foundation
import HealthKit

/// Facade over `HKStatisticsCollectionQuery` producing `Bin` arrays.
struct WeightHealthKitProvider: WeightStatisticsProviding {
    private let healthStore = HKHealthStore()

    func bins(for span: Span) async throws -> [Bin] {
        // Always return 3 years of daily data for demo purposes, but with some missing days
        let days = 3 * 365
        return (0..<days).compactMap { idx in
            let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-idx) * 86_400))
            
            // Skip some days to create missing data (every 7th and 8th day, and some random gaps)
            if idx % 7 == 0 || idx % 8 == 0 {
                return nil // Missing data
            }
            
            // Create some larger gaps (skip 3-4 consecutive days every month)
            if idx % 30 >= 10 && idx % 30 <= 13 {
                return nil // Missing data gap
            }
            
            return Bin(date: date, value: 70 + Double.random(in: -10...10))
        }.sorted { $0.date < $1.date }
    }
    
    func bmiBins(for span: Span) async throws -> [Bin] {
        // Always return 3 years of daily BMI data for demo purposes, with different missing patterns
        let days = 3 * 365
        return (0..<days).compactMap { idx in
            let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-idx) * 86_400))
            
            // Different missing pattern for BMI (every 6th day and some random gaps)
            if idx % 6 == 0 {
                return nil // Missing BMI data
            }
            
            // Create some larger gaps (skip 2-3 consecutive days every 3 weeks)
            if idx % 21 >= 5 && idx % 21 <= 7 {
                return nil // Missing BMI data gap
            }
            
            // BMI typically ranges from 18-30, with some variation
            return Bin(date: date, value: 22 + Double.random(in: -3...8))
        }.sorted { $0.date < $1.date }
    }
} 