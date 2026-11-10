#!/bin/sh
# Command Line Tools ship swift-testing without wiring it into SwiftPM; point at it explicitly.
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if xcodebuild -version >/dev/null 2>&1; then exec swift test "$@"; fi
exec swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
