# sum_cost_usd <dir> —— 把 <dir> 下 cost-*.json 逐份文件的 total_cost_usd 加总,
# echo 出 "%.4f" 格式的美元数;目录不存在/没有匹配文件时输出 "0.0000"。
#
# 逐文件读、逐个起独立 jq 进程解析——不用 `find -exec {} +` 批处理:那样会把
# 所有匹配文件一次性塞给同一个 jq 进程当成一整段 token 流解析,只要其中一份
# 文件损坏(claude 被 CI 超时/OOM 杀掉,留下半截 JSON),jq 在那份文件处直接
# 中断,连排在它后面的正常文件也一起读不到——花费被非确定性地少算/清零
# (具体丢多少取决于 find 返回文件的顺序,顺序是文件系统相关、不保证稳定)。
# 逐文件跑,坏文件只损失它自己那一份(jq 失败输出为空,被下面 case 挡住跳过),
# 不牵连旁边的正常文件。
#
# awk 的 `printf "%.4f"` 会按 LC_NUMERIC 决定小数点符号(某些 locale 下是逗号,
# 比如 de_DE.UTF-8 -> "0,0000"),下游数值比较会因此悄悄失真——强制 LC_ALL=C
# 保证小数点是点号,和 jq 输出、GitHub Actions 默认 locale 一致。
sum_cost_usd() {
  local dir="$1" sum="0.0000" f v
  while IFS= read -r f; do
    v="$(jq -r '.total_cost_usd // empty' "$f" 2>/dev/null)"
    case "$v" in ''|*[!0-9.]*) continue ;; esac   # 空或非数字(损坏/缺字段)→ 跳过这个文件
    sum="$(LC_ALL=C awk -v a="$sum" -v b="$v" 'BEGIN{printf "%.4f", a+b}')"
  done < <(find "$dir" -name 'cost-*.json' 2>/dev/null)
  echo "$sum"
}
