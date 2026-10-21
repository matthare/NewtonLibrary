#!/bin/sh
# Builds the package reader as a command-line tool and runs it on the given files.
#   tests/run_inspect.sh FILE...          (ICON_DIR=folder also saves the icons)
DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DIR/build"
# The Command Line Tools copy of swiftc can be broken, so use Xcode's if it's there
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -O -o "$DIR/build/inspect" "$DIR"/NewtonLibrary/Package/*.swift "$DIR/tests/main.swift" || exit 1
exec "$DIR/build/inspect" "$@"
