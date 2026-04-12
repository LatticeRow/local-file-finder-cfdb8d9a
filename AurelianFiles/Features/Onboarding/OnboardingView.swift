import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search only the folders and files you add from Files.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Aurelian Files keeps indexing and OCR on device. This shell is ready for bookmark-backed sources and local search services.")
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                Label("Add folders or individual files from Files", systemImage: "folder.badge.plus")
                Label("Keep content on device with a local index", systemImage: "lock.shield")
                Label("Search text, PDFs, and OCR results", systemImage: "doc.text.viewfinder")
            }
            .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 12) {
                Button("Add Folder from Files") {}
                    .buttonStyle(.borderedProminent)

                Button("Add Individual Files") {}
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingView()
        .padding()
        .background(AppTheme.background)
        .preferredColorScheme(.dark)
}
