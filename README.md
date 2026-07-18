[中文](README.zh.md) | English

# Hermes Agent Source Code Analysis

> 18,610 commits. ~644,000 lines of Python (before ~720,000 lines of tests). A self-improving agent framework, largely built by AI.
>
> We read the whole thing and took it apart — 15 narrative documents, in Chinese and English.

This is a complete source code analysis of [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) **v0.18.2** (tag [`v2026.7.7.2`](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.7.7.2), commit `9de9c25f6`, 2026-07-07). Not an API reference, not a usage tutorial, but an **architecture teardown** — like disassembling a precision machine to see why each gear is where it is, what it meshes with, and what breaks if you remove it.

Each document is designed to do two things at once: help you **understand the architecture deeply** and **guide you to actually use it**. Every chapter opens with a usage guide (what it is, how to use it, how to configure it, common scenarios, troubleshooting) and then goes into architecture and implementation, answering the same question for each subsystem: **what problem does it face, what choices were made, why not the alternatives, and what happens when things go wrong.**

## Subject of Analysis

Hermes Agent is an MIT-licensed, self-improving AI agent framework by Nous Research. It is several things at once: a usable AI assistant, a unified gateway serving **20 plugin platforms + 9 built-in platforms** of messaging, an execution engine with **69 registered tools**, a training-data factory, and — since v0.18 — a cross-platform desktop client (~143,000 lines of TypeScript).

The interesting part: a large proportion of it was most likely written by AI itself ([evidence in Chapter 00](docs/en/00-project-overview.md)).

## Document Index

**Part I — Getting to Know the System**

| # | Document | One-liner |
|---|----------|-----------|
| 00 | [Project Overview](docs/en/00-project-overview.md) | An AI agent that tries to evolve itself — what it is, why it's built this way, full file index |
| 01 | [Infrastructure Layer](docs/en/01-infrastructure.md) | The control plane held up by 203 files: config, auth, subcommands |

**Part II — The Core Runtime**

| # | Document | One-liner |
|---|----------|-----------|
| 02 | [Agent Core](docs/en/02-agent-core.md) | The inner workings of the conversation orchestrator (incl. LSP, transports) |
| 03 | [Tool System](docs/en/03-tool-system.md) | How 69 tools get registered, dispatched, approved, and sandboxed |
| 04 | [Skill System](docs/en/04-skill-system.md) | How the Agent learns to do things from experience |
| 05 | [Gateway Layer](docs/en/05-gateway.md) | One process, all platforms |
| 06 | [Protocol Adaptation](docs/en/06-protocols.md) | Letting editors and other systems call the Agent (ACP / MCP) |

**Part III — The Plugin & Extension Ecosystem**

| # | Document | One-liner |
|---|----------|-----------|
| 07 | [Plugin Framework](docs/en/07-plugin-framework.md) | Hooks + middleware that let Python tap into any stage |
| 08 | [Built-in Plugins](docs/en/08-builtin-plugins.md) | Capability extension in 18 categories (memory / providers / platforms / observability) |

**Part IV — Standalone Subsystems**

| # | Document | One-liner |
|---|----------|-----------|
| 09 | [Kanban System](docs/en/09-kanban.md) | Multiple Agents collaborating on complex tasks |
| 10 | [Interfaces & Run Modes](docs/en/10-interfaces-and-run-modes.md) | The same Agent, three faces and six ways to run |
| 11 | [Cron Scheduling](docs/en/11-cron-scheduling.md) | Letting the Agent work even when you're not talking |

**Part V — Operations & Engineering**

| # | Document | One-liner |
|---|----------|-----------|
| 12 | [Batch & Trajectories](docs/en/12-batch-and-trajectories.md) | The Agent as a training-data factory |
| 13 | [Engineering Practices](docs/en/13-engineering-practices.md) | The "unsexy" code that keeps a 600,000-line project steady |

**Part VI — The Desktop Client** *(new in v0.18)*

| # | Document | One-liner |
|---|----------|-----------|
| 14 | [Desktop App](docs/en/14-desktop-app.md) | Packing the Agent into a double-click icon (Electron + Tauri) |

## How This Analysis Was Made

644,000 lines of code can't be read accurately by one person — or one AI — in a single pass. Each chapter went through a multi-agent pipeline: the main thread (Opus) reads the source and drafts, and specialized review agents (Sonnet) find the mistakes.

