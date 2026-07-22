# ③ 同步引擎 + 地基 Implementation Plan(Plan 1 / 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建成一台可复用的 GitHub Actions 工作流 `hermes-sync.yml`:喂给它一份 work plan(JSON),它就照单改文档、跑脚本硬检查、派复核 agent 交叉挑错,全过就自动合并 PR,并把每层记录 + 复核评语 + 逐处改动写进指定 issue。

**Architecture:** 一个 `workflow_call` 可复用工作流,核心是一个 bash 编排的"改写↔复核"重试循环(最多 3 轮):每轮先让 `claude -p` 照 work plan 改动、跑 `check-anchors.sh`/`orient.sh` 硬检查,再并行派 3 个复核 agent 各写一份 `{verdict, comments}` JSON;3 个全过则收尾(开 PR、贴 issue、自动合并、按需 bump pin),否则带着复核意见再改一轮;轮数耗尽则贴 issue 报失败、留 PR 交人。所有"要拍板"的阈值都从 `sync-policy.yml` 读。agent 用 headless `claude -p`(非 `--bare`、订阅 token),自动加载 `.claude/agents/`。

**Tech Stack:** GitHub Actions(`workflow_call`)、bash、`gh` CLI、`yq`(读 YAML)、`jq`(读/校验 JSON)、Claude Code headless(`claude -p --output-format json`)、复用 `.claude/agents/factual-reviewer.md` 的审核纪律。

## Global Constraints

以下约束逐字来自 spec(`.github/README.md`)和 ADR(`.github/adr/0001-ci-tech-choices.md`),每个 task 都默认包含:

- **鉴权走订阅、非 bare**:agent 一律 `claude -p`,不加 `--bare`;鉴权用环境变量 `CLAUDE_CODE_OAUTH_TOKEN`;绝不用 `ANTHROPIC_API_KEY`。(ADR 决定一/五)
- **CI 里 agent 不可交互**:`claude -p` 必须带 `--permission-mode acceptEdits`(允许改文件)并用 `--allowedTools` 白名单,否则会卡在权限确认。
- **agent 只出数据,副作用交给 YAML/脚本**:发 issue、开 PR、合并一律由确定的 bash 步骤做,不让 agent 自己 `gh`。(ADR 决定三)
- **绝不直接 push 主分支**:所有改动走自动合并的 PR。(spec 安全网)
- **复核 agent 必须和改写的不是同一个,且结论一致才算过**;复核数量、轮数上限从 `sync-policy.yml` 读,不写死。(spec 原则一 / sync-policy)
- **`.hermes-pin` 只在同步 PR 合并那一刻更新;纠错 PR 不动 pin**。(spec 原则三)
- **总开关**:`sync-policy.yml` 的 `enabled: false` 时,工作流立刻退出、不合并任何东西。
- **本仓禁忌**:提交只 stage 明确路径,绝不 `git add -A`/`git add .`(根目录有无关的 `.codex/`、`AGENTS.md` 等残留)。

---

## File Structure

**新建:**
- `.github/sync-policy.yml` — 全流程规则(总开关、复核数、轮数、flag 条件、复核节奏)。本 plan 只用到 `enabled` 和 `sync:` 段,但一次把整份写全。
- `.github/scripts/lib/policy.sh` — 读 `sync-policy.yml` 的函数(`policy_get`)。
- `.github/scripts/lib/aggregate.sh` — 判定复核结果的函数(`all_reviews_pass`)。
- `.github/scripts/lib/decide.sh` — 合并/bump pin 决策函数(`should_bump_pin`)。
- `.github/scripts/lib/issue.sh` — 拼装标准记录、可折叠明细块的函数(`format_record`、`format_details`)。
- `.github/scripts/sync-run.sh` — ③ 的主编排脚本(改写↔复核重试循环 + 收尾),被工作流调用。
- `.github/schemas/review-verdict.json` — 复核 agent 输出的 JSON Schema(`{verdict, comments}`)。
- `.github/prompts/sync-rewrite.md` — 改写 agent 的提示模板。
- `.github/prompts/sync-review.md` — 复核 agent 的提示模板(嵌 factual-reviewer 纪律 + 要求写 verdict JSON)。
- `.github/workflows/hermes-sync.yml` — `workflow_call` 可复用工作流,调用 `sync-run.sh`。
- `.github/scripts/test/assert.sh` — 极简断言助手(无第三方依赖)。
- `.github/scripts/test/test-policy.sh` / `test-aggregate.sh` / `test-decide.sh` / `test-issue.sh` — 各 lib 的单测。

