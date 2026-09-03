#!/usr/bin/env bash
# Xcode Cloud runs this after cloning the repository, before it resolves package
# dependencies.
#
# Packages/LlamaKit/llama.xcframework is git-ignored — it is ~430 MB and is fetched
# rather than committed (see .gitignore and Scripts/fetch-llama.sh). A fresh Xcode Cloud
# clone therefore has nothing for LlamaKit's `llama` binary target to point at, and the
# build fails during package resolution with:
#
#   local binary target 'llama' at '.../Packages/LlamaKit/llama.xcframework'
#   does not contain a binary artifact
#
# Vendoring it here is what makes a cloud build work at all.
#
# --no-sim skips the iOS Simulator slice, which is built from source with cmake and takes
# several minutes. The workflow only archives for iOS device and macOS, neither of which
# links the Simulator slice. Add a test action that runs on a Simulator and this must drop
# the flag (and cmake must be available) or the Simulator build will not link.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "ci_post_clone: vendoring llama.cpp into Packages/LlamaKit"
Scripts/fetch-llama.sh --no-sim
echo "ci_post_clone: llama.xcframework slices:"
ls -1 Packages/LlamaKit/llama.xcframework
