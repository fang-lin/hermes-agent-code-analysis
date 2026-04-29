[中文](README.zh.md) | English

# Hermes Agent Source Code Analysis

> 6,384 commits. ~587,000 lines of code. 9 months. An agent framework built by one person with AI tools.
>
> We used another AI, spent two days and ~200 million tokens, and tore the whole thing apart.

This is a complete source code analysis of [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) v0.11.0. Not an API reference, not a usage tutorial, but an **architecture teardown** — like disassembling a precision machine to see why each gear is where it is, what it meshes with, and what breaks if you remove it.

12 narrative-style technical documents. Each one answers a question: **what problem does this subsystem face, what choices were made, why not the alternatives, and what happens when things go wrong.**

## Subject of Analysis

Hermes Agent is an open-source self-improving AI agent framework by Nous Research. It's four things at once: a usable AI assistant, a unified gateway serving 19 messaging platforms, an execution engine with 66 tools, and an RL training data factory.

The interesting part — it was most likely built by AI itself ([evidence in doc 00](docs/en/00-project-overview.md)).

## Document Index

| # | Document | One-liner |
|---|----------|-----------|
| 00 | [Project Overview](docs/en/00-project-overview.md) | What Hermes is, why it's designed this way, full file index |
| 01 | [Architecture](docs/en/01-architecture.md) | Follow a message from input to output, end to end |
| 02 | [Agent Core](docs/en/02-agent-core.md) | What's inside the 13,000-line God Object |
| 03 | [Tool System](docs/en/03-tool-system.md) | How 66 tools get registered, dispatched, approved, and throttled |
| 04 | [Skills System](docs/en/04-skills-system.md) | How the Agent learns to do things from experience |
| 05 | [Plugin System](docs/en/05-plugin-system.md) | 16 lifecycle hooks that let Python code tap into any stage |
| 06 | [Gateway](docs/en/06-gateway.md) | One process serving Telegram, Discord, Slack, and more |
| 07 | [TUI & Web](docs/en/07-tui-and-web.md) | Three faces of the same Agent |
| 08 | [Cron & Protocols](docs/en/08-cron-and-protocols.md) | Letting the Agent wake up on its own; letting editors call it |
| 09 | [Deployment](docs/en/09-deployment.md) | Six ways to run, from laptop to GPU cloud |
| 10 | [Batch & RL](docs/en/10-batch-and-rl.md) | The Agent as a training data factory |
| 11 | [Engineering](docs/en/11-engineering-practices.md) | How 587,000 lines get tested, logged, and secured |

## How This Analysis Was Made

587,000 lines of code can't be read accurately by one person — or one AI — in a single pass. We used three AI Agents working in parallel: one reads code and drafts, two find mistakes:

```
Analysis Agent (Sonnet)     → Read source code, produce draft
  ↓
[Factual Review Agent ‖ Literary Review Agent]  → Parallel review, independent
  ↓
Main thread (Opus)          → Second verification → Fix → Incremental recheck → Finalize
```

The entire process consumed approximately **200 million tokens** over **two days**. Each concept was analyzed through a 9-question template (what is it / where did it come from / where does it sit / who depends on it / how does it work / what does it solve / why not alternatives / what happens on failure / what's configurable), woven into a Martin Fowler–style narrative.

The methodology wasn't there from day one — it grew organically from user feedback during the work. The full evolution is recorded in the [work log](docs/en/99-work-log.md).

## Five Most Interesting Findings

1. **This project was most likely written by AI.** The primary contributor averaged 53 commits per day, was more active at 3 AM than at noon, and left 131 Claude Co-Author tags in git history. We estimate 60–80% of the code lines were AI-generated — and the project itself is an AI agent. Dogfooding taken to the extreme.

2. **Two God Objects carry the entire system.** `run_agent.py` (13,293 lines) and `cli.py` (11,395 lines) — nearly 25,000 lines combined. The `agent/` subdirectory was gradually extracted from `run_agent.py`, but the glue code itself is still 13,000 lines.

3. **Security isn't an afterthought — it's 8 layers of defense in depth.** From hardcoded kill patterns (`rm -rf /` unconditionally rejected) to LLM-powered Smart approval mode, from SSRF protection to Tirith content scanning — even with `--yolo` enabled, the most dangerous commands are still blocked.

4. **The guards around Prompt Caching are more clever than the caching itself.** Marking 4 breakpoints takes 30 lines of code, but ensuring cache actually hits — building the system prompt only once per session, normalizing JSON with `sort_keys`, routing dynamic info through user messages instead of the system prompt — these "guard strategies" are scattered across thousands of lines.

5. **It can genuinely train the next generation of itself.** `batch_runner.py` generates trajectories in bulk → `trajectory_compressor.py` compresses them to training window size → `environments/` provides Atropos RL environments → 11 tool call format parsers ensure cross-model compatibility. This isn't a proof of concept — it's a working training pipeline.

## Where This Project Is Heading

> The following predictions come from a "consultation" among three AI Agents with different perspectives — an architect, a product strategist, and an AI researcher — each independently reading all 12 analysis documents. We synthesized their consensus and disagreements.

**The flywheel is real, but it spins slower than you'd think.** The strongest consensus across all three perspectives: the `batch_runner` → `trajectory_compressor` → `environments/` pipeline isn't a toy — it's a production-grade training data factory. But the flywheel has three sticking points: sparse reward signals (most real tasks lack automatic scorers), information loss from trajectory compression (GRPO needs raw logprobs that compressed summaries can't provide), and insufficient long-tail coverage (benchmarks focus on terminal and SWE tasks). The part that will spin first is **tool call format alignment** — `tool_call_parsers/` reimplements 11 formats, which tells you this is still the practical bottleneck.