**依赖(已存在,本 plan 不改):**
- `.claude/skills/hermes-agent-expert/scripts/check-anchors.sh`、`orient.sh` — ③ 的脚本硬检查直接调它们。
- `.claude/agents/factual-reviewer.md` — 复核 agent 的审核纪律来源。

**约定:** 单测用纯 bash(不引 bats),每个 `test-*.sh` `source` 对应 lib 和 `assert.sh`,直接跑 `bash .github/scripts/test/test-*.sh`,退出码 0 为过、非 0 为失败。CI 里对 agent/gh 的调用用环境变量注入的"桩命令"替换(见各 task)。

---

## Task 1:断言助手 + sync-policy.yml + policy 读取

**Files:**
- Create: `.github/scripts/test/assert.sh`
- Create: `.github/sync-policy.yml`
- Create: `.github/scripts/lib/policy.sh`
- Test: `.github/scripts/test/test-policy.sh`

**Interfaces:**
- Produces: `assert_eq <expected> <actual> <msg>`(不等则打印并 `exit 1`);`policy_get <yaml_path> <key_path>`(用 `yq` 取值,回显到 stdout;键不存在回显空串、退出码 0)。

- [ ] **Step 1: 写断言助手**

`.github/scripts/test/assert.sh`:
```bash
# 极简断言:相等则静默,不等则报错退出。供各 test-*.sh source。
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "ASSERT FAIL: ${msg}"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    exit 1
  fi
}
```

- [ ] **Step 2: 写 sync-policy.yml(整份写全)**

`.github/sync-policy.yml`:逐字采用 spec「规则:sync-policy.yml」那段的 YAML(`enabled` + `assess` + `sync` + `audit` 四段)。完整内容:
```yaml
enabled: true

assess:
  flag_when:
    - complexity: deep
    - coverage_gap_new_chapter
    - confidence: low

sync:
  script_checks_must_pass: true
  reviewers: 3
  reviewers_must_all_pass: true
  rewrite_max_rounds: 3
  flagged_still_auto_merge: true

audit:
  enabled: true
  schedule: weekly
  chapters_per_run: 4
  reentry_on_change: true
  bumps_pin: false
```

- [ ] **Step 3: 写 policy 读取函数**

`.github/scripts/lib/policy.sh`:
```bash
# policy_get <yaml_file> <yq_path> —— 读一个策略值到 stdout。
# 用 yq(mikefarah/yq v4)。缺键回显空串,退出码 0。
policy_get() {
  local file="$1" path="$2"
  yq -r "${path} // \"\"" "$file"
}
```

- [ ] **Step 4: 写失败的测试**

`.github/scripts/test/test-policy.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/policy.sh"
pol="$here/../../sync-policy.yml"

assert_eq "true" "$(policy_get "$pol" '.enabled')" "enabled 应为 true"
assert_eq "3"    "$(policy_get "$pol" '.sync.reviewers')" "reviewers 应为 3"
assert_eq "3"    "$(policy_get "$pol" '.sync.rewrite_max_rounds')" "轮数应为 3"
assert_eq "true" "$(policy_get "$pol" '.sync.reviewers_must_all_pass')" "全过才算过"
assert_eq ""     "$(policy_get "$pol" '.sync.nonexistent')" "缺键应回空串"
echo "test-policy: PASS"
```

- [ ] **Step 5: 跑测试,先确认失败**

Run: `bash .github/scripts/test/test-policy.sh`
Expected(还没装 yq 或路径错时):FAIL。装好 `yq`(`brew install yq` 或 CI 里 `mikefarah/yq`)后应能跑。先确认在 `policy.sh` 为空时失败。

- [ ] **Step 6: 跑测试,确认通过**

Run: `bash .github/scripts/test/test-policy.sh`
Expected: 打印 `test-policy: PASS`,退出码 0。

- [ ] **Step 7: 提交**

```bash
git add .github/scripts/test/assert.sh .github/sync-policy.yml .github/scripts/lib/policy.sh .github/scripts/test/test-policy.sh
git commit -m "feat(sync): sync-policy.yml + policy 读取 + 断言助手"
```

---

## Task 2:复核结果判定(all_reviews_pass)

**Files:**
- Create: `.github/scripts/lib/aggregate.sh`
- Create: `.github/schemas/review-verdict.json`
- Test: `.github/scripts/test/test-aggregate.sh`

