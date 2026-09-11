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
| Data-flow disclosure inside the app: the approval card names the host and what is sent before a networked tool runs; Settings › Privacy › "Where your data goes" lists every destination (guidelines 5.1.1(i) / 5.1.2(i)) | `Sotto/Engines/Tools/ToolDisclosure.swift`, `PrivacyPane.dataFlowGroup` in `SettingsView.swift` |

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
      > Those three UI tests were failing for a while, and it was not the app. The main
      > `WindowGroup` carries `.handlesExternalEvents(matching: ["*"])`, so SwiftUI waits for an
      > external event before making a window; XCUITest execs the binary and sends none, so the app
      > came up with a menu bar and nothing else. Finder, the Dock, Spotlight and `open` all send
      > that event, so no launch a user or a reviewer can perform is affected — proved by
      > `open -n Sotto.app` giving a window and `./Sotto.app/Contents/MacOS/Sotto` giving none.
      > `SottoMacAppDelegate` now re-opens its own bundle when launched with `-uiTesting YES`,
      > which the tests pass; the whole thing is inside `#if DEBUG`, so Release is untouched. If
      > these three start timing out again, check that argument before suspecting the app.
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

**Guidelines 5.1.1(i) and 5.1.2(i), raised on 8 September 2026.** App Review read the app as
sharing personal data with a third-party AI service. It does not: there is no AI API, SDK or
server, and inference is Apple's on-device model or llama.cpp on the device. The rejection
carries its own instruction for that case — *"If the app does not send user data to a
third-party AI service… reply to this rejection to confirm and add this information to the App
Review Information section"* — and both are done: the Notes field in section 4 now opens with
**THIRD-PARTY AI SERVICES: NONE**, and the reply in section 7 says the same. The app also says
it in three places, so a second reviewer cannot form the same impression from the screens:
the approval card before any networked tool names the host and what is sent, Settings › Privacy
has a **Where your data goes** section, and the catalogue footer says a downloaded model runs
on the device. See [iOS rejected on build 1.0 (16)](#ios-rejected-on-build-10-16-8-september-2026).

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
- **Health or Wellness Topics — Yes.** Required by App Review on 8 September 2026 under
  guideline 2.3.6: a general-purpose model will discuss health and wellness if asked, so the
  rating has to say so. It is set on the **App Information** page (Age Rating › Edit), not on
  the version page, and it does not move the rating — the 18+ override stays. The in-app
  notice, the privacy policy and the review notes now all say model output is not medical,
  legal or financial advice, so the four agree.

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

macOS 1.0 was rejected on 4 September 2026, and **iOS 1.0 on 6 September 2026**, both under
**Guideline 2.1 — Information Needed (New App Submission)**, with the same template. It is not a
bug report: Apple asks every developer account with a limited review history for a screen
recording plus five written answers, and asks that the written answers also live in the Notes
field for future submissions.

> **The Notes field alone does not clear a 2.1 request.** iOS carried the answers below in its
> Notes field from 4 September and was rejected anyway. Item 1 — a recording made on a physical
> device, attached to the Resolution Center reply — is the item that closes it, and there is no
> field in App Store Connect that can stand in for it. See
> [Item 1 — the screen recording](#item-1--the-screen-recording) and, for iOS,
> [The iOS answer, 6 September 2026](#the-ios-answer-6-september-2026).

The Notes field caps at **4,000 characters**, so the notes were rewritten to answer Apple's
questions in Apple's own numbering rather than to describe the app freely. Both platforms are
updated and saved in App Store Connect. Keep this file and the field in step.

The two texts differ only where the platform does: the macOS copy names the menu bar item, the
keyboard shortcuts and the compiled-out shell tool; the iOS copy says Airplane Mode and drops
those. Everything else is identical.

> **The macOS field needs the THIRD-PARTY AI SERVICES paragraph too**, added below on
> 11 September 2026 after the iOS rejection. The macOS text was never counted in this file;
> check the 4,000 cap in App Store Connect when pasting and trim section 3 first if it is over.

The source link is there deliberately. A 2.1 request goes to accounts App Review does not know
yet, and a public repository is the cheapest way for a reviewer to check the claims that matter
most here — no server, no analytics, inference on the device. It only works while the repository
stays public.

> Sotto is a free, offline-first AI chat app. No account, no server, no analytics, no ads and no
> in-app purchase of any kind. Answers to the Guideline 2.1 questions follow, numbered as asked.
>
> **THIRD-PARTY AI SERVICES: NONE.** Sotto does not send user data to any third-party AI service
> and contains no AI API, SDK or server. Inference is Apple's FoundationModels framework (the
> on-device model) and the bundled llama.cpp library, both on the device. The catalogue names
> Meta, Google, Microsoft, Alibaba and Mistral AI because their open-weight files are what a
> person downloads; those files are read as data on the device and none of those companies
> receives anything. Settings › Privacy › "Where your data goes" states this in the app.
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

### The iOS answer, 6 September 2026

iOS 1.0 came back on 6 September under the same 2.1 template, on build 1.0 (11), with the answers
already sitting in its Notes field. Nothing in the notes was wrong; the request was for the
recording, which no field can hold. Two things go back this time: the recording, and a build with
two real defects fixed.

**The defects, both found by driving the app rather than by reading it.** Neither shows up in a
unit test, and either one could have turned an information request into a bugs-and-crashes
rejection.

1. **"Import a model instead" on the welcome screen did nothing on iOS.** `RootView` carried a
   `.fileImporter` for `state.isImportingModel`, and `OnboardingView`, a direct descendant,
   carried its own. On iOS a `.fileImporter` is a sheet presentation, and two of them in one
   ancestor→descendant chain do not both work — the outer claimed the slot and the inner never
   presented. The root importer was dead weight there anyway: both of its triggers, the Models
   menu (⇧⌘I) and Settings › Models, are `#if os(macOS)`. It is now macOS-only. Model Library's
   importer was never affected, because it lives inside a presented sheet, which is its own
   presentation context — and that difference is what identified the cause.
2. **Raw `<tool_response>` markup reached the transcript.** The GGUF system prompt tells the model
   its results come back inside those tags, and `GGUFEngine` feeds them that way, so a small model
   writes the wrapper itself. `ToolCallScanner` stripped `<tool_call>` and nothing else, so the
   echo streamed straight through. It now swallows `<tool_response>` blocks, a stray closing tag,
   and holds back a partial tag across chunks (`<tool_` is the shared prefix of both, so a
   hold-back sized for `<tool_call>` alone leaked the other one a chunk at a time). Apple's engine
   got the same treatment through `ToolCallScanner.strippingEchoedResponses`: it calls tools
   natively and is never shown these tags, but it streams a growing snapshot straight to the
   transcript with nothing in between, and a 3B model can still write a convention it met in
   pretraining. Twelve tests cover both shapes.

Verified in the running app on an iPhone 17 simulator, iOS 26.5: the welcome-screen button opens
the Files picker, a picked file imports (a deliberately malformed one raises "…is not a readable
GGUF file" in onboarding's own alert, which proves the whole presentation chain works); Apple
Intelligence answered "What time is it right now?" through the date tool in 3.2 s at 63 tok/s;
Qwen2.5 0.5B downloaded from the catalogue (397,808,192 bytes, matching the manifest), loaded, and
answered through the same tool in 5.2 s at 75 tok/s — no protocol markup in either transcript.

**Navigation on iOS is not the Mac's, and the notes must say so.** There are no keyboard
shortcuts. The **⋯ button at the top right of a chat** is the way in to Change model, Persona,
Compare two models, New chat, Model library, Personas, Tools and Settings; the **☰ button at the
top left** opens the chat list, which itself carries Model library and Settings at its foot. The
earlier iOS notes inherited "(⇧⌘L)", "(⇧⌘P)", "(⇧⌘K)" and "(⇧⌘T)" from the Mac copy — the same
class of mistake as the welcome-button wording above, and it sends a reviewer looking for
something that is not there.

#### iOS Notes field (3,972 characters; App Store Connect counted the 3,990-character draft as 7 over)

Rewritten on 11 September 2026 for the 8 September rejection: it opens with the third-party AI
answer, declares the health topic, and names the approval card. Paste it over what is in App
Store Connect.

> Sotto is a free, offline-first AI chat app. No account, no server, no analytics, no ads and no in-app purchase of any kind. Guideline 2.1 answers follow, numbered as asked.
>
> THIRD-PARTY AI SERVICES: NONE. Sotto does not send user data to any third-party AI service and contains no AI API, SDK or server. Inference is Apple's FoundationModels framework (the on-device model) and the bundled llama.cpp library, both on the device. The catalogue names Meta, Google, Microsoft, Alibaba and Mistral AI because their open-weight files are what a person downloads; those files are read as data on the device and none of those companies receives anything. Settings > Privacy > "Where your data goes" states this in the app.
>
> 2. PURPOSE AND AUDIENCE
> Sotto runs a language model entirely on the device: ask questions, draft and rewrite text, summarise documents, get help with code. Inference happens on this iPhone, so it works in Airplane Mode and a conversation never leaves the device. For privacy-conscious general users, students, writers and developers. Rated 18+ because model output is unfiltered; Health or Wellness Topics is declared because a general model will discuss them if asked.
>
> 3. SETTING UP AND REACHING THE MAIN FEATURES
> No sign-in, no credentials, no sample files needed. The welcome screen's main button reads "Start chatting". Tap it, type a message, send. With Apple Intelligence on, it answers on-device with no download and no network.
> If Apple Intelligence is unavailable, the "Apple Intelligence" card on the welcome screen says why. Tap Start chatting, then the ... button at the top right of the chat > Model library > + > Browse catalog > "Qwen2.5 0.5B Instruct" (398 MB, first in the list) > Download. Then ... > Change model... > Qwen2.5 0.5B Instruct. Everything after that download works in Airplane Mode.
> That same ... button opens Personas, Tools, Compare two models, Model library and Settings; the menu button at the top left opens the chat list. Settings > Privacy shows where each kind of data goes and a live count of the bytes the app has sent.
>
> 4. EXTERNAL SERVICES
> None for core functionality. There is no authentication service, payment processor, analytics SDK, ad network or third-party AI API. The only outbound requests, each started by the person:
> - huggingface.co - a model download, and an optional weekly catalogue check that ships off. Restricted in code to https://huggingface.co.
> - googleapis.com/customsearch/v1 - an optional Google Programmable Search tool, off until the person supplies their own API key. Only the search words the model chose are sent; a card names Google and asks first.
> - a URL the person writes themselves in the optional HTTPS-request tool; the card names the host and asks first.
> A downloaded .gguf file is model weights read as data by llama.cpp. Nothing downloaded is executed and the app's functionality does not change (guideline 2.5.2).
>
> 5. REGIONAL DIFFERENCES
> None. The same features and content ship in all 175 regions: no geo-gating, regional pricing, region-specific content, or server that could vary by region. Where Apple Intelligence is unavailable, the welcome screen says so and the person downloads a model instead.
>
> 6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
> Sotto is not in a regulated industry and provides no medical, legal or financial advice as a feature; the in-app notice says model output is none of those. It redistributes no model weights: the catalogue links to each publisher's own files on Hugging Face and shows the publisher and licence for every entry. The bundled llama.cpp library is MIT-licensed and named in Settings > About.
>
> GENERATED TEXT
> Sotto does not filter or fact-check model output, and says so on the welcome screen, the empty chat and Settings > About. Nothing is shared between users, so there is nothing to report or block.
>
> Privacy policy: https://sotto.eonix.lk/privacy
> Support: https://sotto.eonix.lk/support
> Source code: https://github.com/yasasalwis/Sotto

#### iOS Resolution Center reply (3977 of 4,000 characters)

Attach the iPhone recording to this. It claims a build with both fixes in it, so send it only
against that build.

> Thank you for the review. The recording is attached and the answers follow, numbered as asked; they are also in the App Review Information notes now.
>
> Our testing on a physical iPhone since the last build found two defects, both fixed in the build attached here: "Import a model instead" on the welcome screen did not open the file picker, and a model could print raw <tool_response> markup into a reply.
>
> 1. SCREEN RECORDING
> Attached, captured on a physical iPhone running the current public iOS release. It begins by launching the app from the Home Screen, then follows the typical flow: welcome screen, first message answered on-device, model library and catalogue, personas, tools, privacy page. The three cases you list do not apply, but rather than leave them unanswered:
> - Registration, login, deletion: Sotto has no accounts - no sign-up, sign-in, profile or server - so there is nothing to register, log into or delete.
> - User-generated content: nothing written is uploaded, published or visible to anyone else; conversations stay in the app's container on the device. No content reaches another user, so there is nothing to report or block.
> - Paid content: the app is free in full - no in-app purchases, subscription, ads or paid tier.
>
> 2. PURPOSE AND AUDIENCE
> Sotto runs a language model entirely on the device: ask questions, draft and rewrite text, summarise documents, get help with code. Other AI chat apps send every message to a server; Sotto sends nothing. Inference happens on the iPhone, so it works in Airplane Mode and a conversation never leaves the device. For privacy-conscious general users, students, writers, developers, and anyone handling confidential material. Rated 18+ because model output is unfiltered.
>
> 3. SETTING UP AND REACHING THE MAIN FEATURES
> No sign-in, credentials or sample files are needed. The welcome screen's main button reads "Start chatting": tap it, type a message, send. With Apple Intelligence on, it answers on-device with no download and no network. If Apple Intelligence is unavailable the welcome screen says why; tap Start chatting, then the "..." button at the top right of the chat > Model library > + > Browse catalog > "Qwen2.5 0.5B Instruct" (398 MB, first in the list) > Download, then "..." > Change model. That same "..." button opens Personas, Tools, Compare two models and Settings; Settings > Privacy counts the bytes the app has sent.
>
> 4. EXTERNAL SERVICES
> None for core functionality. Inference is Apple's FoundationModels framework plus the bundled llama.cpp library, both on-device. There is no authentication service, payment processor, analytics SDK, ad network or third-party AI API. The only outbound requests are: huggingface.co, for a model download the person starts and an optional weekly catalogue check that ships off, restricted in code to huggingface.co; googleapis.com/customsearch/v1, an optional Google Programmable Search tool inert until the person supplies their own API key; and a URL the person writes in the optional HTTPS-request tool. A downloaded .gguf file is weights read as data by llama.cpp: nothing downloaded is executed and the app's functionality does not change (guideline 2.5.2).
>
> 5. REGIONAL DIFFERENCES
> None - the app functions consistently across all regions. No geo-gating, regional pricing, region-specific content, or server that could vary by region. The only variation is Apple's own: where Apple Intelligence is unavailable, the person downloads a model instead.
>
> 6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
> Sotto is not in a regulated industry and gives no medical, legal or financial advice. It redistributes no model weights: the catalogue links to each publisher's own files on Hugging Face and shows the publisher and licence for every entry (Apache-2.0, MIT, Llama 3.2 Community License, Gemma Terms of Use, Qwen Research License). The bundled llama.cpp library is MIT-licensed and named in Settings > About. Source: https://github.com/yasasalwis/Sotto

#### Shot list for the iPhone recording

Only this needs a physical iPhone; everything else above is done. Two to three minutes.

Before recording:
- Install the **new** TestFlight build — the one with the two fixes, not 1.0 (11).
- **Delete the app first** so the recording opens on a genuine first run. This also deletes any
  model already downloaded, which is the point: the welcome screen is what a reviewer meets.
- Turn on a Focus so no notification banner lands mid-take, and record on the latest public iOS.
- Do **not** film "Import a model instead". It is fixed, but it opens the Files app and puts your
  own documents on screen. Nothing in Apple's request asks for it.

In order:
1. The Home Screen, then tap the Sotto icon. Launch it in the recording, not before it.
2. The welcome screen. Hold it about three seconds so the generated-text notice is readable.
3. Tap **Start chatting**, tap the composer, and let the keyboard come up — the composer and send
   button must stay visible, which is what the 1.0 (11) fix was for. Type a question and send it.
   Let the answer stream in rather than cutting to it.
4. **Turn on Airplane Mode and ask a second question.** This is the whole claim of the app in one
   shot, and it is the cheapest thing a reviewer can verify.
5. Turn Airplane Mode off. **⋯ › Model library › + › Browse catalog**, far enough down to show
   the publisher and licence on the entries. Start the Qwen2.5 0.5B download; you can cut away
   rather than wait it out.
6. **⋯ › Personas**, **⋯ › Tools**, then **⋯ › Settings › Privacy** for the bytes-sent counter.

Afterwards: check it frame by frame before sending — a contact sheet
(`ffmpeg -i in.mov -vf "fps=1/6,scale=400:-1,tile=3x3" sheet.png`) catches a leaked notification
or a stalled answer in one look. If the file is too large for Resolution Center, re-encode rather
than trim: `ffmpeg -i in.mov -vcodec libx264 -crf 28 -preset veryfast -an out.mp4`.

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
| Age rating | Calculated 13+, **overridden to 18+** (19+ Brazil and Korea; 17+ on OS earlier than 26). **Health or Wellness Topics: Yes** from 11 September 2026, at App Review's request |
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

### Submitted on build 1.0 (11)

Both platforms went back to App Review on 4 September 2026 — macOS at 7:15 PM, iOS at 7:17 PM,
both on **build 1.0 (11)** from Xcode Cloud, both **Waiting for Review**. The earlier submissions
on build 3 were removed rather than left in the queue: a reviewer typing on the empty chat screen
would have met the keyboard bug, which is a Guideline 2.1 rejection waiting to happen.

Attaching a new build means removing the version from review first (App Store Connect will not
swap a build underneath a submission), so both lost their place in the queue. That was the right
trade against shipping a build whose composer disappears behind the keyboard.

### iOS rejected on build 1.0 (11), 6 September 2026

**iOS came back under Guideline 2.1 — Information Needed, the same template macOS got**, on the
same build. Its Notes field already carried the answers, which did not pre-empt it: the request
is for the recording, and only the recording clears it.

| | iOS | macOS |
|---|---|---|
| Build under review | 1.0 (11) | 1.0 (11) |
| Status | **Rejected — 2.1 Information Needed**, 6 September 2026 | — |

What goes back: an iPhone recording, the reply in
[The iOS answer, 6 September 2026](#the-ios-answer-6-september-2026), and **a new build** — two
defects found while testing this one are fixed there, the welcome screen's dead import button and
raw `<tool_response>` markup in replies. Both are described in that section.

Because a new build is attached, the version has to be removed from review first, as on
4 September. Upload the Xcode Cloud build, add it to the version, then reply.

**macOS is untouched by this.** It is still under review on build 1.0 (11), and the two fixes do
not change anything a Mac reviewer sees — the importer guard is macOS-behaviour-preserving by
construction and the tag stripping is engine-level. Whether to push the same build to macOS as
well is a judgement call: it would lose macOS its place in the queue for a fix that only shows on
iOS. Leaving it is defensible; if macOS is rejected for anything else, roll the fixes in then.

### Answered and resubmitted, 6 September 2026

**iOS 1.0 went back to App Review on build 1.0 (16), and is Waiting for Review.** Submission
`e925623c-04ee-408f-8329-2841869c4eb7`, the same one that was rejected — the reply and the new
build go onto the existing thread rather than a fresh submission.

What was sent:
- **The recording.** Made on the iPhone against build 14, exported from iMovie as a 4K landscape
  file with the portrait capture letterboxed inside it, 4 min 57 s, 130 MB. Re-encoded to 1920×1080
  H.264 at CRF 27 — **9.7 MB**, content untouched. The original would very likely have been refused
  by the attachment upload, and the upload path caps at 10 MB, so there is not much room above this.
- **The reply**, on the Resolution Center thread with the file attached.
- **Build 1.0 (16)** swapped onto the version in place of 13.
- **The Notes field**, replaced with the iOS text in this file.

Two claims in the drafted reply were wrong by the time it was sent and were corrected first: it
said the recording begins on the Home Screen (it begins in TestFlight), and it named two fixes when
there were nine. **Read the reply against the artefact before sending it, not against the plan.**

> **The Resolution Center field counts characters differently from the Notes field.** 3,986
> characters by `wc -m` came back as 41 over the 4,000 limit — line breaks are counted as two.
> Budget about 3,900 for a reply of this shape.

> **The attachment needs the text in place first.** Uploading the file before the reply body was
> typed left the input holding a file the page never registered — no filename, no progress. Type
> the reply, then attach, then wait for "Processing…" to become the filename before sending.
> Submitting is two steps, not one: **Update Review** on the version page moves the item to *Ready
> for Review*, and **Resubmit to App Review** on the submission page actually sends it.

### iOS rejected on build 1.0 (16), 8 September 2026

Submission `e925623c-04ee-408f-8329-2841869c4eb7` came back on 8 September with two items,
reviewed on an iPhone 17 Pro Max. Neither is a bug report, and the 2.1 information request is
closed — the recording did its job.

| Guideline | What Apple said | What is true | What goes back |
|---|---|---|---|
| 2.3.6 Accurate Metadata | The age rating must say **Yes** to *Health or Wellness Topics* | A general-purpose model will discuss health if asked; the questionnaire said No | Set Yes on the App Information page; the 18+ override stays |
| 5.1.1(i) / 5.1.2(i) Privacy | The app "appears to share the user's personal data with a third-party AI service" without saying what, to whom, or asking first | It does not. No AI API, SDK or server; inference is on the device | Confirm it in the reply and in the Notes field — the rejection's own instruction for that case — plus a build that says so in the app |

**Where the impression came from.** Nothing in the code sends a conversation anywhere, so the
reviewer inferred it from the screens. The plausible sources, in order: the model catalogue,
where every entry names an AI company — Meta, Google, Microsoft, Alibaba, Mistral AI — next to
a Download button; the Google search tool in Tools; and *Delegate a task*, described as a
second model session. None of those screens said, at the point of reading, that inference stays
on the device. They do now.

**What changed in the app**, all on iOS and macOS alike:

- **The approval card discloses before it asks.** `ToolDisclosure` builds, for every tool
  call, one line saying what is sent and to whom: the Google tool's card reads *"Sends only
  these search words to Google (www.googleapis.com), under your own API key. Nothing else from
  this chat is sent."*, an HTTPS tool's names the host it was set up with, and a built-in's says
  *"Nothing leaves this device."* The *leaves this device* badge now shows for the Google tool
  as well — before, only HTTPS tools carried it. Nothing is sent until **Allow once** or
  **Always allow** is tapped, which was already true.
- **Settings › Privacy › Where your data goes.** Seven rows — conversations, model inference,
  third-party AI services (*none*, naming OpenAI, Anthropic, Google, Meta and Microsoft),
  model downloads (`huggingface.co`), the Google search tool (`googleapis.com`), HTTPS tools,
  and a link to the privacy policy. The pane's subtitle now says *"Nothing you type is sent to
  any AI service."*
- **The iPhone shows the bytes-sent counter.** The notes and the privacy policy both promised
  a live count on the Privacy page; the Mac had it as a stat card and the iPhone layout had
  dropped it. A reviewer checking that claim would have found nothing. It is a row now.
- **The catalogue footer** adds: *"A downloaded model runs on this device: nothing you type is
  sent to Hugging Face, to the model's publisher, or to any AI service."*
- **The generated-text notice** — welcome screen, empty chat, Settings › About — adds that
  none of it is medical, legal or financial advice, so the app matches the new age-rating answer.
- **`PRIVACY.md`** gains a *No third-party AI service* section, describes the card, and says
  the same about advice. Last-updated is 11 September 2026. **The page at
  `sotto.eonix.lk/privacy` is a separate Next.js repository** —
  `/Volumes/Yasas Data/WebstormProjects/sotto-web`, `github.com/yasasalwis/sotto-web`,
  deployed by Vercel from `main` — and `app/privacy/page.tsx` there was updated to match on
  the branch `privacy-11-september`. It reaches the live page only when that branch is merged;
  the reply says the policy is updated, so merge first.
- Tests: six `ToolDisclosureTests` and a harness test that an HTTPS tool's card names the host
  before anything runs. macOS 222 tests, iOS 219, all green on 11 September 2026.

**Before replying, in this order:**

- [x] App Store Connect › App Information › Age Rating › **Edit** → *Health or Wellness
      Topics*: **Yes** → Save. Confirm the shown rating is still 18+.
- [x] Push and merge the `privacy-11-september` branch of `sotto-web` (Vercel deploys `main`),
      then check `https://sotto.eonix.lk/privacy` shows "Last updated 11 September 2026" and the
      *No third-party AI service* heading.
- [x] Xcode Cloud build from this commit; remove the iOS version from review and add the new
      build to it (build 16 does not have the disclosure).
- [x] Paste the iOS Notes text from section 4 over the Notes field (App Store Connect's own counter
      is what matters: the 3,990-character draft showed as 7 over and was trimmed to 3,972).
- [ ] Add the THIRD-PARTY AI SERVICES paragraph to the macOS Notes field as well.
- [x] Reply on the Resolution Center thread with the text below (2,767 characters by
      `wc -m`; Resolution Center counts line breaks as two, so it lands near
      2,784). Then **Update Review** on the version page and
      **Resubmit to App Review** on the submission page.

#### iOS Resolution Center reply, 11 September 2026

It claims the new build, the age-rating change and the republished policy, so send it only
after all three are done.

> Thank you for the review. Both items are addressed. A new build is attached, and the answers below are also in the App Review Information notes.
>
> GUIDELINE 2.3.6 - AGE RATING
> "Health or Wellness Topics" is now set to Yes on the App Information page; the rating stays 18+. The notice shown on the welcome screen, the empty chat and Settings > About now also says that nothing a model writes is medical, legal or financial advice.
>
> GUIDELINES 5.1.1(i) AND 5.1.2(i) - THIRD-PARTY AI SERVICE
> To confirm: Sotto does not send user data to a third-party AI service and does not include one. There is no AI API, SDK or server behind the app. Inference runs on the device through Apple's FoundationModels framework (the on-device model) and the bundled llama.cpp library; a conversation is never transmitted anywhere, and the app answers in Airplane Mode. The model catalogue names publishers such as Meta, Google, Microsoft, Alibaba and Mistral AI because their open-weight files are what a person downloads; those files are read as data on the device, and none of those companies receives anything from the app.
>
> The only requests the app can make, each started by the person, are: a model download from huggingface.co (the host is pinned in code); an optional weekly catalogue check that ships off; and two optional tools that ship off - a Google Programmable Search tool that needs the person's own API key, and HTTPS tools the person writes themselves. For those two tools, what leaves the device is the argument values the model chose, never the conversation.
>
> Even so, the attached build makes the disclosure explicit inside the app rather than only in the policy:
> - The approval card shown before any networked tool runs now states what is sent and to whom, for example "Sends only these search words to Google (www.googleapis.com), under your own API key. Nothing else from this chat is sent." It carries a "leaves this device" badge, and nothing is sent until the person taps Allow. Built-in tools' cards say "Nothing leaves this device."
> - Settings > Privacy has a new "Where your data goes" section listing where conversations, inference, third-party AI services (none), model downloads, the search tool and HTTPS tools each go, with a link to the privacy policy, and on iPhone a running count of the bytes the app has sent.
> - The model catalogue states that a downloaded model runs on the device and that nothing typed is sent to Hugging Face, to the publisher, or to any AI service.
>
> The privacy policy at https://sotto.eonix.lk/privacy is updated to match: it identifies every case in which data leaves the device, what is sent, who receives it, and that no third-party AI service is involved.
>
> Source code, for verification: https://github.com/yasasalwis/Sotto

### Answered and resubmitted, 11 September 2026

**iOS 1.0 went back to App Review on build 1.0 (18) at 12:29 PM and is Waiting for Review**, on
the same submission `e925623c-04ee-408f-8329-2841869c4eb7`. Done from App Store Connect in the
browser, in this order:

1. **Age rating.** The questionnaire already had *Health or Wellness Topics* = **Yes** and *Medical
   or Treatment Information* = Infrequent when opened, with the 18+ override in place and the
   page's Save button disabled — nothing to change. The rejection was written against whatever
   the questionnaire said on 8 September; if it was changed by hand between then and now, that
   change is what the reply describes.
2. **Privacy page.** `sotto-web` `main` at `f398c85`; Vercel had it live within a minute.
3. **Build.** Commit `b3f1be0` pushed; Xcode Cloud build 18 started at 12:18 PM. **Archive - iOS
   succeeded** and was processed by 12:21 PM. **Archive - macOS failed** at *Prepare Build for
   App Store Connect*, and so did build 19's. The compile was clean; the reason is in Apple's
   "Action needed" email, not in the Xcode Cloud logs (which say only "Preparing build for App
   Store Connect failed"):

   > ITMS-90062: The value for key CFBundleShortVersionString [1.0] in the Info.plist file must
   > contain a higher version than that of the previously approved version [1.0].
   > ITMS-90186: Invalid Pre-Release Train - The train version '1.0' is closed for new build
   > submissions.

   macOS 1.0 was approved on 4 September, which closes the 1.0 train for macOS: **every macOS
   archive with `MARKETING_VERSION = 1.0` is refused at upload from now on**, so every push to
   `main` shows a red build until the version is bumped. The iOS action is unaffected while iOS
   1.0 is still under review. **The same will happen to iOS the moment iOS 1.0 is approved.**

   What to do, in order: wait for the iOS decision on build 18 (a bump now would strand the
   version under review); then bump `MARKETING_VERSION` to `1.0.1` (or `1.1`) in the Sotto
   target, create that version on both platforms in App Store Connect, and push. If the red
   builds are a nuisance before then, edit the *Default* workflow's *Archive - macOS* action and
   set *Distribution Preparation* to **None** temporarily — remember to set it back to *App Store
   Connect*, or the next macOS release will produce a green build that never reaches App Store
   Connect (see [Xcode Cloud](#xcode-cloud)).

   **Done at 1:28 PM on 11 September:** *Archive - macOS* → *Distribution Preparation* = **None**
   in the *Default* workflow, so pushes go green again while the 1.0 train is closed. **This
   must be put back to *App Store Connect* before the next macOS release**, together with the
   version bump — a green build with *None* uploads nothing.
4. **Notes field.** The 3,990-character draft showed as **7 over** in App Store Connect's own
   counter, so the opening sentence was shortened to "Guideline 2.1 answers follow, numbered as
   asked." — 10 to spare. Saved.
5. **Build swap.** On the version page the build row has a Delete control on hover; deleting 16
   exposes *Add Build*, which listed 18 only after a page reload (it had shown 17 as newest a
   minute earlier). Saved, and the sidebar flipped from *1.0 Rejected* to *1.0 Prepare for
   Submission*.
6. **Reply.** Posted on the thread at 12:28 PM from the submission page's *Reply to App Review*,
   with 1,233 characters to spare.
7. **Update Review** on the version page turned the item *Ready for Review*, which enabled
   **Resubmit to App Review** on the submission page. Clicked; status *Waiting for Review*.

**Not done:** the macOS Notes field does not carry the THIRD-PARTY AI SERVICES paragraph. macOS
1.0 is approved, so it goes in with the next macOS version.

### Third round of TestFlight fixes, on build 1.0 (13)

Build 13 went to the phone for the App Review recording and came back with five reports before a
frame was shot. All five were real; none would have been found by reading the code, and two would
have been in front of a reviewer.

- **A tool call rendered as a code block, and the answer never arrived.** On Gemma 2 2B, "Hello"
  produced nothing but ```` ```tool_call ````, the JSON, and `</tool_call>`. The prompt asks for a
  `<tool_call>` block; a model with no such token in its vocabulary reaches for the nearest thing
  it knows, a fenced code block with `tool_call` as the language. `ToolCallScanner` recognised only
  the literal tag, so the whole call was passed through as prose and `current_datetime` — a real
  Sotto tool, correctly named — never ran. The scanner now takes the fence as an opening marker,
  accepts either `</tool_call>` or the closing fence as its terminator, and drops a stray closing
  tag left behind when the bare-JSON path recovers a call on its own.
- **Settings rows starved their controls.** `SettingsRow` gave the title-and-detail column
  `maxWidth: .infinity`, which is free on a Mac and is not on a 402pt phone: "Apple Intelligence"
  wrapped to two lines beside a vertically centred chevron, and the "Manage…" button broke
  mid-word into "Manag e…". The control is now sized first and the description wraps instead.
  **`fixedSize`, not `layoutPriority`** — `SottoToggleStyle` carries a `Spacer` so the capsule sits
  at the trailing edge when it has a visible label, which makes it greedy; given priority it took
  the whole row and left four rows looking as though they had vanished. Asking for the ideal width
  prices that `Spacer` at nothing.
- **"Chip" showed a device identifier on iOS.** `machdep.cpu.brand_string` is a Mac sysctl; iOS
  fell back to `hw.machine`, which is the device, so an iPhone 15 Pro read `iPhone16,1` under a
  heading that was wrong twice over. `DeviceCapabilities.appleChips` translates it, falling back to
  the raw identifier for anything newer than this build.
- **Settings › General › Manage swapped the sheet.** There is one `.sheet` for the whole app, on
  `MainView`. Setting `state.sheet = .tools` from inside the Settings sheet changed the item
  underneath an open sheet, so SwiftUI tore Settings down and built Tools in its place — the stall
  reported as "app stuck when close the general for few seconds", and the way back led to the chat
  rather than to Settings. On iOS it is now a `NavigationLink` pushing `ToolsView(showsCloseButton:
  false)` onto the stack Settings already has. Same family as the onboarding importer: **on iOS,
  ask what is already presented before presenting anything.**
- **"persona: default" was read as "the default persona".** The composer chip fell back to
  "default" when a conversation had no persona — beside a setting called *Default persona*, that
  reads as confirmation rather than absence. It says "none" now. The setting itself was never
  broken: a new chat does take `defaultPersonaID`, verified on the Simulator. What it does not do
  is reach back into a chat that is already open, which is the chat you are looking at when you
  close Settings.

The sidebar's full-width "＋ New chat" card is also gone on iOS, replaced by a "Chats" header with
a compact circular button. The Mac keeps the wide row, where the width is free and the ⌘N hint has
somewhere to sit.

macOS 219 tests, iOS 216, all green.

### Second round of TestFlight fixes

Build 1.0 (5) came back with "Continues asking for chat history and apologize": "what is a LLM"
called *Search my chats* four times, every one failed, and the reply opened with an apology. Three
causes, all fixed in 1.0 (7):

- **The arguments never arrived.** The gateway asked the model for a JSON object inside a string
  and it sent the search words bare, which parsed to `{}` and failed the tool's required `query`.
  A tool with one required text parameter now takes a bare value directly.
- **Nothing stopped the retry.** A per-reply ledger refuses a tool after two failures and tells the
  model to answer without it.
- **The catalogue had lost its restraint.** Summarising each tool to its first sentence dropped the
  "Do not call it for general knowledge" guidance the descriptions carry — a regression introduced
  with the summaries. The preamble now says it once, for all tools.

Tool-call cards are hidden outright on iOS when the setting is off, failures included.

Build 1.0 (6) then reported **"This conversation is longer than the model's context window"** on a
short chat. That was accounting, not length: `PromptBuilder` trimmed history against the raw
context length while the engine separately wrote the tool definitions into the same window, and
nothing subtracted them. Engines now report a measured `toolFootprintTokens` and `ChatSession`
reserves it before trimming. The schema-per-tool path had the same gap all along.

### Memory, context ceiling and subagents

- **Conversations remember past the window.** Turns that no longer fit are folded into a running
  digest rather than dropped, rebuilt after a turn that had to drop something so no reply waits on
  it. On Apple's fixed 4,096 tokens this is the difference between a model that contradicts itself
  after five exchanges and one that does not.
- **The context picker goes to 131,072** — the largest any catalogue model is trained for (Llama
  3.2, Phi-3.5 mini). Nothing needed to change to make that safe: the runtime already clamps to
  `min(setting, the model's own length)` and refuses a load that will not fit. **256K is not
  reachable** — no catalogue model is trained that far, and a 3B model would need roughly 30 GB of
  KV cache to try.
- **Subagents.** A `delegate` tool hands one self-contained task to a second session with its own
  window and returns only the answer. One shot: no tools, no nesting, task capped at 2,000
  characters. Ships switched off and asks before each run, because it costs a whole extra
  generation.

Built-ins are now **twenty-six**; four still ship enabled.

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

> **Since 11 September 2026, *Archive - macOS* has Distribution Preparation set to *None*** —
> macOS 1.0 is approved, its train is closed, and every macOS 1.0 upload was failing. Set it back
> to *App Store Connect* when `MARKETING_VERSION` is bumped for the next macOS release.

1. **`ci_scripts/ci_post_clone.sh`** vendors llama.cpp. `Packages/LlamaKit/llama.xcframework`
   is git-ignored, so a fresh clone has nothing behind LlamaKit's `llama` binary target and
   package resolution fails with *"does not contain a binary artifact"*. It passes `--no-sim`,
   which is correct only while the workflow has no Simulator test action.
2. **Distribution Preparation = App Store Connect** on both archive actions. It defaults to
   *None*, which produces a green build whose archive never reaches App Store Connect — the
   build looks fine and no build ever appears on the version page.

### Still outstanding

- [ ] **Everything in the checklist under
      [iOS rejected on build 1.0 (16)](#ios-rejected-on-build-10-16-8-september-2026)** — the
      age-rating answer, the republished privacy page, the new build, both Notes fields, the
      reply.
- [ ] **Look at the iPhone screenshots again before replying.** Apple's *Prevent Common Issues*
      list calls out guideline 2.3.3: screenshots must show the app in use, "not merely the title
      art, login page, or splash screen". Sotto's welcome screen is the closest thing it has to a
      splash screen, and it is a plausible first screenshot. If one of the four is the welcome
      screen, replace it with a chat mid-answer, the model library, or the tools list. This cannot
      be checked from the repository — only in App Store Connect.
- [ ] **macOS.** Whatever its state, its Notes field should carry the THIRD-PARTY AI SERVICES
      paragraph and its next build should be this commit, so the two platforms say the same thing.

> **No version bump is needed.** `CURRENT_PROJECT_VERSION` is still `1` in the project and always
> has been; Xcode Cloud sets the build number on upload, which is where 3, 5, 7 and 11 came from.
> Bumping it by hand is only for an archive made locally.
>
> **`MARKETING_VERSION`, on the other hand, must go up after each approval.** macOS 1.0 was
> approved on 4 September and from build 18 onward every macOS upload of version 1.0 is refused
> with ITMS-90062 / ITMS-90186. Bump it once iOS 1.0 is decided; see the 11 September entry.

### Closed

- [x] **`AppLinks.sourceCode`** — `https://github.com/yasasalwis/Sotto` was private, so the
      "Source" link in Settings › About returned 404 for every user. The repository was made
      public on 4 September 2026; the URL now answers 200 unauthenticated. Nothing in the code
      changed. **If the repository is ever made private again, this link breaks in the shipped
      build** — change `Sotto/Domain/AppLinks.swift` at the same time.
