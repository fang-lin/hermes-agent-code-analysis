# policy_get <yaml_file> <yq_path> —— 读一个策略值到 stdout。
# 用 yq(mikefarah/yq v4)。缺键回显空串,退出码 0。
policy_get() {
  local file="$1" path="$2"
  yq -r "${path} // \"\"" "$file"
}