**Interfaces:**
- Consumes: 每个复核 agent 产出一个 JSON 文件,形如 `{"verdict":"pass"|"fail","comments":"...全文..."}`,由 schema `review-verdict.json` 约束。
- Produces: `all_reviews_pass <dir>`(目录里所有 `review-*.json` 的 `verdict` 都是 `pass` 时退出码 0,否则非 0;目录里一个文件都没有也算不过,退出码 1)。

- [ ] **Step 1: 写 verdict schema**

`.github/schemas/review-verdict.json`:
```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "comments"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "comments": { "type": "string", "minLength": 1 }
  }
}
```

- [ ] **Step 2: 写判定函数**

`.github/scripts/lib/aggregate.sh`:
```bash
# all_reviews_pass <dir> —— dir 下所有 review-*.json 的 verdict 都为 pass 才退出 0。
# 没有任何 review 文件视为不过(退出 1)。
all_reviews_pass() {
  local dir="$1"
  shopt -s nullglob
  local files=("$dir"/review-*.json)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || return 1
  local f v
  for f in "${files[@]}"; do
    v="$(jq -r '.verdict' "$f" 2>/dev/null)"
    [ "$v" = "pass" ] || return 1
  done
  return 0
}
```

- [ ] **Step 3: 写失败的测试**

`.github/scripts/test/test-aggregate.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/aggregate.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 空目录 → 不过
all_reviews_pass "$tmp"; assert_eq "1" "$?" "空目录应不过"

# 三个都 pass → 过
for n in 1 2 3; do echo '{"verdict":"pass","comments":"ok"}' > "$tmp/review-$n.json"; done
all_reviews_pass "$tmp"; assert_eq "0" "$?" "三个 pass 应过"

# 有一个 fail → 不过
echo '{"verdict":"fail","comments":"锚点对不上"}' > "$tmp/review-2.json"
all_reviews_pass "$tmp"; assert_eq "1" "$?" "含 fail 应不过"

echo "test-aggregate: PASS"
```

- [ ] **Step 4: 跑测试确认失败**

Run: `bash .github/scripts/test/test-aggregate.sh`
Expected: `aggregate.sh` 未写时 FAIL(`all_reviews_pass: command not found`)。

- [ ] **Step 5: 跑测试确认通过**

Run: `bash .github/scripts/test/test-aggregate.sh`
Expected: 打印 `test-aggregate: PASS`。

- [ ] **Step 6: 提交**

```bash
git add .github/scripts/lib/aggregate.sh .github/schemas/review-verdict.json .github/scripts/test/test-aggregate.sh
git commit -m "feat(sync): 复核 verdict schema + all_reviews_pass 判定"
```

---

## Task 3:合并决策(should_bump_pin)

**Files:**
- Create: `.github/scripts/lib/decide.sh`
- Test: `.github/scripts/test/test-decide.sh`

**Interfaces:**
- Consumes: 环境无关,纯函数。
- Produces: `should_bump_pin <cycle>`(`cycle` 为 `sync` 时退出 0=要 bump;为 `audit` 时退出 1=不 bump;其它值退出 2=报错)。

- [ ] **Step 1: 写决策函数**

`.github/scripts/lib/decide.sh`:
```bash
# should_bump_pin <cycle> —— 同步循环合并要 bump pin,复核循环不 bump。
should_bump_pin() {
  case "$1" in
    sync)  return 0 ;;
    audit) return 1 ;;
    *)     echo "unknown cycle: $1" >&2; return 2 ;;
  esac
}
```

- [ ] **Step 2: 写失败的测试**

`.github/scripts/test/test-decide.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/decide.sh"

should_bump_pin sync;  assert_eq "0" "$?" "sync 应 bump"
should_bump_pin audit; assert_eq "1" "$?" "audit 不 bump"
should_bump_pin xxx 2>/dev/null; assert_eq "2" "$?" "未知 cycle 应报错"
echo "test-decide: PASS"
```

- [ ] **Step 3: 跑测试确认失败**

Run: `bash .github/scripts/test/test-decide.sh` → FAIL(函数未定义)。

- [ ] **Step 4: 跑测试确认通过**

Run: `bash .github/scripts/test/test-decide.sh` → `test-decide: PASS`。

- [ ] **Step 5: 提交**

```bash
git add .github/scripts/lib/decide.sh .github/scripts/test/test-decide.sh
git commit -m "feat(sync): should_bump_pin 合并决策"
```

