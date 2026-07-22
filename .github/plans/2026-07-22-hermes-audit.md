# 复核循环 Implementation Plan(Plan 3 / 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建成工作流 `hermes-audit.yml`:每周挑出"待复核"的章(依复核记录表判定),每章派 `factual-reviewer` 对当前 pin 通盘复核,把确认的错列成 work plan 交给 ③ 出纠错 PR,并更新复核记录表——同一状态只核一次,某章源码或文档一变就重新计入。

**Architecture:** 三段式:准备 job 读 `audit-ledger.json` 判出待复核的章、按 `chapters_per_run` 取上限,输出 matrix 清单;matrix 每章一个 `claude -p`(以 factual-reviewer 的纪律)通盘复核、把确认的错写成 work plan 条目;finalize 汇总——有错就调 ③(cycle=audit,不 bump pin)出纠错 PR,并把这一轮所有核过的章在记录表里盖章,记录表更新走一个自动合并的 ledger PR。

**Tech Stack:** GitHub Actions(cron + 动态 matrix)、bash、`gh`、`yq`、`jq`、Claude Code headless、复用 Plan 1 的 `hermes-sync.yml`、Plan 2 的 `chapter-source-map.yml`/`srcmap.sh`、`.claude/agents/factual-reviewer.md`。

## Global Constraints

同 Plan 1/2。要点:agent 走 `claude -p` 非 bare + 订阅 token;agent 只出 JSON,副作用交给 bash;阈值读 `sync-policy.yml`(本 plan 用 `.audit.chapters_per_run`);复核 agent 必须独立、贴代码举证;**纠错 PR 不动 pin**;提交只 stage 明确路径。

---

## File Structure

**新建:**
- `audit-ledger.json` — 复核记录表(仓库根,git 跟踪),初值 `{}`。
- `.github/schemas/audit-ledger.json` — 记录表 schema。
- `.github/scripts/lib/ledger.sh` — `chapter_doc_commit`、`chapter_source_changed`、`is_pending`、`stamp_chapter` 四个函数。
- `.github/scripts/audit-prep.sh` — 读记录表 → 待复核的章 → 取上限 → 输出 matrix 清单。
- `.github/schemas/audit-review.json` — 复核输出 schema(`{errors: plan_items[]}`)。
- `.github/prompts/audit-review.md` — 通盘复核提示。
- `.github/scripts/audit-finalize.sh` — 汇总 → 调 ③ → 盖章 → ledger PR。
- `.github/workflows/hermes-audit.yml` — 每周 cron + 手动;准备 → matrix → finalize。
- Test:`.github/scripts/test/test-ledger.sh`、`test-audit-prep.sh`。

**依赖(已存在):** Plan 1 的 `assert.sh`/`sync-policy.yml`/`hermes-sync.yml`;Plan 2 的 `chapter-source-map.yml`/`srcmap.sh`。

---

## Task 1:记录表 schema + 初值 + ledger 函数

**Files:**
- Create: `audit-ledger.json`
- Create: `.github/schemas/audit-ledger.json`
- Create: `.github/scripts/lib/ledger.sh`
- Test: `.github/scripts/test/test-ledger.sh`

**Interfaces:**
- Produces:
  - `chapter_doc_commit <ch> <docs_dir>` —— 回显 `docs/zh/<ch>*.md` 的最近 commit hash(用 git log)。
  - `chapter_source_changed <ledger> <map> <ch> <cur_pin> <gh_cmd>` —— 记录里该章 pin 到 cur_pin 之间、该章地盘下有改动则退出 0,否则 1;记录里无该章 pin 也退出 0(视为要核)。
  - `is_pending <ledger> <map> <ch> <cur_pin> <docs_dir>` —— 该章待复核则退出 0。
  - `stamp_chapter <ledger> <ch> <pin> <commit> <result>` —— 回显更新后的 ledger JSON。

- [ ] **Step 1: 写 schema + 初值**

