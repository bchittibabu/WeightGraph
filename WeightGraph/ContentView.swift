//
//  ContentView.swift
//  WeightGraph
//
//  Created by Barath Chittibabu on 04/07/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var model = WeightGraphModel(store: WeightStore(provider: WeightHealthKitProvider()))

    var body: some View {
        WeightChart(model: model)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Unit", selection: $model.unit) {
                            ForEach(WeightUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                    } label: {
                        Image(systemName: "scalemass")
                    }
                }
            }
    }
}

#Preview {
    ContentView()
}