```
Main thread (Opus)        → read source, draft against the v1 (v0.11.0) depth baseline
  ↓
Depth Review ‖ Literary Review   → parallel: depth gaps / narrative quality
  ↓
Factual Review            → verify every claim against actual code
  ↓
Main thread (Opus)        → double-verify every ⚠️/❌ finding → fix → finalize
```

A hard rule ran through the whole project: **every review finding was independently re-verified against the source before being written into the docs** — two independent code reads had to agree. Each concept was analyzed through a 9-question template (what is it / where did it come from / where does it sit / who depends on it / how does it work / what does it solve / why not alternatives / what happens on failure / what's configurable), woven into a narrative rather than dumped as tables.

The Chinese was written first, then translated to English through a dedicated translation-review pipeline with a shared [terminology glossary](docs/TRANSLATION_GLOSSARY.md) — code identifiers, line numbers, and Mermaid IDs preserved verbatim; only prose and comments translated. The translation pass even surfaced and fixed two errors in the Chinese source.

The methodology grew organically from user feedback during the work; the full evolution is recorded in the work log (Chinese only, below).

## A Few Things Worth Knowing

1. **A large share of the code was most likely written by AI** — and the project itself is an AI agent. Dogfooding taken to the extreme ([Chapter 00](docs/en/00-project-overview.md)).

2. **The god-file decomposition actually worked.** `run_agent.py` shrank from 13,293 lines (v0.11.0) to **6,013** as the `agent/` subdirectory was progressively extracted. But the giants moved elsewhere — `gateway/run.py` (20,719 lines) and `cli.py` (16,184 lines) are the new heavyweights ([Chapters 02](docs/en/02-agent-core.md), [05](docs/en/05-gateway.md), [10](docs/en/10-interfaces-and-run-modes.md)).

3. **The security model is honest about its own boundaries.** `SECURITY.md` distinguishes *real boundaries* (sandbox / process isolation) from *heuristics* (command approval, redaction, Skills Guard) — and states plainly that prompt injection and heuristic bypasses are **out of scope**, with no bug-bounty program. Drawing the line honestly is itself a mark of engineering maturity ([Chapter 13](docs/en/13-engineering-practices.md)).

4. **The guards around Prompt Caching are more clever than the caching itself.** Dual injection (static memory in the system prompt for cache hits, dynamic retrieval in user messages for freshness) and three-tier progressive disclosure for skills are exemplary cache-friendly designs ([Chapter 02](docs/en/02-agent-core.md)).

5. **It can genuinely produce data to train the next generation of itself** — `batch_runner.py` mass-generates trajectories → `trajectory_compressor.py` compresses them to the training window. Note: the RL *training* environments were moved out of the main repo in v0.14.0, so Chapter 12 focuses on the data-generation side that remains ([Chapter 12](docs/en/12-batch-and-trajectories.md)).

## What Changed Since v0.11.0

This analysis supersedes an earlier one of v0.11.0 (12 documents). The main shifts:

- **RL training infrastructure moved out** of the main repo (v0.14.0) — Chapter 12 refocused from "Batch & RL" to trajectory generation only.
- **Platform migration** — core messaging platforms moved from gateway built-ins to plugins (now 20 plugin + 9 built-in).
- **A desktop client appeared** (v0.17) — a full Electron + React app with a Tauri bootstrap installer, added as Chapter 14.
- **The doc set grew** from 12 to 15 chapters and is now **fully bilingual** (Chinese + English).

## Disclaimer

Independent analysis, not official Nous Research documentation. All code references have been independently verified. Based on v0.18.2 source; later versions may differ.

## Process Documentation *(Chinese only)*

- [审核报告汇总 / Review Report](docs/zh/98-审核报告汇总.md) — all review findings and corrections
- [工作日志 / Work Log](docs/zh/99-工作日志.md) — how the methodology grew from zero

---

Made by **Lin Fang** — exploring how AI tools can be used to understand AI systems.

Reach out: [X](https://x.com/hausewoods) | [Email](mailto:fanglin.me@gmail.com) | [GitHub](https://github.com/fang-lin)

If this analysis is useful to you, a ⭐ helps others find it.
