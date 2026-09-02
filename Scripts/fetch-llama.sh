#!/usr/bin/env bash
# Vendors the llama.cpp binary framework used by Packages/LlamaKit.
#
#   Scripts/fetch-llama.sh            # macOS + iOS device slices from the pinned upstream release,
#                                     # plus an iOS Simulator slice built from source when cmake is present
#   Scripts/fetch-llama.sh --no-sim   # skip the Simulator slice (device + macOS only)
#
# The upstream release archive is verified against a pinned SHA-256 before it is unpacked.
set -euo pipefail

LLAMA_TAG="b10759"
LLAMA_ZIP_SHA256="58ba646be6f64133dfd28d10b50e248763afbfef05f091a9d69bcca21387eb64"
LLAMA_ZIP_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="${ROOT}/Packages/LlamaKit"
WORK_DIR="${PACKAGE_DIR}/.artifacts"
OUTPUT="${PACKAGE_DIR}/llama.xcframework"
WITH_SIM=1
for arg in "$@"; do
  case "$arg" in
    --no-sim) WITH_SIM=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

mkdir -p "${WORK_DIR}"
ZIP="${WORK_DIR}/llama-${LLAMA_TAG}-xcframework.zip"
if [[ ! -f "${ZIP}" ]]; then
  echo "Downloading ${LLAMA_ZIP_URL}"
  curl -sSL --fail -o "${ZIP}" "${LLAMA_ZIP_URL}"
fi
ACTUAL_SHA="$(shasum -a 256 "${ZIP}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA}" != "${LLAMA_ZIP_SHA256}" ]]; then
  echo "Checksum mismatch for ${ZIP}" >&2
  echo "  expected ${LLAMA_ZIP_SHA256}" >&2
  echo "  actual   ${ACTUAL_SHA}" >&2
  rm -f "${ZIP}"
  exit 1
fi

rm -rf "${WORK_DIR}/release"
mkdir -p "${WORK_DIR}/release"
unzip -q -o "${ZIP}" -d "${WORK_DIR}/release"
RELEASE_XCF="${WORK_DIR}/release/build-apple/llama.xcframework"
MACOS_FW="${RELEASE_XCF}/macos-arm64_x86_64/llama.framework"
IOS_FW="${RELEASE_XCF}/ios-arm64/llama.framework"
ARGS=(
  -framework "${MACOS_FW}" -debug-symbols "${RELEASE_XCF}/macos-arm64_x86_64/dSYMs/llama.dSYM"
  -framework "${IOS_FW}" -debug-symbols "${RELEASE_XCF}/ios-arm64/dSYMs/llama.dSYM"
)

if [[ "${WITH_SIM}" == "1" ]]; then
  if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is not installed; skipping the iOS Simulator slice." >&2
    echo "Install it (brew install cmake, or pip install cmake) and re-run to enable Simulator builds." >&2
  else
    SRC="${WORK_DIR}/llama.cpp"
    if [[ ! -d "${SRC}" ]]; then
      git clone --quiet --depth 1 --branch "${LLAMA_TAG}" https://github.com/ggml-org/llama.cpp.git "${SRC}"
    fi
    echo "Building the iOS Simulator slice from source (this takes a few minutes)…"
    (cd "${SRC}" && ./build-xcframework.sh ios-sim >"${WORK_DIR}/ios-sim-build.log" 2>&1) || {
      echo "Simulator build failed; see ${WORK_DIR}/ios-sim-build.log" >&2
      exit 1
    }
    ARGS+=(-framework "${SRC}/build-ios-sim/framework/llama.framework" -debug-symbols "${SRC}/build-ios-sim/dSYMs/llama.dSYM")
  fi
fi

rm -rf "${OUTPUT}"
xcrun xcodebuild -create-xcframework "${ARGS[@]}" -output "${OUTPUT}" >/dev/null
echo "Wrote ${OUTPUT}"
plutil -p "${OUTPUT}/Info.plist" | grep LibraryIdentifier