---

## Task 4:issue 记录拼装(format_record / format_details)

**Files:**
- Create: `.github/scripts/lib/issue.sh`
- Test: `.github/scripts/test/test-issue.sh`

**Interfaces:**
- Produces:
  - `format_record <layer> <run_url> <summary_kv_file>` —— 回显 spec「标准记录」那种格式的一段 markdown(`### [layer] · run_url` 加若干 `- k:v` 行,`summary_kv_file` 每行一个 `k=v`)。
  - `format_details <summary> <body_file>` —— 回显一个 `<details><summary>…</summary>\n\n<body>\n</details>` 折叠块。

- [ ] **Step 1: 写拼装函数**

`.github/scripts/lib/issue.sh`:
```bash
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
```

- [ ] **Step 2: 写失败的测试**

`.github/scripts/test/test-issue.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/issue.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

printf '时间=14:03 → 14:11\ntoken=本层 140k / 累计 140k\n' > "$tmp/kv"
out="$(format_record "③同步" "https://run/1" "$tmp/kv")"
assert_eq "### [③同步] · https://run/1" "$(printf '%s\n' "$out" | sed -n 1p)" "标题行"
assert_eq "- 时间:14:03 → 14:11" "$(printf '%s\n' "$out" | sed -n 2p)" "时间行"
assert_eq "- token:本层 140k / 累计 140k" "$(printf '%s\n' "$out" | sed -n 3p)" "token 行"

printf -- '- #1 改了 A\n' > "$tmp/body"
d="$(format_details "本次改了哪些" "$tmp/body")"
assert_eq "<details><summary>本次改了哪些</summary>" "$(printf '%s\n' "$d" | sed -n 1p)" "details 头"
echo "test-issue: PASS"
```

- [ ] **Step 3: 跑测试确认失败**

Run: `bash .github/scripts/test/test-issue.sh` → FAIL。

- [ ] **Step 4: 跑测试确认通过**

Run: `bash .github/scripts/test/test-issue.sh` → `test-issue: PASS`。

- [ ] **Step 5: 提交**

```bash
git add .github/scripts/lib/issue.sh .github/scripts/test/test-issue.sh
git commit -m "feat(sync): issue 标准记录 + 折叠块拼装"
```

---

## Task 5:改写 & 复核提示模板

**Files:**
- Create: `.github/prompts/sync-rewrite.md`
- Create: `.github/prompts/sync-review.md`

**Interfaces:**
- Consumes(运行时占位符,由 `sync-run.sh` 用 `envsubst` 或 `sed` 填):`${WORK_PLAN}`(work plan JSON)、`${PIN}`(当前 pin tag)、`${REVIEW_OUT}`(复核 agent 要写的 JSON 文件路径)、`${SCHEMA}`(verdict schema 路径)。
- Produces:两个提示文件,分别驱动"改写"和"复核"两类 `claude -p` 调用。

- [ ] **Step 1: 写改写提示**

`.github/prompts/sync-rewrite.md`:
```markdown
你是 hermes-agent 文档的维护者。严格照下面这份 work plan 逐条修改文档和 skill 锚点,不要多改、不要少改。

work plan(JSON):
${WORK_PLAN}

要求:
1. 逐条按 `位置` 定位到 `docs/` 或 `.claude/skills/` 里的文件,把 `现状` 改成 `改成什么`。
2. 每条改动都要先用 grep 到当前 pin(${PIN})的真实源码里核对 `源码依据`,确认无误再改。
3. 如果同一处的锚点行号变了,顺手更新 `.claude/skills/hermes-agent-expert/scripts/anchors.txt`。
4. 只改 work plan 点到的地方。改完不要自己提交、不要开 PR——外层脚本会处理。
```

- [ ] **Step 2: 写复核提示**

`.github/prompts/sync-review.md`:
```markdown
你是独立复核员,身份和纪律同 `.claude/agents/factual-reviewer.md`:强制贴代码举证、反橡皮图章、逐条核对。你**没有**参与刚才的改写。

任务:对照当前 pin(${PIN})的真实源码,逐条复核这份 work plan 声称做出的每一处改动是否属实、是否正确。

work plan(JSON):
${WORK_PLAN}

对每一条:grep 源码依据,确认改后的文档说法与源码一致。任一条对不上、或依据站不住,整体判 fail。

**输出**:把结论写成 JSON 文件到路径 `${REVIEW_OUT}`,且必须符合 schema `${SCHEMA}`:
- `verdict`:全部属实且正确 → `"pass"`;否则 `"fail"`。
- `comments`:逐条评语全文——每条改动核了什么、贴了哪段代码、判过还是打回,一字不落。

只写这个 JSON 文件,别的什么都不做。
```

