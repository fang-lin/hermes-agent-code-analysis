# ADR-0001:文档自动同步在 GitHub Actions 里的技术选型

- **状态**:已采纳(2026-07-20)
- **相关**:设计见 [`.github/README.md`](../README.md);实现任务见 `/tasks`
- **背景约束**:非交互、全自动、走 Max 订阅额度、每步要产出可解析的"过/不过"+ 评语全文、全程可审计

这套自动化要在 GitHub Actions 里用 Claude Code 跑多 agent 的"评估+规划 / 同步 / 定期复核"流水线。下面几个技术选择彼此相扣(鉴权 → 是否用 --bare → 命名 agent 能不能自动加载 → 并行怎么做),所以合并成一份 ADR 讲清。每条决定都附了核实来源(官方文档)。

---

## 决定一:跑 agent 用 claude-code-action + 订阅 token,全程不用 `--bare`

**决定**:CI 里跑 agent 用 `anthropics/claude-code-action`(默认的非 `--bare` 模式),鉴权用 `CLAUDE_CODE_OAUTH_TOKEN`(`claude setup-token` 生成的一年期订阅 token)。

**为什么**:
- 项目主人的成本选择是走 **Max 订阅、不按 token 逐次计费**。`ANTHROPIC_API_KEY` 是按量付费,正是要避开的。
- 订阅 token 在 CI 里能用,但有一个硬约束:**`--bare` 模式会忽略 `CLAUDE_CODE_OAUTH_TOKEN`**(官方设计,不是 bug)。而且 `--bare` 还会**跳过 `.claude/agents/` 的自动加载**(见决定五)。两件事都指向同一个结论:**不用 `--bare`**。
- 放弃 `--bare` 的唯一代价是它的"快启动";CI 里真正的开销是 API 调用,不是启动时间,这点损失可忽略。

**代价 / 已知风险**:
- `claude-code-action` 默认是非 bare、支持 `claude_code_oauth_token` 输入——但"action 里有没有 `--bare` 等价开关、订阅 token 在 action 里是否 100% 顺畅",官方文档没逐字演示,**构建时要实测确认**。
- 订阅额度和平时在终端用 Claude Code **共享同一个 5 小时 / 每周窗口**;CI 大量跑会挤占这份额度。这点已在设计里向项目主人挑明,由他决定,不设自动护栏。
- token 约一年一换。

**否掉的方案**:`ANTHROPIC_API_KEY`。它是官方 CI 例子的默认、且不受 `--bare` 限制——但**按 token 计费**,与订阅的成本选择冲突。若将来改用按量计费,这条 ADR 需重开。

---

## 决定二:多 agent 并行用 GitHub Actions matrix,不用 Dynamic Workflows

**决定**:每个阶段的扇出用 GitHub Actions 的 **matrix**,形状统一为三段:
1. **准备 job**(纯脚本):算出这次要处理哪些章 / 区域,输出成一个 JSON 数组;
2. **matrix job**:照数组**动态**并行(`matrix: fromJSON(needs.prep.outputs.list)`),一份处理一章 / 一个区域,各自跑命名 agent、出结构化结果;
3. **汇总 job**:等前面全跑完,收齐结果,算整体复杂度 / 置信度、贴 issue、决定下一步。

**为什么**:
- **官方 CI 标准做法**。GitHub Actions 的例子都是"一个 action = 一个任务",并行靠 matrix,坑少、可预期。
- **日志天然分开**:每章一个 job,GitHub 页面上就是独立的一条,点进去是那章的原始日志——正好支撑"每个复核 agent 评语进 issue"的审计要求。
- **互不拖累**:某章的 job 失败不影响其它;重跑只重跑那一章。

**否掉的方案**:让一个 `claude -p` 跑 Dynamic Workflow(`.claude/workflows/*.js`,用 `agent()/pipeline()` 在进程内扇出)。它**能**在 headless `claude -p` 里跑,但:
- 不是官方推荐的 CI 用法(`ultracode` 关键字在 `-p` 传入时会被忽略,官方 CI 例子里没有 workflow 的先例);
- 进程内扇出的日志和产出都糊在一次运行里,跨章汇总和逐条审计不如 matrix 清楚。

