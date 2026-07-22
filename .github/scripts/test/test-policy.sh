#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/policy.sh"
pol="$here/../../sync-policy.yml"

assert_eq "true" "$(policy_get "$pol" '.enabled')" "enabled 应为 true"
assert_eq "3"    "$(policy_get "$pol" '.sync.reviewers')" "reviewers 应为 3"
assert_eq "3"    "$(policy_get "$pol" '.sync.rewrite_max_rounds')" "轮数应为 3"
assert_eq "true" "$(policy_get "$pol" '.sync.reviewers_must_all_pass')" "全过才算过"
assert_eq ""     "$(policy_get "$pol" '.sync.nonexistent')" "缺键应回空串"
echo "test-policy: PASS"
