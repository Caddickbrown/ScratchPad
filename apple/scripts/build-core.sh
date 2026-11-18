#!/usr/bin/env bash
#
# Builds scratchpad-ffi for Apple platforms and generates its Swift bindings.
#
#   apple/scripts/build-core.sh               the phone and the Mac (arm64 + x86_64), into apple/Frameworks/ScratchpadCoreFFI.xcframework
#   apple/scripts/build-core.sh --if-needed   nothing, if the xcframework is newer than everything under core/
#   apple/scripts/build-core.sh --host-only   the Mac slice only, this Mac's arch: enough for swift test
#
# Cargo output goes to $CARGO_TARGET_DIR (default core/target). The xcframework is a build
# product and is ignored by git; the generated Swift is committed, so a diff shows any change to the boundary.
# A fresh checkout must run this once before xcodegen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE="$ROOT/core"
# rustup's cargo, which has the Apple targets (aarch64-apple-darwin, aarch64-apple-ios). A Homebrew or
# /usr/local rustc only builds for its own host, which left the Mac slice x86_64-only.
export PATH="$HOME/.cargo/bin:$PATH"
CARGO="$(command -v cargo)"; RUSTC="$(command -v rustc)"
if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    CARGO="$HOME/.cargo/bin/cargo" RUSTC="$HOME/.cargo/bin/rustc"
    "$HOME/.cargo/bin/rustup" target list --installed | grep -qx aarch64-apple-darwin ||
        { echo "error: run ~/.cargo/bin/rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios" >&2; exit 1; }
fi
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$CORE/target}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
# Xcode's script phases export settings for the app's own SDK, which point cargo at the wrong one.
unset SDKROOT PLATFORM_NAME EFFECTIVE_PLATFORM_NAME ARCHS ONLY_ACTIVE_ARCH \
      SWIFT_PLATFORM_TARGET_PREFIX LLVM_TARGET_TRIPLE_SUFFIX 2>/dev/null || true
export IPHONEOS_DEPLOYMENT_TARGET=18.0 MACOSX_DEPLOYMENT_TARGET=15.0

CRATE=scratchpad-ffi LIBNAME=scratchpad_ffi NAME=ScratchpadCoreFFI
OUT="$ROOT/apple/Frameworks" GENERATED="$ROOT/apple/Sources/ScratchpadFFI"
IF_NEEDED=0 IOS=1
for arg in "$@"; do
    case "$arg" in
        --if-needed) IF_NEEDED=1 ;;
        --host-only) IOS=0 ;;
        -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown option $arg" >&2; exit 2 ;;
    esac
done

XCF="$OUT/$NAME.xcframework"
if [[ $IF_NEEDED == 1 && -f "$XCF/Info.plist" ]] && \
   [[ -z "$(find "$CORE/Cargo.toml" "$CORE/Cargo.lock" "$CORE/scratchpad-core" "$CORE/scratchpad-ffi" -type f -newer "$XCF/Info.plist" -print -quit)" ]]; then
    echo "build-core: $NAME.xcframework is up to date"; exit 0
fi

note() { echo "build-core: $*"; }
HOST="$("$RUSTC" -vV | sed -n 's/^host: //p')"
build() { (cd "$CORE" && nice -n 10 "$CARGO" build --locked --quiet --release -p "$CRATE" --lib --target "$1"); }

note "generating Swift bindings for $CRATE"
(cd "$CORE" && nice -n 10 "$CARGO" build --locked --quiet -p "$CRATE" --lib)
HEADERS="$CARGO_TARGET_DIR/apple/$NAME/Headers"
TMP="$CARGO_TARGET_DIR/apple/$NAME/generated"
rm -rf "$TMP" "$HEADERS"; mkdir -p "$TMP" "$HEADERS" "$GENERATED"
(cd "$CORE" && nice -n 10 "$CARGO" run --locked --quiet -p "$CRATE" --features cli --bin uniffi-bindgen -- \
    generate --library "$CARGO_TARGET_DIR/debug/lib$LIBNAME.dylib" --language swift --no-format --out-dir "$TMP")
cmp -s "$TMP/$LIBNAME.swift" "$GENERATED/$LIBNAME.swift" || cp "$TMP/$LIBNAME.swift" "$GENERATED/$LIBNAME.swift"
cp "$TMP/${LIBNAME}FFI.h" "$HEADERS/"
cp "$TMP/${LIBNAME}FFI.modulemap" "$HEADERS/module.modulemap"

args=()
if [[ $IOS == 1 ]]; then
    # One universal Mac library, so the app links on Apple silicon and Intel Macs alike.
    MAC="$CARGO_TARGET_DIR/apple/$NAME/macos-universal/lib$LIBNAME.a"
    for t in aarch64-apple-darwin x86_64-apple-darwin; do note "building for $t"; build "$t"; done
    mkdir -p "$(dirname "$MAC")"
    lipo -create -output "$MAC" \
        "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/lib$LIBNAME.a" \
        "$CARGO_TARGET_DIR/x86_64-apple-darwin/release/lib$LIBNAME.a"
    args+=(-library "$MAC" -headers "$HEADERS")
else
    note "building for $HOST"
    build "$HOST"
    args+=(-library "$CARGO_TARGET_DIR/$HOST/release/lib$LIBNAME.a" -headers "$HEADERS")
fi
if [[ $IOS == 1 ]]; then
    note "building for aarch64-apple-ios"
    build aarch64-apple-ios
    args+=(-library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/lib$LIBNAME.a" -headers "$HEADERS")
fi
mkdir -p "$OUT"
rm -rf "$XCF"
xcodebuild -create-xcframework "${args[@]}" -output "$XCF" >/dev/null
note "done: $XCF"
