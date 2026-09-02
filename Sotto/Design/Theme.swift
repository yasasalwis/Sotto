import SwiftUI

/// Design tokens transcribed from the Sotto design document. The palette is a single
/// light theme by design; every colour in the app must come from here.
enum Theme {
    enum Colors {
        static let ink = Color(hex: 0x171A19)
        static let text = Color(hex: 0x262A27)
        static let textSecondary = Color(hex: 0x41453F)
        static let muted = Color(hex: 0x5E625F)
        static let mutedLight = Color(hex: 0x7A7E7A)
        static let hint = Color(hex: 0x8A8E88)
        static let faint = Color(hex: 0x9A9E98)
        static let placeholder = Color(hex: 0xA2A6A0)
        static let disabledText = Color(hex: 0xB4B8B2)

        static let accent = Color(hex: 0x1F6B63)
        static let accentDark = Color(hex: 0x14403C)
        static let accentSoft = Color(hex: 0xDDE8E5)
        static let accentTint = Color(hex: 0xE4EAE8)
        static let accentPale = Color(hex: 0xF2F6F5)
        static let accentBackground = Color(hex: 0xF7FAF9)

        static let canvas = Color(hex: 0xE9E9E5)
        static let sidebar = Color(hex: 0xF4F5F3)
        static let panel = Color(hex: 0xFAFAF8)
        static let chrome = Color(hex: 0xF7F7F5)
        static let surface = Color.white
        static let surfaceMuted = Color(hex: 0xF2F3F1)
        static let surfaceWarm = Color(hex: 0xFCFCFA)

        static let border = Color(hex: 0xEAEAE6)
        static let borderMedium = Color(hex: 0xE3E3DE)
        static let borderStrong = Color(hex: 0xDDDDD8)
        static let borderSidebar = Color(hex: 0xE7E7E2)
        static let hairline = Color(hex: 0xF0F0EC)
        static let hairlineSoft = Color(hex: 0xF2F2EE)
        static let hairlinePanel = Color(hex: 0xEFEFEA)
        static let track = Color(hex: 0xE0E0DB)

        static let sendDisabledBackground = Color(hex: 0xDFE5E3)
        static let sendDisabledForeground = Color(hex: 0x8FA8A3)
        static let barLow = Color(hex: 0xCFDCD9)
        static let barMid = Color(hex: 0x9CBBB5)
        static let dotDim = Color(hex: 0xD6D6D0)

        static let danger = Color(hex: 0xB0483C)
        static let dangerBorder = Color(hex: 0xE8CFCB)
    }

    enum Fonts {
        static let sansFamily = "Geist"
        static let monoRegular = "IBMPlexMono"
        static let monoMedium = "IBMPlexMono-Medium"

        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.custom(sansFamily, size: size).weight(weight)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            let name = weight == .regular ? monoRegular : monoMedium
            return Font.custom(name, size: size)
        }
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 11
        static let cardLarge: CGFloat = 12
        static let composer: CGFloat = 14
        static let bubble: CGFloat = 14
        static let sheet: CGFloat = 26
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let page: CGFloat = 44
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 252
        static let sidebarCompactWidth: CGFloat = 212
        static let inspectorWidth: CGFloat = 274
        static let toolbarHeight: CGFloat = 52
        static let minimumWindowWidth: CGFloat = 900
        static let minimumWindowHeight: CGFloat = 600
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
