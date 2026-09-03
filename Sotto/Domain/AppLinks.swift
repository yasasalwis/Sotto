import Foundation

/// The public pages App Review and the App Store listing point at, in one place so the
/// in-app links, the store listing and the review notes cannot drift apart.
///
/// The privacy policy and support pages live on sotto.eonix.lk; the source stays on GitHub.
/// Replace these if the pages move again — nothing else in the app hard-codes a URL.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://sotto.eonix.lk/privacy")!
    static let support = URL(string: "https://sotto.eonix.lk/support")!
    static let sourceCode = URL(string: "https://github.com/yasasalwis/Sotto")!

    /// Shown wherever a person first meets generated text. Sotto runs models on the device and
    /// does not review, filter or fact-check what they produce, and saying so plainly is both
    /// honest and what App Review expects of an app that generates text.
    static let generatedContentNotice = """
        Sotto runs language models on this device. They invent things, get facts wrong, and can \
        produce text you did not want. Nothing they write is checked by anyone. Treat an answer \
        as a draft and verify anything that matters.
        """

    /// The one-line form, for places with no room for the paragraph.
    static let generatedContentNoticeShort = "Models make things up. Check anything that matters."
}
