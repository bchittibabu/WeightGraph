import Foundation
import HealthKit

// Extension for chunking arrays
extension Range where Bound == Int {
    func chunked(into size: Int) -> [Range<Int>] {
        var chunks: [Range<Int>] = []
        var start = lowerBound
        while start < upperBound {
            let end = Swift.min(start + size, upperBound)
            chunks.append(start..<end)
            start = end
        }
        return chunks
    }
}

/// Facade over `HKStatisticsCollectionQuery` producing `Bin` arrays.
struct WeightHealthKitProvider: WeightStatisticsProviding {
    private let healthStore = HKHealthStore()

    func bins(for span: Span) async throws -> [Bin] {
        // Generate 10 years of optimized data with reduced computational complexity
        let days = 365 * 10
        let startWeight = 75.0
        
        // Pre-calculate constants to avoid repeated calculations
        let twoPi = 2.0 * Double.pi
        let seasonalMultiplier = 1.5
        let dietCycleMultiplier = 3.0
        let agingRate = 0.5
        
        return await withTaskGroup(of: [Bin].self) { group in
            // Process data in chunks for better performance
            let chunkSize = 365 // Process one year at a time
            let chunks = (0..<days).chunked(into: chunkSize)
            
            for chunk in chunks {
                group.addTask {
                    return chunk.compactMap { idx in
                        // Simplified missing data pattern
                        if idx % 7 == 0 || idx % 11 == 0 { return nil }
                        if idx % 180 < 14 { return nil } // Vacation gaps
                        
                        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-idx) * 86_400))
                        
                        // Optimized trend calculations
                        let yearsFromStart = Double(idx) / 365.0
                        let dayOfYear = Double(idx % 365)
                        
                        let agingTrend = yearsFromStart * agingRate
                        let seasonalVariation = sin((dayOfYear / 365.0) * twoPi - .pi/2) * seasonalMultiplier
                        let dietCycleVariation = sin((yearsFromStart / 1.5) * twoPi) * dietCycleMultiplier
                        let dailyVariation = Double.random(in: -1.5...1.5)
                        
                        let weight = startWeight + agingTrend + seasonalVariation + dietCycleVariation + dailyVariation
                        let clampedWeight = max(50.0, min(120.0, weight))
                        
                        return Bin(date: date, value: clampedWeight)
                    }
                }
            }
            
            // Collect and sort results
            var allBins: [Bin] = []
            for await chunk in group {
                allBins.append(contentsOf: chunk)
            }
            return allBins.sorted { $0.date < $1.date }
        }
    }
    
    func bmiBins(for span: Span) async throws -> [Bin] {
        // Generate 10 years of optimized BMI data
        let days = 365 * 10
        let baseHeight = 1.75
        let startWeight = 75.0
        let heightSquared = baseHeight * baseHeight
        
        // Pre-calculate constants
        let twoPi = 2.0 * Double.pi
        let seasonalMultiplier = 1.5
        let dietCycleMultiplier = 3.0
        let agingRate = 0.5
        
        return await withTaskGroup(of: [Bin].self) { group in
            let chunkSize = 365
            let chunks = (0..<days).chunked(into: chunkSize)
            
            for chunk in chunks {
                group.addTask {
                    return chunk.compactMap { idx in
                        // BMI measurements are less frequent
                        if idx % 3 == 0 || idx % 13 == 0 { return nil }
                        if idx % 180 < 14 { return nil } // Vacation gaps
                        
                        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-idx) * 86_400))
                        
                        // Optimized BMI calculations
                        let yearsFromStart = Double(idx) / 365.0
                        let dayOfYear = Double(idx % 365)
                        
                        let agingTrend = yearsFromStart * agingRate
                        let seasonalVariation = sin((dayOfYear / 365.0) * twoPi - .pi/2) * seasonalMultiplier
                        let dietCycleVariation = sin((yearsFromStart / 1.5) * twoPi) * dietCycleMultiplier
                        let dailyVariation = Double.random(in: -1.0...1.0)
                        
                        let weight = startWeight + agingTrend + seasonalVariation + dietCycleVariation + dailyVariation
                        let clampedWeight = max(50.0, min(120.0, weight))
                        
                        let bmi = clampedWeight / heightSquared
                        let clampedBMI = max(15.0, min(40.0, bmi))
                        
                        return Bin(date: date, value: clampedBMI)
                    }
                }
            }
            
            var allBins: [Bin] = []
            for await chunk in group {
                allBins.append(contentsOf: chunk)
            }
            return allBins.sorted { $0.date < $1.date }
        }
    }
} 