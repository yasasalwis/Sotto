# Sotto — Support

Sotto runs language models on your own device. There is no account and no server, so there is
nothing to sign in to and nothing to be locked out of. If something is not working, it is
happening on your device, and the answers below cover the cases that come up most.

**Contact:** [contact@eonix.lk](mailto:contact@eonix.lk) — expect a reply within three
working days.
**Security reports:** please email rather than opening a public issue. See
[SECURITY.md](SECURITY.md).
**Privacy:** see [PRIVACY.md](PRIVACY.md).

When you write in, it helps to include your device and OS version, the Sotto version from
**Settings › Advanced › About**, and which model you were using.

## Getting started

Sotto can talk to two kinds of model:

- **Apple Intelligence** — Apple's on-device model. Nothing to download; it is ready if your
  device supports Apple Intelligence and you have turned it on in Settings.
- **Open-source models (GGUF)** — you either download one from the built-in catalog
  (**Library**) or import a `.gguf` file you already have.

You do not need both. If Apple Intelligence is available, you can start chatting immediately.

## Common questions

**Is Sotto free? Are there any purchases?**
Sotto is free. There are no in-app purchases, no subscription, no paid tier and no ads. The
only thing that can ever cost you money is a Google Cloud API key, if you choose to set up
the optional search tool — that is billed by Google under your own account, not by Sotto, and
Google's free allowance is 100 searches a day.

**Does Sotto work offline?**
Yes. Inference runs on your device. Once a model is on the device, airplane mode changes
nothing. The only features that need a network are downloading a model and any tool you
explicitly set up to call the internet.

**"Turn on Apple Intelligence in System Settings"**
Apple's on-device model needs Apple Intelligence enabled and a device that supports it. Open
the system Settings app, find Apple Intelligence & Siri, and turn it on. If your device does
not support it, download an open-source model from **Library** instead — everything else in
Sotto works the same way.

**"Apple Intelligence is still downloading its model"**
The system model downloads in the background after you enable Apple Intelligence. It can take
a while on a slow connection. Try again later, or use an imported model in the meantime.

**A model will not load: "not enough memory"**
The estimate is the weights plus the KV cache. Either pick a smaller model or a smaller
quantization, or lower the context length in **Settings › Models**. As a rough guide: a 1B
model is comfortable on any supported device, 3B wants about 3 GB free, and 7B wants about
6 GB and is really a Mac model.

**A download is stuck at "waiting to start" on iPhone**
**Settings › Privacy › Downloads on Wi-Fi only** is on and you are on cellular. Either join
Wi-Fi or turn that setting off. Model files are large — often several gigabytes — so the
default is deliberate.

**A download failed part way**
Downloads resume. Reopen **Library** and press Retry; it continues from where it stopped
rather than starting again. Check you have enough free space for the whole file.

**Answers are slow**
Speed depends on the model size, the quantization and your device. Smaller models are much
faster. On a device under thermal pressure, everything slows down. The tokens-per-second
figure in the inspector tells you what you are actually getting.

**The model said something wrong, or something I did not want**
Sotto does not review, filter or fact-check model output — no one does. Models invent facts
confidently. Treat an answer as a draft and verify anything that matters. If a particular
model behaves badly, try a different one; the catalog covers a range of publishers, and each
model's licence and publisher are listed next to it.

**Where are my conversations stored? Can I get them out?**
On your device only, in Sotto's own container. **Settings › Privacy › Export all
conversations** writes them to a JSON file wherever you choose. **Erase all data** in the same
place deletes everything — conversations, personas, imported models, preferences and any tool
API keys in the keychain — with no copy anywhere else.

**I turned off "Store conversations" and my old chats are still there**
That setting takes effect from the next launch and governs new conversations. Existing chats
stay on disk until you erase them.

## Tools

Sotto has twenty-five built-in tools that run entirely on your device — dates and time zones,
arithmetic and units, percentages and number bases, text rewriting, find-and-replace,
extraction, sorting, word counts and diffs, JSON and CSV, descriptive statistics, encoding,
hashing, random numbers, and a search of your own past chats. None of them needs setup.

Four are on out of the box: date and time, calculator, unit converter and chat search. The
rest are one switch away in **Tools**. They are not on by default because every tool you
enable is described to the model before your conversation starts, and Apple's on-device model
has a small fixed context window — past roughly twenty offered tools it stops answering
altogether. Switching on the handful you actually use works better than switching on
everything.

You can also create tools that reach the internet. Those are off until you configure them,
and default to **Ask every time**, which shows you the exact request before anything is sent.

**Setting up Google search**
1. Create a Programmable Search Engine at
   [programmablesearchengine.google.com](https://programmablesearchengine.google.com/controlpanel/create),
   set to search the whole web, and copy its **search engine id** (`cx`).
2. Create an API key in the [Google Cloud console](https://console.cloud.google.com/apis/credentials)
   with the **Custom Search API** enabled.
3. Paste both into **Tools › Google search**, press **Run once** to check them, then switch
   the tool on.

The key is stored in your keychain, not in Sotto's database, so it never appears in an
export. Only the words the model searches for are sent to Google.

**A tool stopped working**
Open **Tools** and press **Run once** on it. That runs the tool directly, with no model
involved, and shows you the real error — an expired key, a changed address, or a server that
is down. Every tool is capped at 20 seconds, and a single reply may make at most four tool
calls.

**Turning tools off**
One switch at the top of **Tools** disables the whole feature. A persona can also be
restricted to local-only, in which case it never sees a tool that uses the network.

## The menu bar (macOS)

Sotto puts an item in the menu bar: a field that hands a question straight to a chat, your five
most recent chats, and a way into the library, compare, tools, presets and settings windows.

**Sotto keeps running after I close its window**
That is deliberate: the menu bar item needs an app behind it. **Quit Sotto** in the panel, ⌘Q
and the Dock's Quit all quit it as usual. To get the old behaviour back — where closing the
last window quits Sotto — turn **Show in menu bar** off in **Settings › General**, and the
menu bar item goes away with it.

## Privacy and security

**What leaves my device?**
Only four things, all started by you: a model download, the optional weekly catalog check
(off by default), the Google search tool (off by default), and any HTTPS tool you create.
**Settings › Privacy** shows a running count of the bytes Sotto has actually sent, so you can
check this yourself. Full detail is in [PRIVACY.md](PRIVACY.md).

**Can I lock the app?**
**Settings › Privacy › Require Face ID to open** locks Sotto whenever it goes to the
background.

## Reporting a bug

Email [contact@eonix.lk](mailto:contact@eonix.lk) with what you did, what you expected
and what happened. If Sotto crashed and you have turned on **Settings › Privacy › Crash
reports**, the report is waiting in **Settings › Advanced** for you to read and attach — it
stays on your device until you choose to send it.
