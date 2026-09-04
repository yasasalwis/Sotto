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

## 4. Review notes — the answer to the Guideline 2.1 information request

macOS 1.0 was rejected on 4 September 2026 under **Guideline 2.1 — Information Needed (New App
Submission)**. It is not a bug report: Apple asks every developer account with a limited review
history for a screen recording plus five written answers, and asks that the written answers also
live in the Notes field for future submissions.

The Notes field caps at **4,000 characters**, so the notes were rewritten to answer Apple's
questions in Apple's own numbering rather than to describe the app freely. Both platforms are
updated and saved in App Store Connect. Keep this file and the field in step.

The two texts differ only where the platform does: the macOS copy names the menu bar item, the
keyboard shortcuts and the compiled-out shell tool; the iOS copy says Airplane Mode and drops
those. Everything else is identical.

The source link is there deliberately. A 2.1 request goes to accounts App Review does not know
yet, and a public repository is the cheapest way for a reviewer to check the claims that matter
most here — no server, no analytics, inference on the device. It only works while the repository
stays public.

> Sotto is a free, offline-first AI chat app. No account, no server, no analytics, no ads and no
> in-app purchase of any kind. Answers to the Guideline 2.1 questions follow, numbered as asked.
>
> **2. PURPOSE AND AUDIENCE**
> Sotto runs a language model entirely on the device: ask questions, draft and rewrite text,
> summarise documents, get help with code. Mainstream AI chat apps send every message to a
> company's server; Sotto sends nothing. Inference happens on this Mac, so it works with the
> network off and a conversation never leaves the machine. For privacy-conscious general users,
> students, writers, developers, and anyone handling confidential material. Rated 18+ because
> model output is unfiltered.
>
> **3. SETTING UP AND REACHING THE MAIN FEATURES**
> No sign-in, no credentials, no sample files needed. Sotto uses either Apple's on-device model
> or an open-source model downloaded in the app.
> - If Apple Intelligence is on, click "Start with Apple Intelligence" on the welcome screen and
>   send a message. It answers on-device, with no download and no network.
> - If it is unavailable, the welcome screen says so and the button reads "Start chatting". Open
>   Model Library (Shift-Command-L),
>   download "Qwen2.5 0.5B Instruct" — 398 MB, the smallest entry and first in the list, about a
>   minute — then start a chat. Everything after the download works with the Mac offline.
>
> Elsewhere: Presets & Personas (Shift-Command-P) for system prompts, Compare Models
> (Shift-Command-K) for two models side by side, Tools (Shift-Command-T), and Settings › Privacy
> for a live count of the bytes the app has sent. Sotto also puts an item in the menu bar that
> hands a question to a chat; it keeps its Dock icon and its windows, `LSUIElement` is not set,
> and Command-Q quits.
>
> **4. EXTERNAL SERVICES**
> None for core functionality. Inference is Apple's FoundationModels framework plus the bundled
> llama.cpp library, both on-device. There is no authentication service, payment processor,
> analytics SDK, ad network or third-party AI API. The only outbound requests are:
> - `huggingface.co` — a model download the person starts, and an optional weekly catalogue check
>   that is off by default. Downloads are restricted in code to `https://huggingface.co`.
> - `googleapis.com/customsearch/v1` — an optional Google Programmable Search tool, inert until
>   the person supplies their own API key.
> - a URL the person writes themselves in the optional HTTPS-request tool.
>
> A downloaded `.gguf` file is model weights read as data by llama.cpp. Nothing downloaded is
> executed and the app's functionality does not change (guideline 2.5.2). The macOS
> shell-command tool is compiled out of App Store builds.
>
> **5. REGIONAL DIFFERENCES**
> None. The same features and content ship in all 175 regions — no geo-gating, no regional
> pricing, no region-specific content, and no server that could vary by region. The one variation
> is Apple's own: where Apple Intelligence is unavailable, the welcome screen says so and the
> person downloads a model instead.
>
> **6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL**
> Sotto is not in a regulated industry and offers no medical, legal or financial advice. It
> bundles and redistributes no model weights. The in-app catalogue links to each publisher's own
> files on Hugging Face and shows the publisher and licence for every entry (Apache-2.0, MIT,
> Llama 3.2 Community License, Gemma Terms of Use, Qwen Research License). The bundled llama.cpp
> inference library is MIT-licensed and is named in Settings › About.
>
> **GENERATED TEXT**
> Sotto does not filter or fact-check what a model produces, and says so on the welcome screen,
> on the empty chat screen and in Settings › About. The age rating reflects it. No content is
> shared between users, so there is nothing to report or block.
>
> **Privacy policy:** https://sotto.eonix.lk/privacy
> **Support:** https://sotto.eonix.lk/support
> **Source code:** https://github.com/yasasalwis/Sotto

### The welcome-screen button is named twice

`OnboardingView` line 63 (the Mac layout) labels the primary button
`appleAvailable ? "Start with Apple Intelligence" : "Start chatting"`. The compact layout used on
iOS (line 151) always says **Start chatting**.