- [ ] **Step 3: 提交(无测试;下一 task 的 smoke 会实跑它们)**

```bash
git add .github/prompts/sync-rewrite.md .github/prompts/sync-review.md
git commit -m "feat(sync): 改写 & 复核提示模板"
```

---

## Task 6:主编排脚本 sync-run.sh(改写↔复核重试循环 + 收尾)

**Files:**
- Create: `.github/scripts/sync-run.sh`
- Test: `.github/scripts/test/test-sync-run.sh`(用桩命令跑通两条路径:一次过 / 轮数耗尽)

**Interfaces:**
- Consumes(环境变量):`WORK_PLAN`、`CYCLE`(sync|audit)、`ISSUE`(编号)、`NEW_TAG`、`PIN`、`RUN_URL`;可注入桩:`CLAUDE_CMD`(默认 `claude`)、`GH_CMD`(默认 `gh`)、`REPO_ROOT`。
- Produces:退出码 0 = 成功合并;3 = 轮数耗尽交人;2 = 被总开关拦下。落地副作用:创建分支 `auto/<cycle>-<run>`、开 PR、贴 issue、(sync 时)改 `.hermes-pin`。

- [ ] **Step 1: 写主脚本**

`.github/scripts/sync-run.sh`(核心编排;所有外部命令走可注入变量,便于测试):
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/policy.sh"
source "$ROOT/.github/scripts/lib/aggregate.sh"
source "$ROOT/.github/scripts/lib/decide.sh"
source "$ROOT/.github/scripts/lib/issue.sh"
POL="$ROOT/.github/sync-policy.yml"

# 0) 总开关
if [ "$(policy_get "$POL" '.enabled')" != "true" ]; then
  echo "sync-policy.enabled=false,退出"; exit 2
fi

max="$(policy_get "$POL" '.sync.rewrite_max_rounds')"
n_rev="$(policy_get "$POL" '.sync.reviewers')"
work="$(mktemp -d)"; echo "$WORK_PLAN" > "$work/plan.json"
export WORK_PLAN PIN
branch="auto/${CYCLE}-${GITHUB_RUN_ID:-local}"
git -C "$ROOT" checkout -B "$branch" >/dev/null 2>&1

fill() { sed -e "s|\${WORK_PLAN}|$(jq -Rs . <<<"$WORK_PLAN" | sed 's|[&/\]|\\&|g')|g" \
             -e "s|\${PIN}|$PIN|g" -e "s|\${REVIEW_OUT}|$2|g" \
             -e "s|\${SCHEMA}|$ROOT/.github/schemas/review-verdict.json|g" "$1"; }

round=0; passed=0
while [ "$round" -lt "$max" ]; do
  round=$((round+1)); echo "== round $round/$max =="

  # a) 改写
  "$CLAUDE" -p "$(fill "$ROOT/.github/prompts/sync-rewrite.md" '')" \
    --permission-mode acceptEdits \
    --allowedTools "Read,Edit,Write,Bash(grep:*),Bash(rg:*),Grep,Glob" >/dev/null

  # b) 脚本硬检查
  if [ "$(policy_get "$POL" '.sync.script_checks_must_pass')" = "true" ]; then
    if ! bash "$ROOT/.claude/skills/hermes-agent-expert/scripts/check-anchors.sh" \
      && bash "$ROOT/.claude/skills/hermes-agent-expert/scripts/orient.sh"; then
      echo "脚本硬检查未过,重来一轮"; continue
    fi
  fi

  # c) 并行 3 个复核
  rev="$(mktemp -d)"
  for i in $(seq 1 "$n_rev"); do
    "$CLAUDE" -p "$(fill "$ROOT/.github/prompts/sync-review.md" "$rev/review-$i.json")" \
      --permission-mode acceptEdits --allowedTools "Read,Write,Bash(grep:*),Grep,Glob" &
  done
  wait

  # d) 全过?
  if all_reviews_pass "$rev"; then passed=1; break; fi
  echo "复核未全过,带意见再改一轮"
done