**Hermes won't compete head-on with Claude Code — it'll become Claude Code's backend.** `mcp_serve.py` exposes the messaging gateway as MCP tools; `acp_adapter/` implements editor protocol integration. Hermes is simultaneously a standalone tool and infrastructure consumed by other AI tools. The product strategist's take: these two are more like AWS and GitHub Actions than Vim and Emacs. Hermes differentiates on "things Claude Code can't do" — 19 messaging platforms, 24/7 cron scheduling, RL data generation.

**The 13,000-line God Object is a ticking time bomb.** The architect's most confident prediction. `run_agent.py`'s 50+ parameter `__init__` is a textbook case of configuration explosion; `delegate_tool`'s lazy import is a band-aid over circular dependencies. The Transport layer has already been successfully extracted; next up is likely an AgentFactory plus a standalone core loop file. `cli.py` faces the same pressure — the appearance of Ink TUI already signals the direction: moving interaction logic from Python to Node.js.

**Prompt Caching is graduating from cost trick to architectural constraint.** The researcher's unique insight: "what goes in the system prompt vs. user message" is no longer a style question — it's an economic decision. Agents that don't optimize caching can't compete economically. Hermes's "dual injection" strategy (static memory in system prompt for cache hits, dynamic retrieval in user messages for freshness) and the three-tier Progressive Disclosure for skills are exemplary cache-friendly architectures — other frameworks will borrow these designs.

**Skill self-improvement faces a "forgetting vs. generalization" dilemma.** Self-improvement is a real mechanism (`skill_manage(action='patch')` + mandatory system prompt directives), but limited in scope — it modifies local SKILL.md files, not model weights. The deeper problem: if one bad task writes incorrect steps, that error propagates to all subsequent uses of that skill. The researcher predicts the skills system will evolve into a **versioned knowledge base** — with version history, quality scores, and automatic rollback — rather than the current single-file overwrite.

**Open source strategy holds short-term, but faces bifurcation mid-term.** MIT licensing is there to acquire user scale (more users → more training data → better models). But the Gateway module's 64,729 lines of maintenance burden is growing, and 587,000 lines of code expand at 53 commits per day. The product strategist's prediction: the most likely path is keeping the core engine MIT while gradually moving Gateway platform adapters and Skills Hub's official index toward commercial licensing — similar to HashiCorp's path with Terraform.

If this analysis is useful to you, a ⭐ helps others find it.

## Disclaimer

Independent analysis, not official Nous Research documentation. All code references independently verified. Based on v0.11.0 source; later versions may differ.

## Process Documentation

- [Review Report](docs/en/98-review-report.md) — All review findings and corrections
- [Work Log](docs/en/99-work-log.md) — How the methodology grew from zero

---

Made by **Lin Fang** — exploring how AI tools can be used to understand AI systems. Currently working on similar analyses of OpenClaw and the broader autonomous agent ecosystem.

Reach out: [X](https://x.com/hausewoods) | [Email](mailto:fanglin.me@gmail.com) | [GitHub](https://github.com/fang-lin)
