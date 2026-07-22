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
  [ -z "$recpin" ] && return 0                       # 没记录 → 要核
  [ "$recpin" = "$cur" ] && return 1                 # pin 没动 → 地盘必没动
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -n "$(chapters_for_path "$map" "$f")" ] || continue
    case "$(chapters_for_path "$map" "$f")" in *"$ch"*) return 0 ;; esac
  done < <("$gh" api "repos/NousResearch/hermes-agent/compare/${recpin}...${cur}" --jq '.files[].filename' 2>/dev/null)
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
