# ② 评估+规划 Implementation Plan(Plan 2 / 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建成工作流 `hermes-assess-plan.yml`:拿到新版本信息后,读一遍 diff,判断影响到文档哪些章、有多复杂、要不要往下走,并列出一份 work plan;有改动就调用 Plan 1 的 `hermes-sync.yml` 去执行,没影响就关掉 issue。

**Architecture:** 三段式(ADR 决定二的形状):一个纯脚本的**准备 job**用 `gh compare pin...新tag` 取 diff、按"源码地盘对照表"把改动文件归到章、并挑出没有任何章覆盖的"覆盖缺口",输出一个待评估区域的 JSON 数组;一个 **matrix job**照这个数组动态并行,每个区域派一个 `claude -p` 同时给出评估(复杂度四档)和规划(work plan 条目);一个**汇总 job**再派两个交叉挑错 agent(查漏 / 查站不住),然后算整体复杂度与置信度、按 `sync-policy.yml` 决定去向:`none` 关 issue,有改动就 `workflow_call` 调 `hermes-sync.yml`,命中 flag 条件则给 issue 打 `flagged:待抽查`。

**Tech Stack:** GitHub Actions(动态 matrix + `workflow_call`)、bash、`gh`、`yq`、`jq`、Claude Code headless(`claude -p`)。复用 Plan 1 的 `.github/scripts/test/assert.sh`、`.github/sync-policy.yml`、`.github/workflows/hermes-sync.yml`。

## Global Constraints

与 Plan 1 同(逐字见 `.github/plans/2026-07-22-hermes-sync-engine.md` 的 Global Constraints)。要点重申:

- agent 一律 headless `claude -p`、非 `--bare`、`CLAUDE_CODE_OAUTH_TOKEN` 鉴权、带 `--permission-mode acceptEdits` 和 `--allowedTools` 白名单。
- agent 只出 JSON,发 issue / 调下游一律由确定的 bash/YAML 步骤做。
- 阈值(flag 条件、复核严格度)从 `.github/sync-policy.yml` 读,不写死。
- 提交只 stage 明确路径,绝不 `git add -A`。
- `②` 自己不改文档、不动 pin——它只产出 work plan,交给 ③。

---

## File Structure

**新建:**
- `.github/chapter-source-map.yml` — 源码地盘对照表:每章覆盖哪些顶层源码路径前缀。
- `.github/scripts/lib/srcmap.sh` — `chapters_for_path`、`path_is_covered` 两个函数。
- `.github/scripts/assess-prep.sh` — 准备脚本:gh compare → 归章 + 找覆盖缺口 → 输出 matrix 用的区域数组 JSON。
- `.github/scripts/lib/assess-agg.sh` — `overall_complexity`、`decide_route` 两个汇总函数。
- `.github/schemas/region-assessment.json` — 区域 agent 输出 schema(`{complexity, reason, plan_items[]}`)。
- `.github/schemas/crosscheck.json` — 挑错 agent 输出 schema(`{overturned, findings[]}`)。
- `.github/prompts/assess-region.md` — 区域评估+规划提示。
- `.github/prompts/assess-missed.md` — 查漏提示。
- `.github/prompts/assess-unfounded.md` — 查站不住提示。
- `.github/workflows/hermes-assess-plan.yml` — 工作流(准备 → matrix → 汇总 → 调 ③)。
- Test:`.github/scripts/test/test-srcmap.sh`、`test-assess-prep.sh`、`test-assess-agg.sh`。

**依赖(已存在):** Plan 1 的 `assert.sh`、`sync-policy.yml`、`hermes-sync.yml`;`.claude/skills/hermes-agent-expert/scripts/`(浅克隆源码后可跑)。

---

## Task 1:源码地盘对照表 + 归章函数

**Files:**
- Create: `.github/chapter-source-map.yml`
- Create: `.github/scripts/lib/srcmap.sh`
- Test: `.github/scripts/test/test-srcmap.sh`

**Interfaces:**
- Produces:
  - `chapters_for_path <map_yaml> <path>` —— 回显所有"前缀能匹配 path"的章号,每行一个;无匹配则回显空。
  - `path_is_covered <map_yaml> <path>` —— 有任一章覆盖则退出 0,否则退出 1。

- [ ] **Step 1: 写对照表(依 CLAUDE.md 的 15 章结构 + hermes-agent 目录)**

