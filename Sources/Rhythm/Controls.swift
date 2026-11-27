import SwiftUI
import RhythmCore

struct AppSegments<Value: Hashable>: View {
    @Environment(\.rhythmAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(title(option)).font(.system(size: 11, weight: selection == option ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == option ? accent : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 27)
                        .background(selection == option ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(title(option)).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(3).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? 1 : 0.45)
            .accessibilityElement(children: .contain)
    }
}

struct AccentProgress: View {
    @Environment(\.rhythmAccent) private var accent
    var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(accent).frame(width: geometry.size.width * min(1, max(0, value)))
            }
        }.frame(height: 5)
            .accessibilityElement(children: .ignore).accessibilityLabel("Прогресс таймера")
            .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) процентов")
    }
}

struct SelectionDropdown<Value: Hashable>: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.rhythmAccent) private var accent
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var rowTitle: ((Value) -> String)? = nil
    var dot: ((Value) -> Color?)? = nil
    var accessibilityTitle = "Выбрать"
    var footerTitle: String? = nil
    var footerAction: (() -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 7) {
                if let color = dot?(selection) { Circle().fill(color).frame(width: 6, height: 6) }
                Text(title(selection)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(accent)
            }.foregroundStyle(.primary).padding(.horizontal, 10).frame(height: 31)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.06), lineWidth: 0.6))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(accessibilityTitle + ": " + title(selection))
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                SelectionList(selection: $selection, options: options, title: rowTitle ?? title, dot: dot,
                              footerTitle: footerTitle, footerAction: footerAction) { expanded = false }
                    .modifier(RhythmAppearance(store: store)).environmentObject(store)
                    .presentationBackground(.clear)
            }
    }
}

private struct SelectionList<Value: Hashable>: View {
    @EnvironmentObject var store: AppStore
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var dot: ((Value) -> Color?)?
    var footerTitle: String?
    var footerAction: (() -> Void)?
    let dismiss: () -> Void
    @State private var hovered: Value?

    var body: some View {
        VStack(spacing: 4) {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            dismiss()
                            selection = option
                        } label: {
                            HStack(spacing: 8) {
                                if let color = dot?(option) { Circle().fill(color).frame(width: 6, height: 6) }
                                Text(title(option)).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(store.accentColor).opacity(selection == option ? 1 : 0)
                            }.foregroundStyle(.primary).padding(.horizontal, 10).frame(minHeight: 32)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(store.accentColor.opacity(hovered == option ? 0.18 : selection == option ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).onHover { hovered = $0 ? option : nil }
                            .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
            }.frame(height: max(0, min(300, CGFloat(options.count) * 35 - 3)))
            if let footerTitle, let footerAction {
                Divider().padding(.vertical, 3)
                Button { dismiss(); footerAction() } label: {
                    Text(footerTitle).font(.system(size: 11)).foregroundStyle(store.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 29)
                }.buttonStyle(.plain)
            }
        }.padding(7).frame(width: 250).background(MenuGlass())
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AccentSlider: View {
    @Environment(\.rhythmAccent) private var accent
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var accessibilityTitle: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false

    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(1, geometry.size.width - 14)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08)).frame(height: 4)
                Capsule().fill(accent).frame(width: 7 + usable * fraction, height: 4)
                Circle().fill(.white.opacity(0.96))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .frame(width: 14, height: 14).offset(x: usable * fraction)
            }.frame(height: geometry.size.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = range.lowerBound + min(1, max(0, (event.location.x - 7) / usable)) * (range.upperBound - range.lowerBound)
                }.onEnded { _ in dragging = false; onEditingChanged(false) })
        }.frame(height: 20)
            .accessibilityRepresentation {
                Slider(value: $value, in: range, onEditingChanged: onEditingChanged).accessibilityLabel(accessibilityTitle)
            }
    }
}

extension TrackingMode {
    var title: String {
        switch self {
        case .countdown: return "Таймер"
        case .stopwatch: return "Секундомер"
        case .pomodoro: return "Помодоро"
        }
    }
}
