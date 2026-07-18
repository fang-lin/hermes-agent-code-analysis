# hermes-agent-expert — an Agent Skill / 一个 Agent 技能

Install/usage docs for the skill. The agent-facing content is in `SKILL.md` + `reference/`; this file is for the human setting it up.
本文件是给**装它的人**看的安装/用法说明;给 **agent** 读的内容在 `SKILL.md` 和 `reference/` 里。

---

## What it is / 是什么

An **Agent Skill** that gives coding agents (Claude Code — and any agent that can read markdown) expert, source-grounded knowledge of **NousResearch/hermes-agent** internals, so they can **set up, configure, debug, customize, and do secondary development** on hermes efficiently and without the known pitfalls.

一个 **Agent 技能**:让 Claude Code 这类编码 agent 在**搭建 / 配置 / 调试 / 定制 / 二次开发** hermes-agent 时,拥有有源码依据的专家判断,少走弯路。

- Distilled from a full **15-chapter source teardown**, pinned to **v0.18.2** (`9de9c25f6`).
- Defining design: a **Tier 0→3 progressive ladder** that ends at reading the *real* hermes source — the skill's job is to get the agent to the right file/symbol fast, not to replace the source.

## What's inside / 结构

```
SKILL.md                     # always-loaded entry: mental model · task routing · invariants · the Tier 0→3 workflow
reference/
  architecture.md            # request path · agent loop · caching invariant · subsystem→source map
  configuration.md           # config.yaml keys · env vars · Profiles · provider/auth
  debugging.md               # log-file map · diagnostic commands · silent-failure catalog · symptom→cause→fix
  extending.md               # step-by-step recipes: add tool/skill/platform/hook/provider/backend
  worked-examples.md         # two validated end-to-end traces (debug + customize)
scripts/
  orient.sh                  # version + key-file line-drift vs the pinned anchors
  check-anchors.sh           # verify all ~200 anchors resolve against a checkout (6 types)
  anchors.txt / numbers.txt  # the anchor + numeric-claim manifests
```

## Install / 安装

### Claude Code
The skill is a folder — put it where Claude Code discovers skills:

- **Per-project** (recommended): copy or symlink into your hermes repo's `.claude/skills/`.
  ```bash
  # copy:
  cp -r hermes-agent-expert /path/to/hermes-agent/.claude/skills/
  # or symlink (stays in sync if you keep this analysis repo around):
  ln -s "$PWD/hermes-agent-expert" /path/to/hermes-agent/.claude/skills/
  ```
- **Global** (all projects): put it in `~/.claude/skills/hermes-agent-expert/`.

It **auto-loads** when your request matches its description (setting up / configuring / debugging / customizing hermes). Confirm it registered: it shows up in Claude Code's skill list.

不用手动"启用"——请求内容匹配到 description(搭建/配置/调试/定制 hermes)时自动加载。装好后它会出现在 Claude Code 的技能列表里。

### Fetch from the public repo / 从公开仓拿
```bash
git clone --depth 1 https://github.com/fang-lin/hermes-agent-code-analysis
cp -r hermes-agent-code-analysis/.claude/skills/hermes-agent-expert /path/to/hermes-agent/.claude/skills/
```

### Copilot / other agents / 其他 agent
No auto-trigger, but everything is plain markdown — point the agent at `reference/*.md`, or paste the relevant sheet into context when working on hermes.
不自动触发,但内容是纯 markdown——让 agent 直接读 `reference/*.md`,或把对应 sheet 贴进上下文即可。

## Use / 用法

Just work on a hermes task and ask your agent; it climbs **only as far as the problem needs**:
直接让 agent 干 hermes 的活,它按难度**逐层深入**:

- **Tier 0** (`SKILL.md`) — orient + avoid the big mistakes (offline). 定向 + 不犯错。
- **Tier 1** (`reference/`) — operational depth for config / debug / extend. 操作深度。
- **Tier 2** (fetch chapters) — the *why* (design rationale, failure modes). 取全文看为什么。
- **Tier 3** (real source) — the skill points to the exact file/symbol; the agent reads it and solves. 读真源码解决。

## Maintenance — running it against a different hermes version / 维护(对不同版本)

The skill is pinned to v0.18.2. On any checkout, calibrate first:
钉在 v0.18.2。换一台/换版本时,先校准:

```bash
bash scripts/orient.sh        /path/to/hermes-agent   # installed version + key-file line drift
bash scripts/check-anchors.sh /path/to/hermes-agent   # do all ~200 anchors resolve? ERROR 0 = trustworthy
```

- **Small drift / ERROR 0** → line numbers are approximate; grep the symbol to confirm (the skill says this throughout). Trust the drift table over the version string.
- **Large drift / ERRORs** → **re-pin**: update the affected line numbers + `scripts/anchors.txt`, re-run `check-anchors.sh` until `ERROR 0`.

小漂移 → 行号当近似,grep 确认;大漂移/报错 → 重新 pin(改行号 + `anchors.txt`,跑到 `ERROR 0`)。

## Design boundary — what's guaranteed vs. reviewed / 边界(诚实说明)

- **Anchors** = grep-checkable pointers (path / line / symbol / config-key / env-var / command). ~200 of them, **mechanically verified** (`check-anchors.sh`, `ERROR 0` on v0.18.2).
- **Numbers** (69 tools, 23 hooks…) — documented reproducible derivations in `scripts/numbers.txt`, **review-verified** (a naive auto-count is less reliable than the analysis, so deliberately not auto-counted).
- **Judgments** (the "why", design rationale) — **not** anchors; verified by review, not by any script.

"Anchor 机制化保证;数字文档化+review;判断只能 review"——不假装脚本能保证正确性,只保证可证伪的部分。

## Provenance / 出处

Distilled from the 15-chapter bilingual source analysis at
[github.com/fang-lin/hermes-agent-code-analysis](https://github.com/fang-lin/hermes-agent-code-analysis),
hermes-agent **v0.18.2** (tag `v2026.7.7.2`, commit `9de9c25f6`). Independent analysis, not official Nous Research documentation.