`.github/chapter-source-map.yml`:
```yaml
# 每章覆盖哪些顶层源码路径前缀。前缀匹配(path 以某前缀开头即算该章覆盖)。
# 只列"有源码地盘"的章;纯综述章(00)覆盖仓库根的少量文件。
chapters:
  "00": ["README", "pyproject.toml", "hermes-agent/README"]
  "01": ["hermes_cli/"]
  "02": ["hermes_agent/agent", "hermes_agent/lsp", "hermes_agent/transports"]
  "03": ["hermes_agent/tools", "hermes_agent/environments"]
  "04": ["hermes_agent/skills"]
  "05": ["gateway/"]
  "06": ["acp_adapter/", "mcp_serve/"]
  "07": ["hermes_agent/plugins"]
  "08": ["plugins/"]
  "09": ["kanban/"]
  "10": ["hermes_agent/interaction", "hermes_agent/run_modes"]
  "11": ["cron/"]
  "12": ["batch/", "trajectory/"]
  "13": ["scripts/", ".github/"]
  "14": ["apps/desktop/", "bootstrap-installer/", "shared/"]
```

> 注:上面的前缀是按文档结构给的初值,构建时以 hermes-agent v0.18.2 实际顶层目录为准逐条核对(Task 独立测只验函数逻辑,不验前缀是否命中真目录;真目录命中在 smoke 验)。

- [ ] **Step 2: 写归章函数**

`.github/scripts/lib/srcmap.sh`:
```bash
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
```

- [ ] **Step 3: 写失败的测试**

`.github/scripts/test/test-srcmap.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/srcmap.sh"
map="$here/../../chapter-source-map.yml"

assert_eq "05" "$(chapters_for_path "$map" "gateway/router.py")" "gateway 归 05"
assert_eq "01" "$(chapters_for_path "$map" "hermes_cli/main.py")" "hermes_cli 归 01"
assert_eq "14" "$(chapters_for_path "$map" "apps/desktop/electron/main.cjs")" "desktop 归 14"
path_is_covered "$map" "gateway/x.py"; assert_eq "0" "$?" "gateway 有覆盖"
path_is_covered "$map" "brand_new_module/x.py"; assert_eq "1" "$?" "全新模块无覆盖=缺口"
echo "test-srcmap: PASS"
```

- [ ] **Step 4: 跑测试确认失败**

Run: `bash .github/scripts/test/test-srcmap.sh` → FAIL(函数未定义 / map 未建)。

- [ ] **Step 5: 跑测试确认通过**

Run: `bash .github/scripts/test/test-srcmap.sh` → `test-srcmap: PASS`。

- [ ] **Step 6: 提交**

```bash
git add .github/chapter-source-map.yml .github/scripts/lib/srcmap.sh .github/scripts/test/test-srcmap.sh
git commit -m "feat(assess): 源码地盘对照表 + 归章函数"
```

---

## Task 2:准备脚本 assess-prep.sh(diff → 区域数组)

**Files:**
- Create: `.github/scripts/assess-prep.sh`
- Test: `.github/scripts/test/test-assess-prep.sh`

**Interfaces:**
- Consumes(环境变量):`PIN`、`NEW_TAG`;可注入桩 `GH_CMD`(默认 `gh`)提供 `gh api .../compare` 的 files 列表;`MAP`(默认 `.github/chapter-source-map.yml`)。
- Produces:向 stdout 输出一个 JSON 数组,每个元素 `{"region":"ch05","files":["gateway/router.py",...]}`,外加一个特殊元素 `{"region":"gap","files":[未被任何章覆盖的改动文件...]}`(仅当有缺口时)。这个数组就是 matrix 的清单。

- [ ] **Step 1: 写准备脚本**

