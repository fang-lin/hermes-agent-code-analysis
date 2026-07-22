# all_reviews_pass <dir> —— dir 下所有 review-*.json 的 verdict 都为 pass 才退出 0。
# 没有任何 review 文件视为不过(退出 1)。
all_reviews_pass() {
  local dir="$1"
  shopt -s nullglob
  local files=("$dir"/review-*.json)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || return 1
  local f v
  for f in "${files[@]}"; do
    v="$(jq -r '.verdict' "$f" 2>/dev/null)"
    [ "$v" = "pass" ] || return 1
  done
  return 0
}
