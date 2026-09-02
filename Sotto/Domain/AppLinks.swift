import Foundation

/// The public pages App Review and the App Store listing point at, in one place so the
/// in-app links, the store listing and the review notes cannot drift apart.
///
/// Replace these with your own domain if you move the pages off GitHub; nothing else in the
/// app hard-codes a URL.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/yasasalwis/Sotto/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/yasasalwis/Sotto/blob/main/SUPPORT.md")!
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
