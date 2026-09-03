# Runbook

Sotto has no servers. "Operating" it means building, shipping and helping users on their own devices.

## Build & ship

1. `Scripts/fetch-llama.sh` (once per checkout, or after bumping `LLAMA_TAG`).
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Sotto target.
3. `xcodebuild -scheme Sotto -destination 'platform=macOS,arch=arm64' test` and the iOS equivalent must be green.
4. Archive from Xcode (Product › Archive) for macOS and iOS; distribute through TestFlight / App Store or Developer ID.
   For an App Store submission, work through [APP_REVIEW.md](APP_REVIEW.md) — it carries the
   App Store Connect answers, the review notes and the pre-archive checks. Archive from
   **Release**: Debug defines `SOTTO_SHELL_TOOL`, which must never reach App Store Connect.
5. Tag the commit `vX.Y.Z`.

Rollback: re-submit the previous archive. There is no data migration to undo unless a release changed the SwiftData schema; keep schema changes additive (new optional fields) so older builds still open the store.

## Updating llama.cpp

1. Pick a release tag from https://github.com/ggml-org/llama.cpp/releases that ships `llama-<tag>-xcframework.zip`.
2. Download it, compute `shasum -a 256`, update `LLAMA_TAG` and `LLAMA_ZIP_SHA256` in `Scripts/fetch-llama.sh`.
3. Run the script, then `cd Packages/LlamaKit && swift test`. Check `llama.h` for signature changes (the wrapper touches: model/context params, tokenize, chat template, sampler chain, memory clear, abort callback).
4. Build both platforms and run one real generation on each.

## Updating the catalog

Edit `Sotto/Resources/Catalog/models.json`. Every entry needs a working `https://huggingface.co/.../resolve/main/<file>.gguf` URL and the exact `Content-Length` (check with `curl -sIL <url>`). `CatalogTests.bundledCatalogDecodes` enforces the invariants.

## Diagnosing user reports

- Logs: `log stream --predicate 'subsystem == "lk.eonix.Sotto"' --level info` (or Console.app). Categories: app, chat, models, downloads, engine, persistence, privacy, security, llama.cpp.
- Model won't load: look for `Failed to load` in `engine`; the message includes llama.cpp's reason. Common: unsupported architecture in this llama.cpp tag, or memory.
- Download failures: category `downloads`. Resume data survives relaunch; "Retry" restarts from the resume point.
- Store won't open: the app falls back to an in-memory store and shows an alert. The store is at `~/Library/Containers/lk.eonix.Sotto/Data/Library/Application Support/Sotto/Sotto.store` (macOS). Move it aside to recover.
- Crash diagnostics: only if the user enabled Crash reports; JSON files in `.../Sotto/Diagnostics/`, listed in Settings › Advanced.

## Diagnosing a misbehaving tool

1. Open Tools, select the tool, and press **Run once**. That runs it with no model involved, which separates a broken tool from a model that calls it badly.
2. In the log (category `engine`), each run appears as `Tool <name> succeeded|failed`. Prompts and results are not logged.
3. If a GGUF model never calls a tool, check that its reply is not being shown as raw JSON: that means the call block was not recognised. Capture the reply and add a case to `ToolCallScannerTests`.
4. HTTPS tools that fail with a status code usually need a header; shell tools that time out are over the 20 second limit.

## Diagnosing a catalog download

1. In a Debug build, start one from the command line rather than the UI:

   ```
   open -n Sotto.app --args -startCatalogDownload qwen2.5-0.5b-instruct-q4_k_m
   ```

2. Watch the record move in the app's own database:

   ```
   sqlite3 ~/Library/Containers/lk.eonix.Sotto/Data/Library/Application\ Support/Sotto/Sotto.store \
     "select ZNAME, ZSTATERAW, ZRECEIVEDBYTES, ZERRORMESSAGE from ZMODELDOWNLOAD;"
   ```

   The row disappears and one appears in `ZINSTALLEDMODEL` when the file has been validated and moved.

3. A download stuck at zero bytes with no error is the system holding the request: the record's
   message reads "Waiting for a network Sotto is allowed to use." On iOS that is the Wi-Fi-only
   setting; on macOS that setting does not apply.

4. Two copies of the app running at once share one background-session identifier and one database.
   Quit the other copy before investigating.

## Rotating secrets

The app has none of its own. A user may put an API key in the headers of an HTTPS tool; those live in the app's database with the rest of their data and are removed by Settings › Privacy › Erase all data.

## Erasing data

Settings › Privacy › Erase all data removes conversations, personas (re-seeded), models, downloads, diagnostics and preferences. Users can also delete the app container.

## Incident checklist

1. Reproduce with the log stream above.
2. If it's a llama.cpp crash, capture the model name/quant and the `llama.cpp` category output; test the same file with the upstream `llama-cli` at the pinned tag.
3. Fix, add a regression test, ship a point release.
