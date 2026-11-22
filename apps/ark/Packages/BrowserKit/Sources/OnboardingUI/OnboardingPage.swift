import SwiftUI

/// A small, adaptive welcome surface shared by Ark's Apple platform clients.
/// The controls are presentation choices for the welcome mockup; clients can connect them to their
/// own preference stores without making this package depend on browser or engine state.
public struct VezhamOnboardingPage: View {
    public static let completionPreferenceKey = "VezhamOnboardingCompletedV1"

    private enum Scheme: String, CaseIterable {
        case automatic = "Auto"
        case light = "Light"
        case dark = "Dark"
    }

    private enum Interface: String, CaseIterable {
        case classic = "Classic"
        case glass = "Glass"
    }

    private enum Toolbar: String, CaseIterable {
        case above = "Above"
        case left = "Left"
        case right = "Right"
        case below = "Below"
    }

    private struct Theme: Identifiable {
        let name: String
        let colors: [Color]
        var id: String { name }
    }

    private let onContinue: () -> Void
    @State private var scheme: Scheme = .automatic
    @State private var interface: Interface = .classic
    @State private var toolbar: Toolbar = .above
    @State private var selectedTheme = "Merino"

    private let themes = [
        Theme(name: "Merino", colors: [.primary, .blue, .purple, .teal]),
        Theme(name: "Alpine Milk", colors: [.gray, .blue, .cyan, .mint]),
        Theme(name: "Buttercream", colors: [.brown, .orange, .yellow, .pink]),
        Theme(name: "Coastal", colors: [.blue, .teal, .cyan, .indigo]),
    ]

    public init(onContinue: @escaping () -> Void = {}) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "safari")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 12)

                    Text("ONBOARDING")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    Text("Make Vezham yours")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Choose a color scheme, interface style, toolbar layout and theme to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    settingsCard
                        .frame(maxWidth: 720)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            Button(action: onContinue) {
                Label("Continue", systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("vezham-welcome-continue")
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.025))
        .accessibilityIdentifier("vezham-onboarding")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "safari.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Vezham")
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.primary.opacity(0.07), in: Capsule())
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    schemeChoices
                    Divider().frame(height: 110)
                    interfaceChoices
                }
                VStack(alignment: .leading, spacing: 16) {
                    schemeChoices
                    interfaceChoices
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Toolbar layout")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Toolbar.allCases, id: \.self) { item in
                        choiceCard(item.rawValue, selected: toolbar == item) {
                            toolbar = item
                        } content: {
                            toolbarPreview(item)
                        }
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Themes")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(themes) { theme in
                            Button {
                                selectedTheme = theme.name
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 4) {
                                        ForEach(Array(theme.colors.enumerated()), id: \.offset) { _, color in
                                            Circle().fill(color).frame(width: 15, height: 15)
                                        }
                                    }
                                    Text(theme.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                                .frame(width: 108, height: 56, alignment: .leading)
                                .padding(10)
                                .background(.background, in: RoundedRectangle(cornerRadius: 13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .strokeBorder(selectedTheme == theme.name ? Color.accentColor : .primary.opacity(0.10),
                                                      lineWidth: selectedTheme == theme.name ? 2 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(theme.name) theme")
                            .accessibilityAddTraits(selectedTheme == theme.name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var schemeChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Color scheme")
            HStack(spacing: 6) {
                ForEach(Scheme.allCases, id: \.self) { item in
                    choiceCard(item.rawValue, selected: scheme == item) {
                        scheme = item
                    } content: {
                        schemePreview(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var interfaceChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Interface style")
            HStack(spacing: 6) {
                ForEach(Interface.allCases, id: \.self) { item in
                    choiceCard(item.rawValue, selected: interface == item) {
                        interface = item
                    } content: {
                        Circle()
                            .fill(item == .classic ? Color.primary.opacity(0.12) : Color.accentColor.opacity(0.16))
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func choiceCard<Content: View>(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                Text(title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(5)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func schemePreview(_ choice: Scheme) -> some View {
        let isDark = choice == .dark
        return RoundedRectangle(cornerRadius: 7)
            .fill(isDark ? Color.black : Color.white)
            .frame(width: 54, height: 40)
            .overlay(alignment: .top) {
                HStack(spacing: 3) {
                    Circle().fill(.red.opacity(0.85))
                    Circle().fill(.orange.opacity(0.85))
                    Circle().fill(.green.opacity(0.85))
                }
                .frame(width: 20, height: 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.14), lineWidth: 1)
            }
            .overlay {
                if choice == .automatic {
                    HStack(spacing: 0) {
                        Color.white.frame(width: 25)
                        Color.black
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(3)
                }
            }
    }

    private func toolbarPreview(_ choice: Toolbar) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(.primary.opacity(0.08))
                .frame(width: 58, height: 38)
            RoundedRectangle(cornerRadius: 3)
                .fill(.background)
                .frame(width: 30, height: 23)
            switch choice {
            case .above:
                Capsule().fill(Color.accentColor).frame(width: 28, height: 3).offset(y: -13)
            case .below:
                Capsule().fill(Color.accentColor).frame(width: 28, height: 3).offset(y: 13)
            case .left:
                Capsule().fill(Color.accentColor).frame(width: 3, height: 19).offset(x: -17)
            case .right:
                Capsule().fill(Color.accentColor).frame(width: 3, height: 19).offset(x: 17)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VezhamOnboardingPage()
}
