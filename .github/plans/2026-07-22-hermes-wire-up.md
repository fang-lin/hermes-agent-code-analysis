# ① 改写 + 串起整条链路 Implementation Plan(Plan 4 / 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 ① 新版本检测改成新设计(只检测新版本、开 sync issue、触发 ②),并把 ①→②→③ 与 复核循环→③ 两条链路真正接通、跑通一次端到端。

**Architecture:** ① 的脚本退化成"比 release 和 pin,新则开 issue 并 `gh workflow run` 触发 ②";③ `hermes-sync.yml` 增开 `workflow_dispatch` 触发口,让 ② 和 复核循环能用 `gh workflow run` 调它(前三个 plan 都按这个假设写的,这里补上)。最后用测试钩子模拟一次新版本,验证整条链。

**Tech Stack:** 复用前三个 plan 的全部产物。本 plan 主要是改写 + 接线 + 集成测试,新增代码少。

## Global Constraints

同前。特别地:① 仍是纯脚本、不花 token、不碰 diff、不动 pin;所有跨工作流触发用 `gh workflow run`;secrets 显式传;提交只 stage 明确路径。

---

## File Structure

**改写:**
- `.github/scripts/hermes-release-watch.sh` — 退化为"检测新版本"(去掉旧的 orient/check-anchors/drift 逻辑)。
- `.github/workflows/hermes-release-watch.yml` — 新版本→开 sync issue→触发 ②(去掉旧的 drift-issue 逻辑)。
- `.github/workflows/hermes-sync.yml` — 增开 `workflow_dispatch`(Plan 1 只开了 `workflow_call`)。

**改文档:**
- `.github/adr/0001-ci-tech-choices.md` — 记入本轮实现细化(claude -p、③ 加 dispatch 口、gh compare 分页)。
- `.github/README.md` — 文件清单状态从"待建"改为"已建"。

**Test:** `.github/scripts/test/test-release-watch.sh`。

---

## Task 1:改写 ① 检测脚本

**Files:**
- Modify: `.github/scripts/hermes-release-watch.sh`(整体替换为下述内容)
- Test: `.github/scripts/test/test-release-watch.sh`

**Interfaces:**
- Consumes:测试钩子环境变量 `HERMES_PIN_TAG`、`HERMES_LATEST`、`GH_CMD`、`REPO_ROOT`。
- Produces:stdout 第一行为 `UPTODATE (<tag>)` 或 `NEW <tag>`;退出码 0。

- [ ] **Step 1: 写新脚本(替换旧内容)**

`.github/scripts/hermes-release-watch.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
# ① 新版本检测:比 NousResearch/hermes-agent 的最新 release 和 .hermes-pin。
# 相同 → UPTODATE;更新 → NEW <tag>。纯脚本、不花 token、不碰 diff、不动 pin。
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
pin="${HERMES_PIN_TAG:-$(grep '^tag=' "$ROOT/.hermes-pin" | cut -d= -f2)}"
latest="${HERMES_LATEST:-$("$GH" api repos/NousResearch/hermes-agent/releases/latest --jq .tag_name)}"
if [ "$latest" = "$pin" ]; then
  echo "UPTODATE ($pin)"
else
  echo "NEW $latest"
fi
```

- [ ] **Step 2: 写失败的测试**

`.github/scripts/test/test-release-watch.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
sh="$root/.github/scripts/hermes-release-watch.sh"

out="$(HERMES_PIN_TAG=v1 HERMES_LATEST=v1 REPO_ROOT="$root" bash "$sh")"
assert_eq "UPTODATE (v1)" "$out" "同版应 UPTODATE"
out="$(HERMES_PIN_TAG=v1 HERMES_LATEST=v2 REPO_ROOT="$root" bash "$sh")"
assert_eq "NEW v2" "$out" "新版应 NEW v2"
echo "test-release-watch: PASS"
```

- [ ] **Step 3: 跑测试确认失败(旧脚本输出不匹配)→ 替换 → 通过**

Run: `bash .github/scripts/test/test-release-watch.sh`
旧脚本(orient/drift 逻辑)时 FAIL;替换后 Expected: `test-release-watch: PASS`。

- [ ] **Step 4: 提交**

