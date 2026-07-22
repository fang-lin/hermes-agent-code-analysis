# ADR-0001:文档自动同步在 GitHub Actions 里的技术选型

- **状态**:已采纳(2026-07-20)
- **相关**:设计见 [`.github/README.md`](../README.md);实现任务见 `/tasks`
- **背景约束**:非交互、全自动、走 Max 订阅额度、每步要产出可解析的"过/不过"加评语全文、全程可审计

这套自动化要在 GitHub Actions 里用 Claude Code 跑多 agent 的流水线,包括评估+规划、同步、定期复核几段。下面几个技术选择是彼此相扣的:鉴权怎么选,决定了能不能用 `--bare` 模式;能不能用 `--bare`,又牵连到命名 agent 会不会自动加载、以及并行该怎么做。所以把它们合成一份 ADR 一起讲清楚。每条决定都附了核实来源。

---

## 决定一:用 claude-code-action 加订阅 token,全程不用 `--bare`

CI 里跑 agent,用 `anthropics/claude-code-action`,保持它默认的非 `--bare` 模式;鉴权用 `CLAUDE_CODE_OAUTH_TOKEN`,也就是 `claude setup-token` 生成的那个一年期订阅 token。

这么选,首先是因为成本。项目主人的选择是走 Max 订阅、不按 token 逐次计费,而 `ANTHROPIC_API_KEY` 恰恰是按量付费,正是要避开的。订阅 token 在 CI 里能用,但有一个硬约束:`--bare` 模式会忽略它(这是官方设计,不是 bug)。不巧的是,`--bare` 还会跳过 `.claude/agents/` 的自动加载(见决定五)。两件事都指向同一个结论——不用 `--bare`。放弃 `--bare` 唯一的代价是它的快启动,而 CI 里真正的开销是 API 调用而非启动时间,这点损失可以忽略。

有几处风险要认下来。其一,`claude-code-action` 默认非 bare、也支持 `claude_code_oauth_token` 输入,但"这个 action 里到底有没有 `--bare` 的等价开关、订阅 token 在其中是否全程顺畅",官方文档没有逐字演示,构建时要实测确认。其二,订阅额度和平时在终端用 Claude Code 共享同一个 5 小时/每周窗口,CI 大量跑会挤占它,这一点已向项目主人挑明,由他定夺,不设自动护栏。其三,token 大约一年一换。

被否掉的方案是 `ANTHROPIC_API_KEY`。它是官方 CI 例子里的默认,也不受 `--bare` 限制,唯一的问题是按 token 计费,和订阅这个成本选择相冲突。将来若改用按量计费,这条 ADR 需要重开。

## 决定二:并行用 GitHub Actions matrix,不用 Dynamic Workflows

每个阶段的多 agent 扇出,用 GitHub Actions 的 matrix 来做,形状统一为三段。先是一个纯脚本的准备 job,算出这次要处理哪些章或哪些区域,把结果输出成一个 JSON 数组。接着是 matrix job,照这个数组动态并行(`matrix: fromJSON(needs.prep.outputs.list)`),一份处理一章或一个区域,各自跑命名 agent、产出结构化结果。最后是一个汇总 job,等前面全跑完,收齐结果,算出整体复杂度和置信度,贴进 issue,再决定下一步去哪。

选 matrix 有三个理由。它是官方 CI 的标准做法,GitHub Actions 的例子都是"一个 action 对应一个任务",并行交给 matrix,坑少、可预期。它的日志天然分开,每章一个 job,在 GitHub 页面上就是独立的一条,点进去是那一章的原始日志,正好支撑"每个复核 agent 评语进 issue"这条审计要求。它还互不拖累,某一章的 job 失败不影响其它章,重跑也只重跑那一章。

被否掉的是让一个 `claude -p` 去跑 Dynamic Workflow(`.claude/workflows/*.js`,用 `agent()`、`pipeline()` 在进程内扇出)。它确实能在 headless `claude -p` 里运行,但一来不是官方推荐的 CI 用法(`ultracode` 关键字在 `-p` 传入时会被忽略,官方 CI 例子里也没有 workflow 的先例),二来进程内扇出的日志和产出都糊在同一次运行里,跨章汇总和逐条审计都不如 matrix 清楚。

核实来源:https://code.claude.com/docs/en/workflows.md 、https://code.claude.com/docs/en/github-actions.md

## 决定三:agent 只出 JSON,由确定的 YAML 步骤贴 issue

agent 用 `--output-format json` 配 `--json-schema` 产出经校验的结构化结果,而"把结果发到 issue"这件事交给后续一个确定的 YAML 步骤去做(用 `jq` 解析,再 `gh issue comment`),不让 agent 自己去发。复核 agent 的 schema 同时给两样东西:一个机器可读的 `verdict`(过还是不过),一段 `comments`(评语全文,原样进 issue)。

这么分是为了让审计记录稳定。指望 agent 每次都把格式贴对、都记得贴,并不可靠;把"产出数据"和"发布这个副作用"分开之后,记录的格式就由脚本来保证。这也正是官方 headless 文档演示的标准做法(`claude -p ... --output-format json | jq | gh issue comment`)。`verdict` 让"三个复核 agent 必须全过"这道门由机器来判,`comments` 则保证评语一字不落地留档。

核实来源:https://code.claude.com/docs/en/headless.md

## 决定四:③ 同步做成可复用工作流,两条循环共用

把"改写、复核、合并"这一段做成一个 `workflow_call` 可复用工作流,同步循环的评估+规划和复核循环都来调它,work plan 以 JSON 字符串作为输入传进去。③ 是两条循环共享的引擎,而"被多个上游工作流复用"正是 `workflow_call` 的用途。

