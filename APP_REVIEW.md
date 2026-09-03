# App Store submission checklist

Everything App Review needs, and every App Store Connect answer, in one place. Sotto is
**free**: no in-app purchases, no subscription, no ads, no paid tier. Nothing in the app or
the listing should suggest otherwise.

Work through this top to bottom for each submission.

---

## 1. In the repository — done

These are in the code and need no further action. They are listed so a later change does not
quietly undo one.

| Item | Where |
|---|---|
| App icon, iOS (light / dark / tinted, 1024², opaque, no alpha) | `Sotto/Assets.xcassets/AppIcon.appiconset` |
| App icon, macOS (16–512 @1x/2x, rounded, with alpha) | same |
| Icon is regenerable from the in-app mark | `Scripts/make-app-icon.swift` |
| Privacy manifest declaring UserDefaults, disk space and file-timestamp reasons | `Sotto/PrivacyInfo.xcprivacy` |
| `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt per upload) | `Sotto/Info.plist` |
| `LSSupportsOpeningDocumentsInPlace = true` (a multi-GB GGUF is not copied to Inbox first) | `Sotto/Info.plist` |
| `NSFaceIDUsageDescription` | `Sotto/Info.plist` |
| No unused push / CloudKit entitlements | the stray `Sotto.entitlements` was deleted; sandbox and network come from build settings |
| Sandbox grants read **and write** on user-chosen files | `ENABLE_USER_SELECTED_FILES = readwrite` in the project. Settings › Privacy › Export writes to the file the save panel returns, and a read-only grant lets the panel choose a destination and then refuses the write |
| Generated-text notice in onboarding, the empty chat and Settings › About | `AppLinks.generatedContentNotice` |
| Privacy-policy, support and source links in Settings › About | `Sotto/Domain/AppLinks.swift` |
| Shell tool compiled out of App Store builds (guideline 2.5.2) | `ToolKind.shellToolIsCompiledIn` |
| Model download host pinned to `huggingface.co` at runtime | `ModelCatalog.validate()` |
| Menu bar item is a normal `MenuBarExtra`, not a background-only app | `SottoApp`; `LSUIElement` is deliberately unset, so Sotto keeps its Dock icon and windows |

> **`AppLinks` points at `sotto.eonix.lk` for the privacy policy and support pages, and at
> GitHub for the source.** If a page moves, change `Sotto/Domain/AppLinks.swift` and the URLs
> in App Store Connect together.

### The shell tool

The macOS "Shell command" tool is **not** in App Store builds. Guideline 2.5.2 does not allow
an app to execute code that introduces or changes its functionality, and under App Sandbox the
command would be confined to Sotto's own container anyway, so it could not do what it
advertises.

It is compiled in only when `SOTTO_SHELL_TOOL` is defined, which the Debug configuration does.
To ship a Developer ID build outside the store with the tool present, add `SOTTO_SHELL_TOOL`
to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the Release configuration for that build only.
Never add it to a build destined for App Store Connect.

---

## 2. Before you archive

- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Sotto target.
      `CURRENT_PROJECT_VERSION` must increase on every upload, even a rejected one.
- [ ] `Scripts/fetch-llama.sh` has been run in this checkout.
- [ ] `xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=macOS,arch=arm64' test` is green.
      Run the whole scheme, not `-only-testing:SottoTests`. `SottoUITests` covers the sandboxed
      export, and CI cannot: it builds with `CODE_SIGNING_ALLOWED=NO`, so no entitlements are
      applied and a sandbox fault is invisible there.
- [ ] `xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=iOS Simulator,name=iPhone 17' test` is green.
- [ ] `cd Packages/LlamaKit && swift test` is green.
- [ ] Product › Archive for iOS, then for macOS. Archive from the **Release** configuration —
      Debug would ship the shell tool.
- [ ] In the Organizer, **Validate App** before Distribute. Validation catches a missing icon,
      a bad privacy manifest and an entitlement mismatch before review does.

---

## 3. App Store Connect answers

### Pricing

**Free.** No in-app purchases. Do not create any IAP records — an app with no purchase code
and an IAP record configured is a rejection.

### Privacy — "App Privacy" section

Answer: **Data Not Collected**.

