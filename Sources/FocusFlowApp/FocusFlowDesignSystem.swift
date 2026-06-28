import AppKit
import SwiftUI

enum AppColor {
    static let bgBase = adaptive(light: "#F7F4ED", dark: "#15181E")
    static let surfaceCard = adaptive(light: "#FFFDF9", dark: "#1F242C")
    static let surfaceSubtle = adaptive(light: "#EFEBE1", dark: "#28303A")
    static let textPrimary = adaptive(light: "#2F3440", dark: "#F1F3F6")
    static let textSecondary = adaptive(light: "#8A8F98", dark: "#AEB6C0")
    static let borderSubtle = adaptive(light: "#E0DACF", dark: "#39424D")
    static let actionPrimary = adaptive(light: "#5B7CFA", dark: "#8AA2FB")
    static let actionOnPrimary = adaptive(light: "#FFFFFF", dark: "#0E1740")
    static let actionContainer = adaptive(light: "#E6ECFF", dark: "#27324F")
    static let actionOnContainer = adaptive(light: "#26336E", dark: "#E6ECFF")
    static let focusRing = adaptive(light: "#3A5BD9", dark: "#A9BBFC")
    static let success = adaptive(light: "#5BAF85", dark: "#7BC99A")
    static let peach = adaptive(light: "#F2A24C", dark: "#FFB86B")
    static let calmLavender = adaptive(light: "#EEE9FF", dark: "#2E2A44")
    static let warning = adaptive(light: "#B07A2E", dark: "#E0B56B")
    static let error = adaptive(light: "#C46A6A", dark: "#E18A8A")
    static let chipReading = adaptive(light: "#E1E8FF", dark: "#27324F")
    static let chipPractice = adaptive(light: "#DDEEE4", dark: "#22392F")
    static let chipMemory = adaptive(light: "#EEE9FF", dark: "#332E49")
    static let chipBreak = adaptive(light: "#FCEBD4", dark: "#43361F")

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

struct CompactSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
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

    func lavenderPanel(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(AppColor.calmLavender, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColor.focusRing.opacity(0.18)))
    }

    func gentleSheet(maxWidth: CGFloat = 520) -> some View {
        self
            .padding(24)
            .frame(maxWidth: maxWidth)
            .background(AppColor.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.borderSubtle.opacity(0.6)))
            .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
    }
}

struct AchievementBadge: View {
    let title: String
    let iconName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(AppColor.peach)
                .frame(width: 52, height: 52)
                .background(AppColor.peach.opacity(0.16), in: Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 96)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement: \(title)")
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
