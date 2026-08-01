#!/bin/sh
# Runs the TouchSeal unit tests.
#
# The tests use swift-testing, which ships inside the active developer
# directory. With full Xcode installed, `swift test` finds it unaided. With
# only the Command Line Tools, Testing.framework is present but neither on the
# framework search path nor on the runtime search path, so both are supplied
# here.
#
# None of these tests touch the Keychain or Touch ID.
set -eu

developer_dir="$(xcode-select --print-path)"

case "$developer_dir" in
*/CommandLineTools)
    frameworks="$developer_dir/Library/Developer/Frameworks"
    interop="$developer_dir/Library/Developer/usr/lib"
    exec swift test \
        -Xswiftc -F -Xswiftc "$frameworks" \
        -Xlinker -rpath -Xlinker "$frameworks" \
        -Xlinker -rpath -Xlinker "$interop" \
        "$@"
    ;;
*)
    exec swift test "$@"
    ;;
esac
