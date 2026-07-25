import AppKit
import SwiftUI

struct OnboardingChoiceCard: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusLarge, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusLarge, style: .continuous)
                            .stroke(
                                selected ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: selected ? 1.5 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SetupStatusBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        let accent = isReady ? AutoSuggestTheme.success : AutoSuggestTheme.warning
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.16))
            )
            .foregroundStyle(accent)
    }
}

struct CommandSnippetCard: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(command)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                )
        }
    }
}

struct SuggestionPreviewCard: View {
    var body: some View {
        SettingsSection {
            VStack(alignment: .leading, spacing: 14) {
                Label("How suggestions appear", systemImage: "text.cursor")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "When AutoSuggest has a completion, the suggested text appears inline and stays visually separate from what you already typed."
                    )
                    .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Thanks for the")
                            .font(.title3.weight(.medium))
                        Text(" quick update")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                    )

                    HStack(spacing: 10) {
                        KeycapView(label: "Tab", accentColor: AutoSuggestTheme.brand, highlighted: true)
                        Text("to accept the highlighted completion")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ShortcutHighlightRow: View {
    let title: String
    let subtitle: String
    let keycaps: [String]
    let accentColor: Color
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(keycaps, id: \.self) { keycap in
                    KeycapView(label: keycap, accentColor: accentColor, highlighted: highlighted)
                }
            }
        }
    }
}

struct ShortcutActionCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        SettingsSection {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct KeycapView: View {
    let label: String
    let accentColor: Color
    let highlighted: Bool

    var body: some View {
        Text(label)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(highlighted ? 0.16 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accentColor.opacity(highlighted ? 0.35 : 0.25), lineWidth: 1)
                    )
            )
            .foregroundStyle(highlighted ? accentColor : .primary)
    }
}
