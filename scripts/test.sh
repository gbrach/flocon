#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
flags=(--disable-sandbox --build-system native --disable-xctest)
# Some Command Line Tools releases ship Testing in a framework instead of the compiler's import path.
developer="$(xcode-select -p)"
frameworks="$developer/Library/Developer/Frameworks"
if [[ -d "$frameworks/Testing.framework" ]]; then
    flags+=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
fi
swift test "${flags[@]}" "$@"
