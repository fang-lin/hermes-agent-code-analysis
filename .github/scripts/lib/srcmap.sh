# chapters_for_path <map_yaml> <path> —— 回显所有前缀匹配 path 的章号(每行一个)。
chapters_for_path() {
  local map="$1" path="$2" ch pfx
  while IFS= read -r ch; do
    while IFS= read -r pfx; do
      [ -n "$pfx" ] || continue
      case "$path" in "$pfx"*) echo "$ch"; break ;; esac
    done < <(yq -r ".chapters.\"$ch\"[]" "$map")
  done < <(yq -r '.chapters | keys | .[]' "$map")
}

# path_is_covered <map_yaml> <path> —— 有任一章覆盖则退出 0。
path_is_covered() {
  [ -n "$(chapters_for_path "$1" "$2")" ]
}
