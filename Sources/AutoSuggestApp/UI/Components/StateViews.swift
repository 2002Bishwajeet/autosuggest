import SwiftUI

/// Centered empty-state placeholder for lists with no items.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AutoSuggestTheme.spacingSM) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AutoSuggestTheme.spacingXL)
        .accessibilityElement(children: .combine)
    }
}

/// Inline error message with an optional Retry action.
struct InlineErrorCard: View {
    let message: String
    let retry: (label: String, action: () -> Void)?

    init(message: String, retry: (label: String, action: () -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .top, spacing: AutoSuggestTheme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AutoSuggestTheme.error)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button(retry.label, action: retry.action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(AutoSuggestTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AutoSuggestTheme.radiusMedium, style: .continuous)
                .fill(AutoSuggestTheme.error.opacity(AutoSuggestTheme.badgeFillOpacity))
        )
        .accessibilityElement(children: .combine)
    }
}
