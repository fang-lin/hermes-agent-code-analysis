source "$(dirname "${BASH_SOURCE[0]}")/srcmap.sh"

# docs/zh/<ch>*.md 的最近 commit
chapter_doc_commit() {
  local ch="$1" docs="${2:-docs/zh}"
  git log -1 --format=%H -- "$docs/$ch"*.md 2>/dev/null
}

# 记录里该章 pin → cur_pin 之间,该章地盘下有没有改动(gh compare 过滤)
chapter_source_changed() {
  local ledger="$1" map="$2" ch="$3" cur="$4" gh="${5:-gh}"
  local recpin; recpin="$(jq -r --arg c "$ch" '.[$c].pin // ""' "$ledger")"
  [ -z "$recpin" ] && return 0
  [ "$recpin" = "$cur" ] && return 1
  # 拉 recpin..cur 的改动文件;gh 失败必须 fail-safe(当作要复核),不能悄悄当"没变"。
  # 注:gh api compare 的 files 约 300 个封顶,超大 diff 会截断——TODO(后续) 加分页。
  local files
  if ! files="$("$gh" api "repos/NousResearch/hermes-agent/compare/${recpin}...${cur}" --jq '.files[].filename')"; then
    echo "ledger: gh compare 失败(ch=$ch ${recpin}...${cur}),按'需复核'处理" >&2
    return 0
  fi
  local f hits
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(chapters_for_path "$map" "$f")"   # 只调一次(修 Minor:原来调两次)
    # 行锚定匹配,避免子串误判(修 Minor:原来是 *"$ch"* 子串匹配)
    case $'\n'"$hits"$'\n' in *$'\n'"$ch"$'\n'*) return 0 ;; esac
  done <<< "$files"
  return 1
}

# 待复核 = 无记录 / 文档 commit 变了 / 地盘源码变了
is_pending() {
  local ledger="$1" map="$2" ch="$3" cur="$4" docs="${5:-docs/zh}"
  local rec; rec="$(jq -r --arg c "$ch" '.[$c] // "null"' "$ledger")"
  [ "$rec" = "null" ] && return 0
  local recdoc curdoc
  recdoc="$(jq -r --arg c "$ch" '.[$c].doc_commit' "$ledger")"
  curdoc="$(chapter_doc_commit "$ch" "$docs")"
  [ "$recdoc" != "$curdoc" ] && return 0
  chapter_source_changed "$ledger" "$map" "$ch" "$cur"
}

# 盖章:更新一章记录,回显新 ledger
stamp_chapter() {
  local ledger="$1" ch="$2" pin="$3" commit="$4" result="$5"
  jq --arg c "$ch" --arg p "$pin" --arg d "$commit" --arg r "$result" \
    '.[$c] = {pin:$p, doc_commit:$d, result:$r}' "$ledger"
}
