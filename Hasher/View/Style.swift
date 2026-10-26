//
//  Style.swift
//  Hasher
//

import SwiftUI

extension Color {
    static let appBackground = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let hairline = Color(red: 0.137, green: 0.137, blue: 0.149)
}

/// The one filled button per screen: Start, Done, New search.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.appBackground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 0.95))
            .cornerRadius(16)
    }
}

enum Format {
    /// Three significant digits with a unit: "842", "28.5 K", "2.85 B". Past trillions, a power of ten.
    static func compact(_ value: Double) -> String {
        guard value >= 1_000 else { return String(Int(value)) }
        guard value < 1e15 else { return "10^\(Int(log10(value)))" }
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        let (scale, suffix) = units.first { value >= $0.0 }!
        let scaled = value / scale
        let decimals = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2
        return String(format: "%.\(decimals)f %@", scaled, suffix)
    }

    static func duration(_ seconds: Double) -> String {
        switch seconds {
        case ..<60: return "\(max(Int(seconds), 1)) s"
        case ..<3_600: return "\(Int(seconds / 60)) min"
        case ..<86_400: return "\(Int(seconds / 3_600)) h"
        default: return "\(Int(seconds / 86_400)) days"
        }
    }
}