`.github/scripts/assess-prep.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
MAP="${MAP:-$ROOT/.github/chapter-source-map.yml}"
source "$ROOT/.github/scripts/lib/srcmap.sh"

# 取改动文件清单(仅文件名)。gh api compare 分页上限 300,超了要翻页——此处先取第一页,
# 构建时若 files 数达 300 需补 --paginate(见 Self-Review 待实测)。
files="$("$GH" api "repos/NousResearch/hermes-agent/compare/${PIN}...${NEW_TAG}" \
          --jq '.files[].filename')"

declare -A byreg; gaps=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  chs="$(chapters_for_path "$MAP" "$f")"
  if [ -z "$chs" ]; then gaps+="$f"$'\n'; continue; fi
  while IFS= read -r ch; do byreg["ch$ch"]+="$f"$'\n'; done <<< "$chs"
done <<< "$files"

# 拼 JSON 数组
{
  printf '['
  first=1
  for reg in "${!byreg[@]}"; do
    [ "$first" = 1 ] && first=0 || printf ','
    printf '{"region":"%s","files":%s}' "$reg" \
      "$(printf '%s' "${byreg[$reg]}" | jq -R . | jq -s 'map(select(length>0))')"
  done
  if [ -n "$gaps" ]; then
    [ "$first" = 1 ] || printf ','
    printf '{"region":"gap","files":%s}' \
      "$(printf '%s' "$gaps" | jq -R . | jq -s 'map(select(length>0))')"
  fi
  printf ']'
}
```

- [ ] **Step 2: 写失败的测试(桩 gh compare)**

`.github/scripts/test/test-assess-prep.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<'EOF'
#!/usr/bin/env bash
# 只认 --jq '.files[].filename',回三个文件:两个归章、一个缺口
printf '%s\n' "gateway/router.py" "hermes_cli/x.py" "brand_new/y.py"
EOF
chmod +x "$stub/gh"

out="$(GH_CMD="$stub/gh" REPO_ROOT="$root" PIN=vA NEW_TAG=vB bash "$root/.github/scripts/assess-prep.sh")"
# 区域集合应含 ch05、ch01、gap
assert_eq "3" "$(jq 'length' <<<"$out")" "应有 3 个区域(ch05/ch01/gap)"
assert_eq "brand_new/y.py" "$(jq -r '.[]|select(.region=="gap").files[0]' <<<"$out")" "缺口文件对"
echo "test-assess-prep: PASS"
```

- [ ] **Step 3: 跑测试确认失败 → 补脚本 → 确认通过**

Run: `bash .github/scripts/test/test-assess-prep.sh`
先 FAIL(脚本缺失),补全后 Expected: `test-assess-prep: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/assess-prep.sh .github/scripts/test/test-assess-prep.sh
git commit -m "feat(assess): 准备脚本 diff→归章→区域数组(含覆盖缺口)"
```

---

## Task 3:区域评估 + 挑错的 schema 和提示

**Files:**
- Create: `.github/schemas/region-assessment.json`
- Create: `.github/schemas/crosscheck.json`
- Create: `.github/prompts/assess-region.md`
- Create: `.github/prompts/assess-missed.md`
- Create: `.github/prompts/assess-unfounded.md`

**Interfaces:**
- Produces:两个 schema、三个提示。区域 agent 产出 `{complexity, reason, plan_items[]}`;两个挑错 agent 各产出 `{overturned, findings[]}`。

- [ ] **Step 1: 写区域评估 schema**

`.github/schemas/region-assessment.json`:
```json
{
  "type": "object", "additionalProperties": false,
  "required": ["complexity", "reason", "plan_items"],
  "properties": {
    "complexity": { "type": "string", "enum": ["none", "cosmetic", "shallow", "deep"] },
    "reason": { "type": "string", "minLength": 1 },
    "plan_items": {
      "type": "array",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["位置", "现状", "改成什么", "源码依据", "类型"],
        "properties": {
          "位置": {"type":"string"}, "现状": {"type":"string"},
          "改成什么": {"type":"string"}, "源码依据": {"type":"string"},
          "类型": {"type":"string","enum":["cosmetic","shallow","deep","new-chapter","new-section","new-anchor"]}
        }
      }
    }
  }
}
```

- [ ] **Step 2: 写挑错 schema**

`.github/schemas/crosscheck.json`:
```json
{
  "type": "object", "additionalProperties": false,
  "required": ["overturned", "findings"],
  "properties": {
    "overturned": { "type": "boolean" },
    "findings": { "type": "array", "items": { "type": "string" } }
  }
}
```

- [ ] **Step 3: 写区域评估提示**

