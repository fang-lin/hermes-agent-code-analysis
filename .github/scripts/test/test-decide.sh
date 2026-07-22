#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/decide.sh"

should_bump_pin sync;  assert_eq "0" "$?" "sync 应 bump"
should_bump_pin audit; assert_eq "1" "$?" "audit 不 bump"
should_bump_pin xxx 2>/dev/null; assert_eq "2" "$?" "未知 cycle 应报错"
echo "test-decide: PASS"
