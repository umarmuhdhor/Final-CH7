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
    /// Spacing and hatching of the two Figma bars.
    struct Style {
        var gap: CGFloat
        var tickWidth: CGFloat
        var tickRadius: CGFloat
        var hatchPitch: CGFloat
        var hatchWidth: CGFloat
        var shadowRadius: CGFloat
        var shadowY: CGFloat

        /// The evidence card's bar: 3 pt apart, 2.5 pt tick, hatching every 5 pt.
        static let card = Style(gap: 3, tickWidth: 2.5, tickRadius: 1.25, hatchPitch: 5, hatchWidth: 1.2,
                                shadowRadius: 4, shadowY: 3)
        /// The "Penilaian Risiko Shoo" bar (1252:2047): 1.5 pt apart, 2 pt tick, 0.6 pt hatching every 2.48 pt,
        /// shadow blur 4 at y 1.5.
        static let score = Style(gap: 1.5, tickWidth: 2, tickRadius: 0.625, hatchPitch: 2.48, hatchWidth: 0.6,
                                 shadowRadius: 2, shadowY: 1.5)
    }

    /// Weights of this card's reason and every heavier one before it, in order.
    let weights: [Int]
    var style: Style = .card

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
            let gaps = CGFloat(fractions.count + 1) * style.gap + style.tickWidth
            let usable = max(0, proxy.size.width - gaps)
            HStack(spacing: style.gap) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                    HatchedCapsule(
                        fill: DetailStyle.segments[min(index, DetailStyle.segments.count - 1)],
                        hatch: .white.opacity(0.3), pitch: style.hatchPitch, lineWidth: style.hatchWidth
                    )
                    .frame(width: usable * fraction)
                    .shadow(color: DetailStyle.barTick.opacity(0.35), radius: style.shadowRadius, y: style.shadowY)
                }
                RoundedRectangle(cornerRadius: style.tickRadius)
                    .fill(DetailStyle.barTick)
                    .frame(width: style.tickWidth, height: 16)
                HatchedCapsule(fill: DetailStyle.barTrack, hatch: DetailStyle.barTrackHatch,
                               pitch: style.hatchPitch, lineWidth: style.hatchWidth)
            }
            .frame(height: 16)
            .offset(y: -3)
        }
        // The bar is 10 pt in the layout (Figma "Bar"); the tick overhangs it.
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// 10 pt capsule with 45° hatching (Figma "Hatch").
private struct HatchedCapsule: View {
    let fill: Color
    let hatch: Color
    var pitch: CGFloat = 5
    var lineWidth: CGFloat = 1.2

    var body: some View {
        Capsule()
            .fill(fill)
            .overlay {
                Canvas { context, size in
                    var path = Path()
                    // Figma draws each line over half the bar height ("M 0 10 L 4.96 0", every 2.48).
                    let run = pitch == 5 ? size.height : pitch * 2
                    var x: CGFloat = -run
                    while x < size.width + run {
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + run, y: 0))
                        x += pitch
                    }
                    context.stroke(path, with: .color(hatch), lineWidth: lineWidth)
                }
            }
            .clipShape(Capsule())
            .frame(height: 10)
    }
}

/// While the page loads: an empty page that a blue line scans down and up (2.4 s).
/// Reduce Motion keeps the empty page without the line.
private struct PageScanPlaceholder: View {
    let pageWidth: CGFloat
    let topInset: CGFloat

    @Environment(\.shooReduceMotion) private var reduceMotion