`.github/prompts/assess-region.md`:
```markdown
你在评估 hermes-agent 从 ${PIN} 到 ${NEW_TAG} 的一版改动,对某一文档区域(${REGION})的影响。

这个区域涉及的改动文件:
${FILES}

材料:上面这些文件的 diff 片段,以及该区域当前的文档原文(在 docs/ 里,章号见 ${REGION})。

请一次判断两样:
1. 复杂度,四选一并说明理由:none(文档说法没受影响)/ cosmetic(只是行号挪了)/ shallow(几处事实或锚点要更新)/ deep(行为或架构变了,得重读源码)。
2. 规划:列出具体要改的每一处(位置、现状、改成什么、源码依据 文件:行:符号、类型)。deep 的可以给粗清单。

若 ${REGION} 是 "gap"(覆盖缺口,即这些是没有任何章覆盖的新代码):判断要不要开新文档——够大够独立→新开一章(类型 new-chapter),现有某章容得下→加一节(new-section),小工具/配置→加锚点(new-anchor),无关紧要→plan_items 留空、complexity 记 none。

**输出**:把结果写成符合 schema ${SCHEMA} 的 JSON 到 ${OUT}。只写这个文件。
```

- [ ] **Step 4: 写查漏提示**

`.github/prompts/assess-missed.md`:
```markdown
你是"查漏"复核员。下面是本版所有改动文件里,**没有被归入任何评估区域**的那些(通常是脚本判定其所在目录无文档覆盖,或压根没被文档路径引用):
${UNCLAIMED_FILES}

追问一句:这些改动里,有没有其实影响了某条文档说法、只是文档没用路径引用它的?重点抓"代码位置没变、含义却变了(比如默认值、行为)、锚点检测报不出来"的情况。

**输出**:符合 schema ${SCHEMA} 的 JSON 到 ${OUT}。`overturned=true` 表示你发现了被漏掉的真实影响;`findings` 列出每一条。只写这个文件。
```

- [ ] **Step 5: 写查站不住提示**

`.github/prompts/assess-unfounded.md`:
```markdown
你是"查站不住"复核员。下面是各区域 agent 汇总出的改动清单(work plan):
${WORK_PLAN}

逐条审:这条依据(源码文件:行:符号)对不对?grep 真源码(pin=${PIN})核对。会不会根本不用改、或者改反了方向?

**输出**:符合 schema ${SCHEMA} 的 JSON 到 ${OUT}。`overturned=true` 表示你推翻了至少一条;`findings` 列出每一条问题(指明是 work plan 第几条)。只写这个文件。
```

- [ ] **Step 6: 提交(无单测;schema/提示在 Task 4 汇总逻辑和 smoke 里被用到)**

```bash
git add .github/schemas/region-assessment.json .github/schemas/crosscheck.json \
        .github/prompts/assess-region.md .github/prompts/assess-missed.md .github/prompts/assess-unfounded.md
git commit -m "feat(assess): 区域评估/挑错的 schema 与提示"
```

---

## Task 4:汇总函数(overall_complexity / decide_route)

**Files:**
- Create: `.github/scripts/lib/assess-agg.sh`
- Test: `.github/scripts/test/test-assess-agg.sh`

**Interfaces:**
- Consumes: 各区域 `{complexity,...}` JSON 文件所在目录;两个挑错结果 JSON;`sync-policy.yml`。
- Produces:
  - `overall_complexity <dir>` —— 回显目录里各区域 complexity 的最高档(none<cosmetic<shallow<deep)。
  - `decide_route <overall> <has_changes> <any_overturned> <has_new_chapter>` —— 回显 `close` / `proceed` / `proceed_flagged` 之一(规则见下)。

- [ ] **Step 1: 写汇总函数**

`.github/scripts/lib/assess-agg.sh`:
```bash
# overall_complexity <dir> —— 各区域 complexity 取最高档。
overall_complexity() {
  local dir="$1" rank=0 best="none" f c r
  declare -A R=([none]=0 [cosmetic]=1 [shallow]=2 [deep]=3)
  for f in "$dir"/region-*.json; do
    [ -e "$f" ] || continue
    c="$(jq -r '.complexity' "$f")"; r="${R[$c]:-0}"
    [ "$r" -gt "$rank" ] && { rank="$r"; best="$c"; }
  done
  echo "$best"
}

# decide_route <overall> <has_changes(0/1)> <any_overturned(0/1)> <has_new_chapter(0/1)>
#   全 none 或没改动         → close
#   命中 flag 条件(deep/新章/被推翻→低置信) → proceed_flagged
#   否则                     → proceed
decide_route() {
  local overall="$1" has_changes="$2" overturned="$3" newchap="$4"
  if [ "$has_changes" != "1" ] || [ "$overall" = "none" ]; then echo "close"; return; fi
  if [ "$overall" = "deep" ] || [ "$newchap" = "1" ] || [ "$overturned" = "1" ]; then
    echo "proceed_flagged"; return
  fi
  echo "proceed"
}
```