`.github/schemas/audit-ledger.json`:
```json
{
  "type": "object",
  "additionalProperties": {
    "type": "object", "additionalProperties": false,
    "required": ["pin", "doc_commit", "result"],
    "properties": {
      "pin": {"type":"string"}, "doc_commit": {"type":"string"},
      "result": {"type":"string","enum":["pass"]}
    }
  }
}
```

`audit-ledger.json`(初值,全空 = 15 章全待复核,头一轮补齐):
```json
{}
```

- [ ] **Step 2: 写 ledger 函数**

`.github/scripts/lib/ledger.sh`:
```bash
source "$(dirname "${BASH_SOURCE[0]}")/srcmap.sh"

# docs/zh/<ch>*.md 的最近 commit
chapter_doc_commit() {
  local ch="$1" docs="${2:-docs/zh}"
  git log -1 --format=%H -- "$docs/$ch"*.md 2>/dev/null
}

# 记录里该章 pin → cur_pin 之间,该章地盘下有没有改动(gh compare 过滤)
chapter_source_changed() {
  local ledger="$1" map="$2" ch="$3" cur="$4" gh="${5:-gh}"
  local recpin; recpin="$(jq -r --arg c "$ch" '.[$c].pin // ""' "$ledger")"
  [ -z "$recpin" ] && return 0                       # 没记录 → 要核
  [ "$recpin" = "$cur" ] && return 1                 # pin 没动 → 地盘必没动
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -n "$(chapters_for_path "$map" "$f")" ] || continue
    case "$(chapters_for_path "$map" "$f")" in *"$ch"*) return 0 ;; esac
  done < <("$gh" api "repos/NousResearch/hermes-agent/compare/${recpin}...${cur}" --jq '.files[].filename' 2>/dev/null)
  return 1
}

# 待复核 = 无记录 / 文档 commit 变了 / 地盘源码变了
is_pending() {
  local ledger="$1" map="$2" ch="$3" cur="$4" docs="${5:-docs/zh}"
  local rec; rec="$(jq -r --arg c "$ch" '.[$c] // "null"' "$ledger")"
  [ "$rec" = "null" ] && return 0
  local recdoc curdoc
  recdoc="$(jq -r --arg c "$ch" '.[$c].doc_commit' "$ledger")"
  curdoc="$(chapter_doc_commit "$ch" "$docs")"
  [ "$recdoc" != "$curdoc" ] && return 0
  chapter_source_changed "$ledger" "$map" "$ch" "$cur"
}

# 盖章:更新一章记录,回显新 ledger
stamp_chapter() {
  local ledger="$1" ch="$2" pin="$3" commit="$4" result="$5"
  jq --arg c "$ch" --arg p "$pin" --arg d "$commit" --arg r "$result" \
    '.[$c] = {pin:$p, doc_commit:$d, result:$r}' "$ledger"
}
```

- [ ] **Step 3: 写失败的测试(桩 gh compare;git log 用真仓的存在文件)**

`.github/scripts/test/test-ledger.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"; source "$here/../lib/ledger.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
map="$root/.github/chapter-source-map.yml"

# stamp 往空表加一章
echo '{}' > "$tmp/l.json"
stamp_chapter "$tmp/l.json" "05" "vA" "commitX" "pass" > "$tmp/l2.json"
assert_eq "vA" "$(jq -r '."05".pin' "$tmp/l2.json")" "盖章写入 pin"
assert_eq "pass" "$(jq -r '."05".result' "$tmp/l2.json")" "盖章写入 result"

# 无记录 → pending
echo '{}' > "$tmp/empty.json"
is_pending "$tmp/empty.json" "$map" "05" "vNow" "$root/docs/zh"; assert_eq "0" "$?" "无记录=待复核"

# 文档 commit 对得上、pin 也对得上 → 不 pending
cur_doc="$(chapter_doc_commit "05" "$root/docs/zh")"
jq -n --arg d "$cur_doc" '{"05":{pin:"vNow",doc_commit:$d,result:"pass"}}' > "$tmp/match.json"
is_pending "$tmp/match.json" "$map" "05" "vNow" "$root/docs/zh"; assert_eq "1" "$?" "全对上=不待复核"
echo "test-ledger: PASS"
```