    private static let period = 2.4
    private static let bandHeight: CGFloat = 46
    private static let travel: CGFloat = 196
    private static let bar = DetailStyle.hex(0xDDE6F1)
    private static let line = DetailStyle.hex(0x1A73D9)
    private static let band = DetailStyle.hex(0x4FB4F2)
    /// Blocks of the empty page: x, y, width, height.
    private static let blocks: [CGRect] = [
        CGRect(x: 16, y: 22, width: 120, height: 12),
        CGRect(x: 16, y: 44, width: 238, height: 70),
        CGRect(x: 16, y: 126, width: 200, height: 9),
        CGRect(x: 16, y: 142, width: 226, height: 9),
        CGRect(x: 16, y: 158, width: 170, height: 9),
        CGRect(x: 16, y: 174, width: 214, height: 9),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10.8, style: .continuous).fill(.white)
            ForEach(Self.blocks, id: \.minY) { block in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Self.bar)
                    .frame(width: block.width, height: block.height)
                    .offset(x: block.minX, y: block.minY)
            }
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                    scanLine.offset(y: abs(sin(turn * .pi)) * Self.travel - Self.bandHeight)
                }
            }
        }
        .frame(width: pageWidth, height: EvidencePhoto.height)
        .clipped()
        .offset(y: topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }

    private var scanLine: some View {
        LinearGradient(colors: [Self.band.opacity(0), Self.band.opacity(0.38)], startPoint: .top, endPoint: .bottom)
            .frame(height: Self.bandHeight)
            .overlay(alignment: .bottom) { Self.line.frame(height: 2) }
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
                    .transition(.opacity)
            } else if isLoading {
                PageScanPlaceholder(pageWidth: Self.pageWidth, topInset: Self.pageInset)
                    .transition(.opacity)
            }
        }
        // Scan placeholder → the page copy: a 0.2 s cross-fade, gentle enough for Reduce Motion.
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .frame(height: Self.height)
        .clipShape(panel)
        .overlay(panel.stroke(DetailStyle.photoStroke))
    }

    /// Room kept above and below an area: its outline, the glow and the tag over its top edge.
    static let areaMargin: CGFloat = 30

    /// Where the page sits, how big it is and how far it scrolls so the first area is in view. An area taller
    /// than the panel shrinks the page until it fits whole, outline and tag included (never cut off).
    static func layout(imageSize: CGSize, cssWidth: CGFloat?, highlights: [CGRect], panelWidth: CGFloat)
        -> (origin: CGPoint, scale: CGFloat, pageHeight: CGFloat, pageWidth: CGFloat)
    {
        let fullScale = pageWidth / max(cssWidth ?? imageSize.width, 1)
        let room = height - 2 * areaMargin
        // The outline sits 4 pt outside the area on each side, at every size.
        let fit = highlights.first.map { min(1, max(room - 8, 1) / max($0.height * fullScale, 1)) } ?? 1
        let width = pageWidth * fit
        let pageHeight = imageSize.height * width / max(imageSize.width, 1)
        let scale = fullScale * fit
        let maxShift = max(0, pageHeight + pageInset - height)
        // The area sits a little below the middle, leaving the tag above it room.
        let target = height / 2 + Spotlight.tagHeight / 2
        let shift = highlights.first.map { min(max(0, $0.midY * scale + pageInset - target), maxShift) } ?? 0
        return (CGPoint(x: (panelWidth - width) / 2, y: pageInset - shift), scale, pageHeight, width)
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
                    .frame(width: layout.pageWidth, height: layout.pageHeight)
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
struct Spotlight: View {
    /// The tag's capsule: 13 pt text with 3 pt above and below.
    static let tagHeight: CGFloat = 22
    let holes: [CGRect]
    let size: CGSize
    let tag: String?

    private var numbered: Bool { holes.count > 1 }
    /// Figma "Highlight" (1252:2138): #E5483B, 2 pt, with a white 55 % glow (blur 8).
    private var outline: Color { numbered ? DetailStyle.marker : DetailStyle.barTick }
    private var glow: Color { numbered ? DetailStyle.marker.opacity(0.5) : .white.opacity(0.55) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                // Past the edges, so no undimmed strip shows at a rounded edge; the card clips it to its panel.
                path.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -size.width, dy: -size.height))
                for hole in holes { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 8, height: 8)) }
            }
            .fill(DetailStyle.spotlight.opacity(0.5), style: FillStyle(eoFill: true))
            ForEach(Array(holes.enumerated()), id: \.offset) { index, hole in
                RoundedRectangle(cornerRadius: 8)
                    .stroke(outline, lineWidth: 2)
                    .shadow(color: glow, radius: 4)
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
                        // Figma "Highlight Tag": SF Pro Display Semibold 13 in a 22 pt white capsule.
                        Text(verbatim: tag)
                            .activityFont(13, .semibold)
                            .foregroundStyle(DetailStyle.title)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white, in: Capsule())
                            .shadow(color: DetailStyle.pageShadow.opacity(0.15), radius: 1.5, y: 1)
                            .fixedSize()
                    }
                    // Right edge 7.7 pt past the outline (Figma); the tag sits wholly above the outline so it never
                    // covers what is marked (Figma let it overlap by half, which hid the first line of text).
                    .offset(x: hole.maxX + 7.7, y: hole.minY - Self.tagHeight - 3)
            }
        }
        .allowsHitTesting(false)
    }
}

/// DT-04: a reason with several marks (an unusual request in many places, say): one photo per mark, swiped
/// sideways, each centred on its own mark with the single-area spotlight. Dots under the photo say how many.
struct EvidenceCarousel: View {
    let image: UIImage
    let highlights: [CGRect]
    var pageCSSWidth: CGFloat?
    var tag: String?

