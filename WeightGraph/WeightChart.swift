import SwiftUI
import Charts
#if os(iOS)
import UIKit
#endif
import os

private let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "WeightGraph", category: "Scrolling")

/// High-Performance WeightChart for Large Datasets (10+ years)
/// 
/// Performance Optimizations:
/// 1. **Progressive Data Loading**: Adaptive windowing with overlapping buffers for continuous scrolling
/// 2. **Intelligent Caching**: Caches Y-domain and BMI normalization calculations
/// 3. **Debounced Updates**: Prevents excessive recalculations during rapid changes
/// 4. **Data Density Adaptation**: Adjusts window size based on local data density
/// 5. **Smooth Scrolling**: 4x buffer multiplier eliminates stuttering at window boundaries
/// 6. **Real-time Updates**: Progressive loading triggered by scroll position changes
/// 
/// Smooth Scrolling Features:
/// - **Overlapping Windows**: Prevents data gaps during scroll transitions
/// - **Adaptive Point Count**: 500-2000 points based on data density and span
/// - **Responsive Updates**: 20ms debounce for scroll position changes
/// - **Gesture Sensitivity**: Lower thresholds for better scroll detection
/// 
/// Key Changes from Original:
/// - `model.bins` → `getProgressiveWindowData()` with density-based adaptation
/// - Real-time scroll position tracking with `updateVisibleDataProgressively()`
/// - Overlapping 4x buffers instead of discrete 2x windows
/// - OSSignpost logging for performance monitoring
public struct WeightChart<Model: WeightGraphModeling>: View {
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
    
    // Performance optimization: Cache calculated values
    @State private var cachedWeightDomain: ClosedRange<Double>?
    @State private var cachedBMINormalization: (min: Double, max: Double, weightMin: Double, weightMax: Double)?
    @State private var lastUpdateTimestamp: Date = Date()
    