So the macOS notes must say *Start with Apple Intelligence* for the Apple-Intelligence path — the
earlier wording sent a reviewer looking for a button that is not on screen when the feature is on,
which is the exact path the notes recommend. The iOS notes are correct as they stand. This was
caught by running the Release build rather than by reading the code, and it is worth re-checking
whenever the onboarding copy changes.

### Item 1 — the screen recording

Apple's first item is the one the Notes field cannot satisfy: **a screen recording made on a
physical device running the latest OS**, starting from app launch and showing the typical user
flow. It has to be attached to the Resolution Center reply, one per platform.

Sotto has no account, no user-generated content and nothing paid, so the three sub-cases Apple
lists do not apply — say so in the reply rather than leaving them unanswered. What the recording
must show, in order:

1. Launching the app from the Home Screen or Dock — not a build already running.
2. The welcome screen, including the generated-text notice.
3. Either sending a message to Apple's on-device model, or the Library download of
   Qwen2.5 0.5B Instruct followed by a chat. Show a real answer streaming in.
4. Enough of Personas, Compare, Tools and Settings › Privacy to make the feature set legible.

Keep it two to three minutes. On iOS, record with the built-in screen recorder on a physical
iPhone; the Simulator is not a physical device and Apple will say so. On macOS, record this Mac
with a Release build, not a Debug one — Debug compiles the shell tool in.

**The macOS recording is done** (`Sotto-macOS-demo.mp4`, 75 s, sent 4 September 2026). How it
was made, because the same recipe is what makes it safe to repeat:

- **Record against a throwaway container, never your own.** Copy the Release `.app`, change
  `CFBundleIdentifier` (e.g. `lk.eonix.sotto.rev2`), re-sign ad-hoc with the original
  entitlements (`codesign -d --entitlements :-` to extract them first). A new bundle id means a
  new container, so the recording shows a genuine first run and cannot touch real conversations
  or tool settings. A first attempt against the real container clicked a tool toggle by
  accident; this removes that whole class of mistake.
- **Drive by accessibility element, not by screen coordinates.** `click button 1 of group 1 of
  window 1` hits the onboarding button even when another window overlaps; a click at fixed
  coordinates hits whatever happens to be on top. Guard every keystroke with a check that Sotto
  is frontmost.
- **Turn tool calling off in the demo container** (`defaults write <id> toolsEnabled -bool
  false`). Otherwise the model may call *Search my chats*, the approval card appears, and the
  answer never arrives — the one thing the recording exists to show.
- **Crop to the window, do not trust a clean desktop.** Pin every Sotto window to a fixed rect,
  record the full screen, then `crop=2300:1760:720:140` in ffmpeg. The raw capture contained the
  Dock, the menu bar, a weather widget naming the city, desktop files and a Finder window. Trim
  the head with output seeking (`-i input -ss N`, not `-ss N -i input`, which snaps to a
  keyframe) so the first frame is already the settled welcome screen.
- **Check the result frame by frame before sending.** A 3×3 contact sheet
  (`fps=1/9,scale=600:-1,tile=3x3`) catches a stale error banner, a stalled answer or a leaked
  window in one look.

## 5. Things to weigh before you submit

Not blockers — decisions that are yours.

- **Deployment target is iOS 26.5 / macOS 26.5.** That is a very narrow device base for a 1.0.
  Nothing in App Review objects, but it decides who can install the app. Lowering it means
  checking the Foundation Models availability guards and re-testing.
- **Reviewers may not have Apple Intelligence enabled**, in which case the first thing they
  meet is a 398 MB download. The review notes above steer them to the smallest model; keeping
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

### Submitted

Both platforms went to App Review on 3 September 2026. macOS came back on 4 September under
Guideline 2.1; iOS has not been picked up yet.

| | iOS | macOS |
|---|---|---|
| Version | 1.0 | 1.0 |
| Build | 1.0 (3), from Xcode Cloud | 1.0 (3), from Xcode Cloud |
| Status | Waiting for Review | **Rejected — 2.1 Information Needed** |
| Submission ID | — | `a79f663e-ab9a-43c8-9904-d4be15e8cd7e` |

The macOS rejection was a request for information, not a defect: Apple asks accounts with a
limited review history for a screen recording and five written answers. Section 4 is that
answer, and both Notes fields in App Store Connect were rewritten to match on 4 September 2026.

**Answered and resubmitted on 4 September 2026 at 4:42 PM.** The Resolution Center reply
(3,998 of the 4,000 characters allowed) went out with `Sotto-macOS-demo.mp4` attached, the
version item flipped from Rejected to Accepted, and macOS 1.0 is **Waiting for Review** again on
the same build 1.0 (3) — no app code changed.

> App Store Connect warned that **build 4 was available** and offered to swap. Build 3 was kept:
> the only commits between them are `272ace9` (CI post-clone script) and `d7c558c` (this file),
> neither of which touches app code, and build 3 is what the iOS submission also carries.
> Submitting the same binary on both platforms keeps the two reviews comparable.

**iOS will almost certainly get the same request.** Its Notes field carries the same answers
already, which may pre-empt it; if it does not, attach an iPhone recording to that reply — and
that one cannot be produced from this Mac, because it needs a physical iPhone.