# e) 收尾
if [ "$passed" != "1" ]; then
  printf '%s\n' "### [③同步] 轮数($max)耗尽仍未通过,交人处理" \
    | "$GH" issue comment "$ISSUE" --body-file -
  exit 3
fi

# bump pin(仅 sync)
if should_bump_pin "$CYCLE"; then
  sed -i.bak "s/^tag=.*/tag=$NEW_TAG/" "$ROOT/.hermes-pin" && rm -f "$ROOT/.hermes-pin.bak"
  git -C "$ROOT" add .hermes-pin
fi

# 贴 issue 明细(评语 + 改动),开 PR,自动合并
"$ROOT/.github/scripts/lib/_finalize.sh" "$rev" "$branch" "$ISSUE" "$CYCLE"
```

> 说明:`_finalize.sh` 负责"拼折叠块 → `gh issue comment` → `gh pr create` → `gh pr merge --auto --squash`",在 Task 7 里写并测。本 task 先把编排主体和两条控制流(一次过 / 耗尽)测通。

- [ ] **Step 2: 写测试(桩掉 claude/gh/脚本检查,验证控制流)**

`.github/scripts/test/test-sync-run.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

# 桩:claude 什么都不干但落一个 pass/fail 的 review 文件;gh/finalize 记录调用
stub="$(mktemp -d)"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/claude" <<'EOF'
#!/usr/bin/env bash
# 从 --prompt 里认出是复核(要写 REVIEW_OUT)。参数里含 review 提示时写 verdict。
for a in "$@"; do case "$a" in *"独立复核员"*) out=$(printf '%s\n' "$@" | grep -o '/tmp[^ ]*review-[0-9]*.json' | head -1); echo "{\"verdict\":\"${VERDICT:-pass}\",\"comments\":\"c\"}" > "$out";; esac; done
exit 0
EOF
chmod +x "$stub/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/gh"; chmod +x "$stub/gh"

# 一次过
VERDICT=pass CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
[ "$?" -eq 0 ] || { echo "期望一次过退出 0"; exit 1; }

# 轮数耗尽(复核恒 fail)
VERDICT=fail CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" \
  WORK_PLAN='[]' CYCLE=sync ISSUE=1 NEW_TAG=vX PIN=vY RUN_URL=u \
  bash "$root/.github/scripts/sync-run.sh" >/dev/null 2>&1
[ "$?" -eq 3 ] || { echo "期望耗尽退出 3"; exit 1; }

echo "test-sync-run: PASS"
```

> 注:桩脚本要跳过 Task 7 的 `_finalize.sh`(测试里可临时把它替换成 `true`,或让 `_finalize.sh` 在 Task 7 前先放一个 `exit 0` 占位并在 Task 7 补全并补测)。为保持每 task 可独立通过,本 task 先建 `.github/scripts/lib/_finalize.sh` 内容仅 `#!/usr/bin/env bash` + `exit 0`。

- [ ] **Step 3: 建 _finalize.sh 占位**

`.github/scripts/lib/_finalize.sh`:
```bash
#!/usr/bin/env bash
# 占位,Task 7 补全。
exit 0
```

- [ ] **Step 4: 跑测试确认失败 → 补主脚本 → 确认通过**

Run: `bash .github/scripts/test/test-sync-run.sh`
先在 `sync-run.sh` 缺失时 FAIL;补全后 Expected: `test-sync-run: PASS`。

- [ ] **Step 5: 提交**

```bash
git add .github/scripts/sync-run.sh .github/scripts/lib/_finalize.sh .github/scripts/test/test-sync-run.sh
git commit -m "feat(sync): sync-run 编排 + 改写复核重试循环(控制流测通)"
```

---

## Task 7:收尾 _finalize.sh(贴 issue 明细 + 开 PR + 自动合并)

**Files:**
- Modify: `.github/scripts/lib/_finalize.sh`(从占位补全)
- Test: `.github/scripts/test/test-finalize.sh`

**Interfaces:**
- Consumes: `_finalize.sh <review_dir> <branch> <issue> <cycle>`;用可注入的 `GH_CMD`;从 `review_dir` 读各 `review-*.json` 的 `comments`。
- Produces: 副作用序列(每步走 `GH_CMD`):`git commit` 改动 → push 分支 → `gh pr create` → `gh issue comment`(评语折叠块 + 改动折叠块 + 标准记录)→ `gh pr merge --auto --squash`。测试断言这几条命令按序被调用。

- [ ] **Step 1: 写 _finalize.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail
rev="$1"; branch="$2"; issue="$3"; cycle="$4"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/issue.sh"

