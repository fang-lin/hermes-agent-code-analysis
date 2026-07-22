#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
sh="$root/.github/scripts/hermes-release-watch.sh"

out="$(HERMES_PIN_TAG=v1 HERMES_LATEST=v1 REPO_ROOT="$root" bash "$sh")"
assert_eq "UPTODATE (v1)" "$out" "同版应 UPTODATE"
out="$(HERMES_PIN_TAG=v1 HERMES_LATEST=v2 REPO_ROOT="$root" bash "$sh")"
assert_eq "NEW v2" "$out" "新版应 NEW v2"
echo "test-release-watch: PASS"
