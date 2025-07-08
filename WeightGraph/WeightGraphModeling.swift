import Foundation
import Combine

/// Abstraction over the view-model so the SwiftUI layer can swap real vs mock.
@MainActor
public protocol WeightGraphModeling: ObservableObject {
    var span: Span { get set }
    var scrollDate: Date { get set }
    var bins: [Bin] { get }
    var bmiBins: [Bin] { get }
    var showBMI: Bool { get set }
    func onAppear()
} 