# 1) 提交改动(只 stage docs/ 和 skill,绝不 -A)
git -C "$ROOT" add docs/ .claude/skills/ .hermes-pin 2>/dev/null || true
git -C "$ROOT" commit -m "auto(${cycle}): 照 work plan 同步文档" >/dev/null
git -C "$ROOT" push -u origin "$branch" >/dev/null

# 2) 开 PR
pr="$("$GH" pr create --base main --head "$branch" \
      --title "auto(${cycle}): 文档同步" --body "见关联 issue #${issue}")"

# 3) 贴 issue:评语折叠块 + 改动折叠块
body="$(mktemp)"
{
  comments="$(mktemp)"
  for f in "$rev"/review-*.json; do jq -r '.comments' "$f"; echo; done > "$comments"
  format_details "复核 agent 评语全文" "$comments"
  git -C "$ROOT" show --stat --oneline HEAD | tail -n +2 > "$comments"
  format_details "本次改了哪些" "$comments"
} > "$body"
"$GH" issue comment "$issue" --body-file "$body"

# 4) 自动合并
"$GH" pr merge "$pr" --auto --squash
```

- [ ] **Step 2: 写测试(桩 gh/git,断言调用序列)**

`.github/scripts/test/test-finalize.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
stub="$(mktemp -d)"; log="$stub/calls"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; [ "\$1 \$2" = "pr create" ] && echo "https://pr/9"; exit 0
EOF
chmod +x "$stub/gh"
rev="$stub/rev"; mkdir -p "$rev"
echo '{"verdict":"pass","comments":"逐条核对全属实"}' > "$rev/review-1.json"

# 在临时 git 仓里跑,避免碰真仓
work="$stub/repo"; mkdir -p "$work/.github/scripts/lib"
cp "$root/.github/scripts/lib/issue.sh" "$work/.github/scripts/lib/"
cp "$root/.github/scripts/lib/_finalize.sh" "$work/.github/scripts/lib/"
( cd "$work" && git init -q && git commit -q --allow-empty -m init )

GH_CMD="$stub/gh" REPO_ROOT="$work" \
  bash "$work/.github/scripts/lib/_finalize.sh" "$rev" "auto/x" "7" "sync" >/dev/null 2>&1 || true

grep -q "gh pr create" "$log" || { echo "应调用 pr create"; exit 1; }
grep -q "gh issue comment" "$log" || { echo "应调用 issue comment"; exit 1; }
grep -q "gh pr merge" "$log" || { echo "应调用 pr merge"; exit 1; }
echo "test-finalize: PASS"
```

- [ ] **Step 3: 跑测试确认失败(占位版)→ 补全 → 确认通过**

Run: `bash .github/scripts/test/test-finalize.sh`
占位版(只 `exit 0`)时不产生任何 gh 调用 → FAIL;补全后 Expected: `test-finalize: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/lib/_finalize.sh .github/scripts/test/test-finalize.sh
git commit -m "feat(sync): _finalize 贴 issue 明细 + 开 PR + 自动合并"
```

---

## Task 8:hermes-sync.yml 可复用工作流 + actionlint

**Files:**
- Create: `.github/workflows/hermes-sync.yml`

**Interfaces:**
- Consumes(`workflow_call` inputs):`work_plan`(string)、`cycle`(string)、`issue_number`(string)、`new_tag`(string,sync 用);`secrets`:`CLAUDE_CODE_OAUTH_TOKEN`(显式传,不自动继承)。
- Produces:一个可被 ② / 复核循环 `uses:` 调用的工作流,内部跑 `sync-run.sh`。

- [ ] **Step 1: 写工作流**

`.github/workflows/hermes-sync.yml`:
```yaml
name: hermes 同步引擎(可复用)

on:
  workflow_call:
    inputs:
      work_plan:    { type: string, required: true }
      cycle:        { type: string, required: true }   # sync | audit
      issue_number: { type: string, required: true }
      new_tag:      { type: string, required: false, default: "" }
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: { required: true }

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: 装 yq / claude
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
          curl -fsSL https://claude.ai/install.sh | bash
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: 跑单测(自检)
        run: for t in .github/scripts/test/test-*.sh; do bash "$t"; done
      - name: 同步
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          GH_TOKEN: ${{ github.token }}
          WORK_PLAN: ${{ inputs.work_plan }}
          CYCLE: ${{ inputs.cycle }}
          ISSUE: ${{ inputs.issue_number }}
          NEW_TAG: ${{ inputs.new_tag }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          git config user.name "hermes-sync-bot"
          git config user.email "actions@github.com"
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)"
          export PIN
          bash .github/scripts/sync-run.sh
