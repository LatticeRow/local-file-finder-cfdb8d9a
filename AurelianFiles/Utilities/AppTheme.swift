import SwiftUI

enum AppTheme {
    static let background = LinearGradient(
        colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.10, green: 0.08, blue: 0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let canvas = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let card = Color(red: 0.13, green: 0.13, blue: 0.17)
    static let cardBorder = Color(red: 0.44, green: 0.34, blue: 0.18).opacity(0.45)
    static let accent = Color(red: 0.90, green: 0.76, blue: 0.45)
    static let primaryText = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let secondaryText = Color(red: 0.76, green: 0.74, blue: 0.68)
}
