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
decide_route() {
  local overall="$1" has_changes="$2" overturned="$3" newchap="$4"
  if [ "$has_changes" != "1" ] || [ "$overall" = "none" ]; then echo "close"; return; fi
  if [ "$overall" = "deep" ] || [ "$newchap" = "1" ] || [ "$overturned" = "1" ]; then
    echo "proceed_flagged"; return
  fi
  echo "proceed"
}
