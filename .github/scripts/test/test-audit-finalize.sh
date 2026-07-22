#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"

# 真仓基线:跑完必须原样——脚本会在 REPO_ROOT 指向的仓里 checkout/commit/push,
# 这里 REPO_ROOT 永远指向临时仓,真仓不该被 `git -C` 碰到分毫。
base_branch="$(git -C "$root" branch --show-current)"
base_status="$(git -C "$root" status --porcelain)"

stub="$(mktemp -d)"; log="$stub/calls"; full="$stub/calls-full"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"
printf 'gh %s\n' "\$*" >> "$full"
[ "\$1 \$2" = "pr create" ] && echo "https://pr/1"
exit 0
EOF
chmod +x "$stub/gh"

# 临时仓,带 ledger + srcmap + policy + libs + 一份"总开关开着"的 sync-policy
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib" "$work/docs/zh"
cp "$root/.github/scripts/lib/ledger.sh" "$root/.github/scripts/lib/srcmap.sh" \
   "$root/.github/scripts/lib/policy.sh" "$work/.github/scripts/lib/"
cp "$root/.github/chapter-source-map.yml" "$work/.github/"
cat > "$work/.github/sync-policy.yml" <<'EOF'
enabled: true
audit:
  enabled: true
EOF
echo '{}' > "$work/audit-ledger.json"; echo x > "$work/docs/zh/05-x.md"
( cd "$work" && git init -q -b main && git add -A && git commit -q -m init )
main_branch="$(git -C "$work" branch --show-current)"

rev="$stub/rev"; mkdir -p "$rev"
echo '{"errors":[{"位置":"05 §1","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$rev/review-05.json"
# 06 故意不写 review-06.json——模拟 matrix 里这条腿崩了、没落下复核结果

GH_CMD="$stub/gh" REPO_ROOT="$work" ISSUE=1 PIN=vNow \
  bash "$root/.github/scripts/audit-finalize.sh" "$rev" '["05","06"]' >/dev/null 2>&1 || true

# (a) 有错应派 ③
grep -q "gh workflow run" "$log" || { echo "有错应派 ③"; exit 1; }

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
