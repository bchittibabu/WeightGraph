import Foundation
import Combine
import os

@MainActor
public final class WeightGraphModel: ObservableObject, WeightGraphModeling {
    // MARK: - Published API
    @Published public var span: Span = .week {
        didSet { updateBins() }
    }

    @Published public var scrollDate: Date = Date() {
        didSet { updateWindow() }
    }

    @Published public private(set) var bins: [Bin] = []
    
    @Published public private(set) var bmiBins: [Bin] = []
    
    @Published public var showBMI: Bool = false

    @Published public var unit: WeightUnit = WeightUnit.current {
        didSet {
            WeightUnit.current = unit
            updateWindow()
        }
    }

    // Target weight goal (in current unit)
    @Published public var targetRange: ClosedRange<Double> = 68...72

    // MARK: - Private
    private let store: WeightStore
    private var cancellables = Set<AnyCancellable>()

    // Windowed subset for performance
    private var allWeightBins: [Bin] = [] {
        didSet { updateWindow() }
    }
    
    private var allBMIBins: [Bin] = [] {
        didSet { updateWindow() }
    }

    private let modelLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "WeightGraph", category: "Model")

    public init(store: WeightStore) {
        self.store = store
        bindStore()
        store.refresh()
    }

    public func onAppear() {
        // kickoff refresh each time view appears
        store.refresh()
    }

    private func bindStore() {
        store.$binsBySpan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] map in
                guard let self else { return }
                self.allWeightBins = map[self.span] ?? []
            }
            .store(in: &cancellables)
            
        store.$bmiBinsBySpan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] map in
                guard let self else { return }
                self.allBMIBins = map[self.span] ?? []
            }
            .store(in: &cancellables)
    }

    private func updateBins() {
        // update bins for new span
        allWeightBins = store.binsBySpan[span] ?? []
        allBMIBins = store.bmiBinsBySpan[span] ?? []
        // ensure scrollDate remains clamped within data
        let currentBins = allWeightBins.isEmpty ? allBMIBins : allWeightBins
        if let first = currentBins.first?.date, let last = currentBins.last?.date {
            scrollDate = min(max(scrollDate, first), last)
        }
    }

    private func updateWindow() {
        let signpostID = OSSignpostID(log: modelLog)
        os_signpost(.begin, log: modelLog, name: "updateWindow", signpostID: signpostID)
        
        // Always provide full dataset - remove aggressive windowing that limits scrolling
        // The SwiftUI Charts framework handles performance optimization internally
        if !allWeightBins.isEmpty {
            if unit == .kilogram {
                bins = allWeightBins
            } else {
                bins = allWeightBins.map { Bin(date: $0.date, value: $0.value * unit.factor) }
            }
        } else {
            bins = []
        }
        
        if !allBMIBins.isEmpty {
            bmiBins = allBMIBins
        } else {
            bmiBins = []
        }
        
        os_signpost(.end, log: modelLog, name: "updateWindow", signpostID: signpostID)
    }
} 