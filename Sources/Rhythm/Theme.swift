import AppKit
import SwiftUI
import RhythmCore

enum Palette {
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.035) : .white.opacity(0.26)
    }
    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.075) : .black.opacity(0.065)
    }
}

extension AccentChoice {
    var title: String {
        switch self {
        case .system: return L10n.text("System")
        case .blue: return L10n.text("Blue")
        case .purple: return L10n.text("Purple")
        case .pink: return L10n.text("Pink")
        case .red: return L10n.text("Red")
        case .orange: return L10n.text("Orange")
        case .yellow: return L10n.text("Yellow")
        case .green: return L10n.text("Green")
        case .graphite: return L10n.text("Graphite")
        case .custom: return L10n.text("Custom color")
        }
    }

    var nativeColor: NSColor {
        switch self {
        case .system: return .controlAccentColor
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .graphite: return .systemGray
        case .custom: return .controlAccentColor
        }
    }
}

@MainActor
enum AppAppearance {
    static func apply(_ preference: String, to application: NSApplication) {
        let appearance: NSAppearance?
        switch preference {
        case "dark": appearance = NSAppearance(named: .darkAqua)
        case "light": appearance = NSAppearance(named: .aqua)
        default: appearance = nil
        }
        // AppKit owns the appearance for every panel and popover. Clearing the app
        // override restores macOS inheritance; SwiftUI must not keep a window override.
        if application.appearance?.name != appearance?.name { application.appearance = appearance }
    }
}

extension AppStore {

    var accentNSColor: NSColor {
        guard ledger.preferences.accentChoice == .custom else { return ledger.preferences.accentChoice.nativeColor }
        let number = UInt32(ledger.preferences.customAccentHex, radix: 16) ?? 0x6E64D4
        return NSColor(srgbRed: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, alpha: 1)
    }

    var accentColor: Color { Color(nsColor: accentNSColor) }

    var accentForeground: Color {
        guard let color = accentNSColor.usingColorSpace(.sRGB) else { return .white }
        let brightness = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return brightness > 0.63 ? .black.opacity(0.85) : .white
    }

    func setCustomAccent(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        ledger.preferences.customAccentHex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        ledger.preferences.accentChoice = .custom
        save()
    }
}

private struct AccentForegroundKey: EnvironmentKey { static let defaultValue: Color = .white }
private struct AccentColorKey: EnvironmentKey { static let defaultValue = Color(nsColor: NSColor.controlAccentColor) }
extension EnvironmentValues {
    var rhythmAccent: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
    var rhythmAccentForeground: Color {
        get { self[AccentForegroundKey.self] }
        set { self[AccentForegroundKey.self] = newValue }
    }
}

struct RhythmAppearance: ViewModifier {
    @ObservedObject var store: AppStore
    func body(content: Content) -> some View {
        content.accentColor(store.accentColor).tint(store.accentColor)
            .environment(\.rhythmAccent, store.accentColor)
            .environment(\.rhythmAccentForeground, store.accentForeground)
            .environment(\.locale, L10n.locale)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.alphaValue = opacity
    }
}

struct MenuGlass: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        let style = GlassStyle(opacity: store.ledger.preferences.backgroundOpacity, blur: store.ledger.preferences.backgroundBlur)
        ZStack {
            VisualEffect(opacity: style.materialOpacity)
            Color(nsColor: .windowBackgroundColor).opacity(style.tintOpacity)
        }
        .allowsHitTesting(false)
    }
}

extension MenuBarIcon {
    var title: String {
        switch self {
        case .rhythm: return "time_"
        case .timer: return L10n.text("Timer")
        case .circle: return L10n.text("Circle")
        }
    }
    var symbol: String {
        switch self {
        case .rhythm: return "circle.dotted.circle"
        case .timer: return "timer"
        case .circle: return "circle"
        }
    }
}

extension CategoryColor {
    var tint: Color {
        switch self {
        case .mint: return Color(red: 0.48, green: 0.72, blue: 0.61)
        case .blue: return Color(red: 0.48, green: 0.65, blue: 0.85)
        case .lavender: return Color(red: 0.57, green: 0.53, blue: 0.86)
        case .peach: return Color(red: 0.86, green: 0.62, blue: 0.43)
        case .rose: return Color(red: 0.84, green: 0.51, blue: 0.58)
        case .yellow: return Color(red: 0.77, green: 0.70, blue: 0.37)
        }
    }
}

