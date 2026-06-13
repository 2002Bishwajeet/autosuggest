import AppKit
import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

struct SimplePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct BannerView: View {
    let banner: AppBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.headline)
                Text(banner.message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch banner.kind {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    private var symbolColor: Color {
        switch banner.kind {
        case .info:
            AutoSuggestTheme.info
        case .success:
            AutoSuggestTheme.success
        case .warning:
            AutoSuggestTheme.warning
        case .error:
            AutoSuggestTheme.error
        }
    }
}
