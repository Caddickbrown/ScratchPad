#!/usr/bin/env bash
#
# Builds scratchpad-ffi for Apple platforms and generates its Swift bindings.
#
#   apple/scripts/build-core.sh               the phone and this Mac, into apple/Frameworks/ScratchpadCoreFFI.xcframework
#   apple/scripts/build-core.sh --if-needed   nothing, if the xcframework is newer than everything under core/
#   apple/scripts/build-core.sh --host-only   the Mac slice only: enough for swift test
#
# Cargo output goes to $CARGO_TARGET_DIR (default core/target). The xcframework is a build
# product and is ignored by git; the generated Swift is committed, so a diff shows any change to the boundary.
# A fresh checkout must run this once before xcodegen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE="$ROOT/core"
export PATH="$HOME/.cargo/bin:$PATH"
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
HOST="$(rustc -vV | sed -n 's/^host: //p')"
build() { (cd "$CORE" && nice -n 10 cargo build --locked --quiet --release -p "$CRATE" --lib --target "$1"); }

note "generating Swift bindings for $CRATE"
(cd "$CORE" && nice -n 10 cargo build --locked --quiet -p "$CRATE" --lib)
HEADERS="$CARGO_TARGET_DIR/apple/$NAME/Headers"
TMP="$CARGO_TARGET_DIR/apple/$NAME/generated"
rm -rf "$TMP" "$HEADERS"; mkdir -p "$TMP" "$HEADERS" "$GENERATED"
(cd "$CORE" && nice -n 10 cargo run --locked --quiet -p "$CRATE" --features cli --bin uniffi-bindgen -- \
    generate --library "$CARGO_TARGET_DIR/debug/lib$LIBNAME.dylib" --language swift --no-format --out-dir "$TMP")
cmp -s "$TMP/$LIBNAME.swift" "$GENERATED/$LIBNAME.swift" || cp "$TMP/$LIBNAME.swift" "$GENERATED/$LIBNAME.swift"
cp "$TMP/${LIBNAME}FFI.h" "$HEADERS/"
cp "$TMP/${LIBNAME}FFI.modulemap" "$HEADERS/module.modulemap"

args=()
note "building for $HOST"
build "$HOST"
args+=(-library "$CARGO_TARGET_DIR/$HOST/release/lib$LIBNAME.a" -headers "$HEADERS")
if [[ $IOS == 1 ]]; then
    note "building for aarch64-apple-ios"
    build aarch64-apple-ios
    args+=(-library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/lib$LIBNAME.a" -headers "$HEADERS")
fi
mkdir -p "$OUT"
rm -rf "$XCF"
xcodebuild -create-xcframework "${args[@]}" -output "$XCF" >/dev/null
note "done: $XCF"