- [ ] **Step 4: 跑测试确认失败 → 补 → 通过**

Run: `bash .github/scripts/test/test-ledger.sh` → 先 FAIL,补全后 `test-ledger: PASS`。
(注:第三个断言依赖 `docs/zh/05*.md` 存在且已提交;本仓已有,故 `chapter_doc_commit` 回真 hash。)

- [ ] **Step 5: 提交**

```bash
git add audit-ledger.json .github/schemas/audit-ledger.json .github/scripts/lib/ledger.sh .github/scripts/test/test-ledger.sh
git commit -m "feat(audit): 复核记录表 schema/初值 + ledger 判定与盖章函数"
```

---

## Task 2:准备脚本 audit-prep.sh(待复核章 → matrix 清单)

**Files:**
- Create: `.github/scripts/audit-prep.sh`
- Test: `.github/scripts/test/test-audit-prep.sh`

**Interfaces:**
- Consumes:环境 `PIN`(当前 pin);读 `audit-ledger.json`、`chapter-source-map.yml`、`sync-policy.yml`(取 `.audit.chapters_per_run`)、`docs/zh`。
- Produces:向 stdout 输出一个章号 JSON 数组(最多 `chapters_per_run` 个),如 `["00","01","02","03"]`;没有待复核的章则输出 `[]`。

- [ ] **Step 1: 写脚本**

`.github/scripts/audit-prep.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/ledger.sh"
LEDGER="$ROOT/audit-ledger.json"; MAP="$ROOT/.github/chapter-source-map.yml"
POL="$ROOT/.github/sync-policy.yml"; DOCS="$ROOT/docs/zh"
limit="$(policy_get "$POL" '.audit.chapters_per_run')"

pending=()
# 章号来自对照表的 keys(有源码地盘的章);逐章判 pending
while IFS= read -r ch; do
  is_pending "$LEDGER" "$MAP" "$ch" "$PIN" "$DOCS" && pending+=("$ch")
done < <(yq -r '.chapters | keys | .[]' "$MAP")

# 取上限,拼 JSON 数组
printf '%s\n' "${pending[@]:0:$limit}" | jq -R . | jq -s 'map(select(length>0))'
```

- [ ] **Step 2: 写测试(全空 ledger → 头几章都 pending,取上限 4)**

`.github/scripts/test/test-audit-prep.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
# 用真仓(ledger 初值为空 → 全章 pending),验证取上限 4、且元素是章号
out="$(REPO_ROOT="$root" PIN=vNow bash "$root/.github/scripts/audit-prep.sh")"
assert_eq "4" "$(jq 'length' <<<"$out")" "空表应取满 chapters_per_run=4"
assert_eq "00" "$(jq -r '.[0]' <<<"$out")" "第一个应是最小章号 00"
echo "test-audit-prep: PASS"
```

- [ ] **Step 3: 跑测试确认失败 → 补 → 通过**