    // Window size for visible data (performance optimization)
    private var windowMultiplier: Double = 4.0 // Show 4x the visible span for smoother scrolling
    
    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading) {
            spanPicker
            chartTypeToggle
            chartView
        }
        .onAppear { 
            model.onAppear()
            updateVisibleDataOptimized()
            // Initialize scroll position to latest data
            currentScrollPosition = model.bins.last?.date ?? Date()
        }
        .onChange(of: model.bins) { _, _ in
            // Debounce updates to avoid excessive recalculations
            lastUpdateTimestamp = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if Date().timeIntervalSince(self.lastUpdateTimestamp) >= 0.04 {
                    self.updateVisibleDataOptimized()
                    // Update scroll position if it's not set or if new data is available
                    if self.currentScrollPosition == nil || (self.model.bins.last?.date ?? Date()) > (self.currentScrollPosition ?? Date()) {
                        self.currentScrollPosition = self.model.bins.last?.date ?? Date()
                    }
                }
            }
        }
        .onChange(of: model.bmiBins) { _, _ in
            // Debounce updates to avoid excessive recalculations
            lastUpdateTimestamp = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if Date().timeIntervalSince(self.lastUpdateTimestamp) >= 0.04 {
                    self.updateVisibleDataOptimized()
                }
            }
        }
        .onChange(of: model.span) { _, newSpan in
            os_log("Span changed to %@ - updating visible data", log: perfLog, type: .info, String(describing: newSpan))
            
            // Clear cache when span changes
            cachedWeightDomain = nil
            cachedBMINormalization = nil
            
            // Debounce rapid span changes to improve performance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateVisibleDataOptimized()
            }
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
        // Use cached domain calculation for performance
        let yDomain = getOptimizedYDomain()
        
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
                
                // Trigger progressive data loading on scroll position change
                updateVisibleDataProgressively()
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
            DragGesture(minimumDistance: 2) // More sensitive detection
                .onChanged { value in
                    // Only detect horizontal scrolling gestures
                    let isHorizontalScroll = abs(value.translation.width) > abs(value.translation.height) * 1.2
                    let isSignificantMovement = abs(value.translation.width) > 5 // Lower threshold
                    
                    if isHorizontalScroll && isSignificantMovement && !hasDetectedScrollInCurrentGesture {
                        hasDetectedScrollInCurrentGesture = true
                        handleScrollStart()
                    }
                }
                .onEnded { value in
                    // Reset for next gesture
                    hasDetectedScrollInCurrentGesture = false
                    
                    // Only handle if it was a horizontal scroll
                    let isHorizontalScroll = abs(value.translation.width) > abs(value.translation.height) * 1.2
                    let isSignificantMovement = abs(value.translation.width) > 5
                    
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
        
        // Use all data points for full scrollable experience
        let points = dataPoints
        
        var segments: [[Bin]] = []
        var currentSegment: [Bin] = []
        
        // Data should already be sorted from the model, but ensure it
        let sortedPoints = points.sorted { $0.date < $1.date }
        
        // Define maximum gap based on span (optimized)
        let maxGap: TimeInterval
        switch model.span {
        case .week:
            maxGap = 3 * 24 * 60 * 60 // 3 days
        case .month:
            maxGap = 7 * 24 * 60 * 60 // 1 week
        case .year:
            maxGap = 30 * 24 * 60 * 60 // 1 month
        }
        
        for point in sortedPoints {
            if currentSegment.isEmpty {
                currentSegment.append(point)
            } else {
                let lastPoint = currentSegment.last!
                let timeDifference = point.date.timeIntervalSince(lastPoint.date)
                
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
        updateVisibleDataOptimized()
    }
    
    private func updateVisibleDataOptimized() {
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "updateVisibleData", signpostID: signpostID)
        
        // Performance optimization: Only process windowed data for chart rendering
        visibleDataPoints = getWindowedData(from: model.bins)
        
        // Cache BMI normalization values to avoid recalculating on every update
        guard !model.bmiBins.isEmpty && !model.bins.isEmpty else {
            visibleBMIPoints = []
            cachedBMINormalization = nil
            os_signpost(.end, log: perfLog, name: "updateVisibleData", signpostID: signpostID)
            return
        }
        
        // Use cached normalization if available
        let normalization: (min: Double, max: Double, weightMin: Double, weightMax: Double)
        if let cached = cachedBMINormalization {
            normalization = cached
        } else {
            // Only calculate on visible BMI data for performance
            let visibleBMIData = getWindowedData(from: model.bmiBins)
            let visibleWeightData = getWindowedData(from: model.bins)
            
            let bmiValues = visibleBMIData.map { $0.value }
            let weightValues = visibleWeightData.map { $0.value }
            
            let bmiMin: Double = bmiValues.min() ?? 18
            let bmiMax: Double = bmiValues.max() ?? 35
            let weightMin = weightValues.min() ?? 0
            let weightMax = weightValues.max() ?? 1
            
            normalization = (min: bmiMin, max: bmiMax, weightMin: weightMin, weightMax: weightMax)
            cachedBMINormalization = normalization
        }
        
        // Avoid division by zero
        guard normalization.max > normalization.min, normalization.weightMax > normalization.weightMin else {
            visibleBMIPoints = []
            os_signpost(.end, log: perfLog, name: "updateVisibleData", signpostID: signpostID)
            return
        }
        
        let bmiRange = normalization.max - normalization.min
        let weightRange = normalization.weightMax - normalization.weightMin
        
        // Only process windowed BMI data
        let windowedBMIData = getWindowedData(from: model.bmiBins)
        visibleBMIPoints = windowedBMIData.compactMap { bin in
            guard bin.value >= normalization.min && bin.value <= normalization.max else { return nil }
            
            let normalizedValue = normalization.weightMin + (bin.value - normalization.min) * weightRange / bmiRange
            guard normalizedValue >= normalization.weightMin && normalizedValue <= normalization.weightMax else { return nil }
            
            return Bin(date: bin.date, value: normalizedValue)
        }
        
        os_signpost(.end, log: perfLog, name: "updateVisibleData", signpostID: signpostID)
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
        // Clear cache to force recalculation with new scroll position
        cachedWeightDomain = nil
        cachedBMINormalization = nil
        
        // Post-scroll Y-domain and BMI normalization updates
        DispatchQueue.main.async {
            self.updateVisibleDataOptimized()
        }
    }
    
    /// Progressive data loading for real-time scroll updates
    private func updateVisibleDataProgressively() {
        // Only update if we're not in a rapid scroll gesture
        guard !isScrolling else { return }
        
        // Debounce rapid scroll position changes
        lastUpdateTimestamp = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // Very short debounce for responsiveness
            if Date().timeIntervalSince(self.lastUpdateTimestamp) >= 0.015 {
                // Only clear domain cache, keep BMI normalization cache for speed
                self.cachedWeightDomain = nil
                self.updateVisibleDataOptimized()
            }
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
    
    // MARK: - Performance Optimization Methods
    
    /// Returns windowed data with progressive loading for smooth scrolling
    private func getWindowedData(from allBins: [Bin]) -> [Bin] {
        guard !allBins.isEmpty else { return [] }
        
        // For smaller datasets, use all data for best experience
        let totalPoints = allBins.count
        guard totalPoints > 1000 else { return allBins }
        
        guard let scrollPosition = currentScrollPosition else { 
            // If no scroll position, return a reasonable amount from the end
            let sortedBins = allBins.sorted { $0.date < $1.date }
            let endIndex = sortedBins.count
            let startIndex = max(0, endIndex - 1500) // Show last 1500 points
            return Array(sortedBins[startIndex..<endIndex])
        }
        
        // Use progressive loading strategy for smooth scrolling
        return getProgressiveWindowData(from: allBins, around: scrollPosition)
    }
    
    /// Progressive data loading strategy for smooth continuous scrolling
    private func getProgressiveWindowData(from allBins: [Bin], around scrollPosition: Date) -> [Bin] {
        let sortedBins = allBins.sorted { $0.date < $1.date }
        
        // Calculate adaptive window size based on span and total data
        let baseWindowSize: TimeInterval
        let bufferMultiplier: Double = 4.0 // Larger buffer for smooth scrolling
        
        switch model.span {
        case .week:
            baseWindowSize = 7 * 24 * 60 * 60 * bufferMultiplier // 4 weeks total
        case .month:
            baseWindowSize = 30 * 24 * 60 * 60 * bufferMultiplier // 4 months total  
        case .year:
            baseWindowSize = 365 * 24 * 60 * 60 * bufferMultiplier // 4 years total
        }
        
        // Find center point in the data
        let centerIndex = sortedBins.firstIndex { $0.date >= scrollPosition } ?? sortedBins.count / 2
        
        // Calculate dynamic range based on data density
        let averageDataDensity = calculateDataDensity(sortedBins, around: centerIndex)
        let adaptivePointCount = min(2000, max(500, Int(baseWindowSize / averageDataDensity)))
        
        // Create overlapping windows for smooth transitions
        let halfRange = adaptivePointCount / 2
        let startIndex = max(0, centerIndex - halfRange)
        let endIndex = min(sortedBins.count, centerIndex + halfRange)
        
        let windowedData = Array(sortedBins[startIndex..<endIndex])
        
        os_log("Progressive window: center=%d, range=%d-%d, points=%d, density=%.2f", 
               log: perfLog, type: .debug, centerIndex, startIndex, endIndex, windowedData.count, averageDataDensity)
        
        return windowedData
    }
    
    /// Calculate average time interval between data points for adaptive windowing
    private func calculateDataDensity(_ sortedBins: [Bin], around centerIndex: Int) -> TimeInterval {
        guard sortedBins.count > 1 else { return 86400 } // Default to 1 day
        
        // Sample a small range around the center to calculate density
        let sampleStart = max(0, centerIndex - 50)
        let sampleEnd = min(sortedBins.count - 1, centerIndex + 50)
        
        guard sampleEnd > sampleStart else { return 86400 }
        
        let timeSpan = sortedBins[sampleEnd].date.timeIntervalSince(sortedBins[sampleStart].date)
        let pointCount = Double(sampleEnd - sampleStart)
        
        return timeSpan / pointCount
    }
    
    /// Cached Y domain calculation for better performance
    private func getOptimizedYDomain() -> ClosedRange<Double> {
        if let cached = cachedWeightDomain {
            return cached
        }
        
        // Use windowed data for domain calculation
        let windowedData = getWindowedData(from: model.bins)
        let weightValues = windowedData.map { $0.value }
        
        guard !weightValues.isEmpty else {
            let defaultDomain = 0.0...1.0
            cachedWeightDomain = defaultDomain
            return defaultDomain
        }
        
        let minY = weightValues.min() ?? 0
        let maxY = weightValues.max() ?? 1
        let yPadding = (maxY - minY) * 0.1
        let yDomain = (minY - yPadding)...(maxY + yPadding)
        
        // Cache the result
        cachedWeightDomain = yDomain
        return yDomain
    }
}

#Preview {
    struct PreviewProviderStore: WeightStatisticsProviding {
        func bins(for span: Span) async throws -> [Bin] {
            // Generate more extensive data for preview - up to 10 years
            let count: Int = span == .week ? 7 : span == .month ? 30 : 3650 // 10 years for year view
            let startWeight = 75.0
            
            return (0..<count).compactMap { idx in
                let date = Date().addingTimeInterval(Double(-idx) * 86_400)
                
                // Skip some days to create realistic missing data
                if idx % 7 == 0 || (idx % 5 == 0 && idx % 10 != 0) {
                    return nil // Missing data pattern
                }
                
                // Create realistic weight trends for preview
                let yearsFromStart = Double(idx) / 365.0
                let agingTrend = yearsFromStart * 0.3 // Slower trend for preview
                let seasonalVariation = sin((Double(idx % 365) / 365.0) * 2.0 * .pi) * 2.0
                let dailyVariation = Double.random(in: -1.0...1.0)
                
                let weight = startWeight + agingTrend + seasonalVariation + dailyVariation
                let clampedWeight = max(60.0, min(90.0, weight))
                
                return Bin(date: date, value: clampedWeight)
            }.sorted { $0.date < $1.date }
        }
        
        func bmiBins(for span: Span) async throws -> [Bin] {
            // Generate correlated BMI data for preview
            let count: Int = span == .week ? 7 : span == .month ? 30 : 3650 // 10 years for year view
            let baseHeight = 1.75
            let startWeight = 75.0
            
            return (0..<count).compactMap { idx in
                let date = Date().addingTimeInterval(Double(-idx) * 86_400)
                
                // BMI measured less frequently
                if idx % 3 == 0 || idx % 8 == 0 {
                    return nil // Missing BMI data
                }
                
                // Calculate BMI based on weight trends
                let yearsFromStart = Double(idx) / 365.0
                let agingTrend = yearsFromStart * 0.3
                let seasonalVariation = sin((Double(idx % 365) / 365.0) * 2.0 * .pi) * 2.0
                let dailyVariation = Double.random(in: -0.5...0.5)
                
                let weight = startWeight + agingTrend + seasonalVariation + dailyVariation
                let clampedWeight = max(60.0, min(90.0, weight))
                let bmi = clampedWeight / (baseHeight * baseHeight)
                
                return Bin(date: date, value: bmi)
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
