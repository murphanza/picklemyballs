#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# SDK-independent tests. Apple SDK compilation is a separate Xcode check.
swift_bin="${SWIFT_BIN:-swift}"
cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/pickle-score-check.XXXXXX")"
trap 'rm -rf "$cache_dir"' EXIT
export XDG_CACHE_HOME="$cache_dir"
export CLANG_MODULE_CACHE_PATH="$cache_dir/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir/modules"
"$swift_bin" test --jobs "${SWIFT_TEST_JOBS:-4}" \
    --cache-path "$cache_dir/pm" \
    --config-path "$cache_dir/config" \
    --security-path "$cache_dir/security"