Run: `bash .github/scripts/test/test-audit-prep.sh` → 先 FAIL,补全后 `test-audit-prep: PASS`。
(前提:`audit-ledger.json` 初值 `{}` 已提交,故全章 pending。)

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/audit-prep.sh .github/scripts/test/test-audit-prep.sh
git commit -m "feat(audit): 准备脚本 待复核章→取上限→matrix 清单"
```

---

## Task 3:复核 schema + 提示

**Files:**
- Create: `.github/schemas/audit-review.json`
- Create: `.github/prompts/audit-review.md`

**Interfaces:**
- Produces:复核 agent 产出 `{errors: [work plan 条目...]}`,条目字段与 Plan 2 的 region-assessment plan_items 完全一致(`位置/现状/改成什么/源码依据/类型`),好让 ③ 直接消费。`errors` 为空数组表示这章没查出错。

- [ ] **Step 1: 写 schema**

`.github/schemas/audit-review.json`:
```json
{
  "type": "object", "additionalProperties": false,
  "required": ["errors"],
  "properties": {
    "errors": {
      "type": "array",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["位置","现状","改成什么","源码依据","类型"],
        "properties": {
          "位置":{"type":"string"},"现状":{"type":"string"},"改成什么":{"type":"string"},
          "源码依据":{"type":"string"},"类型":{"type":"string","enum":["shallow","deep"]}
        }
      }
    }
  }
}
```

- [ ] **Step 2: 写提示**

`.github/prompts/audit-review.md`:
```markdown
你是独立复核员,身份和纪律同 `.claude/agents/factual-reviewer.md`:强制贴代码举证、反橡皮图章、逐条核对。

任务:对着当前 pin(${PIN})的真实源码,把第 ${CHAPTER} 章文档从头通盘复核一遍。逐条把文档里带 `文件:行号`/符号 的事实断言 grep 回真源码核对,找出所有对不上、过时、或讲错的地方。

对每一处确认的错(先报出、再自己独立复核一遍,两次都成立才算),产出一条修正:位置、现状(文档现在怎么写)、改成什么、源码依据(文件:行:符号)、类型(shallow/deep)。

**输出**:符合 schema ${SCHEMA} 的 JSON 到 ${OUT}。没查出错就写 `{"errors":[]}`。只写这个文件。
```

- [ ] **Step 3: 提交**

```bash
git add .github/schemas/audit-review.json .github/prompts/audit-review.md
git commit -m "feat(audit): 通盘复核 schema + 提示(errors=work plan 条目)"
```

---

## Task 4:audit-finalize.sh(汇总 → 调 ③ → 盖章 → ledger PR)

**Files:**
- Create: `.github/scripts/audit-finalize.sh`
- Test: `.github/scripts/test/test-audit-finalize.sh`

**Interfaces:**
- Consumes:`audit-finalize.sh <review_dir> <chapters_json>`;环境 `ISSUE`、`PIN`;可注入 `GH_CMD`;读各 `review-<ch>.json`。
- Produces:合并所有 `errors` 成 work plan;有错则 `gh workflow run hermes-sync.yml -f cycle=audit ...`;把 `<chapters_json>` 里每一章在 ledger 里盖章(pass);ledger 更新走一个分支 + 自动合并 PR。

- [ ] **Step 1: 写脚本**

`.github/scripts/audit-finalize.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
rev="$1"; chapters="$2"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/ledger.sh"
LEDGER="$ROOT/audit-ledger.json"; DOCS="$ROOT/docs/zh"

# 1) 合并确认的错 → work plan
work="$(jq -s '[.[].errors[]?]' "$rev"/review-*.json)"
n="$(jq 'length' <<<"$work")"

# 2) 有错 → 调 ③(audit,不动 pin)
if [ "$n" -gt 0 ]; then
  "$GH" workflow run hermes-sync.yml \
    -f work_plan="$work" -f cycle=audit -f issue_number="$ISSUE" -f new_tag=""
  "$GH" issue comment "$ISSUE" --body "复核查出 $n 处错,已派 ③ 出纠错 PR"
else
  "$GH" issue comment "$ISSUE" --body "本轮复核未查出错"
fi

# 3) 逐章盖章(pass),更新 ledger
tmp="$LEDGER"
for ch in $(jq -r '.[]' <<<"$chapters"); do
  commit="$(chapter_doc_commit "$ch" "$DOCS")"
  stamp_chapter "$tmp" "$ch" "$PIN" "$commit" "pass" > "$LEDGER.new" && mv "$LEDGER.new" "$LEDGER"
done

