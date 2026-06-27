import SwiftUI

// Calm Focus color tokens for an ADHD-friendly learning app.
// Treat this file as a project skill reference. Do not copy it into app sources
// unless the implementation task explicitly asks for frontend code changes.

enum AppColor {
    enum Light {
        static let bgBase = Color(hex: "#F7F4EF")
        static let surfaceCard = Color(hex: "#FEFCF8")
        static let surfaceSubtle = Color(hex: "#ECE7DF")
        static let textPrimary = Color(hex: "#24313A")
        static let textSecondary = Color(hex: "#56636E")
        static let borderSubtle = Color(hex: "#D8D2C9")
        static let actionPrimary = Color(hex: "#3F6F8C")
        static let actionOnPrimary = Color(hex: "#FFFFFF")
        static let actionContainer = Color(hex: "#D7E7EE")
        static let actionOnContainer = Color(hex: "#163445")
        static let focusRing = Color(hex: "#7259A3")
        static let success = Color(hex: "#2F7D68")
        static let warning = Color(hex: "#8A5A10")
        static let error = Color(hex: "#A84D4D")
        static let chipReading = Color(hex: "#DCEAF2")
        static let chipPractice = Color(hex: "#DDEBE4")
        static let chipMemory = Color(hex: "#E6E0F2")
        static let chipBreak = Color(hex: "#EFE5D4")
    }

    enum Dark {
        static let bgBase = Color(hex: "#151A1E")
        static let surfaceCard = Color(hex: "#1F252B")
        static let surfaceSubtle = Color(hex: "#29323A")
        static let textPrimary = Color(hex: "#F1F4F5")
        static let textSecondary = Color(hex: "#B8C2CA")
        static let borderSubtle = Color(hex: "#3A444D")
        static let actionPrimary = Color(hex: "#8DBDD3")
        static let actionOnPrimary = Color(hex: "#102631")
        static let focusRing = Color(hex: "#B7A6E3")
        static let success = Color(hex: "#7CCCB4")
        static let warning = Color(hex: "#E0B56B")
        static let error = Color(hex: "#E18A8A")
        static let chipReading = Color(hex: "#263D4A")
        static let chipPractice = Color(hex: "#263F36")
        static let chipMemory = Color(hex: "#39324B")
        static let chipBreak = Color(hex: "#4A3C27")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

