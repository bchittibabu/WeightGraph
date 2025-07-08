import Foundation

public enum WeightUnit: String, CaseIterable, Identifiable {
    case kilogram, pound

    public var id: String { rawValue }

    /// Conversion factor from kilograms to this unit.
    var factor: Double {
        switch self {
        case .kilogram: return 1.0
        case .pound: return 2.20462
        }
    }

    /// Display symbol.
    var symbol: String {
        switch self {
        case .kilogram: return "kg"
        case .pound: return "lb"
        }
    }

    // MARK: - Persistence
    private static let key = "WeightUnitPreference"

    public static var current: WeightUnit {
        get {
            if let raw = UserDefaults.standard.string(forKey: key), let unit = WeightUnit(rawValue: raw) {
                return unit
            }
            return .kilogram
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
} 