# 4) ledger 更新走自动合并 PR(不直接 push main)
br="auto/audit-ledger-${GITHUB_RUN_ID:-local}"
git -C "$ROOT" checkout -B "$br" >/dev/null 2>&1
git -C "$ROOT" add audit-ledger.json
git -C "$ROOT" commit -m "audit: 盖章本轮复核过的章" >/dev/null
git -C "$ROOT" push -u origin "$br" >/dev/null
pr="$("$GH" pr create --base main --head "$br" --title "audit: 更新复核记录表" --body "见 #${ISSUE}")"
"$GH" pr merge "$pr" --auto --squash
```

- [ ] **Step 2: 写测试(桩 gh;临时 git 仓)**

`.github/scripts/test/test-audit-finalize.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; log="$stub/calls"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; [ "\$1 \$2" = "pr create" ] && echo "https://pr/1"; exit 0
EOF
chmod +x "$stub/gh"

# 临时仓,带 ledger + srcmap + libs
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib" "$work/docs/zh"
cp "$root/.github/scripts/lib/ledger.sh" "$root/.github/scripts/lib/srcmap.sh" "$work/.github/scripts/lib/"
cp "$root/.github/chapter-source-map.yml" "$work/.github/"
echo '{}' > "$work/audit-ledger.json"; echo x > "$work/docs/zh/05-x.md"
( cd "$work" && git init -q && git add -A && git commit -q -m init )

rev="$stub/rev"; mkdir -p "$rev"
echo '{"errors":[{"位置":"05 §1","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$rev/review-05.json"

GH_CMD="$stub/gh" REPO_ROOT="$work" ISSUE=1 PIN=vNow \
  bash "$root/.github/scripts/audit-finalize.sh" "$rev" '["05"]' >/dev/null 2>&1 || true

grep -q "gh workflow run" "$log" || { echo "有错应派 ③"; exit 1; }
grep -q "gh pr create" "$log" || { echo "ledger 应走 PR"; exit 1; }
assert_eq "pass" "$(jq -r '."05".result' "$work/audit-ledger.json")" "05 应盖章 pass"
echo "test-audit-finalize: PASS"
```

- [ ] **Step 3: 跑测试确认失败 → 补 → 通过**

Run: `bash .github/scripts/test/test-audit-finalize.sh` → 先 FAIL,补全后 `test-audit-finalize: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/audit-finalize.sh .github/scripts/test/test-audit-finalize.sh
git commit -m "feat(audit): audit-finalize 汇总→调③→盖章→ledger PR"
```

---

## Task 5:hermes-audit.yml 工作流 + actionlint

**Files:**
- Create: `.github/workflows/hermes-audit.yml`

- [ ] **Step 1: 写工作流**

`.github/workflows/hermes-audit.yml`:
```yaml
name: hermes 定期复核

on:
  schedule:
    - cron: "0 7 * * 1"   # 每周一 07:00 UTC
  workflow_dispatch: {}

permissions: { contents: write, issues: write, pull-requests: write }

