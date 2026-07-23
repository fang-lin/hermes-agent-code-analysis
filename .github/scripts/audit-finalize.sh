#!/usr/bin/env bash
set -uo pipefail
rev="$1"; chapters="$2"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/ledger.sh"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/issue.sh"
source "$ROOT/.github/scripts/lib/cost.sh"

# 0) 总开关(kill-switch):sync-policy 顶层关掉,或复核这一环(audit)自己关掉,
#    都不该跑 audit-finalize——什么都不派、什么都不盖章。
if [ "$(policy_get "$ROOT/.github/sync-policy.yml" '.enabled')" != "true" ] || \
   [ "$(policy_get "$ROOT/.github/sync-policy.yml" '.audit.enabled')" != "true" ]; then
  echo "sync-policy 关闭,audit-finalize 跳过" >&2; exit 0
fi

LEDGER="$ROOT/audit-ledger.json"; DOCS="$ROOT/docs/zh"

# 1) 合并确认的错 → work plan(-sc:slurp 成一个数组,同时压成单行——
#    只 -s 会 pretty-print 成多行,当 -f work_plan= 的值传给 gh workflow run 会被破坏)
work="$(jq -sc '[.[].errors[]?]' "$rev"/review-*.json)"
n="$(jq 'length' <<<"$work")"

# 2) 贴标准记录(人可读,有错时附"查出的错"折叠块),再决定要不要调 ③(audit,不动 pin)
chapter_count="$(jq 'length' <<<"$chapters")"
reviewed_count=0
for f in "$rev"/review-*.json; do [ -e "$f" ] || continue; reviewed_count=$((reviewed_count+1)); done

# 本层花了多少钱(尽力而为,cost-*.json 缺失/损坏时按 0 算,不影响流程)——
# download-artifact merge-multiple 把每个 matrix 分支的 cost-<chapter>.json 和
# review-<chapter>.json 拍平进同一个 $rev,跟读 review 结果同目录扫。
layer_cost="$(sum_cost_usd "$rev")"

kv="$(mktemp)"
{
  printf '触发=每周复核(%s 章)\n' "$chapter_count"
  printf '干了什么=%s 章通盘复核\n' "$reviewed_count"
  if [ "$n" -gt 0 ]; then
    printf '结论=查出 %s 处错,已派 ③ 出纠错 PR\n' "$n"
  else
    printf '结论=未查出错\n'
  fi
  printf 'token=本层 %s 美元 / 累计 %s 美元\n' "$layer_cost" "$layer_cost"
} > "$kv"
body="$(mktemp)"
{
  format_record "复核循环" "${RUN_URL:-}" "$kv"
  if [ "$n" -gt 0 ]; then
    errs_readable="$(mktemp)"
    jq -r '.[] | "- \(.["位置"]):「\(.["现状"])」→「\(.["改成什么"])」(\(.["类型"]),依据 \(.["源码依据"]))"' <<<"$work" \
      > "$errs_readable"
    format_details "查出的错(${n} 处)" "$errs_readable"
    rm -f "$errs_readable"
    # n>0 才会往下派 ③(见下方),贴一份交给它的机器原文,留痕可审计。
    handoff_raw="$(mktemp)"
    { printf '```json\n'; printf '%s\n' "$work"; printf '```\n'; } > "$handoff_raw"
    format_details "交给 ③ 的输入(work_plan 机器原文)" "$handoff_raw"
    rm -f "$handoff_raw"
  fi
} > "$body"
"$GH" issue comment "$ISSUE" --body-file "$body"
rm -f "$kv" "$body"

if [ "$n" -gt 0 ]; then
  "$GH" workflow run hermes-sync.yml \
    -f work_plan="$work" -f cycle=audit -f issue_number="$ISSUE" -f new_tag="" \
    -f prior_cost="$layer_cost"
fi

# 3) 逐章盖章(pass)——只盖真有复核结果的章。matrix 某一腿崩了、没落下
#    review-<ch>.json 的章,不能被当成"过了"悄悄盖章——那样会把它可能存在的
#    错漏判成"无错"、从复核队列里丢掉。留空不盖,下一轮 audit-prep 会因为
#    没记录继续把它判成 pending,重新排进来。
missing=()
for ch in $(jq -r '.[]' <<<"$chapters"); do
  f="$rev/review-$ch.json"
  if [ ! -e "$f" ]; then
    echo "audit-finalize: $ch 无复核结果($f 不存在),跳过盖章,留待下轮" >&2
    missing+=("$ch")
    continue
  fi
  commit="$(chapter_doc_commit "$ch" "$DOCS")"
  stamp_chapter "$LEDGER" "$ch" "$PIN" "$commit" "pass" > "$LEDGER.new" && mv "$LEDGER.new" "$LEDGER"
done

if [ "${#missing[@]}" -gt 0 ]; then
  "$GH" issue comment "$ISSUE" --body "${#missing[@]} 章复核结果缺失,未盖章,下轮重试"
fi

# 4) ledger 更新走一个分支 + 自动合并 PR(绝不直接 push main)
br="auto/audit-ledger-${GITHUB_RUN_ID:-local}"
git -C "$ROOT" checkout -B "$br" >/dev/null 2>&1
git -C "$ROOT" add "$LEDGER"
if git -C "$ROOT" diff --cached --quiet; then
  echo "ledger 无改动(章全被跳过或结果不变),audit-finalize 跳过开 PR" >&2
  exit 0
fi
git -C "$ROOT" commit -m "audit: 盖章本轮复核过的章" >/dev/null
git -C "$ROOT" push -u origin "$br" >/dev/null
pr="$("$GH" pr create --base main --head "$br" --title "audit: 更新复核记录表" --body "见 #${ISSUE}")"
"$GH" pr merge "$pr" --auto --squash
