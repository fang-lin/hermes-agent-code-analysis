#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/aggregate.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 空目录 → 不过
all_reviews_pass "$tmp"; assert_eq "1" "$?" "空目录应不过"

# 三个都 pass → 过
for n in 1 2 3; do echo '{"verdict":"pass","comments":"ok"}' > "$tmp/review-$n.json"; done
all_reviews_pass "$tmp"; assert_eq "0" "$?" "三个 pass 应过"

# 有一个 fail → 不过
echo '{"verdict":"fail","comments":"锚点对不上"}' > "$tmp/review-2.json"
all_reviews_pass "$tmp"; assert_eq "1" "$?" "含 fail 应不过"

# 传 expected_count:文件数不够(复核 agent 崩溃、没写文件)即使已有的都 pass 也不过
tmp2="$(mktemp -d)"
for n in 1 2; do echo '{"verdict":"pass","comments":"ok"}' > "$tmp2/review-$n.json"; done
all_reviews_pass "$tmp2" 3; assert_eq "1" "$?" "2 个 pass 但要求 3 个应不过"
all_reviews_pass "$tmp2" 2; assert_eq "0" "$?" "2 个 pass 且要求 2 个应过"
rm -rf "$tmp2"

echo "test-aggregate: PASS"
