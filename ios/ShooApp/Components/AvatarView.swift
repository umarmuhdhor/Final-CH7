import SwiftUI

/// The 12 avatars `avatar_01…avatar_12` (D-alief-13). `avatar_01…04` are the ON-02 memoji the user can
/// pick (#120); the rest are placeholders for the server's random pick. Re-skin when the final design arrives.
enum AvatarCatalog {
    struct Avatar: Equatable {
        let symbol: String
        let color: Color
    }

    static let ids: [String] = (1...12).map { String(format: "avatar_%02d", $0) }

    private static let avatars: [Avatar] = [
        Avatar(symbol: "hare.fill", color: .orange),
        Avatar(symbol: "tortoise.fill", color: .green),
        Avatar(symbol: "bird.fill", color: .blue),
        Avatar(symbol: "fish.fill", color: .teal),
        Avatar(symbol: "pawprint.fill", color: .brown),
        Avatar(symbol: "ant.fill", color: .red),
        Avatar(symbol: "ladybug.fill", color: .pink),
        Avatar(symbol: "leaf.fill", color: .mint),
        Avatar(symbol: "star.fill", color: .yellow),
        Avatar(symbol: "moon.fill", color: .indigo),
        Avatar(symbol: "sun.max.fill", color: .orange),
        Avatar(symbol: "cloud.fill", color: .cyan),
    ]

    static let fallback = Avatar(symbol: "person.fill", color: .gray)

    static func avatar(for id: String) -> Avatar {
        guard let index = ids.firstIndex(of: id) else { return fallback }
        return avatars[index]
    }
}

/// The picked memoji, or a coloured circle with the avatar's symbol. Decorative unless a name is given.
struct AvatarView: View {
    let id: String
    var size: CGFloat = 44
    var name: String?

    var body: some View {
        image
            .frame(width: size, height: size)
            .accessibilityHidden(name == nil)
            .accessibilityLabel(Text(verbatim: name ?? ""))
    }

    @ViewBuilder private var image: some View {
        if let memoji = OnboardingAvatar.memoji(for: id) {
            Image(memoji)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            let avatar = AvatarCatalog.avatar(for: id)
            Image(systemName: avatar.symbol)
                .resizable()
                .scaledToFit()
                .padding(size * 0.24)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(avatar.color.gradient, in: Circle())
        }
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(56)), count: 4)) {
        ForEach(AvatarCatalog.ids, id: \.self) { AvatarView(id: $0) }
    }
    .padding()
}
