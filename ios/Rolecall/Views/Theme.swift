import SwiftUI

/// The visual system. Warm paper ground, near-black warm ink, one restrained clay accent
/// used only for the primary action. Everything scales with Dynamic Type; nothing is a
/// fixed point size that would clip at the accessibility sizes.
enum Theme {

    enum Palette {
        static let paper = Color("Paper")
        static let surface = Color("Surface")
        static let surfaceRaised = Color("SurfaceRaised")
        static let ink = Color("Ink")
        static let inkSecondary = Color("InkSecondary")
        static let inkTertiary = Color("InkTertiary")
        static let hairline = Color("Hairline")
        static let verified = Color("VerifiedText")
        static let caution = Color("CautionText")
        static let accent = Color("AccentColor")
    }

    enum Metric {
        static let gutter: CGFloat = 20
        static let rowSpacing: CGFloat = 4
        static let cardRadius: CGFloat = 16
        static let sectionGap: CGFloat = 28
        /// The board and the role page hold to a single readable column, centred on the
        /// paper ground. A no-op on iPhone (narrower than this); on iPad it keeps the app
        /// from reading as a stretched phone.
        static let readingWidth: CGFloat = 700
    }
}

extension View {
    /// Clamp content to `Theme.Metric.readingWidth` and centre it. Apply to the scrolling
    /// column, not the background.
    func rolecallReadingColumn() -> some View {
        frame(maxWidth: Theme.Metric.readingWidth)
            .frame(maxWidth: .infinity)
    }

    /// Scroll indicators, hidden only for App Store screenshot capture (a launch arg the
    /// shipping app is never launched with) so a mid-fade scroll bar can't land in a frame.
    func rolecallScrollIndicators() -> some View {
        let capturing = ProcessInfo.processInfo.arguments.contains("-uitest-seed")
        return scrollIndicators(capturing ? .hidden : .automatic)
    }
}

/// A serif face for the display line gives the board an editorial voice without any
/// bundled font. Falls back cleanly if the system serif is unavailable.
extension Font {
    static func rolecallDisplay(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
    static func rolecallTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .serif)
    }
}

extension View {
    /// Standard page ground.
    func rolecallBackground() -> some View {
        background(Theme.Palette.paper.ignoresSafeArea())
    }
}
