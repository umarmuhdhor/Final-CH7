import SwiftUI
import UIKit

/// What kind of signal a reason is, for "Sinyal: …" and the tag on the photo (Figma "Formulir sensitif",
/// "Logo tiruan"). Ids from contracts/detector-interface.md; an unknown id still gets a name.
enum SignalKind: Equatable {
    case sensitiveForm
    case copiedLogo
    case lookalikeDomain
    case brandInAddress
    case cheapEnding
    case suspiciousLink
    case newDomain
    case urgentWording
    case unusualRequest
    case hoax
    case knownScam
    case other

    init(signalId: String) {
        switch signalId {
        case let id where id.hasPrefix("asks_"): self = .sensitiveForm
        case "brand_logo_offsite": self = .copiedLogo
        case "lookalike_domain": self = .lookalikeDomain
        case "brand_plus_keyword": self = .brandInAddress
        case "cheap_tld": self = .cheapEnding
        case "suspicious_link": self = .suspiciousLink
        case "new_domain": self = .newDomain
        case "urgent_language": self = .urgentWording
        case "unreasonable_request": self = .unusualRequest
        case "hoax_claim": self = .hoax
        case "db_match": self = .knownScam
        default: self = .other
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .sensitiveForm: "signal.sensitiveForm"
        case .copiedLogo: "signal.copiedLogo"
        case .lookalikeDomain: "signal.lookalikeDomain"
        case .brandInAddress: "signal.brandInAddress"
        case .cheapEnding: "signal.cheapEnding"
        case .suspiciousLink: "signal.suspiciousLink"
        case .newDomain: "signal.newDomain"
        case .urgentWording: "signal.urgentWording"
        case .unusualRequest: "signal.unusualRequest"
        case .hoax: "signal.hoax"
        case .knownScam: "signal.knownScam"
        case .other: "signal.other"
        }
    }

    /// Only these point at something on the page; the rest show the photo plain (Figma "Tanpa highlight").
    var isOnPage: Bool {
        switch self {
        case .sensitiveForm, .copiedLogo, .urgentWording, .unusualRequest, .hoax: true
        default: false
        }
    }
}

/// Figma "Progres Risiko": one segment per reason up to this card, a tick at the running total, then
/// the hatched rest. Widths follow the weights; the total never passes 100 % (`score = min(100, Σ)`).
struct ContributionBar: View {
    /// Weights of this card's reason and every heavier one before it, in order.
    let weights: [Int]

    private static let gap: CGFloat = 3
    private static let tickWidth: CGFloat = 3

    /// Fractions of the bar per segment, capped so their sum is at most 1.
    static func fractions(_ weights: [Int]) -> [Double] {
        var left = 100.0
        return weights.map { weight in
            let part = min(Double(max(weight, 0)), left)
            left -= part
            return part / 100
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let fractions = Self.fractions(weights)
            let gaps = CGFloat(fractions.count + 1) * Self.gap + Self.tickWidth
            let usable = max(0, proxy.size.width - gaps)
            HStack(spacing: Self.gap) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                    HatchedCapsule(
                        fill: DetailStyle.segments[min(index, DetailStyle.segments.count - 1)],
                        hatch: .white.opacity(0.3)
                    )
                    .frame(width: usable * fraction)
                    .shadow(color: DetailStyle.barTick.opacity(0.35), radius: 4, y: 3)
                }
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(DetailStyle.barTick)
                    .frame(width: Self.tickWidth, height: 16)
                HatchedCapsule(fill: DetailStyle.barTrack, hatch: DetailStyle.barTrackHatch)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// 10 pt capsule with 45° hatching every 5 pt (Figma "Hatch", 1.2 pt).
private struct HatchedCapsule: View {
    let fill: Color
    let hatch: Color

    var body: some View {
        Capsule()
            .fill(fill)
            .overlay {
                Canvas { context, size in
                    var path = Path()
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 5
                    }
                    context.stroke(path, with: .color(hatch), lineWidth: 1.2)
                }
            }
            .clipShape(Capsule())
            .frame(height: 10)
    }
}

/// Figma "Bukti" (416:10831): the page on a pale panel. One area on the page gets the white spotlight
/// with a tag ("Spotlight (default)"); several areas get yellow outlines with numbers ("Spotlight +
/// kuning"); none shows the photo plain ("Tanpa highlight"). Red stays for risk status only.
struct EvidencePhoto: View {
    /// The page as an image (screenshot today; the page copy's snapshot from fase 18b).
    let image: UIImage?
    /// Areas to light up, in page CSS px; empty = plain photo.
    var highlights: [CGRect] = []
    /// Width of the page in CSS px, when it differs from the image's own width.
    var pageCSSWidth: CGFloat?
    var tag: String?
    var isLoading = false

    static let height: CGFloat = 212
    /// "Halaman": 270 pt wide, 10 pt from the top, 10.8 pt corners.
    private static let pageWidth: CGFloat = 270
    private static let pageInset: CGFloat = 10

    var body: some View {
        let panel = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .topLeading) {
            DetailStyle.photoFill
            if let image {
                page(image)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: Self.height)
        .clipShape(panel)
        .overlay(panel.stroke(DetailStyle.photoStroke))
    }