```bash
git add .github/scripts/hermes-release-watch.sh .github/scripts/test/test-release-watch.sh
git commit -m "refactor(watch): ① 退化为纯新版本检测(去 orient/drift)"
```

---

## Task 2:改写 ① 工作流(新版本→开 issue→触发 ②)

**Files:**
- Modify: `.github/workflows/hermes-release-watch.yml`(整体替换)

- [ ] **Step 1: 写工作流**

`.github/workflows/hermes-release-watch.yml`:
```yaml
name: hermes 新版本检测

on:
  schedule:
    - cron: "0 6 * * *"   # 每天 06:00 UTC
  workflow_dispatch: {}

permissions: { contents: read, issues: write, actions: write }

concurrency: { group: hermes-release-watch, cancel-in-progress: false }

jobs:
  watch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: chk
        env: { GH_TOKEN: "${{ github.token }}" }
        run: |
          out="$(bash .github/scripts/hermes-release-watch.sh)"; echo "$out"
          echo "status=$out" >> "$GITHUB_OUTPUT"
      - name: 新版本 → 开 issue + 触发 ②
        if: startsWith(steps.chk.outputs.status, 'NEW')
        env: { GH_TOKEN: "${{ github.token }}" }
        run: |
          tag="$(echo '${{ steps.chk.outputs.status }}' | awk '{print $2}')"
          gh label create sync-cycle --color 0E8A16 2>/dev/null || true
          issue="$(gh issue create --title "sync: $tag" --label sync-cycle \
            --body "上游新版本 $tag,启动同步。" --json number --jq .number)"
          gh workflow run hermes-assess-plan.yml -f new_tag="$tag" -f issue_number="$issue"
```

- [ ] **Step 2: actionlint**

Run: `./actionlint .github/workflows/hermes-release-watch.yml` → 0 错误。

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/hermes-release-watch.yml
git commit -m "refactor(watch): ① 新版本→开 sync issue→触发 ②"
```

---

## Task 3:给 ③ 加 workflow_dispatch 触发口

**Files:**
- Modify: `.github/workflows/hermes-sync.yml`(把 `on:` 从只有 `workflow_call` 扩为同时支持 `workflow_dispatch`)

**理由:** Plan 2/3 的 finalize 用 `gh workflow run hermes-sync.yml -f ...` 触发 ③,而 `gh workflow run` 走的是 `workflow_dispatch`。Plan 1 只开了 `workflow_call`,这里补上 `workflow_dispatch`(输入同名),两个口共用同一份 job。

- [ ] **Step 1: 改 on 段**

把 `.github/workflows/hermes-sync.yml` 的 `on:` 改为:
```yaml
on:
  workflow_call:
    inputs:
      work_plan:    { type: string, required: true }
      cycle:        { type: string, required: true }
      issue_number: { type: string, required: true }
      new_tag:      { type: string, required: false, default: "" }
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: { required: true }
  workflow_dispatch:
    inputs:
      work_plan:    { type: string, required: true }
      cycle:        { type: string, required: true }
      issue_number: { type: string, required: true }
      new_tag:      { type: string, required: false, default: "" }
