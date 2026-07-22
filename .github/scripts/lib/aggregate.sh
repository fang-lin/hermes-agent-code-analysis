# all_reviews_pass <dir> [expected_count] —— dir 下所有 review-*.json 的 verdict 都为
# pass 才退出 0。没有任何 review 文件视为不过(退出 1)。
# 传了 expected_count 时,还要求 review-*.json 的数量恰好等于它——否则视为不过
# (防止复核 agent 崩溃、没写文件,导致文件数少于策略要求的复核人数却被判过)。
all_reviews_pass() {
  local dir="$1" expected="${2:-}"
  shopt -s nullglob
  local files=("$dir"/review-*.json)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || return 1
  if [ -n "$expected" ] && [ "${#files[@]}" -ne "$expected" ]; then return 1; fi
  local f v
  for f in "${files[@]}"; do
    v="$(jq -r '.verdict' "$f" 2>/dev/null)"
    [ "$v" = "pass" ] || return 1
  done
  return 0
}