App Review contact on both: Yasas Alwis, +94769722082, yasaslive@gmail.com. Sign-in not
required. Release is set to **automatic** on approval — change it on the version page if you
would rather hold the launch.

### TestFlight feedback, and what it changed

The first TestFlight session on a physical iPhone 15 Pro (iOS 26.6.1, build 1.0 (3)) produced two
reports. Both were real, and both are fixed.

**"The chat and the send button is not viable and keyboards cannot hide."** `EmptyChatView` had a
fixed intrinsic height of roughly 460pt inside a `VStack` with `maxHeight: .infinity`. With the
keyboard up an iPhone leaves about 416pt, so the stack overflowed and pushed `ComposerView` off
the bottom of the screen — nothing to type into, and, because nothing on that screen scrolled, no
way to dismiss the keyboard either. The empty state is now a `ScrollView` that still centres its
content when it fits, carries `.scrollDismissesKeyboard(.interactively)`, and dismisses on a
background tap; the transcript got the same scroll-to-dismiss. Verified on an iPhone 17 simulator
with the software keyboard up: composer visible, send button reachable, swipe puts the keyboard
away.

**"Hide tool calls. Tools calls when general questions asked."** Asking "what is is LLM" made the
model call *Search my chats* and then *Unit converter* (`from: years, to: days`), which failed, so
the reply opened with "I apologize for the confusion." Two causes, two fixes:

- Every enabled tool's full `GenerationSchema` was written into the 4,096-token window up front, so
  the model was choosing from a menu already in front of it. `DynamicToolGateway` replaces that
  with a single `use_tool` dispatcher: the model sees one schema plus a list of names and one-line
  summaries, and has to name a tool deliberately to use it. Same quarter-of-the-window budget as
  before, but it now holds the **whole** library instead of about twenty tools — there is a test
  asserting exactly that. Settings › General › **Ask for tools by name** turns it off.
- The cards themselves are off by default now (**Show tool calls in chat**). A call that *failed*
  is still shown, because it is usually the reason the answer above it is wrong.

Neither change touches the macOS layout, and both are covered by unit tests in `ToolTests.swift`.

### TestFlight

Set up on 4 September 2026, prompted by the line in Apple's rejection under *Prevent Common
Issues*: "Apps are reviewed on physical devices to mirror real-world conditions… Use TestFlight
to distribute builds for beta testing on real devices."

| | |
|---|---|
| Group | **Internal Testers** (internal, automatic distribution on — this cannot be changed later) |
| Tester | `yasaslive@gmail.com`, the account holder — status **Invited** |
| Builds | iOS 1.0 (3), macOS 1.0 (3), plus iOS 1.0 (1) which automatic distribution picked up on its own |
| Test Information | Feedback email, privacy-policy URL and beta review contact filled; beta review notes mirror section 4 |

Internal testers need no Beta App Review, so the build is installable as soon as the invitation
is accepted. **Xcode Cloud builds are never distributed automatically** — the group's automatic
setting only covers builds uploaded from Xcode, which is why 1.0 (3) had to be added by hand on
each platform. Do the same for every future Xcode Cloud build.

The iOS build carries a **What to Test** note with the shot list for the App Review recording,
so the instructions travel with the build instead of living only in this file.

> **Record build 3, not build 1.** Build 1 is an old upload that automatic distribution added;
> it is not what is under review. TestFlight offers the newest build first, so this only matters
> if someone scrolls back.

### Xcode Cloud

Workflow **Default** builds `main` from `github.com/yasasalwis/Sotto`, with two actions,
Archive - iOS and Archive - macOS. Two things had to be fixed before it produced a usable
build, and both will bite again if they are undone:

1. **`ci_scripts/ci_post_clone.sh`** vendors llama.cpp. `Packages/LlamaKit/llama.xcframework`
   is git-ignored, so a fresh clone has nothing behind LlamaKit's `llama` binary target and
   package resolution fails with *"does not contain a binary artifact"*. It passes `--no-sim`,
   which is correct only while the workflow has no Simulator test action.
2. **Distribution Preparation = App Store Connect** on both archive actions. It defaults to
   *None*, which produces a green build whose archive never reaches App Store Connect — the
   build looks fine and no build ever appears on the version page.

### Still outstanding

- [ ] The screen recording Apple asked for under Guideline 2.1 — one per platform, made on a
      physical device. See section 4, "Item 1 — the screen recording". The Resolution Center
      reply is written and saved as a draft; it needs the recording attached before it is sent.
- [ ] If review comes back asking about the age rating, the answers behind the 18+ override
      are recorded in section 3.

### Closed

- [x] **`AppLinks.sourceCode`** — `https://github.com/yasasalwis/Sotto` was private, so the
      "Source" link in Settings › About returned 404 for every user. The repository was made
      public on 4 September 2026; the URL now answers 200 unauthenticated. Nothing in the code
      changed. **If the repository is ever made private again, this link breaks in the shipped
      build** — change `Sotto/Domain/AppLinks.swift` at the same time.
