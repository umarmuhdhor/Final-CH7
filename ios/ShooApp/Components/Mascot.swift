import SwiftUI

/// The Shoo owl in one of its 23 poses (Figma "alief maskot" `2431:12759`).
/// Images live in `Assets.xcassets/Mascot/mascot-<rawValue>`, transparent, at most 600 px tall.
/// Figma names in comments, so a design note like "Kaget" maps to a case.
enum Mascot: String, CaseIterable, Sendable {
    case angry          // Marah
    case celebrate      // Loncat senang
    case cry            // Nangis
    case fly            // Terbang
    case here           // Ini dia!
    case hero           // Pahlawan
    case idle           // Diam (default)
    case magnifier      // Detektif
    case nervous        // Cemas
    case peek           // Ngintip (body only; pair with `peekHands` over a sheet edge)
    case point          // Nunjuk
    case pout           // Cemberut
    case run            // Lari
    case scared         // Takut
    case shh            // Sstt
    case shock          // Kaget
    case sit            // Duduk
    case sleep          // Tidur
    case sorry          // Maaf
    case tapHere = "tapdown2" // Tap di sini
    case think          // Mikir
    case thumbsUp = "thumbsup" // Jempol
    case wave           // Melambai

    var assetName: String { "mascot-\(rawValue)" }

    /// Decorative: callers put the meaning in the text next to it.
    var image: Image { Image(assetName) }

    /// Width / height of the asset, so a pose can be laid out by height alone.
    var aspectRatio: CGFloat {
        switch self {
        case .angry: 519.0 / 600
        case .celebrate: 587.0 / 600
        case .cry: 493.0 / 600
        case .fly: 890.0 / 600
        case .here: 646.0 / 600
        case .hero: 614.0 / 600
        case .idle: 502.0 / 600
        case .magnifier: 496.0 / 600
        case .nervous: 428.0 / 600
        case .peek: 848.0 / 600
        case .point: 603.0 / 600
        case .pout: 455.0 / 600
        case .run: 742.0 / 600
        case .scared: 450.0 / 600
        case .shh: 441.0 / 600
        case .shock: 514.0 / 600
        case .sit: 664.0 / 600
        case .sleep: 706.0 / 600
        case .sorry: 448.0 / 600
        case .tapHere: 570.0 / 600
        case .think: 470.0 / 600
        case .thumbsUp: 509.0 / 600
        case .wave: 493.0 / 600
        }
    }

    /// The fingers of `peek`, on the same 848x600 canvas, drawn in front of a sheet edge.
    static let peekHandsAssetName = "mascot-peek-hands"

    /// Row (as a fraction of the `peek` height) where the sheet edge cuts the body:
    /// 821 of 884 in the source, per plan/alief/ref/maskot-generate.md.
    static let peekEdgeFraction: CGFloat = 821.0 / 884.0
}

/// A pose sized by height, hidden from VoiceOver (the text next to it carries the meaning).
struct MascotImage: View {
    let pose: Mascot
    var height: CGFloat

    var body: some View {
        pose.image
            .resizable()
            .interpolation(.high)
            .aspectRatio(pose.aspectRatio, contentMode: .fit)
            .frame(width: height * pose.aspectRatio, height: height)
            .accessibilityHidden(true)
    }
}

#Preview("All poses") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
            ForEach(Mascot.allCases, id: \.self) { pose in
                VStack {
                    MascotImage(pose: pose, height: 100)
                    Text(pose.rawValue).font(.caption)
                }
            }
        }
        .padding()
    }
}
