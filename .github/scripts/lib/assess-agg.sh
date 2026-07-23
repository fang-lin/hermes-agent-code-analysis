# overall_complexity <dir> —— 各区域 complexity 取最高档。
overall_complexity() {
  local dir="$1" rank=0 best="none" f c r
  declare -A R=([none]=0 [cosmetic]=1 [shallow]=2 [deep]=3)
  for f in "$dir"/region-*.json; do
    [ -e "$f" ] || continue
    c="$(jq -r '.complexity' "$f")"; r="${R[$c]:-0}"
    [ "$r" -gt "$rank" ] && { rank="$r"; best="$c"; }
  done
  echo "$best"
}

# decide_route <overall> <has_changes(0/1)> <any_overturned(0/1)> <has_new_chapter(0/1)>
#   全 none 或没改动         → close
#   命中 flag 条件(deep/新章/被推翻→低置信) → proceed_flagged
#   否则                     → proceed
# 注意:这里的 flag 条件是硬编码,必须与 sync-policy.yml 的 .assess.flag_when
# (complexity:deep / coverage_gap_new_chapter / confidence:low)保持一致——
# 改策略时记得回来同步这个函数,反之亦然。
decide_route() {
  local overall="$1" has_changes="$2" overturned="$3" newchap="$4"
  if [ "$has_changes" != "1" ] || [ "$overall" = "none" ]; then echo "close"; return; fi
  if [ "$overall" = "deep" ] || [ "$newchap" = "1" ] || [ "$overturned" = "1" ]; then
    echo "proceed_flagged"; return
  fi
  echo "proceed"
}

# should_handoff <overall_complexity> <plan_items_count> <policy_file> —— 该不该交本地做?
# 满足任一 → 回显 "yes";否则 "no"。读 sync-policy 的 assess.handoff。
# 依赖 policy_get(lib/policy.sh):调用方需先 source 好那个文件。
should_handoff() {
  local overall="$1" count="$2" pol="$3"
  local on_deep over
  on_deep="$(policy_get "$pol" '.assess.handoff.on_deep')"
  over="$(policy_get "$pol" '.assess.handoff.plan_items_over')"
  if [ "$on_deep" = "true" ] && [ "$overall" = "deep" ]; then echo yes; return; fi
  # over 为空或 0 时关闭这条;非零且 count 超过则交本地
  if [ -n "$over" ] && [ "$over" != "0" ] && [ "$count" -gt "$over" ]; then echo yes; return; fi
  echo no
}