    @State private var page = 0
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { index, rect in
                    EvidencePhoto(image: image, highlights: [rect], pageCSSWidth: pageCSSWidth, tag: tag)
                        .padding(.horizontal, 1) // keeps the panel's outline clear of the page edge
                        .tag(index)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: Self.spoken(index, of: highlights.count, locale: locale)))
                        .accessibilityAddTraits(.isImage)
                        .accessibilityIdentifier("detail.screenshot")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: EvidencePhoto.height)
            dots
        }
        // The marks can change under the open card (the copy replaces the screenshot, "Try again", a saved copy):
        // a page past the new last one would leave the carousel blank with no dot lit.
        .onChange(of: highlights.count) { _, count in page = Self.clampedPage(page, count: count) }
    }

    /// `page` kept inside `0..<count` (0 when there are no marks).
    static func clampedPage(_ page: Int, count: Int) -> Int {
        min(max(page, 0), max(count - 1, 0))
    }

    /// Page dots: the current one wide and dark (Figma page-control look on a light card).
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(highlights.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? DetailStyle.title : DetailStyle.secondary.opacity(0.35))
                    .frame(width: index == page ? 16 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
    }

    /// "Screenshot of the page, 1 of 3".
    static func spoken(_ index: Int, of count: Int, locale: Locale) -> String {
        let language = AppLanguage(locale: locale)
        let photo = L10n.string("Screenshot of the page", language: language)
        return L10n.string("\(photo), \(index + 1) of \(count)", language: language)
    }
}

/// DT-04: an on-page reason Shoo can't point at on the copy of the page (its field or text isn't shown, e.g. a
/// form inside a hidden login box). Same panel as `AddressEvidence`, with one line instead of an unmarked photo.
struct UnmarkedEvidence: View {
    let kind: SignalKind

    var body: some View {
        let panel = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text("Shoo can't point to this on the page: it may be hidden")
                .activityFont(15)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DetailStyle.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AddressEvidence.height)
        .background(DetailStyle.photoFill)
        .clipShape(panel)
        .overlay(panel.stroke(DetailStyle.photoStroke))
        .accessibilityElement(children: .combine)
    }
}

/// Figma "Evidence Card" (1252:2114, REVISI PRU): photo, reason, "Sinyal: …" on a pale card.
struct EvidenceCard: View {
    let reason: Evidence
    let image: UIImage?
    /// Where this reason sits on `image`, in page CSS px; `nil` = the reason's own marks.
    var highlights: [CGRect]?
    let isLoadingImage: Bool
    var pageCSSWidth: CGFloat?
    /// The scan's `domain` (registrable domain, or the full host on a shared platform, #495): a reason about the address shows it instead of the page (DT-04).
    var domain: String?
    /// The page copy is on screen with its marks: an on-page reason with no mark there points at nothing visible
    /// (a field inside a hidden login box, say), so the card says so instead of showing an unmarked page.
    var marksKnown = false

    /// On-page reason, page copy shown, and no mark for it: a photo would point at nothing.
    static func showsUnmarkedNote(kind: SignalKind, highlights: [CGRect], hasImage: Bool, marksKnown: Bool) -> Bool {
        kind.isOnPage && marksKnown && hasImage && highlights.isEmpty
    }

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reason.kind.isAddress, let domain {
                AddressEvidence(domain: domain, kind: reason.kind, reasonText: reason.text, host: reason.host)
                    .accessibilityIdentifier("detail.address.\(reason.index)")
            } else if Self.showsUnmarkedNote(kind: reason.kind, highlights: highlights ?? reason.highlights,
                                             hasImage: image != nil, marksKnown: marksKnown) {
                UnmarkedEvidence(kind: reason.kind)
                    .accessibilityIdentifier("detail.unmarked.\(reason.index)")
            } else if image != nil || isLoadingImage {
                // Not tappable: the card already shows the part that matters, with its marks (no full screen view).
                // Several marks: one photo per mark in a carousel, each centred on its own mark, so none is cut.
                let marks = reason.kind.isOnPage ? (highlights ?? reason.highlights) : []
                let tag = L10n.string(reason.kind.title, language: language)
                if marks.count > 1, let image {
                    EvidenceCarousel(image: image, highlights: marks, pageCSSWidth: pageCSSWidth, tag: tag)
                        .accessibilityIdentifier("detail.carousel.\(reason.index)")
                } else {
                    EvidencePhoto(
                        image: image,
                        highlights: marks,
                        pageCSSWidth: pageCSSWidth,
                        tag: tag,
                        isLoading: isLoadingImage
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Screenshot of the page"))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("detail.screenshot")
                }
            }
            // Figma "Keterangan": the reason, then "Sinyal: …", 4 pt apart and 4 pt in.
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: reason.text)
                    .activityFont(17, .semibold)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(DetailStyle.title)
                    .fixedSize(horizontal: false, vertical: true)
                (Text("Signal:").foregroundStyle(DetailStyle.secondary) + Text(verbatim: " ")
                    + Text(verbatim: L10n.string(reason.kind.title, language: language))
                    .foregroundStyle(DetailStyle.title))
                    .activityFont(17, rounded: true)
                    .figmaLineHeight(23.8, relativeTo: .body)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: reason.spokenLine(language: language)))
            .accessibilityIdentifier("detail.evidence.\(reason.index)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DetailStyle.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.9)))
        .figmaCardShadow()
    }
}