```
job 里读输入的地方保持不变(`inputs.*` 两个触发口通用)。`workflow_dispatch` 触发时 secret 从仓库环境自动可见,无需显式传。

> 大小注意:`workflow_dispatch` 单个输入有长度上限。若某次 work plan 特别大超限,退回"把 work plan 贴进 issue、③ 从 issue 读"的方式(见 Self-Review 的待实测项)。常规体量的 work plan 直接走输入即可。

- [ ] **Step 2: actionlint + 提交**

Run: `./actionlint .github/workflows/hermes-sync.yml` → 0 错误。
```bash
git add .github/workflows/hermes-sync.yml
git commit -m "feat(sync): ③ 增开 workflow_dispatch,供 ②/复核循环 gh workflow run 触发"
```

---

## Task 4:整条链路 smoke(模拟一次新版本)

**Files:**（无新增;需 secret)

- [ ] **Step 1: 用测试钩子伪造一个新版本,只跑 ①**

先不真触发下游,单验 ① 的判断和开 issue:临时用 `workflow_dispatch` 跑 `hermes 新版本检测`,并确认在真有新版本时它开出 `sync: <tag>` issue、并 `gh workflow run` 了 ②。
```bash
gh workflow run "hermes 新版本检测"
gh run watch
```
Expected:若上游确有 > pin 的 release,则新建了一个 `sync-cycle` 标签的 issue,且 ② 被触发(在 Actions 页能看到 `hermes 评估+规划` 随后启动)。若上游暂无新版本(pin 已是最新),① 打印 UPTODATE、不开 issue——此时改用下一步的手动方式验证 ②③。

- [ ] **Step 2: 手动串 ②→③(拿一个真 tag)**

若当前 pin 已是最新,直接手动喂 ② 一个"假想更新"来验证 ②→③:开一个测试 issue,`gh workflow run "hermes 评估+规划" -f new_tag=<pin 之后的某真 tag> -f issue_number=<测试 issue>`,`gh run watch`。
Expected:② 评估出影响、列 work plan、`gh workflow run hermes-sync.yml`;③ 随后改文档、复核、开自动合并 PR;若 cycle=sync,PR 合并时 `.hermes-pin` bump 到新 tag。核对 issue 里三层记录齐全、复核评语折叠块在、PR 的改动正确。

- [ ] **Step 3: 记录整条链的 token 与耗时,确认审计记录完整**

在那个 sync issue 里应能从上到下读到:①(token 0)→②(本层/累计 token)→③(本层/累计 token)三条标准记录,加复核评语折叠块和改动折叠块。缺哪块补哪块。

---

## Task 5:收口 ADR 与 spec 状态

**Files:**
- Modify: `.github/adr/0001-ci-tech-choices.md`
- Modify: `.github/README.md`

- [ ] **Step 1: ADR 追加"实现阶段的细化"一节**

在 ADR 末尾加一节,记三条落地时对原决定的细化(内容据实,示意):
- **决定一细化**:agent 调用最终用 headless `claude -p`(非 claude-code-action),因为"改写↔复核"要在 bash 循环里反复调、matrix 里逐 job 调,`claude -p` 更好套;两者都是非 bare + 订阅 token,决定一的核心理由不变,且顺带绕开了"action 里 token 顺不顺"那处不确定。
- **决定四细化**:③ 同时开 `workflow_call` 和 `workflow_dispatch`;上游用 `gh workflow run`(dispatch)触发。work plan 常规走输入;超长时退回"贴 issue、③ 从 issue 读"。
- **新增待实测**:`gh api compare` files ≥ 300 的分页(`--paginate`)。

- [ ] **Step 2: 更新 spec 文件清单状态**

`.github/README.md` 的「文件清单和进度」表:把 `hermes-assess-plan.yml`、`hermes-sync.yml`、`hermes-audit.yml`、`audit-ledger.json`、源码地盘对照表、`sync-policy.yml` 的状态由 `⬜ 待建` 改为 `✅ 已建`;① 一行由"逻辑待按新设计改"改为"✅ 已建(新设计)"。

- [ ] **Step 3: 提交并推送**

```bash
git add .github/adr/0001-ci-tech-choices.md .github/README.md
git commit -m "docs: ADR 记实现细化 + spec 文件清单状态更新为已建"
git push origin main
```

---

## Self-Review

- **Spec coverage(本 plan 范围 = ① 改写 + 集成)**:① 只检测新版本、开 issue、触发 ②、不碰 diff/pin(Task 1/2);③ 双触发口打通 ②/audit 的 `gh workflow run`(Task 3);整条 ①→②→③ 与 audit→③ 端到端(Task 4);审计记录三层齐全(Task 4 step 3);ADR/spec 收口(Task 5)。至此 spec 全部条目落到某个 plan 的某个 task。
- **Placeholder scan**:无 TODO/TBD。
- **Type consistency**:① 输出 `NEW <tag>` 被 yml 的 `awk '{print $2}'` 消费一致;`gh workflow run hermes-assess-plan.yml -f new_tag -f issue_number` 与 Plan 2 工作流的 `workflow_dispatch.inputs` 同名;`gh workflow run hermes-sync.yml -f work_plan -f cycle -f issue_number -f new_tag` 与 Task 3 补的 dispatch 输入同名。
- **待实测(转 ADR,Task 5 记入)**:`workflow_dispatch` 输入长度上限对大 work plan 的影响;`gh api compare` 分页;cron 时段(① 每日 06:00、audit 每周一 07:00)错开无冲突。
