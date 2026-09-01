import SwiftUI

// The compact settings card shown in the menu-bar popover. It reads live state
// from ClockSettings and routes every change through a ClockController. Size and
// theme preview live on hover and commit on click; the popover stays open until
// the user clicks outside or presses Esc.
struct SettingsPanel: View {
    @ObservedObject var settings: ClockSettings
    let controller: any ClockController

    @Environment(\.colorScheme) private var scheme
    @State private var hoveredSize: ClockSize?
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            sizeRow
            themeRow
            opacityRow
            Divider()
            toggles
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { launchAtLogin = controller.isLaunchAtLoginEnabled }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text(AppInfo.name).fontWeight(.semibold)
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private var sizeRow: some View {
        row("Size") {
            HStack(spacing: 6) {
                ForEach(ClockSize.allCases, id: \.self) { size in
                    let selected = settings.size == size
                    Text(size.shortLabel)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 32, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(
                                selected ? Color.accentColor
                                    : (hoveredSize == size ? Color.primary.opacity(0.14)
                                                           : Color.primary.opacity(0.06)))
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                hoveredSize = size
                                controller.previewSize(size)
                            } else if hoveredSize == size {
                                hoveredSize = nil
                            }
                        }
                        .onTapGesture { controller.commitSize(size) }
                }
                Spacer(minLength: 0)
            }
            .onHover { inside in
                if !inside {
                    hoveredSize = nil
                    controller.endPreviews()
                }
            }
        }
    }

    private var themeRow: some View {
        row("Theme") {
            HStack(spacing: 8) {
                ForEach(ClockTheme.allCases, id: \.self) { theme in
                    ThemeSwatch(theme: theme, scheme: scheme, selected: settings.theme == theme)
                        .onHover { hovering in if hovering { controller.previewTheme(theme) } }
                        .onTapGesture { controller.commitTheme(theme) }
                }
                Spacer(minLength: 0)
            }
            .onHover { inside in if !inside { controller.endPreviews() } }
        }
    }

    private var opacityRow: some View {
        row("Opacity") {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { settings.opacity },
                                      set: { controller.setOpacity($0) }),
                       in: ClockSettings.minOpacity...ClockSettings.maxOpacity)
                Text("\(Int((settings.opacity * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private var toggles: some View {
        VStack(spacing: 8) {
            switchRow("Sweeping Second Hand",
                      Binding(get: { settings.sweepSeconds }, set: { controller.setSweepSeconds($0) }))
            switchRow("Show Hour Numerals",
                      Binding(get: { settings.showNumerals }, set: { controller.setShowNumerals($0) }))
            switchRow("Float Over Fullscreen Apps",
                      Binding(get: { settings.floatOverFullscreen }, set: { controller.setFloatOverFullscreen($0) }))
            switchRow("Click-Through",
                      Binding(get: { settings.clickThrough }, set: { controller.setClickThrough($0) }))
            switchRow("Launch at Login",
                      Binding(get: { launchAtLogin },
                              set: { newValue in
                                  launchAtLogin = newValue
                                  controller.setLaunchAtLogin(newValue)
                                  launchAtLogin = controller.isLaunchAtLoginEnabled
                              }))
        }
        .font(.system(size: 12))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit DeskClock") { controller.quit() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: layout helpers

    private func row<Content: View>(_ label: String,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            content()
        }
    }

    private func switchRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title) }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }
}

// A theme is shown as its hand color with a small second-hand dot — the same
// two colors the theme paints onto the clock — ringed when it's the active one.
private struct ThemeSwatch: View {
    let theme: ClockTheme
    let scheme: ColorScheme
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(theme.handColor(scheme)).frame(width: 16, height: 16)
            Circle().fill(theme.secondColor(scheme)).frame(width: 6, height: 6)
        }
        .padding(2)
        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Circle())
        .help(theme.title)
    }
}
