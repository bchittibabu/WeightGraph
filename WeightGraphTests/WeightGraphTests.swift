//
//  WeightGraphTests.swift
//  WeightGraphTests
//
//  Created by Barath Chittibabu on 04/07/25.
//

import Testing
import WeightGraph
import Foundation

struct WeightGraphTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func binModelEqualityAndIdentifiable() throws {
        let now = Date()
        let binA = Bin(date: now, value: 70.5)
        let binB = Bin(date: now, value: 70.5)
        try #expect(binA == binB)
        try #expect(binA.id == now)
    }

    @Test func weightStoreReturnsMockCounts() async throws {
        let weekBins = (0..<7).map { Bin(date: Calendar.current.startOfDay(for: Date().addingTimeInterval(Double($0)*86400)), value: Double($0)) }
        let monthBins = (0..<30).map { Bin(date: Calendar.current.startOfDay(for: Date().addingTimeInterval(Double($0)*86400)), value: Double($0)) }
        let provider = MockWeightProvider(store: [ .week: weekBins, .month: monthBins ])
        let store = WeightStore(provider: provider)
        store.refresh()
        // Give the asynchronous task a chance to run; in XCTest we'd await publisher; here simple sleep.
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        try #expect(store.binsBySpan[.week]?.count == 7)
        try #expect(store.binsBySpan[.month]?.count == 30)
    }

    @Test func weightStorePublishesBinsBySpan() async throws {
        let allSpans: [Span] = [.week, .month, .year]
        let data: [Span: [Bin]] = Dictionary(uniqueKeysWithValues: allSpans.map { span in
            let bins = (0..<5).map { idx in
                Bin(date: Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(idx)*86400)), value: Double(idx))
            }
            return (span, bins)
        })

        let provider = MockWeightProvider(store: data)
        let store = WeightStore(provider: provider)

        // Collect first published output after refresh
        let expectation = Expectation(description: "binsBySpan published")

        let task = Task {
            for await value in store.$binsBySpan.values where !value.isEmpty {
                expectation.fulfill()
                break
            }
        }

        store.refresh()
        try await expectation.finish()
        task.cancel()

        try #expect(store.binsBySpan[.year]?.count == 5)
    }

}
