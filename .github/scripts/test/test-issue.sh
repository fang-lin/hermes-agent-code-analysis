#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/issue.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

printf '时间=14:03 → 14:11\ntoken=本层 140k / 累计 140k\n' > "$tmp/kv"
out="$(format_record "③同步" "https://run/1" "$tmp/kv")"
assert_eq "### [③同步] · https://run/1" "$(printf '%s\n' "$out" | sed -n 1p)" "标题行"
assert_eq "- 时间:14:03 → 14:11" "$(printf '%s\n' "$out" | sed -n 2p)" "时间行"
assert_eq "- token:本层 140k / 累计 140k" "$(printf '%s\n' "$out" | sed -n 3p)" "token 行"

printf -- '- #1 改了 A\n' > "$tmp/body"
d="$(format_details "本次改了哪些" "$tmp/body")"
assert_eq "<details><summary>本次改了哪些</summary>" "$(printf '%s\n' "$d" | sed -n 1p)" "details 头"

# kv 文件末行无换行符,也要渲染出来(read 循环加固回归)
printf 'a=1\nb=2' > "$tmp/kv2"   # 故意不带末尾换行
out2="$(format_record "L" "u" "$tmp/kv2")"
assert_eq "- a:1" "$(printf '%s\n' "$out2" | sed -n 2p)" "无末换行 首行"
assert_eq "- b:2" "$(printf '%s\n' "$out2" | sed -n 3p)" "无末换行 末行不丢"

echo "test-issue: PASS"
