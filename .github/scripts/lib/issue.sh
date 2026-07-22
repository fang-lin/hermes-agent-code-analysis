# format_record <layer> <run_url> <kv_file> —— 输出一条标准记录 markdown。
# kv_file 每行 "键=值",按序渲染成 "- 键:值"。
format_record() {
  local layer="$1" run_url="$2" kv_file="$3"
  printf '### [%s] · %s\n' "$layer" "$run_url"
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf -- '- %s:%s\n' "${line%%=*}" "${line#*=}"
  done < "$kv_file"
}

# format_details <summary> <body_file> —— 输出一个可折叠块。
format_details() {
  local summary="$1" body_file="$2"
  printf '<details><summary>%s</summary>\n\n' "$summary"
  cat "$body_file"
  printf '\n</details>\n'
}