- [ ] **Step 2: 写失败的测试**

`.github/scripts/test/test-assess-agg.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"; source "$here/../lib/assess-agg.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo '{"complexity":"cosmetic"}' > "$tmp/region-1.json"
echo '{"complexity":"shallow"}'  > "$tmp/region-2.json"
assert_eq "shallow" "$(overall_complexity "$tmp")" "取最高档 shallow"
echo '{"complexity":"deep"}'     > "$tmp/region-3.json"
assert_eq "deep" "$(overall_complexity "$tmp")" "有 deep 取 deep"

assert_eq "close"           "$(decide_route none 0 0 0)" "无改动=close"
assert_eq "close"           "$(decide_route none 1 0 0)" "全 none=close"
assert_eq "proceed"         "$(decide_route shallow 1 0 0)" "shallow 稳=proceed"
assert_eq "proceed_flagged" "$(decide_route deep 1 0 0)" "deep=flagged"
assert_eq "proceed_flagged" "$(decide_route shallow 1 0 1)" "开新章=flagged"
assert_eq "proceed_flagged" "$(decide_route shallow 1 1 0)" "被推翻=flagged"
echo "test-assess-agg: PASS"
```

- [ ] **Step 3: 跑测试确认失败 → 补 → 通过**

Run: `bash .github/scripts/test/test-assess-agg.sh` → 先 FAIL,补全后 `test-assess-agg: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/lib/assess-agg.sh .github/scripts/test/test-assess-agg.sh
git commit -m "feat(assess): 汇总 overall_complexity + decide_route(读 flag 规则)"
```

---

## Task 5:hermes-assess-plan.yml 工作流

**Files:**
- Create: `.github/workflows/hermes-assess-plan.yml`

**Interfaces:**
- Consumes:被 ① 触发(方式 Plan 4 定;本 task 先支持 `workflow_dispatch` 手动触发,输入 `new_tag`、`issue_number`)。读 `.hermes-pin` 得 `PIN`。
- Produces:准备 → matrix(区域评估)→ 汇总(挑错 + 定去向)。`proceed*` 时用 `workflow_call` 调 `hermes-sync.yml` 传 work plan;`close` 时关 issue。

- [ ] **Step 1: 写工作流**

`.github/workflows/hermes-assess-plan.yml`:
```yaml
name: hermes 评估+规划

on:
  workflow_dispatch:
    inputs:
      new_tag:      { type: string, required: true }
      issue_number: { type: string, required: true }

permissions: { contents: read, issues: write, pull-requests: write }

jobs:
  prep:
    runs-on: ubuntu-latest
    outputs:
      regions: ${{ steps.p.outputs.regions }}
    steps:
      - uses: actions/checkout@v4
      - run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
      - id: p
        env: { GH_TOKEN: "${{ github.token }}" }
        run: |
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)"
          regions="$(PIN="$PIN" NEW_TAG='${{ inputs.new_tag }}' bash .github/scripts/assess-prep.sh)"
          echo "regions=$regions" >> "$GITHUB_OUTPUT"

  assess:
    needs: prep
    if: ${{ needs.prep.outputs.regions != '[]' }}
    runs-on: ubuntu-latest
    strategy:
      matrix: { region: ${{ fromJSON(needs.prep.outputs.regions) }} }
    steps:
      - uses: actions/checkout@v4
      - run: curl -fsSL https://claude.ai/install.sh | bash; echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: 评估一个区域
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          REGION: ${{ matrix.region.region }}
          FILES: ${{ toJSON(matrix.region.files) }}
          NEW_TAG: ${{ inputs.new_tag }}
        run: |
          PIN="$(grep '^tag=' .hermes-pin | cut -d= -f2)"
          OUT="region-${REGION}.json"
          prompt="$(REGION="$REGION" FILES="$FILES" PIN="$PIN" NEW_TAG="$NEW_TAG" \
            OUT="$OUT" SCHEMA=.github/schemas/region-assessment.json \
            envsubst < .github/prompts/assess-region.md)"
          claude -p "$prompt" --permission-mode acceptEdits \
            --allowedTools "Read,Write,Bash(grep:*),Grep,Glob"
      - uses: actions/upload-artifact@v4
        with: { name: "region-${{ matrix.region.region }}", path: "region-*.json" }

  finalize:
    needs: [prep, assess]
    if: ${{ always() }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { path: regions, merge-multiple: true }
      - name: 挑错 + 定去向 + 派发
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          GH_TOKEN: ${{ github.token }}
          ISSUE: ${{ inputs.issue_number }}
          NEW_TAG: ${{ inputs.new_tag }}
        run: bash .github/scripts/assess-finalize.sh regions
```

