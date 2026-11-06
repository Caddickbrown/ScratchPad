#!/bin/sh
# What's on the ⌘K menu, on this Mac: no app, no host, no simulator. The menu's rules are the kit's, tested there.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -o "$out/commands" "$here/../../../kit/swift/CommandPalette.swift" "$here/../../Sources/ScratchpadApp/ScratchpadCommands.swift" "$here/main.swift"
"$out/commands"