**核实来源**:https://code.claude.com/docs/en/workflows.md 、https://code.claude.com/docs/en/github-actions.md

---

## 决定三:结构化 I/O —— agent 只出 JSON,由确定的 YAML 步骤贴 issue

**决定**:agent 用 `--output-format json --json-schema <schema>` 产出经校验的结构化结果;**发到 issue 这件事交给后续一个确定的 YAML 步骤**(用 `jq` 解析 + `gh issue comment`),不让 agent 自己发。复核 agent 的 schema 同时给两样:机器可读的 `verdict`(过 / 不过)+ `comments`(评语全文,原样进 issue)。

**为什么**:
- **审计记录要稳定**。让 agent 自己把格式贴对、每次都贴,不可靠;把"产出数据"和"发布副作用"分开,记录格式就由脚本保证。
- 这正是官方 headless 文档演示的标准做法(`claude -p ... --output-format json | jq | gh issue comment`)。
- `verdict` 让"3 个复核 agent 必须全过"这道门是机器判的;`comments` 保证评语一字不落留档。

**核实来源**:https://code.claude.com/docs/en/headless.md

---

## 决定四:③ 同步做成可复用工作流(`workflow_call`),两条循环共用

**决定**:把"改写 + 复核 + 合并"这段做成一个 `workflow_call` 可复用工作流;同步循环的"评估+规划"和复核循环都调它,work plan 以 JSON 字符串当输入传入。

**为什么**:③ 是两条循环共享的引擎,"被多个上游工作流复用"正是 `workflow_call` 的用途。

**代价 / 已知风险**:
- `workflow_call` 的 **secrets 不自动继承**,调用方要显式往下传(`secrets: {...}`)。
- 官方没有 `workflow_call` + `claude-code-action` 的端到端演示,机制上推得通,但**构建时要实测**。

**核实来源**:https://docs.github.com/en/actions/using-workflows/reusing-workflows

---

## 决定五:命名 subagent 靠 checkout + 自动加载

**决定**:复用 `.claude/agents/*.md` 里已定义的命名复核 agent(factual-reviewer 等),CI 里靠 `actions/checkout` 拉下仓库 + `claude-code-action`(非 --bare)**自动发现并加载**,不手动传定义。

**为什么**:`.claude/agents/` 是项目文件,checkout 后 action 会自动找到;和本地交互模式行为一致。这也是"不用 `--bare`"的又一个理由——`--bare` 不自动加载、得用 `--agents <json>` 手工塞,CI 里徒增维护。

**核实来源**:https://code.claude.com/docs/en/github-actions.md 、https://code.claude.com/docs/en/headless.md

---

## 决定六:ledger 更新走 PR,不直接 push

**决定**:复核循环一次跑完,把这轮所有章的 `audit-ledger.json` 更新(改过的 + 没改只盖章的)**打成一个 PR 自动合并**。一次运行一个 ledger PR。

**为什么**:守住"绝不直接 push 主分支"这条底线,让纯元数据变更也统一走可回退的 PR;一次运行合成一个 PR,不至于每章一个碎 PR。

---

## 一句话总览

| # | 决定 | 一句话理由 |
|---|------|-----------|
| 1 | claude-code-action + 订阅 token,不用 --bare | 走订阅不按量计费;--bare 会废掉 token 和 agent 自动加载 |
| 2 | matrix 并行(准备→matrix→汇总) | 官方 CI 标准,日志分开好审计,互不拖累 |
| 3 | agent 出 JSON,YAML 步骤贴 issue | 审计记录稳定,不靠 agent 自觉;官方标准做法 |
| 4 | ③ 做成 workflow_call 两条循环共用 | 共享引擎正是可复用工作流的用途 |
| 5 | subagent 靠 checkout 自动加载 | 项目文件,非 --bare 自动发现 |
| 6 | ledger 更新走 PR | 守住不直接 push 主分支 |

**留到构建时实测的三处不确定**:① claude-code-action 里订阅 token 是否全程顺畅;② `workflow_call` + claude-code-action 端到端;③ 大 diff 下 `gh compare` 的分页 / 体积上限。
