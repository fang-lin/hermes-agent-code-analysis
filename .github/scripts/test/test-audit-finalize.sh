#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"

# audit-finalize.sh 的分支名带 ${GITHUB_RUN_ID:-local} 后缀;本测试断言的是
# 精确分支名 auto/audit-ledger-local,在 CI 里 GITHUB_RUN_ID 已被设置,必须
# 在此 unset 让分支名确定性地落回 -local,不依赖跑这个测试时外部环境有没有设它。
unset GITHUB_RUN_ID

# 真仓基线:跑完必须原样——脚本会在 REPO_ROOT 指向的仓里 checkout/commit/push,
# 这里 REPO_ROOT 永远指向临时仓,真仓不该被 `git -C` 碰到分毫。
base_branch="$(git -C "$root" branch --show-current)"
base_status="$(git -C "$root" status --porcelain)"

stub="$(mktemp -d)"; log="$stub/calls"; full="$stub/calls-full"; lastbody="$stub/last-body"; trap 'rm -rf "$stub"' EXIT
# gh 桩:除了记调用,还把 --body-file 内容(stdin '-' 或真文件路径)落到 lastbody,
# 供断言"复核循环"标准记录是否真的贴进了 issue 正文。
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"
printf 'gh %s\n' "\$*" >> "$full"
[ "\$1 \$2" = "pr create" ] && echo "https://pr/1"
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--body-file" ]; then
    if [ "\$a" = "-" ]; then cat > "$lastbody"; else cat "\$a" > "$lastbody" 2>/dev/null; fi
  fi
  prev="\$a"
done
exit 0
EOF
chmod +x "$stub/gh"

# 临时仓,带 ledger + srcmap + policy + libs + 一份"总开关开着"的 sync-policy
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib" "$work/docs/zh"
cp "$root/.github/scripts/lib/ledger.sh" "$root/.github/scripts/lib/srcmap.sh" \
   "$root/.github/scripts/lib/policy.sh" "$root/.github/scripts/lib/issue.sh" \
   "$root/.github/scripts/lib/cost.sh" "$work/.github/scripts/lib/"
cp "$root/.github/chapter-source-map.yml" "$work/.github/"
cat > "$work/.github/sync-policy.yml" <<'EOF'
enabled: true
audit:
  enabled: true
EOF
echo '{}' > "$work/audit-ledger.json"; echo x > "$work/docs/zh/05-x.md"
( cd "$work" && git init -q -b main )
git -C "$work" config user.email ci@local && git -C "$work" config user.name ci
( cd "$work" && git add -A && git commit -q -m init )
main_branch="$(git -C "$work" branch --show-current)"

rev="$stub/rev"; mkdir -p "$rev"
echo '{"errors":[{"位置":"05 §1","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$rev/review-05.json"
# 06 故意不写 review-06.json——模拟 matrix 里这条腿崩了、没落下复核结果
# 顺带丢两份 cost-*.json 进复核目录(模拟 download-artifact merge-multiple 把
# matrix 各分支的 cost-<chapter>.json 跟 review-<chapter>.json 拍平进同一个目录)。
echo '{"total_cost_usd":0.03}' > "$rev/cost-05.json"
echo '{"total_cost_usd":0.04}' > "$rev/cost-06.json"

GH_CMD="$stub/gh" REPO_ROOT="$work" ISSUE=1 PIN=vNow \
  bash "$root/.github/scripts/audit-finalize.sh" "$rev" '["05","06"]' >/dev/null 2>&1 || true

# (a) 有错应派 ③
grep -q "gh workflow run" "$log" || { echo "有错应派 ③"; exit 1; }

# (a2) 有错时应贴"复核循环"标准记录(含折叠块列出查出的错),而不是原来的一句话
grep -q "^### \[复核循环\] · " "$lastbody" || { echo "应贴 复核循环 标准记录(format_record 头,带 · 分隔)"; cat "$lastbody"; exit 1; }
grep -q "^- 触发:每周复核(2 章)$" "$lastbody" || { echo "标准记录应含'触发'行(2 章=chapters 长度)"; cat "$lastbody"; exit 1; }
grep -q "^- 干了什么:1 章通盘复核$" "$lastbody" || { echo "标准记录应含'干了什么'行(1 章=有复核结果的 review-*.json 数)"; cat "$lastbody"; exit 1; }
grep -q "^- 结论:查出 1 处错,已派 ③ 出纠错 PR$" "$lastbody" || { echo "标准记录应含'结论'行"; cat "$lastbody"; exit 1; }
grep -q "<summary>查出的错(1 处)</summary>" "$lastbody" || { echo "有错应有'查出的错'折叠块"; cat "$lastbody"; exit 1; }

