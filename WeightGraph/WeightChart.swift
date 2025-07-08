import SwiftUI
import Charts
#if os(iOS)
import UIKit
#endif
import os

private let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "WeightGraph", category: "Scrolling")

struct WeightChart<Model: WeightGraphModeling>: View {
    @ObservedObject var model: Model
    @State private var currentSpan: Span = .week
    @State private var shouldScrollToLatest = false
    @State private var isScrolling = false
    @State private var scrollPosition: Date?
    @State private var visibleDataPoints: [Bin] = []
    @State private var visibleBMIPoints: [Bin] = []

    var body: some View {
        VStack(alignment: .leading) {
            spanPicker
            chartTypeToggle
            chartView
        }
        .onAppear { 
            model.onAppear()
            updateVisibleData()
        }
        .onChange(of: model.bins) { _, _ in
            updateVisibleData()
        }
        .onChange(of: model.bmiBins) { _, _ in
            updateVisibleData()
        }
        .onChange(of: model.span) { _, _ in
            updateVisibleData()
        }
    }

    private var spanPicker: some View {
        Picker("Span", selection: $model.span) {
            ForEach(Span.allCases, id: \.self) { span in
                Text(label(for: span)).tag(span)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var chartTypeToggle: some View {
        HStack {
            Spacer()
            Button(action: {
                model.showBMI.toggle()
            }) {
                HStack {
                    Image(systemName: "person.fill")
                    Text(model.showBMI ? "Hide BMI" : "Show BMI")
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var chartView: some View {
        let weightValues = model.bins.map { $0.value }
        
        // Use only weight values for domain calculation
        let minY = weightValues.min() ?? 0
        let maxY = weightValues.max() ?? 1
        let yPadding = (maxY - minY) * 0.1
        let yDomain = (minY - yPadding)...(maxY + yPadding)
        
        let visibleLength: TimeInterval
        switch model.span {
        case .week:
            visibleLength = 7 * 24 * 60 * 60
        case .month:
            visibleLength = 30 * 24 * 60 * 60
        case .year:
            visibleLength = 365 * 24 * 60 * 60
        }
        
        return VStack(alignment: .leading) {
            buildChart(yDomain: yDomain, visibleLength: visibleLength)
                .id(model.span)
        }
    }
    
    @ViewBuilder
    private func buildChart(yDomain: ClosedRange<Double>, visibleLength: TimeInterval) -> some View {
        Chart {
            weightChartContent
            if model.showBMI {
                bmiChartContent
            }
        }
        .chartForegroundStyleScale([
            "Weight": .blue,
            "BMI": .green
        ])
        .chartScrollableAxes(.horizontal)
        .chartScrollTargetBehavior(.paging)
        .chartXVisibleDomain(length: visibleLength)
        .chartYScale(domain: yDomain)
        .chartScrollPosition(initialX: model.bins.first?.date ?? Date())
        .chartScrollPosition(x: .constant(scrollPosition ?? Date()))
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Weight chart"))
        .onScrollPhaseChange { oldPhase, newPhase in
            handleScrollPhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
    }
    
    @ChartContentBuilder
    private var weightChartContent: some ChartContent {
        let weightSegments = getConnectedSegments(from: visibleDataPoints)
        ForEach(Array(weightSegments.enumerated()), id: \.offset) { segmentIndex, segment in
            ForEach(segment) { bin in
                LineMark(
                    x: .value("Date", bin.date),
                    y: .value("Weight", bin.value),
                    series: .value("Series", "Weight-\(segmentIndex)")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue)

                PointMark(
                    x: .value("Date", bin.date),
                    y: .value("Weight", bin.value)
                )
                .symbolSize(20)
                .foregroundStyle(.blue)
            }
        }
    }
    
    @ChartContentBuilder
    private var bmiChartContent: some ChartContent {
        let bmiSegments = getConnectedSegments(from: visibleBMIPoints)
        ForEach(Array(bmiSegments.enumerated()), id: \.offset) { segmentIndex, segment in
            ForEach(segment) { bin in
                LineMark(
                    x: .value("Date", bin.date),
                    y: .value("BMI", bin.value),
                    series: .value("Series", "BMI-\(segmentIndex)")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.green)

                PointMark(
                    x: .value("Date", bin.date),
                    y: .value("BMI", bin.value)
                )
                .symbolSize(20)
                .foregroundStyle(.green)
            }
        }
    }
    
    // MARK: - Smart Line Connection Logic
    
    private func getConnectedSegments(from dataPoints: [Bin]) -> [[Bin]] {
        guard !dataPoints.isEmpty else { return [] }
        
        var segments: [[Bin]] = []
        var currentSegment: [Bin] = []
        
        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        
        for (_, point) in sortedPoints.enumerated() {
            if currentSegment.isEmpty {
                currentSegment.append(point)
            } else {
                let lastPoint = currentSegment.last!
                let timeDifference = point.date.timeIntervalSince(lastPoint.date)
                
                // Define maximum gap based on span
                let maxGap: TimeInterval
                switch model.span {
                case .week:
                    maxGap = 7 * 24 * 60 * 60 // 3 days
                case .month:
                    maxGap = 30 * 24 * 60 * 60 // 1 week
                case .year:
                    maxGap = 30 * 24 * 60 * 60 // 1 month
                }
                
                if timeDifference <= maxGap {
                    // Continue current segment
                    currentSegment.append(point)
                } else {
                    // Start new segment due to gap
                    if !currentSegment.isEmpty {
                        segments.append(currentSegment)
                    }
                    currentSegment = [point]
                }
            }
        }
        
        // Add the last segment
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }
        
        return segments
    }
    
    // MARK: - Post-Scroll Calculations
    
    private func handleScrollPhaseChange(oldPhase: ScrollPhase, newPhase: ScrollPhase) {
        switch newPhase {
        case .idle:
            // Scrolling stopped - perform calculations
            if isScrolling {
                isScrolling = false
                os_log("Scroll ended - updating visible data", log: perfLog, type: .info)
                updateVisibleDataAfterScroll()
            }
        case .tracking, .interacting:
            // Scrolling started
            if !isScrolling {
                isScrolling = true
                os_log("Scroll started", log: perfLog, type: .info)
            }
        case .decelerating, .animating:
            // Still scrolling but decelerating or animating
            break
        @unknown default:
            break
        }
    }
    
    private func updateVisibleData() {
        // Update visible data points based on current scroll position
        visibleDataPoints = model.bins
        visibleBMIPoints = model.bmiBins.compactMap { bin in
            let bmiValues = model.bmiBins.map { $0.value }
            let weightValues = model.bins.map { $0.value }
            
            let bmiMin: Double = bmiValues.min() ?? 18
            let bmiMax: Double = bmiValues.max() ?? 35
            let weightMin = weightValues.min() ?? 0
            let weightMax = weightValues.max() ?? 1
            
            guard bin.value >= bmiMin && bin.value <= bmiMax else { return nil }
            
            let normalizedValue = weightMin + (bin.value - bmiMin) * (weightMax - weightMin) / (bmiMax - bmiMin)
            guard normalizedValue >= weightMin && normalizedValue <= weightMax else { return nil }
            
            return Bin(date: bin.date, value: normalizedValue)
        }
    }
    
    private func updateVisibleDataAfterScroll() {
        // Perform expensive calculations only after scrolling stops
        DispatchQueue.main.async {
            updateVisibleData()
        }
    }

    private func label(for span: Span) -> String {
        switch span {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    // Simple OLS regression (returns nil if less than 2 points)
    private func regression(for bins: [Bin]) -> (startDate: Date, startValue: Double, endDate: Date, endValue: Double)? {
        guard bins.count >= 2 else { return nil }
        let n = Double(bins.count)
        let dates = bins.map { $0.date.timeIntervalSince1970 }
        let weights = bins.map { $0.value }
        let sumX = dates.reduce(0, +)
        let sumY = weights.reduce(0, +)
        let sumXY = zip(dates, weights).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = dates.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        guard let firstDate = bins.first?.date, let lastDate = bins.last?.date else { return nil }
        let startVal = slope * firstDate.timeIntervalSince1970 + intercept
        let endVal = slope * lastDate.timeIntervalSince1970 + intercept
        return (firstDate, startVal, lastDate, endVal)
    }
}

#Preview {
    struct PreviewProviderStore: WeightStatisticsProviding {
        func bins(for span: Span) async throws -> [Bin] {
            let count: Int = span == .week ? 7 : span == .month ? 30 : 365
            return (0..<count).compactMap { idx in
                // Skip some days to create missing data
                if idx % 5 == 0 || idx % 7 == 0 {
                    return nil // Missing data
                }
                
                return Bin(date: Date().addingTimeInterval(Double(-idx) * 86_400), value: 70 + Double(idx).truncatingRemainder(dividingBy: 5))
            }.sorted { $0.date < $1.date }
        }
        
        func bmiBins(for span: Span) async throws -> [Bin] {
            let count: Int = span == .week ? 7 : span == .month ? 30 : 365
            return (0..<count).compactMap { idx in
                // Different missing pattern for BMI
                if idx % 4 == 0 {
                    return nil // Missing BMI data
                }
                
                return Bin(date: Date().addingTimeInterval(Double(-idx) * 86_400), value: 22 + Double(idx).truncatingRemainder(dividingBy: 3))
            }.sorted { $0.date < $1.date }
        }
    }
    let store = WeightStore(provider: PreviewProviderStore())
    let model = WeightGraphModel(store: store)
    return WeightChart(model: model)
}

// Helper for empty chart content
struct EmptyChartContent: ChartContent {
    init() {}
    var body: Never { fatalError() }
} 