> `assess-finalize.sh`(挑错→汇总→贴 issue→`close`/派发)在 Task 6 写并测。

- [ ] **Step 2: actionlint 验证**

Run: `./actionlint .github/workflows/hermes-assess-plan.yml`(actionlint 已在 Plan 1 Task 8 下载)。Expected: 0 错误。动态 matrix 的 `fromJSON` 写法若报警,按提示调整。

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/hermes-assess-plan.yml
git commit -m "feat(assess): hermes-assess-plan.yml(准备→matrix→汇总)"
```

---

## Task 6:assess-finalize.sh(挑错 → 汇总 → 派发 / 关 issue)

**Files:**
- Create: `.github/scripts/assess-finalize.sh`
- Test: `.github/scripts/test/test-assess-finalize.sh`

**Interfaces:**
- Consumes: `assess-finalize.sh <regions_dir>`;环境 `ISSUE`、`NEW_TAG`;可注入 `CLAUDE_CMD`、`GH_CMD`;读 `region-*.json`。
- Produces:合并所有 plan_items 成一份 work plan;跑两个挑错 agent;调 `overall_complexity`/`decide_route`;把标准记录贴 issue;`close` 时关 issue,`proceed*` 时用 `gh workflow run hermes-sync.yml`(或 `workflow_call`,Plan 4 串真链路时定)派发,`proceed_flagged` 额外打 `flagged:待抽查` 标签。

- [ ] **Step 1: 写脚本**

`.github/scripts/assess-finalize.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
dir="$1"
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
CLAUDE="${CLAUDE_CMD:-claude}"; GH="${GH_CMD:-gh}"
source "$ROOT/.github/scripts/lib/assess-agg.sh"

# 1) 合并 work plan
work="$(jq -s '[.[].plan_items[]?]' "$dir"/region-*.json)"
has_changes=$([ "$(jq 'length' <<<"$work")" -gt 0 ] && echo 1 || echo 0)
newchap=$([ "$(jq '[.[]|select(.类型=="new-chapter")]|length' <<<"$work")" -gt 0 ] && echo 1 || echo 0)

# 2) 两个挑错 agent(桩可注入),各写 crosscheck JSON
cc="$(mktemp -d)"
"$CLAUDE" -p "查漏" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/missed.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/missed.json"
"$CLAUDE" -p "查站不住" --permission-mode acceptEdits --allowedTools "Read,Write,Grep" \
  > "$cc/unfounded.json" 2>/dev/null || echo '{"overturned":false,"findings":[]}' > "$cc/unfounded.json"
overturned=$([ "$(jq -s 'any(.[]; .overturned)' "$cc"/*.json)" = "true" ] && echo 1 || echo 0)

# 3) 汇总 + 定去向
overall="$(overall_complexity "$dir")"
route="$(decide_route "$overall" "$has_changes" "$overturned" "$newchap")"

# 4) 贴 issue 标准记录
printf '### [②评估+规划] route=%s complexity=%s overturned=%s\n' "$route" "$overall" "$overturned" \
  | "$GH" issue comment "$ISSUE" --body-file -

# 5) 去向
case "$route" in
  close)
    "$GH" issue close "$ISSUE" --comment "评估:无影响,收工" ;;
  proceed|proceed_flagged)
    [ "$route" = proceed_flagged ] && "$GH" issue edit "$ISSUE" --add-label "flagged:待抽查"
    "$GH" workflow run hermes-sync.yml \
      -f work_plan="$work" -f cycle=sync -f issue_number="$ISSUE" -f new_tag="$NEW_TAG" ;;
esac
```

- [ ] **Step 2: 写测试(桩 claude/gh,验三条去向)**

`.github/scripts/test/test-assess-finalize.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; log="$stub/calls"; trap 'rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\necho "{\\"overturned\\":false,\\"findings\\":[]}"\n' > "$stub/claude"; chmod +x "$stub/claude"
cat > "$stub/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$1 \$2" >> "$log"; exit 0
EOF
chmod +x "$stub/gh"