# (a3) 有错时还应贴一份交给③的机器原文(work_plan 原始 JSON,可审计)
grep -q "交给 ③ 的输入" "$lastbody" || { echo "派③应带 work_plan 机器原文折叠块"; cat "$lastbody"; exit 1; }
grep -q '"源码依据":"f:1"' "$lastbody" || { echo "机器原文折叠块应含 work_plan 原始字段值"; cat "$lastbody"; exit 1; }

# (a4) token 行应是真实求和(0.03+0.04=0.0700),不是占位/空白;派③时应把本层
# 花费当 prior_cost 传下去(用 $full,因为 $log 只记了前两个词,抓不到 -f 参数)。
grep -q "^- token:本层 0.0700 美元 / 累计 0.0700 美元$" "$lastbody" || { echo "token 行应是真实求和"; cat "$lastbody"; exit 1; }
grep -q -- "-f prior_cost=0.0700" "$full" || { echo "派③应把本层花费当 prior_cost 传下去"; cat "$full"; exit 1; }

# (b) ledger 更新走 PR,不是直接推 main:既要看到 gh pr create,
#     也要确认那个 ledger 提交真的没有落在 main 分支上。
grep -q "gh pr create" "$log" || { echo "ledger 应走 PR"; exit 1; }
cur_branch="$(git -C "$work" branch --show-current)"
[ "$cur_branch" != "$main_branch" ] || { echo "不该直接停在 $main_branch 上提交"; exit 1; }
assert_eq "auto/audit-ledger-local" "$cur_branch" "应切到 auto/audit-ledger-<run id> 分支"
git -C "$work" log "$main_branch" --oneline | grep -q "audit: 盖章" \
  && { echo "ledger 提交不该出现在 $main_branch 历史里"; exit 1; }

# (c) 只盖真有复核结果的章:05 有 review 文件 → 盖章 pass;
#     06 没有 review 文件(matrix 腿崩了)→ 不盖章,留 pending,并发提醒评论。
assert_eq "pass" "$(jq -r '."05".result' "$work/audit-ledger.json")" "05 应盖章 pass"
assert_eq "vNow" "$(jq -r '."05".pin' "$work/audit-ledger.json")" "05 应写入本轮 pin"
# doc_commit 必须是 $work 仓里 05*.md 的真实 commit hash(非空)——
# chapter_doc_commit 内部的 git 若跑在了错的仓(比如进程 cwd 那个仓)会
# exit 128 被吞掉、悄悄回显空串,is_pending 会把 "" 当成"文档变了",
# 该章永远盖不上章、卡在复核队列里出不去。用绝对路径 glob 避免让 shell
# 按当前 cwd(而不是 $work)展开 05*.md。
real_doc_commit="$(git -C "$work" log -1 --format=%H -- "$work/docs/zh/05"*.md)"
[ -n "$real_doc_commit" ] || { echo "测试前提坏了:真实仓里 05 的 doc_commit 查不到"; exit 1; }
assert_eq "$real_doc_commit" "$(jq -r '."05".doc_commit' "$work/audit-ledger.json")" "05 应盖上真实 doc_commit(非空)"
assert_eq "false" "$(jq 'has("06")' "$work/audit-ledger.json")" "06 无复核结果,不该被盖章"
grep -q "复核结果缺失" "$full" || { echo "有章缺复核结果,应有 issue comment 提醒下轮重试"; exit 1; }

# (d) 总开关(sync-policy.enabled 或 audit.enabled)关闭 → 提前退出,不发任何 gh 调用
: > "$log"; : > "$full"
cat > "$work/.github/sync-policy.yml" <<'EOF'
enabled: false
audit:
  enabled: true
EOF
GH_CMD="$stub/gh" REPO_ROOT="$work" ISSUE=1 PIN=vNow \
  bash "$root/.github/scripts/audit-finalize.sh" "$rev" '["05","06"]' >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "总开关关闭时应正常退出(0),实得 $rc"; exit 1; }
[ ! -s "$log" ] || { echo "总开关关闭时不该有任何 gh 调用"; cat "$log"; exit 1; }

# 真仓状态原样未动
assert_eq "$base_branch" "$(git -C "$root" branch --show-current)" "真仓分支不该变"
assert_eq "$base_status" "$(git -C "$root" status --porcelain)" "真仓工作区不该变"

echo "test-audit-finalize: PASS"
