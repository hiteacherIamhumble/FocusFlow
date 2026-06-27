import AppKit
import SwiftUI

enum AppColor {
    static let bgBase = adaptive(light: "#F7F4EF", dark: "#151A1E")
    static let surfaceCard = adaptive(light: "#FEFCF8", dark: "#1F252B")
    static let surfaceSubtle = adaptive(light: "#ECE7DF", dark: "#29323A")
    static let textPrimary = adaptive(light: "#24313A", dark: "#F1F4F5")
    static let textSecondary = adaptive(light: "#56636E", dark: "#B8C2CA")
    static let borderSubtle = adaptive(light: "#D8D2C9", dark: "#3A444D")
    static let actionPrimary = adaptive(light: "#3F6F8C", dark: "#8DBDD3")
    static let actionOnPrimary = adaptive(light: "#FFFFFF", dark: "#102631")
    static let actionContainer = adaptive(light: "#D7E7EE", dark: "#263D4A")
    static let actionOnContainer = adaptive(light: "#163445", dark: "#F1F4F5")
    static let focusRing = adaptive(light: "#7259A3", dark: "#B7A6E3")
    static let success = adaptive(light: "#2F7D68", dark: "#7CCCB4")
    static let warning = adaptive(light: "#8A5A10", dark: "#E0B56B")
    static let error = adaptive(light: "#A84D4D", dark: "#E18A8A")
    static let chipReading = adaptive(light: "#DCEAF2", dark: "#263D4A")
    static let chipPractice = adaptive(light: "#DDEBE4", dark: "#263F36")
    static let chipMemory = adaptive(light: "#E6E0F2", dark: "#39324B")
    static let chipBreak = adaptive(light: "#EFE5D4", dark: "#4A3C27")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: best == .darkAqua ? dark : light)
        })
    }
}

enum AppFont {
    static let pageTitle = Font.title.weight(.bold)
    static let sectionTitle = Font.title2.weight(.bold)
    static let cardTitle = Font.headline.weight(.semibold)
    static let body = Font.body
    static let supporting = Font.callout
    static let metadata = Font.caption
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColor.actionOnPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(
                AppColor.actionPrimary.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColor.focusRing.opacity(configuration.isPressed ? 0.65 : 0), lineWidth: 2)
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 42)
            .background(
                AppColor.surfaceCard.opacity(configuration.isPressed ? 0.70 : 0.96),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.55)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct AdaptiveButtonRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

extension View {
    func focusCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.75)))
    }

    func calmPanel(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(AppColor.actionContainer, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.borderSubtle.opacity(0.45)))
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: String) {
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
            srgbRed: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
