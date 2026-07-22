# policy_get <yaml_file> <yq_path> —— 读一个策略值到 stdout。
# 用 yq(mikefarah/yq v4)。缺键(yq 返回 null)回显空串;false/0 等值原样返回。
policy_get() {
  local file="$1" path="$2" v
  v="$(yq -r "${path}" "$file")"
  [ "$v" = "null" ] && echo "" || echo "$v"
}
