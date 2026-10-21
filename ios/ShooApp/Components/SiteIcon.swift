import SwiftUI

/// Monogram for a site: first letter of the domain in a rounded square.
///
/// Favicons are deliberately not downloaded: fetching `faviconUrl` would make the app contact a
/// suspected scam host and cache its image on disk (D-alief-A03, SECURITY §3 P9).
struct SiteIcon: View {
    let domain: String
    var size: CGFloat = 40

    static func monogram(for domain: String) -> String {
        let host = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        return host.first(where: \.isLetter).map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Text(verbatim: Self.monogram(for: domain))
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        SiteIcon(domain: "bca-verifikasi.site")
        SiteIcon(domain: "www.p0stindonesia.com")
    }
}