struct RhythmMark: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().trim(from: 0.04, to: 0.44).stroke(style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            Circle().trim(from: 0.54, to: 0.94).stroke(style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            Circle().frame(width: size * 0.15, height: size * 0.15)
        }
        .rotationEffect(.degrees(-30))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct QuietIconButton: View {
    @Environment(\.rhythmAccent) private var accent
    let symbol: String
    let help: String
    var selected = false
    var size: CGFloat = 28
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? accent : Color.secondary)
                .frame(width: size, height: size)
                .background(selected ? accent.opacity(0.16) : Color.primary.opacity(hovered ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(help)
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.rhythmAccentForeground) private var foreground
    @Environment(\.rhythmAccent) private var accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(accent.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Explicit colour avoids the native SwiftUI switch bridge applying a different tint on macOS 15.
struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.rhythmAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? accent : .secondary.opacity(0.24))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.09), lineWidth: 0.5))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                        .frame(width: 12, height: 12).padding(2)
                }
                .frame(width: 28, height: 16)
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

struct AccentCheckboxStyle: ToggleStyle {
    @Environment(\.rhythmAccent) private var accent
    @Environment(\.rhythmAccentForeground) private var foreground

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? accent : .primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(configuration.isOn ? 0 : 0.4), lineWidth: 1))
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(foreground) }
                    }
                    .frame(width: 15, height: 15)
                configuration.label.font(AppTypography.body)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox) }
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(Palette.card(scheme), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line(scheme), lineWidth: 1))
    }
}

extension View {
    func cardSurface(padding: CGFloat = 14) -> some View { modifier(CardSurface(padding: padding)) }
}

enum AppTypography {
    static let pageTitle = Font.system(size: 21, weight: .semibold)
    static let panelTitle = Font.system(size: 14, weight: .semibold)
    static let editorTitle = Font.system(size: 16, weight: .semibold)
    static let section = Font.system(size: 11, weight: .semibold)
    static let rowTitle = Font.system(size: 12, weight: .medium)
    static let body = Font.system(size: 12)
    static let detail = Font.system(size: 11)
    static let small = Font.system(size: 10)
    static let totalSize: CGFloat = 27
    static let metricSize: CGFloat = 18
}

extension Text {
    func timeDisplay(size: CGFloat) -> some View {
        font(.system(size: size, weight: .medium)).monospacedDigit().tracking(-size / 54)
    }
}

struct SectionCaption: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(AppTypography.section)
            Spacer()
            if let trailing { Text(trailing).font(AppTypography.detail).monospacedDigit() }
        }
        .foregroundStyle(.secondary)
    }
}

struct CategoryPicker: View {
    @EnvironmentObject var store: AppStore
    @Binding var selection: UUID
    var allowsManagement = true
    var showsProgress = false
    private var options: [UUID] {
        var ids = store.categories.map(\.id)
        if let selected = store.ledger.category(selection), selected.isArchived { ids.insert(selected.id, at: 0) }
        return ids
    }
    var body: some View {
        SelectionDropdown(selection: $selection, options: options,
                          title: { store.ledger.category($0)?.name ?? L10n.text("Category") },
                          rowTitle: { id in
            guard let category = store.ledger.category(id) else { return L10n.text("Category") }
            if !showsProgress { return category.name + (category.isArchived ? L10n.text(" · archived") : "") }
            let worked = store.ledger.total(on: store.now, categoryID: id, at: store.now)
            let goal = store.ledger.plannedMinutes(for: id, on: store.now)
            return category.name + " · " + TimeText.duration(worked) + (goal > 0 ? " / " + TimeText.duration(Double(goal * 60)) : "")
        }, dot: { store.ledger.category($0)?.color.tint }, accessibilityTitle: L10n.text("Category"),
                          footerTitle: allowsManagement ? L10n.text("Manage Categories…") : nil,
                          footerAction: allowsManagement ? { store.showCategories = true } : nil)
    }
}

struct EmptyNote: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .ultraLight)).foregroundStyle(.tertiary).padding(.bottom, 3)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle).font(AppTypography.detail).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
