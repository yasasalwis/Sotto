# Privacy Policy — Sotto

**Last updated: 11 September 2026**

Sotto is a chat app that runs language models on your own device. It has no account, no
server and no analytics. This policy describes every case in which data leaves your device,
which is a short list.

## The short version

**Sotto's developer collects nothing.** No account, no sign-in, no identifiers, no usage
statistics, no crash telemetry, no advertising, no tracking, no third-party SDKs that phone
home. Your conversations are never transmitted to us, because there is no "us" to transmit
them to — there is no Sotto server.

## No third-party AI service

Sotto does not send anything you type, attach or generate to any AI service, and it contains
no AI API, SDK or server. Every answer is produced on your device:

- **Apple Intelligence** runs through Apple's Foundation Models framework, which is the model
  built into your device. Sotto uses the on-device model only.
- **Downloaded and imported models** run through the bundled llama.cpp library on your device.

The model catalog names publishers such as Meta, Google, Microsoft, Alibaba and Mistral AI
because their open-weight model files are what you download. Those files are read as data on
your device; none of those companies, and no other AI provider — OpenAI, Anthropic or anyone
else — receives anything from Sotto. **Settings › Privacy › Where your data goes** repeats this
inside the app, row by row.

## What Sotto stores, and where

Everything Sotto keeps is stored **only on your device**, inside the app's own container:

| Data | Where it lives | Notes |
|---|---|---|
| Conversations and messages | App container (`Sotto.store`) | Storing them is optional — turn off **Settings › Privacy › Store conversations** and they exist only in memory until you quit. |
| Personas and tool definitions | App container | Created by you. |
| Downloaded and imported model weights | App container (`Models/`) | Excluded from device backups because of their size. |
| Preferences | App container | Standard user defaults. |
| API keys you type into a tool | System keychain | Written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and no iCloud sync, so a key never leaves the device, never enters an export, and never appears in a log. |
| Crash diagnostics | App container (`Diagnostics/`) | Off by default. When on, MetricKit writes reports to your device; you read them in **Settings › Advanced** and choose whether to share one. Nothing is uploaded automatically. |

On iOS the conversation store is written with
`NSFileProtectionCompleteUntilFirstUserAuthentication`, so it is encrypted at rest by the
system. On macOS it relies on FileVault.

**Settings › Privacy › Erase all data** deletes all of the above, including the keychain
items, with no copy anywhere else.

## When data leaves your device

Inference never does. Apple's Foundation Models framework runs on your device, and imported
GGUF models run through llama.cpp on your device. What you type into a chat is not
transmitted anywhere.

There are exactly four paths that reach the network, and all four are started by you:

1. **Downloading a model from the catalog.** A request to `huggingface.co` for the model file
   you tapped. Hugging Face receives the request as any web download would; see
   [Hugging Face's privacy policy](https://huggingface.co/privacy). Sotto sends no
   identifier, no account and nothing about you. The host is pinned in code: a catalog entry
   that points anywhere other than `huggingface.co` over HTTPS is refused.
2. **The weekly catalog check** (*Settings › Privacy › Model catalog updates*, **off by
   default**). Once a week, a request to Hugging Face's public API asking which quantizations
   exist for the models in the built-in catalog. It sends no information about you or your
   conversations.
3. **The Google search tool** (**off by default**, and unusable until you supply your own
   Google API key and Programmable Search Engine id). When a model calls it, the search words
   the model chose are sent to Google's Custom Search API under *your* key. Google's handling
   of that request is governed by [Google's privacy
   policy](https://policies.google.com/privacy). Your conversation is not sent — only the
   query. With **Ask every time** (the default) a card in the chat shows the exact search
   words, names Google and the address they go to (`www.googleapis.com`), and nothing is sent
   until you tap **Allow**. Choosing **Always allow** on that card is what turns the prompt
   off; you can turn it back on in the tool's settings.
4. **An HTTPS tool you create yourself.** Sotto sends the request you configured, to the
   address you wrote, with the argument values the model chose. Sotto restricts these to
   `https` and percent-encodes argument values so a model cannot alter the address, but the
   destination and what reaches it are your choice. The same card asks first, names the host,
   and states that only the argument values shown are sent.

**Settings › Privacy** shows a running count of the bytes Sotto has actually put on the
network, so you can check this description against the app's behaviour, and its **Where your
data goes** section lists each of the cases above next to the address it reaches.

## What Sotto does not do

- No advertising, and no advertising identifier.
- No tracking, in the App Store's sense or any other. Sotto does not link data to you or your
  device and does not share data with data brokers.
- No third-party analytics, attribution or crash-reporting SDKs.
- No account, no email address, no contacts, no location, no photos, no microphone, no
  camera, no health data.
- No access to your files beyond a file you explicitly pick or drop on the window, which is
  read to extract its text and is not copied anywhere except, for a model file, into Sotto's
  own library.

Face ID / Touch ID, when you turn on **Require Face ID to open**, is used only to unlock the
app. The biometric check is performed by the system; Sotto receives a yes or no and never
sees biometric data.

## Text that models generate

Sotto does not review, filter or fact-check what a model writes. Models invent things, get
facts wrong, and can produce text you did not ask for. A model will discuss health, legal or
financial questions if you ask it to; nothing it writes is medical, legal or financial advice.
Treat an answer as a draft and verify anything that matters. You are responsible for how you
use text a model produces.

Model weights you download or import are third-party works under their own licences, shown
next to each model in the catalog.

## Children

Sotto is not directed at children. Because it can run open-weight models that are not
filtered, it is rated for adults on the App Store.

## Changes

If this policy changes, the "last updated" date above changes with it, and the change ships
with an app update.

## Contact

Questions about this policy, or about privacy in Sotto: **contact@eonix.lk**.
Security reports: see [SECURITY.md](SECURITY.md).