# 场景A:无改动 → close
d="$stub/a"; mkdir -p "$d"; echo '{"complexity":"none","plan_items":[]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh issue close" "$log" || { echo "无改动应 close"; exit 1; }

# 场景B:shallow 有改动 → 派发 workflow run
: > "$log"; d="$stub/b"; mkdir -p "$d"
echo '{"complexity":"shallow","plan_items":[{"位置":"x","现状":"a","改成什么":"b","源码依据":"f:1","类型":"shallow"}]}' > "$d/region-1.json"
CLAUDE_CMD="$stub/claude" GH_CMD="$stub/gh" REPO_ROOT="$root" ISSUE=1 NEW_TAG=vB \
  bash "$root/.github/scripts/assess-finalize.sh" "$d" >/dev/null 2>&1
grep -q "gh workflow run" "$log" || { echo "有改动应派发"; exit 1; }
echo "test-assess-finalize: PASS"
```

- [ ] **Step 3: 跑测试确认失败 → 补 → 通过**

Run: `bash .github/scripts/test/test-assess-finalize.sh` → 先 FAIL,补全后 `test-assess-finalize: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/assess-finalize.sh .github/scripts/test/test-assess-finalize.sh
git commit -m "feat(assess): assess-finalize 挑错+汇总+派发/关 issue"
```

---

## Task 7:端到端 smoke(手动触发,真跑一版)

**Files:**（无新增;用真 `gh`/`claude`,需 secret）

- [ ] **Step 1: 前置**

确认 `CLAUDE_CODE_OAUTH_TOKEN` 已是仓库 secret(Plan 1 Task 9 已加则复用)。

- [ ] **Step 2: 手动触发一版真评估**

拿一个真实的更新版本号(比如上游某个 > pin 的 tag),手动开个 issue 记编号,然后:
```bash
gh workflow run "hermes 评估+规划" -f new_tag=<某真 tag> -f issue_number=<刚开的 issue 号>
gh run watch
```
Expected 核对:①准备 job 输出的 regions 数组里,改动确实按目录归到了对的章(验证 `chapter-source-map.yml` 前缀命中真目录);②matrix 每个区域各跑出一个 region JSON;③finalize 在 issue 里留下 `[②评估+规划] route=... ` 记录;④route 正确(无影响→close;有影响→触发了 `hermes-sync.yml`)。

- [ ] **Step 3: 按 smoke 结果校准对照表**

若某改动没归到预期的章,说明 `chapter-source-map.yml` 的前缀和 hermes-agent 真目录对不上,据实修正前缀,重跑,再提交:
```bash
git add .github/chapter-source-map.yml
git commit -m "fix(assess): 按真目录校准源码地盘对照表前缀"
```

---

## Self-Review

- **Spec coverage(本 plan 范围 = ②)**:源码地盘对照表(Task 1)、diff→归章(Task 2)、覆盖缺口→新章判断(Task 2 gap + Task 3 提示)、区域评估四档 + 规划一次出(Task 3)、查漏/查站不住两视角挑错(Task 3/6)、整体复杂度取最难 + 置信度→去向(Task 4)、flag 条件读 sync-policy(Task 4)、none 关 issue / 有改动调 ③(Task 6)、matrix 三段式(Task 5)。① 触发方式与真链路串联留 Plan 4。
- **Placeholder scan**:无 TODO/TBD;`assess-finalize.sh` 里挑错 agent 用简化桩注入,真提示(assess-missed/unfounded)在 smoke 时接入——已在 Task 6 step 1 注释标明,非遗留占位。
- **Type consistency**:`chapters_for_path`/`path_is_covered`(Task 1)、`overall_complexity`/`decide_route`(Task 4)签名一致;region JSON 的 `{complexity, reason, plan_items[]}` 在 schema(Task 3)、汇总(Task 4)、finalize(Task 6)一致;work plan 条目字段 `{位置,现状,改成什么,源码依据,类型}` 与 Plan 1 的 `hermes-sync.yml` 输入、`sync-review.md` 消费的字段一致。
- **待实测(转 ADR)**:`gh api compare` 分页(files ≥ 300 需 `--paginate`);动态 matrix `fromJSON` 传对象数组给 `matrix.region`;`envsubst` 填多行 `${FILES}` JSON 的转义。均在 Task 7 smoke 暴露并校准。
