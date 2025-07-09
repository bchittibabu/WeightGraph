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
    @State private var visibleDataPoints: [Bin] = []
    @State private var visibleBMIPoints: [Bin] = []
    @State private var isScrolling = false
    @State private var scrollEndTimer: Timer?
    @State private var hasDetectedScrollInCurrentGesture = false
    @State private var selectedPoint: Bin?
    @State private var showCrosshair = false
    @State private var currentScrollPosition: Date?
    @State private var selectedXValue: Date?

    var body: some View {
        VStack(alignment: .leading) {
            spanPicker
            chartTypeToggle
            chartView
        }
        .onAppear { 
            model.onAppear()
            updateVisibleData()
            // Initialize scroll position to latest data
            currentScrollPosition = model.bins.last?.date ?? Date()
        }
        .onChange(of: model.bins) { _, _ in
            updateVisibleData()
            // Update scroll position if it's not set or if new data is available
            if currentScrollPosition == nil || (model.bins.last?.date ?? Date()) > (currentScrollPosition ?? Date()) {
                currentScrollPosition = model.bins.last?.date ?? Date()
            }
        }
        .onChange(of: model.bmiBins) { _, _ in
            updateVisibleData()
        }
        .onChange(of: model.span) { _, _ in
            os_log("Span changed - updating visible data", log: perfLog, type: .info)
            updateVisibleDataAfterScroll()
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
            
            // Add crosshair elements directly here
            if let selectedPoint = selectedPoint, showCrosshair {
                // Highlighted point
                PointMark(
                    x: .value("Date", selectedPoint.date),
                    y: .value("Weight", selectedPoint.value)
                )
                .foregroundStyle(.primary)
                .symbolSize(80)
                
                // Dotted vertical line
                RuleMark(
                    x: .value("Date", selectedPoint.date)
                )
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .annotation(position: .top, alignment: .center) {
                    crosshairAnnotation(for: selectedPoint)
                }
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
        .chartScrollPosition(x: Binding(
            get: { currentScrollPosition ?? model.bins.last?.date ?? Date() },
            set: { newValue in
                currentScrollPosition = newValue
                os_log("Scroll position updated to: %@", log: perfLog, type: .info, newValue.description)
            }
        ))
        .chartXSelection(value: Binding(
            get: { selectedXValue },
            set: { newValue in
                selectedXValue = newValue
                if let selectedDate = newValue {
                    handleChartSelection(at: selectedDate)
                }
            }
        ))
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Weight chart"))
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    // Only detect horizontal scrolling gestures
                    let isHorizontalScroll = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    let isSignificantMovement = abs(value.translation.width) > 8
                    
                    if isHorizontalScroll && isSignificantMovement && !hasDetectedScrollInCurrentGesture {
                        hasDetectedScrollInCurrentGesture = true
                        handleScrollStart()
                    }
                }
                .onEnded { value in
                    // Reset for next gesture
                    hasDetectedScrollInCurrentGesture = false
                    
                    // Only handle if it was a horizontal scroll
                    let isHorizontalScroll = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    let isSignificantMovement = abs(value.translation.width) > 8
                    
                    if isHorizontalScroll && isSignificantMovement {
                        handleScrollEnd()
                    }
                }
        )

    }
    
    @ChartContentBuilder
    private var weightChartContent: some ChartContent {
        let weightSegments = getConnectedSegments(from: visibleDataPoints)
        ForEach(Array(weightSegments.enumerated()), id: \.offset) { segmentIndex, segment in
            ForEach(segment) { bin in
                // Invisible larger tap target
                PointMark(
                    x: .value("Date", bin.date),
                    y: .value("Weight", bin.value)
                )
                .symbolSize(200)
                .foregroundStyle(.clear)
                
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
                // Invisible larger tap target
                PointMark(
                    x: .value("Date", bin.date),
                    y: .value("BMI", bin.value)
                )
                .symbolSize(200)
                .foregroundStyle(.clear)
                
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
    
    @ViewBuilder
    private func crosshairAnnotation(for point: Bin) -> some View {
        VStack(spacing: 2) {
            Text(formatDate(point.date))
                .font(.caption2)
                .foregroundColor(.blue)
            Text("\(point.value, specifier: "%.1f") \(model.unit.symbol)")
                .font(.caption.bold())
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
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
    
    private func updateVisibleData() {
        // Update visible data points based on current data
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

    private func handleScrollStart() {
        // Cancel any existing timer
        scrollEndTimer?.invalidate()
        
        if !isScrolling {
            isScrolling = true
            os_log("Scroll started", log: perfLog, type: .info)
        }
    }
    
    private func handleScrollEnd() {
        // Cancel any existing timer
        scrollEndTimer?.invalidate()
        
        // Set a timer to detect when scrolling has truly ended
        scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            self.isScrolling = false
            self.showCrosshair = false
            self.selectedXValue = nil  // Clear selection state
            os_log("Scroll ended", log: perfLog, type: .info)
            self.updateVisibleDataAfterScroll()
        }
    }
    
    private func updateVisibleDataAfterScroll() {
        // Post-scroll Y-domain and BMI normalization updates
        DispatchQueue.main.async {
            self.updateVisibleData()
        }
    }

    private func handleChartSelection(at selectedDate: Date) {
        // Only handle selection if not currently scrolling
        guard !isScrolling else { return }
        
        // Hide any existing crosshair first
        showCrosshair = false
        
        guard !model.bins.isEmpty else { return }
        
        // Find the closest data point to the selected date
        let selectedBin = model.bins.min { bin1, bin2 in
            abs(bin1.date.timeIntervalSince(selectedDate)) < abs(bin2.date.timeIntervalSince(selectedDate))
        }
        
        guard let selectedBin = selectedBin else { return }
        
        // Set the selected point and show crosshair
        selectedPoint = selectedBin
        
        // Force UI update
        DispatchQueue.main.async {
            self.showCrosshair = true
            os_log("Crosshair should be visible: %@ = %.1f %@, showCrosshair: %@", log: perfLog, type: .info, 
                   self.formatDate(selectedBin.date), selectedBin.value, self.model.unit.symbol, String(self.showCrosshair))
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch model.span {
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM d"
        case .year:
            formatter.dateFormat = "MMM yyyy"
        }
        return formatter.string(from: date)
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