```

- [ ] **Step 2: 装 actionlint 并验证语法**

Run:
```bash
bash <(curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
./actionlint .github/workflows/hermes-sync.yml
```
Expected: 无输出(0 错误)。有报错则按提示修 YAML。

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/hermes-sync.yml
git commit -m "feat(sync): hermes-sync.yml 可复用工作流(workflow_call)"
```

---

## Task 9:端到端 smoke(真跑一次,验证 ADR 的三处不确定)

**Files:**
- Create: `.github/workflows/hermes-sync-smoke.yml`(临时,验完可删)

**Interfaces:**
- Consumes: 一份手写的极小 work plan(改一处无关紧要的锚点)。
- Produces: 一次真实运行,证明 claude-code 订阅 token 在 CI 能跑、`workflow_call` 能被调用、agent 出的 JSON 能被后续步骤读到、PR 能自动合并、issue 有评语折叠块。

- [ ] **Step 1: 建临时触发工作流**

`.github/workflows/hermes-sync-smoke.yml`:
```yaml
name: sync smoke
on: { workflow_dispatch: {} }
jobs:
  smoke:
    uses: ./.github/workflows/hermes-sync.yml
    with:
      work_plan: '[{"位置":"skill/architecture.md 某锚点","现状":"占位","改成什么":"占位(smoke,无实义)","源码依据":"README.md:1","类型":"cosmetic"}]'
      cycle: sync
      issue_number: "0"
      new_tag: ""
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

- [ ] **Step 2: 前置——你手动加 secret**

在本地跑 `claude setup-token`,把生成的 token 加成仓库 secret `CLAUDE_CODE_OAUTH_TOKEN`(仓库 Settings → Secrets)。这一步只能人做。

- [ ] **Step 3: 触发并观察**

Run: `gh workflow run "sync smoke"`,然后 `gh run watch`。
Expected 核对四点:①运行成功;②issue #0 或指定 issue 里出现"复核 agent 评语全文"折叠块;③生成了一个自动合并的 PR;④`.hermes-pin` 因 `issue_number:"0"` 是 smoke 未 bump(cycle=sync 但 new_tag 空,`sed` 不会误改——若会,记为待修)。
若订阅 token / workflow_call / agent JSON 任一处不通,在这里就暴露,回到对应 task 修,并同步更新 ADR 里"待实测的三处"。

- [ ] **Step 4: 删掉 smoke 工作流,提交**

```bash
git rm .github/workflows/hermes-sync-smoke.yml
git commit -m "chore(sync): 移除 smoke 工作流(验证通过)"
```

---

## Self-Review

- **Spec coverage(本 plan 范围 = ③ 引擎 + 地基)**:sync-policy.yml(Task 1)、③ 改写(Task 5/6)、脚本硬检查(Task 6 b)、3 复核 + 全过才算过(Task 2/6 c/d)、rewrite_max_rounds(Task 6)、评语+改动进 issue 折叠块(Task 4/7)、开 PR 自动合并(Task 7)、bump pin 仅 sync(Task 3/6)、总开关(Task 6 step 0)、workflow_call 复用(Task 8)、订阅 token 非 bare(全程)。② / 复核循环 / ① rewrite / 源码地盘表 / audit-ledger 不在本 plan,留 Plan 2–4。
- **Placeholder scan**:`_finalize.sh` 在 Task 6 是有意的 `exit 0` 占位,Task 7 补全并补测,非遗留占位。其余步骤均给了完整代码。
- **Type consistency**:`policy_get`、`all_reviews_pass`、`should_bump_pin`、`format_record`、`format_details`、`_finalize.sh` 的签名在定义与调用处一致;review JSON 的 `{verdict, comments}` 在 schema(Task 2)、复核提示(Task 5)、判定(Task 2)、收尾(Task 7)四处一致。
- **已知待实测(转 ADR)**:claude 在 CI 的安装方式(Task 8 用 `install.sh`,构建时确认)、订阅 token 在非交互 `claude -p` 的稳定性、`sed` 填 `${WORK_PLAN}` 对含特殊字符 JSON 的转义(Task 6 `fill` 用 `jq -Rs`,smoke 时重点验)。