That is accurate. Sotto has no account, no server, no analytics and no third-party SDK that
transmits anything. Conversations, models, personas and preferences stay in the app container.
Tool API keys stay in the keychain.

- **Does your app collect data?** → **No**
- **Tracking** → **No**. Sotto does not track, does not use an advertising identifier and does
  not share data with data brokers.
- **Privacy policy URL** → `https://sotto.eonix.lk/privacy`
  (kept in step with `AppLinks.privacyPolicy`).

> A model download and the optional catalog check contact `huggingface.co`, and the optional
> search tool contacts Google under the person's own API key. None of that is data *you*
> collect, so it does not change the answer — but it is described in the privacy policy and in
> the review notes below, which is what matters.

### Age rating

Sotto runs open-weight models that no one filters, so it can produce mature language and
themes on request. **Answer the questionnaire honestly; do not claim the app filters
content, because it does not.** Realistic answers put Sotto at the adult rating (17+ / 18+).

Two judgement calls worth making deliberately:

- **Unrestricted web access** — Sotto has no embedded browser. The optional Google search tool
  returns titles, snippets and links, is off by default, and needs the person's own API key.
  Decide and be consistent; if in doubt, answering yes costs nothing but the rating you are
  already taking.
- **AI-generated content** — declare it. The app's whole purpose is generating text.

Getting this wrong is a common rejection under guideline 2.3.6 and a common removal later.

### Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in the Info.plist, so the per-upload prompt is
gone. This is correct: Sotto uses only the system's HTTPS/TLS and the system keychain, both
exempt.

The **Hash text** tool computes SHA-256/384/512 through CryptoKit. That does not change the
answer — a hash is a one-way digest, not encryption; nothing is enciphered and nothing can be
recovered — and the implementation is the system's, not Sotto's. Adding cryptography that
*enciphers* data, on the other hand, would mean revisiting this key.

### Content rights

Sotto does not bundle or redistribute any model weights. The catalog lists models and links to
the publisher's own files on Hugging Face; the person downloads directly from the publisher,
and each entry shows its publisher and licence in the app.

Note for your own records, not the reviewer's: **Qwen2.5 3B** and **Qwen2.5 Coder 3B** are
under the Qwen Research License, and **Gemma 2 2B** is under the Gemma Terms of Use. Both carry
use restrictions. Sotto linking to them is fine; redistributing them inside the app would not
be. Do not add weights to the app bundle.

### App Review Information

- Sign-in required: **No**.
- Demo account: none needed.
- Contact: your own email and phone.
- **Notes:** use the text in section 4.

### Listing copy

- [ ] The description says the app is free and does not mention any price, tier or upgrade.
- [ ] The description does not promise the app filters or verifies model output.
- [ ] Screenshots are from the real app at required sizes, with no placeholder content.
- [ ] Support URL → `https://sotto.eonix.lk/support` (kept in step with `AppLinks.support`).

---

## 4. Review notes — paste into App Review Information

