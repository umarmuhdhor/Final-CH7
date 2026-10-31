import SwiftUI

/// Figma "Guardian/Detail Aktivitas" (416:9255 and its states): colours of the Detail screen.
/// Type uses `activityFont` (same Figma type ramp as Activity). Light only, like Activity.
enum DetailStyle {
    static let background = hex(0xF5F8FC)
    static let ink = hex(0x151617)
    static let title = hex(0x191D2F)
    static let link = hex(0x3A3D42)
    static let secondary = hex(0x6A717E)
    static let tick = hex(0x3F4D5A)
    static let needle = hex(0x383D43)
    static let cardTop = hex(0xFEFEFF)
    static let cardShadow = hex(0xE7F2F6)
    static let photoFill = hex(0xEAF1F8)
    static let photoStroke = hex(0xE2E8F0)
    static let pageShadow = hex(0x1A1C2E)
    static let spotlight = hex(0x0B1A2E)
    static let contribution = hex(0xB42318)
    /// Bar segments in order; the fourth and later reuse the last.
    static let segments = [hex(0xFF9500), hex(0xF87541), hex(0xE5483B)]
    static let barTick = hex(0xE5483B)
    static let barTrack = hex(0xE9ECF1)
    static let barTrackHatch = hex(0xCFD5DD)
    static let footer = hex(0xF5F6FC)
    static let safeStroke = hex(0xE3E3E3)
    static let dangerTop = hex(0xBB1616)
    static let dangerBottom = hex(0xFF4F4F)
    static let change = hex(0x186FB9)
    static let scamIconFill = hex(0xFDECEA)
    static let scamIcon = hex(0xE5483B)
    static let safeIconFill = hex(0xE6F8EC)
    static let safeIcon = hex(0x34C759)
    // "Anda menandai ini aman" chip and the greyed AI badge (480:5780).
    static let markedFill = hex(0xEEF5FA)
    static let markedStroke = hex(0xC3DDEC)
    static let markedText = hex(0x1E78BE)
    static let greyBadgeFill = hex(0xF2F4F7)
    static let greyBadgeStroke = hex(0xDFE3E8)
    /// "Spotlight + kuning": several areas in one photo.
    static let marker = hex(0xFFD60A)

    static func hex(_ value: UInt32) -> Color { ActivityStyle.hex(value) }
}
