#if DEBUG
import SwiftUI

/// Every shared component on one screen, for the UI gate screenshots (PROMPT step 7).
/// Debug builds only: launch with `-debug.gallery YES`.
struct ComponentGalleryView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ScoreRing(score: 41, size: 72, lineWidth: 8)
                        ScoreRing(score: 63, size: 72, lineWidth: 8)
                        ScoreRing(score: 92, size: 72, lineWidth: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    StatusChip(badge: .warning)
                    StatusChip(badge: .blocked)
                    StatusChip(badge: .verifiedScam)
                    StatusChip(badge: .markedSafe)
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(AvatarCatalog.ids, id: \.self) { AvatarView(id: $0, size: 40) }
                    }
                    HStack {
                        SiteIcon(url: nil)
                        ActivityBadge(badge: .warning)
                        ActivityBadge(badge: .blocked)
                    }
                }
                Section {
                    EmptyStateView(systemImage: "list.bullet.rectangle", title: "No activity yet", message: "Risky sites you open will show up here.")
                }
            }
            .navigationTitle(Text(verbatim: "Components"))
        }
    }
}

#Preview {
    ComponentGalleryView()
}
#endif