> Sotto is a free, offline-first chat app. There is no account, no server, no analytics and no
> in-app purchase of any kind.
>
> **How to test it in under a minute.** Sotto can use Apple's on-device model or an
> open-source model you download in the app.
>
> - If the review device has Apple Intelligence enabled, tap **Start chatting** on the welcome
>   screen and send a message. It answers on-device with no download and no network.
> - If Apple Intelligence is not available on the review device, the welcome screen says so.
>   Open **Library**, download **Qwen2.5 0.5B Instruct** (approximately 380 MB, the smallest
>   entry, roughly a minute on a good connection), then start a chat. Everything after the
>   download works with the device offline.
>
> **Network use.** Inference always runs on the device; nothing typed into a chat is
> transmitted. The only outbound requests are: a model download the person starts, an optional
> weekly check of the model catalog (off by default), and optional tools the person configures
> themselves. Settings › Privacy shows a live count of the bytes the app has actually sent.
>
> **Downloaded files are data, not code.** A `.gguf` file is a set of model weights read by the
> bundled llama.cpp inference library. Nothing downloaded is executed, and the app's
> functionality does not change based on what is downloaded. Downloads are restricted in code
> to `https://huggingface.co`.
>
> **Generated text.** Sotto runs models locally and does not filter or fact-check their output.
> The app says so on the welcome screen, on the empty chat screen and in Settings › About, and
> the age rating reflects it.
>
> **Tools.** Sotto has twenty-five built-in tools, every one of which runs on the device and
> touches nothing outside the app. Four are on out of the box: date and time, a calculator,
> a unit converter, and a search of the person's own past chats. The other twenty-one are
> switched off until the person turns them on, because Apple's on-device model has a fixed
> context window and every offered tool spends part of it. Tools that use the network — a
> Google search, or an HTTPS request the person defines — are switched off until the person
> supplies their own credentials, and ask for approval before each call.
>
> **Menu bar (macOS).** Sotto puts an item in the menu bar: a field that hands a question to a
> chat in the main window, the five most recent chats, and shortcuts to the other windows.
> Because that item needs an app behind it, closing the last window leaves Sotto running
> instead of quitting; ⌘Q, the panel's own **Quit Sotto** and the Dock's Quit all quit it, and
> turning **Show in menu bar** off in Settings › General restores quit-on-close. Sotto is not a
> background-only app: it keeps its Dock icon and its windows, and `LSUIElement` is not set.
>
> **Privacy policy:** https://sotto.eonix.lk/privacy
> **Support:** https://sotto.eonix.lk/support

---

## 5. Things to weigh before you submit

Not blockers — decisions that are yours.

- **Deployment target is iOS 26.5 / macOS 26.5.** That is a very narrow device base for a 1.0.
  Nothing in App Review objects, but it decides who can install the app. Lowering it means
  checking the Foundation Models availability guards and re-testing.
- **Reviewers may not have Apple Intelligence enabled**, in which case the first thing they
  meet is a 380 MB download. The review notes above steer them to the smallest model; keeping
  that entry in the catalog and first in the list is worth doing deliberately.
- **`DEVELOPMENT_TEAM` is hard-coded** in the project (`835LNLUPAJ`). Fine for you, worth
  knowing if anyone else ever builds this.

---

## 6. After approval

- Tag the commit `vX.Y.Z` (see [RUNBOOK.md](RUNBOOK.md)).
- Keep `PRIVACY.md`, the page served at `https://sotto.eonix.lk/privacy`, `SUPPORT.md` and the
  App Store Connect URLs in step. A privacy policy URL that 404s is grounds for removal.

---

## 7. App Store Connect — what is already filled in

Recorded 3 September 2026. Values live in App Store Connect; this section is a mirror so a
later change can be spotted.

| Field | Value |
|---|---|
| Apple ID | `6808138863` |
| Bundle ID | `lk.eonix.sotto` (App ID registered on the developer portal as "Sotto") |
| Listing name | `Sotto – On Device AI` (en dash; plain "Sotto" is taken on the App Store) |
| Subtitle | `Private AI that runs offline` |
| SKU | `sotto-001` |
| Platforms | iOS + macOS, one record |
| Category | Productivity (primary), Utilities (secondary) |
| Content rights | Contains/accesses third-party content, rights held — the catalog links to publishers' own weights |
| Price | Free, all 175 countries or regions |
| App Privacy | **Data Not Collected**, published. Privacy policy URL set |
| Age rating | Calculated 13+, **overridden to 18+** (19+ Brazil and Korea; 17+ on OS earlier than 26) |
| Sign-in required | No, on both platforms |
| Screenshots | iPhone 6.9" ×4, iPad 13" ×3, Mac ×5 — all from the real app |
| Review notes | Section 4 of this file, pasted into both platforms |

> The app's own name on the device is still **Sotto** — `CFBundleDisplayName` is untouched.
> Only the store listing carries the longer name.

### Still outstanding before Submit for Review

- [ ] **Upload a build.** Both archives validate locally but nothing is uploaded yet. Needs an
      Apple Distribution certificate; Xcode creates one on first App Store export.
- [ ] **App Review contact** — first name, last name, phone and email, on both the iOS and the
      macOS version page. Required to submit.
- [ ] **`AppLinks.sourceCode`** points at `https://github.com/yasasalwis/Sotto`, which returns
      404. It is a live link in Settings › About, so it 404s for users. Make the repository
      public, point it elsewhere, or drop the link.