    /// Where the page sits and how far it scrolls so the first area is in view.
    static func layout(imageSize: CGSize, cssWidth: CGFloat?, highlights: [CGRect], panelWidth: CGFloat)
        -> (origin: CGPoint, scale: CGFloat, pageHeight: CGFloat)
    {
        let imageScale = pageWidth / max(imageSize.width, 1)
        let pageHeight = imageSize.height * imageScale
        let scale = pageWidth / max(cssWidth ?? imageSize.width, 1)
        let maxShift = max(0, pageHeight + pageInset - height)
        let shift = highlights.first.map { min(max(0, $0.midY * scale + pageInset - height / 2), maxShift) } ?? 0
        return (CGPoint(x: (panelWidth - pageWidth) / 2, y: pageInset - shift), scale, pageHeight)
    }

    private func page(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let layout = Self.layout(
                imageSize: image.size, cssWidth: pageCSSWidth, highlights: highlights, panelWidth: proxy.size.width
            )
            let holes = highlights.map { rect in
                CGRect(
                    x: layout.origin.x + rect.minX * layout.scale, y: layout.origin.y + rect.minY * layout.scale,
                    width: rect.width * layout.scale, height: rect.height * layout.scale
                ).insetBy(dx: -4, dy: -4)
            }
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: Self.pageWidth, height: layout.pageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10.8, style: .continuous))
                    .shadow(color: DetailStyle.pageShadow.opacity(0.08), radius: 7.5, y: 4.3)
                    .offset(x: layout.origin.x, y: layout.origin.y)
                if !holes.isEmpty {
                    Spotlight(holes: holes, size: proxy.size, tag: holes.count == 1 ? tag : nil)
                }
            }
        }
    }
}

/// Dim everything but the holes (#0B1A2E at 50 %). One hole: white outline, soft white glow, white tag
/// at its top right. Several: yellow outlines (#FFD60A) with a numbered dot at each top left.
private struct Spotlight: View {
    let holes: [CGRect]
    let size: CGSize
    let tag: String?

    private var numbered: Bool { holes.count > 1 }
    private var outline: Color { numbered ? DetailStyle.marker : .white }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                for hole in holes { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 8, height: 8)) }
            }
            .fill(DetailStyle.spotlight.opacity(0.5), style: FillStyle(eoFill: true))
            ForEach(Array(holes.enumerated()), id: \.offset) { index, hole in
                RoundedRectangle(cornerRadius: 8)
                    .stroke(outline, lineWidth: 2)
                    .shadow(color: outline.opacity(numbered ? 0.5 : 0.55), radius: 4)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                if numbered {
                    Text(verbatim: "\(index + 1)")
                        .activityFont(10, .semibold)
                        .foregroundStyle(DetailStyle.title)
                        .frame(width: 18, height: 18)
                        .background(DetailStyle.marker, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: hole.minX - 9, y: hole.minY - 9)
                }
            }
            if let tag, let hole = holes.first {
                // Right edge 4 pt past the outline: hung off a zero-size anchor so it grows to the left.
                Color.clear
                    .frame(width: 0, height: 0)
                    .overlay(alignment: .topTrailing) {
                        Text(verbatim: tag)
                            .activityFont(9, .semibold)
                            .foregroundStyle(DetailStyle.title)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white, in: Capsule())
                            .shadow(color: DetailStyle.pageShadow.opacity(0.15), radius: 1.5, y: 1)
                            .fixedSize()
                    }
                    .offset(x: hole.maxX + 4, y: hole.minY - 8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Figma "Evidence Card" (416:9273): photo, reason, "Sinyal: …", contribution to the scam score.
struct EvidenceCard: View {
    let reason: Evidence
    let image: UIImage?
    let isLoadingImage: Bool
    var pageCSSWidth: CGFloat?
    var onOpenImage: () -> Void = {}

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if image != nil || isLoadingImage {
                Button(action: onOpenImage) {
                    EvidencePhoto(
                        image: image,
                        highlights: reason.kind.isOnPage ? reason.highlights : [],
                        pageCSSWidth: pageCSSWidth,
                        tag: L10n.string(reason.kind.title, language: language),
                        isLoading: isLoadingImage
                    )
                }
                .buttonStyle(.plain)
                .disabled(image == nil)
                .accessibilityLabel(Text("Screenshot of the page"))
                .accessibilityAddTraits(.isImage)
                .accessibilityHint(Text("Opens a larger view"))
                .accessibilityIdentifier("detail.screenshot")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: reason.text)
                    .activityFont(17, tracking: -0.17)
                    .foregroundStyle(DetailStyle.title)
                    .fixedSize(horizontal: false, vertical: true)
                (Text("Signal:").foregroundStyle(DetailStyle.secondary) + Text(verbatim: " ")
                    + Text(verbatim: L10n.string(reason.kind.title, language: language))
                    .fontWeight(.medium).foregroundStyle(DetailStyle.title))
                    .activityFont(15, tracking: -0.15)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: reason.spokenLine(language: language)))
            .accessibilityIdentifier("detail.evidence.\(reason.index)")
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Scam risk contribution")
                        .activityFont(13)
                        .foregroundStyle(DetailStyle.secondary)
                    Spacer()
                    Text(verbatim: reason.weightText(language: language))
                        .activityFont(15, .semibold, tracking: -0.15)
                        .foregroundStyle(DetailStyle.contribution)
                        .monospacedDigit()
                }
                ContributionBar(weights: reason.runningWeights)
            }
            .padding(.top, 10)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.9)))
        .shadow(color: DetailStyle.cardShadow.opacity(0.06), radius: 8, y: 6)
    }
}
