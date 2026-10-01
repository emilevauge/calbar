import SwiftUI

/// Shown in the list until the first fetch of an account completes. The
/// indicator is only in the view tree while loading, so it does not keep
/// animating in the background.
struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