两点要注意。`workflow_call` 的 secrets 不会自动继承,调用方得显式往下传。另外,官方没有 `workflow_call` 配 `claude-code-action` 的端到端演示,机制上推得通,但构建时要实测。

核实来源:https://docs.github.com/en/actions/using-workflows/reusing-workflows

## 决定五:命名 subagent 靠 checkout 加自动加载

复用 `.claude/agents/*.md` 里已经定义好的命名复核 agent(factual-reviewer 等)。CI 里靠 `actions/checkout` 把仓库拉下来,再由 `claude-code-action`(非 bare)自动发现并加载,不用手动传定义。`.claude/agents/` 本来就是项目文件,checkout 之后 action 会自动找到,行为和本地交互模式一致。这也是"不用 `--bare`"的又一个理由:`--bare` 不会自动加载,得用 `--agents <json>` 手工塞,在 CI 里徒增维护负担。

核实来源:https://code.claude.com/docs/en/github-actions.md 、https://code.claude.com/docs/en/headless.md

## 决定六:ledger 更新走 PR,不直接 push

复核循环每跑完一轮,把这一轮所有章的 `audit-ledger.json` 更新——改过的和没改只盖章的——合成一个 PR 自动合并,一次运行对应一个 ledger PR。这么做是为了守住"绝不直接 push 主分支"这条底线,让纯元数据的变更也统一走可回退的 PR;一次运行合成一个 PR,也不至于每章冒出一个碎 PR。

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

有三处不确定留到构建时实测:一是 claude-code-action 里订阅 token 是否全程顺畅,二是 `workflow_call` 配 claude-code-action 的端到端,三是大 diff 下 `gh compare` 的分页和体积上限。

---

## 实现阶段的细化(2026-07,四个 plan 建完后回填)

真正把四条工作流建出来、逐个交叉复核之后,对上面几条决定做了如下细化,并新增一条"上线前必须做"的硬要求。

**决定一细化 —— agent 一律用 headless `claude -p`,不用 claude-code-action。** "改写↔复核"要在 bash 循环里反复调、matrix 里逐 job 调,`claude -p` 更好套;两者都是非 bare + 订阅 token,决定一的核心理由不变,还顺带绕开了"action 里订阅 token 顺不顺"那处不确定。

**决定四细化 —— ③ 同时开 `workflow_call` 和 `workflow_dispatch`。** ② 和复核循环用 `gh workflow run hermes-sync.yml` 派发它,走的是 `workflow_dispatch`;两个触发口共用同一个 job(job 读 `inputs.*`,两种触发都适用)。`secrets:` 块只对 `workflow_call` 生效,`workflow_dispatch` 触发时 job 直接从仓库 secret 读 `CLAUDE_CODE_OAUTH_TOKEN`。work plan 常规走输入;超长时退回"贴 issue、③ 从 issue 读"(尚未实现,留作后续)。

**新增决定七(上线前硬要求)—— 每个跑 agent 的 job 必须先 checkout 被 pin 的 hermes-agent 源码。** 这是复核/评估能不能真正验证的命门。`hermes-agent` 在本仓是 git-ignored、CI 里根本不存在;而所有 agent(③ 的改写/复核、② 的区域评估、复核循环的通盘复核)以及 `check-anchors.sh`/`orient.sh` 都要 grep"真源码"。约定:源码根以含 `run_agent.py` 为准,锚点都是相对该根的裸路径(如 `gateway/run.py`)。所以每个 agent job 要加一步,按合适的 tag 把 `NousResearch/hermes-agent` 浅克隆到一个 `run_agent.py` 在根的目录,再把该路径传给脚本和提示。**用哪个 tag 分流程**:③ 的 sync 循环和 ② 用新版本 tag(要把文档对到新版本);复核循环用当前 pin(核对现有文档对不对)。这一步只有连着真 agent + secret + 能访问上游仓库时才跑得起来,所以放到各 plan 的 smoke 阶段落地并验证,但**必须在第一次真跑前完成**,不能藏在"以后再说"里。

**构建期间交叉复核抓出、且已在代码里落实的加固(供后续维护参考,别再退回):**
- **写 `$GITHUB_OUTPUT` 的 JSON 一律 `jq -sc` 单行** —— 多行值会被 `key=value` 形式截断,让 matrix 拿到坏输入、悄悄跑空。
- **jq 访问中文字段用 `.["类型"]` 括号写法** —— 点号 `.类型` 在 jq 1.7 是编译错误,`set -uo pipefail` 下静默失败、默认 0/空。
- **`gh` / 外部调用失败必须 fail-safe 或大声中止** —— 不能把"调用失败"和"结果为空"混为一谈(assess-prep gh 失败、chapter_source_changed gh 失败、audit-prep 缺配置,都改成了要么大声退出、要么按"需处理"兜底)。
- **kill-switch(`.enabled` / `.audit.enabled`)要在每个花 token 的阶段顶部就查** —— 不能只靠 ③ 兜底,否则关了开关 ② 照样烧 token。
- **matrix 加 `fail-fast: false`,finalize 用容错的 `if:`** —— 一个 flaky 分支不能取消其它分支、更不能跳过 finalize 让整轮白跑;finalize 只盖"确实有复核结果"的部分,其余留待下轮。
- **绝不把 `${{ }}` 直插进 `run:` 脚本文本** —— 上游 tag 名可含 shell 元字符,直插 = 脚本注入;一律走 `env:` 变量再 `"$VAR"` 读。
- **测试全用一次性 mktemp 仓库,绝不碰真仓、绝不真 push** —— 构建早期有个测试真往 origin 推了个垃圾提交,之后所有涉及 git 的测试都改成在临时仓里跑,并在跑后断言真仓分支/状态没变。
