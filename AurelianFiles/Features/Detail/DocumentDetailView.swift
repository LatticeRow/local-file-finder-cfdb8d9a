import SwiftUI

struct DocumentDetailView: View {
    let item: SearchResultItem

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text(item.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Text(item.location)
                    .foregroundStyle(AppTheme.secondaryText)

                Text(item.snippet)
                    .foregroundStyle(AppTheme.primaryText)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(
            item: SearchResultItem(
                title: "Welcome to Aurelian Files",
                location: "Search shell",
                snippet: "Snippet preview placeholder.",
                fileType: "TXT"
            )
        )
    }
    .preferredColorScheme(.dark)
}