jobs:
  prep:
    runs-on: ubuntu-latest
    outputs:
      chapters: ${{ steps.p.outputs.chapters }}
      issue: ${{ steps.p.outputs.issue }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
      - id: p
        env: { GH_TOKEN: "${{ github.token }}" }
        run: |
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)"
          chapters="$(REPO_ROOT="$PWD" PIN="$PIN" bash .github/scripts/audit-prep.sh)"
          echo "chapters=$chapters" >> "$GITHUB_OUTPUT"
          if [ "$chapters" != "[]" ]; then
            gh label create audit-cycle --color 5319E7 2>/dev/null || true
            n="$(gh issue create --title "audit: $(date -u +%F)" --label audit-cycle \
                 --body "本轮复核:$chapters" --json number --jq .number 2>/dev/null || echo 0)"
            echo "issue=$n" >> "$GITHUB_OUTPUT"
          fi

  review:
    needs: prep
    if: ${{ needs.prep.outputs.chapters != '[]' }}
    runs-on: ubuntu-latest
    strategy:
      matrix: { chapter: ${{ fromJSON(needs.prep.outputs.chapters) }} }
    steps:
      - uses: actions/checkout@v4
      - run: curl -fsSL https://claude.ai/install.sh | bash; echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: 通盘复核一章
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          CHAPTER: ${{ matrix.chapter }}
        run: |
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)"
          OUT="review-${CHAPTER}.json"
          prompt="$(CHAPTER="$CHAPTER" PIN="$PIN" OUT="$OUT" \
            SCHEMA=.github/schemas/audit-review.json envsubst < .github/prompts/audit-review.md)"
          claude -p "$prompt" --permission-mode acceptEdits \
            --allowedTools "Read,Write,Bash(grep:*),Grep,Glob"
      - uses: actions/upload-artifact@v4
        with: { name: "review-${{ matrix.chapter }}", path: "review-*.json" }

  finalize:
    needs: [prep, review]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/download-artifact@v4
        with: { path: rev, merge-multiple: true }
      - env:
          GH_TOKEN: ${{ github.token }}
          ISSUE: ${{ needs.prep.outputs.issue }}
        run: |
          git config user.name hermes-audit-bot; git config user.email actions@github.com
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)" \
            bash .github/scripts/audit-finalize.sh rev '${{ needs.prep.outputs.chapters }}'
```

- [ ] **Step 2: actionlint**

Run: `./actionlint .github/workflows/hermes-audit.yml` → 0 错误。

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/hermes-audit.yml
git commit -m "feat(audit): hermes-audit.yml 每周复核(准备→matrix→finalize)"
```

---

## Task 6:端到端 smoke

- [ ] **Step 1: 手动触发一轮**

前置:`CLAUDE_CODE_OAUTH_TOKEN` secret 已加。
```bash
gh workflow run "hermes 定期复核"
gh run watch
```
Expected 核对:①准备 job 因 ledger 空,挑出 00–03 四章、开了 `audit-cycle` issue;②四章各跑出 review JSON;③finalize 里,若有章查出错则触发了 `hermes-sync.yml`(cycle=audit),issue 有"查出 N 处错"记录;④生成了一个更新 `audit-ledger.json` 的自动合并 PR,合并后这四章记录为 pass;⑤再次手动触发,这四章不再被选(除非其源码/文档变了)——验证"同一状态只核一次"。

- [ ] **Step 2: 记录 smoke 结果**

若第 ⑤ 点没成立(核过的章又被选),回到 `is_pending`/`stamp_chapter` 排查 doc_commit 比对,修正并补测。

---

## Self-Review

- **Spec coverage(本 plan 范围 = 复核循环)**:复核记录表 + schema(Task 1)、按章地盘/文档 commit 判待复核(Task 1 `is_pending`)、取 `chapters_per_run` 上限(Task 2)、factual-reviewer 通盘复核 + 二次验证(Task 3 提示)、确认的错→work plan→调 ③ 不动 pin(Task 4)、盖章 + 一改重新计入(Task 1/4)、ledger 更新走 PR(Task 4)、每周 cron(Task 5)。
- **Placeholder scan**:无 TODO/TBD;所有 lib/脚本给了完整实现与测试。
- **Type consistency**:`is_pending`/`stamp_chapter`/`chapter_doc_commit`/`chapter_source_changed` 签名一致;audit-review 的 `errors[]` 条目字段与 Plan 2 plan_items、Plan 1 `hermes-sync.yml` 输入完全一致(`位置/现状/改成什么/源码依据/类型`),③ 可直接消费;复用 Plan 2 的 `srcmap.sh`。
- **待实测(转 ADR / Plan 4)**:`hermes-sync.yml` 目前是 `workflow_call`,而 finalize 用 `gh workflow run` 触发它——需要 ③ 也开 `workflow_dispatch`(Plan 4 串链路时统一处理);`gh api compare` 分页;cron 与 ① 每日检测的时段错开。
