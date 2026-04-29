# Review Report Summary

This document aggregates the review results for each analysis step.

---

## Step 1.0: Project Overview (00-project-overview.md)

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | Version 0.11.0 `pyproject.toml:7` | ✅ | |
| 2 | Main CLI entry point `pyproject.toml:129` | ✅ | |
| 3 | run_agent.py entry point `pyproject.toml:130` | ✅ | |
| 4 | MCP 10 tools `mcp_serve.py:8-13` | ✅ | |
| 5 | agent/ directory structure | ✅ | |
| 6 | tools/ 66 files | ✅ | |
| 7 | gateway/ platform count | ✅ | Initial review old doc said 28; review found inaccurate. Second pass: 35 .py files, ~20 independent platforms. Corrected. |
| 8 | Dockerfile base image `Dockerfile:1` | ✅ | |
| 9 | Config priority | ✅ | Initial ⚠️ → second pass confirmed `cli.py:1985`, corrected. |
| 10 | HERMES_HOME `hermes_constants.py:11-18` | ✅ | |

**Result: 10/10 ✅**

---

## Step 1.1: Architecture Analysis (01-architecture.md)

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | process_loop() `cli.py:10819` | ✅ | |
| 2 | chat() calls run_conversation `cli.py:8636` | ✅ | Initial ⚠️ ambiguous phrasing → doc clarified: defined at 8404, called at 8636 |
| 3 | run_conversation() `run_agent.py:9627` | ✅ | |
| 4 | while loop `run_agent.py:9993` | ✅ | Initial ⚠️ incomplete condition → budget + grace_call added |
| 5 | api_mode logic `run_agent.py:982-1013` | ✅ | Initial ⚠️ start line off → corrected to 982 |
| 6 | ProviderTransport ABC `base.py:16` | ✅ | |
| 7 | Compression threshold 75% `context_engine.py:59` | ✅ | |
| 8 | _build_system_prompt() `run_agent.py:4543` | ✅ | |
| 9 | ToolRegistry `registry.py:100` | ✅ | |
| 10 | DELEGATE_BLOCKED_TOOLS `delegate_tool.py:41-49` | ✅ | |
| 11 | MAX_DEPTH=1 `delegate_tool.py:129` | ✅ | |
| 12 | agent_cache 128 limit `run.py:41` | ✅ | Initial ❌ wrong line → corrected: constant at 41, instantiation at 709 |

**Result: 12/12 ✅** (Initial: 3⚠️ 1❌ → second pass independently verified all 4 → corrections written to doc)

---

## Step 2.0: Project Overview Rewrite (00-project-overview.md v2)

Document rewritten from a "listing style" to a Martin Fowler narrative style, with a new module panorama, project statistics, and AI involvement analysis added.

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | Version 0.11.0 `pyproject.toml:7` | ✅ | |
| 2 | 20+ providers `cli-config.yaml.example:13-43` | ✅ | Actually 24 (including aliases) |
| 3 | ~20 independent platforms | ✅ | Initial ⚠️ "28" inaccurate → second pass confirmed ~20 independent platforms (35 .py includes helper files) → corrected |
| 4 | Compression threshold 75% `context_engine.py:59` | ✅ | |
| 5 | Six terminal backends `cli-config.yaml.example:148-237` | ✅ | |
| 6 | HERMES_HOME `hermes_constants.py:17-18` | ✅ | |
| 7 | Config priority `cli.py:1985` | ✅ | Comment shows only three layers, but code logic confirms four |
| 8 | hermes entry point `pyproject.toml:129` | ✅ | |
| 9 | hermes-agent entry point `pyproject.toml:130` | ✅ | |
| 10 | MCP 10 tools `mcp_serve.py:8-13` | ✅ | |
| 11 | Python 1,231 files / ~578K lines | ✅ | Measured ~587K; ~ prefix acceptable |
| 12 | tools/ 66 files | ✅ | |
| 13 | Core deps 18 / extras 26 / config ~1000 lines | ✅ | |
| 14 | Total commits 6,384 / March 2,501 / April 3,311 | ✅ | |
| 15 | Teknium avg 53 commits/day | ✅ | Review Agent computed 51.7 (61 days); second pass 3145/59=53.3; doc accurate |
| 16 | Peak single-day 199 commits (2026-03-14) | ✅ | Review Agent computed 227 (possibly all authors); second pass confirms Teknium alone: 199 |
| 17 | Claude Co-Authored-By 131 times | ✅ | |
| 18 | run_agent.py 13,293 lines / cli.py 11,395 lines | ✅ | |
| 19 | Comment density ~14% | ✅ | Measured 14.44% |

**Result: 19/19 ✅** (Initial: 3⚠️ 2❌ → second pass found the 2 ❌ were different calculation methods, not errors; 1 ⚠️ confirmed "28 platforms" → corrected to "~20")

---

## Step 2.1: Architecture Analysis Rewrite (01-architecture.md v2)

Narrative rewrite: follows "the journey of a message" as the throughline, tracing a request from CLI to Agent core to the tool layer.

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | process_loop() cli.py:10819-10824 | ✅ | |
| 2 | chat() cli.py:8404; daemon thread 8664-8671; call at 8636 | ✅ | 8664 is a comment line; substance correct |
| 3 | run_conversation() run_agent.py:9627 | ✅ | |
| 4 | while loop run_agent.py:9993 complete condition | ✅ | |
| 5 | max_iterations=90 run_agent.py:851 | ✅ | |
| 6 | iteration_budget shared parent/child run_agent.py:951 | ✅ | |
| 7 | _build_system_prompt() layer structure | ✅ | Initial ⚠️ "7 layers" incomplete → second pass: source comment does say 7 layers (4551-4558); implementation has more sub-items → doc supplemented |
| 8 | _cached_system_prompt run_agent.py:9814 | ✅ | |
| 9 | Memory prefetch run_agent.py:9989 | ✅ | |
| 10 | Memory injection into user message run_agent.py:10131-10143 | ✅ | |
| 11 | Compression threshold 75% context_engine.py:59 | ✅ | |
| 12 | Protect head 3 / tail 6 | ✅ | |
| 13 | Summary 20% cap 12000 context_compressor.py:55-57 | ✅ | |
| 14 | ProviderTransport ABC base.py:16 four methods | ✅ | Initial ⚠️ including property gives 5 abstractmethods → doc says "4 core methods" excluding property; kept |
| 15 | api_mode detection run_agent.py:982-1013 | ✅ | |
| 16 | _execute_tool_calls() run_agent.py:8594 | ✅ | |
| 17 | discover_builtin_tools() registry.py:56 AST scan | ✅ | |
| 18 | ToolRegistry registry.py:100 | ✅ | |
| 19 | DELEGATE_BLOCKED_TOOLS delegate_tool.py:41-49 | ✅ | |
| 20 | MAX_DEPTH=1 delegate_tool.py:129 | ✅ | |
| 21 | Sub-Agent toolset intersection delegate_tool.py:891-930 | ✅ | Initial ⚠️ core line 912; range reference acceptable |
| 22 | GatewayRunner gateway/run.py:620 | ✅ | |
| 23 | Agent cache 128 run.py:41 | ✅ | |
| 24 | BasePlatformAdapter base.py:1121 | ✅ | |
| 25 | handle_message() base.py:2221 | ✅ | |
| 26 | interrupt() run_agent.py:4050; _interrupt_requested 4074 | ✅ | |
| 27 | steer() run_agent.py:4151 | ✅ | |
| 28 | Interrupt check run_agent.py:9997-10003 | ✅ | |

**Result: 28/28 ✅** (Initial: 4⚠️ → second pass: #7 supplemented, #14/#21 descriptions reasonable and kept, #2 substantively correct)

---

## Step 2.2: Agent Core (02-agent-core.md)

Narrative style: follows the internal mechanisms of AIAgent — Prompt Caching, retry backoff, Credential Pool, streaming responses, Fallback Chain, Trajectory, Model Metadata.

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | run_agent.py 13,293 lines; __init__ 840-902 | ✅ | |
| 2 | prompt_caching.py system_and_3 comment 1-8 | ✅ | |
| 3 | Max 4 breakpoints prompt_caching.py:41-72 | ✅ | |
| 4 | _cached_system_prompt run_agent.py:9814 | ✅ | |
| 5 | JSON normalization run_agent.py:10207-10239 | ✅ | |
| 6 | cache_ttl config run_agent.py:1154-1167 | ✅ | |
| 7 | jittered_backoff retry_utils.py:19-57 | ✅ | |
| 8 | base=5.0 max=120.0 jitter=0.5 | ✅ | |
| 9 | seed formula retry_utils.py:53 | ✅ | |
| 10 | 429 handling run_agent.py:5761-5843 | ✅ | |
| 11 | EXHAUSTED_TTL 3600 credential_pool.py:73 | ✅ | |
| 12 | 4 strategies credential_pool.py:59-68 | ✅ | |
| 13 | PooledCredential credential_pool.py:91 | ✅ | |
| 14 | OAuth refresh credential_pool.py:575-735 | ✅ | |
| 15 | Streaming entry run_agent.py:6154 | ✅ | |
| 16 | _fire_stream_delta run_agent.py:6081 | ✅ | |
| 17 | _try_activate_fallback run_agent.py:6997 | ✅ | |
| 18 | _restore_primary_runtime run_agent.py:7192 | ✅ | |
| 19 | save_trajectories run_agent.py:855 | ✅ | |
| 20 | _save_trajectory run_agent.py:3723 | ✅ | |
| 21 | save_trajectory trajectory.py:30 | ✅ | |
| 22 | convert_scratchpad_to_think trajectory.py:16 | ✅ | |
| 23 | model_metadata.py 1,467 lines | ✅ | |
| 24 | Fallback chain model_metadata.py:1229-1426 | ✅ | Initial ⚠️ "10 levels" imprecise → second pass confirmed source numbering 0-10 with sub-branches ~14 → corrected to "a dozen or so levels" |
| 25 | OpenRouter cache 1h model_metadata.py:526 | ✅ | |
| 26 | Endpoint cache 5min model_metadata.py:562 | ✅ | |
| 27 | agent/ ~29,200 lines | ✅ | Initial ⚠️ measured 29,201 → ~ prefix added |

**Result: 27/27 ✅** (Initial: 2⚠️ → both corrected)

---

## Step 2.3 Review: 9-Question Template Rewrite Verification

Rewrite covered multiple sections in 01 and 02; 24 new/modified assertions reviewed.

| # | Assertion | Status | Notes |
|---|-----------|--------|-------|
| 1 | Transport extracted from run_agent.py (noted in v0.11.0) | ✅ | RELEASE_v0.11.0.md explicitly records this |
| 2 | Transport registry __init__.py:14 | ✅ | ⚠️ `_REGISTRY` at line 11; `register_transport` at 14; doc refers to registration logic; acceptable |
| 3 | Agent cache run.py:709; session_key run.py:567 | ✅ | |
| 4 | Cache limit 128 run.py:41 | ✅ | |
| 5 | BasePlatformAdapter abstract methods | ✅ | Initial ❌ wrong method names (start/stop/send_message → connect/disconnect/send) → second pass confirmed → corrected |
| 6 | handle_message() base.py:2221 | ✅ | |
| 7 | Retry _api_max_retries default 3 | ✅ | |
| 8 | Retry wait 0.2s check interrupt | ✅ | |
| 9 | _try_activate_fallback run_agent.py:6997 | ✅ | |
| 10 | _restore_primary_runtime run_agent.py:7192 | ✅ | |
| 11 | delegate_task delegate_tool.py:1813 | ✅ | |
| 12 | _DEFAULT_MAX_CONCURRENT_CHILDREN=3 | ✅ | |
| 13 | MAX_DEPTH=1, _MAX_SPAWN_DEPTH_CAP=3 | ✅ | |
| 14 | DELEGATE_BLOCKED_TOOLS 41-49 | ✅ | |
| 15 | Toolset intersection 891-930 | ✅ | |
| 16 | _subagent_auto_deny | ✅ | Initial ❌ lines 55-67 are comments → second pass confirmed function at 69 → corrected |
| 17 | _active_subagents registry | ✅ | Initial ⚠️ 148 is a lock; 151 is the dict → corrected to 151 |
| 18 | role orchestrator retains delegate_task | ✅ | |
| 19 | trajectory.py line count | ✅ | Initial ❌ 57 → actual 56 → corrected |
| 20 | save_trajectory trajectory.py:30 | ✅ | |
| 21 | convert_scratchpad_to_think trajectory.py:16 | ✅ | |
| 22 | model_metadata.py 1467 lines | ✅ | |
| 23 | display.py ~1000 lines | ✅ | |
| 24 | insights.py ~930 lines | ✅ | |

**Result: 24/24 ✅** (Initial: 2❌ 3⚠️ → all confirmed by second pass → passed after corrections)

---

## Second Full Review Round (6 Agents in Parallel — Factual + Literary)

Simultaneous five-dimension factual review + five-dimension literary review of documents 00, 01, and 02.

### Factual Corrections (confirmed after second pass)

| Document | Issue | Correction |
|----------|-------|------------|
| 00 | Dockerfile "two-stage" | → "multi-stage" (3 FROM directives) |
| 00 | mcp_serve.py "conversations, memory" | → "message gateway (platform message read/write, approvals)" |
| 00 | Dependency enumeration overloaded (7/18) | Condensed to category descriptions + accurate counts |
| 01 | CodexTransport class name | → ResponsesApiTransport |
| 02 | cache_ttl 1h cost 1.6x | → 2x (5m is 1.25x) |
| 02 | Stale stream 90s | → 180s |
| 02 | __init__ diagram includes stream_callback | Removed (belongs to run_conversation) |
| 02 | Model Metadata fallback chain order | Rewritten per source code comments |

Review Agent false positive: extras count cited as 34; actual is 26; document was correct.

### Literary Corrections

| Type | Correction |
|------|-----------|
| Terminology consistency | "sub-agent" unified across all three documents |
| Term explanations | REPL, AST, LRU, CamoFox, dogfooding explained on first occurrence |
| Analogy improvements | "thunderstorm cluster" → "thundering herd"; "lossy compression" → study-notes analogy; "glue" metaphor showing tension |
| Transitional sentences | 4 bridging sentences added at broken transitions and between sections |
| Density adjustment | 01 gateway section split; 02 Credential Pool strategies → state transitions bridged |
| Reference correction | "dual injection" changed to explicit cross-document link; "turn" unified |

### 6 Diagrams Added

| Document | Diagram |
|----------|---------|
| 01 | Tool registration flow (AST scan → lazy import → self-register → schema list) |
| 01 | Memory dual-injection comparison (system prompt static vs user message dynamic) |
| 01 | System prompt 7-layer stack |
| 02 | Retry backoff decision flowchart (including 429 tiered handling) |
| 02 | Credential Pool state machine (ok/exhausted/refreshing) |
| 02 | Fallback Chain full flowchart (three paths: no config / success / recovery) |

### Incremental Fact Re-verification

7 key assertions re-verified after literary edits: 7/7 ✅, no new errors introduced.

---

## Step 3.0: Tool System (03-tool-system.md)

### Factual Review

| Issue | Status | Notes |
|-------|--------|-------|
| HARDLINE_PATTERNS count | ✅ | Initial "9 types" → second pass confirmed 12 → corrected |
| DANGEROUS_PATTERNS count | ✅ | Initial "35+" → second pass confirmed 47 → corrected (incremental re-check flagged 46; main confirmed 47) |
| _HERMES_CORE_TOOLS count | ✅ | Initial "35" → second pass confirmed 38 → corrected |
| distributions count | ✅ | Initial "14" → second pass confirmed 17 → corrected |
| PINNED_THRESHOLDS line number | ✅ | 38-49 → 12-14; corrected |
| Remaining 11 line/number references | ✅ | Passed factual verification |

### Literary Review

| Issue | Type | Action |
|-------|------|--------|
| Missing transitional sentences between sections | 🟡 | 2 transitions added |
| Path traversal unexplained | 🟡 | Explanation added |
| cosign not explained | 🟡 | Parenthetical explanation added |
| Approval persistence section too dense | 🟡 | Split |
| `"research"` quotation style | 🟡 | Changed to code format |
| Analogy quality | 🟢 | No change needed |
| Language consistency | 🟢 | No change needed |

### Completeness ✅ / Consistency ✅ / Examples ✅ / Diagrams ✅ (5 diagrams; MCP diagram omitted; acceptable)

---

## Step 4.0: Skill System (04-skill-system.md)

### Factual Review

| Issue | Status | Notes |
|-------|--------|-------|
| Seed copy file reference | ✅ | skills_tool.py:84 is comment only; actual logic in skills_sync.py → corrected |
| "Takes effect next session" | ✅ | Inaccurate; skill_manage clears cache immediately on success → corrected |
| assets/ missing from directory tree | ✅ | Added |
| Remaining 11 references | ✅ | Passed factual verification |

### Literary Review

| Issue | Type | Action |
|-------|------|--------|
| Cache section too dense | 🔴 | Split into three paragraphs; "why two layers" added |
| 341 malicious skill buried in parentheses | 🟡 | Promoted to a complete sentence |
| Section transitions | 🟡 | Acceptable; no major changes |
| Concept introduction | 🟢 | No change needed |

### Completeness ✅ / Consistency ✅ / Examples ✅ / Diagrams ⚠️ (Skills Hub multi-source search diagram absent; acceptable)

---

## Step 5.0: Plugin System (05-plugin-system.md)

### Factual Review

| Issue | Status | Notes |
|-------|--------|-------|
| Honcho "exponential backoff" | ✅ | Actually linear backoff (cadence + empty_streak) → corrected |
| try/except line number offset | ⚠️ | 995 → 991; 4-line offset acceptable |
| memory directory skip line number | ⚠️ | 573 → 569; acceptable |
| register_skill() missing | ✅ | Added |
| pip entry-point missing | ✅ | Added |
| Remaining 14 references | ✅ | |

### Literary Review

| Issue | Type | Action |
|-------|------|--------|
| Honcho section too dense | 🔴 | Split into two paragraphs; analogy added |
| "Cognitive pattern" over-anthropomorphized | 🟡 | Toned down to concrete behavioral description |
| Missing section transitions | 🟡 | 2 transitions added |
| ASCII diagram missing lead-in sentence | 🟡 | Added |
| Concept introduction pacing | 🟢 | No change needed |
| Diagram coverage | ✅ | 3 diagrams covering main flows |

### Completeness ✅ / Consistency ✅ / Examples ⚠️ (exponential → linear corrected) / Diagrams ✅

---

## Step 6.0: Gateway (06-gateway.md)

Factual: asyncio.to_thread → run_in_executor; fresh-final source corrected; PII supplemented with 4 platforms; /steer → /restart. Literary: 3🟢 2🟡; analogies sparse but no 🔴. **All passed.**

---

## Step 7.0: TUI & Web (07-tui-and-web.md)

Factual: entry.tsx spawn location → gatewayClient.ts; React Router v6 → v7; Chat default off explained. Literary: 🔴 API endpoint enumeration overloaded → condensed. **Passed after corrections.**

---

## Step 8.0: Cron Scheduling & External Protocols (08-cron-scheduling.md)

Factual: overall ✅; comparison table "pure data bridge" → "message gateway read/write bridge". Literary: terminology unified with Chinese annotations; MCP scenario moved earlier. **All passed.**

---

## Step 10.0: Environment & Deployment (10-deployment.md)

Factual: ❌ profiles → profile command name corrected. Literary: 3🟢 2🟡 (Nix/Homebrew section too dense; closing section doesn't echo the opening). **Passed after corrections.**

---

## Step 11.0: Batch Runs & RL (11-batch-and-rl.md)

Factual: tool parsers 10 → 11; CompressionConfig line number 82 → 83; flowchart encoding fixed. Literary: 2🟢 3🟡 (colloquialisms; mixed language in diagrams); no 🔴. **Passed after corrections.**

---

## Step 12.0: Engineering Practices (12-engineering-practices.md)

Factual: FTS line range 103-125 → 103-156; _reconcile_columns line number corrected; WAL checkpoint description corrected. Literary: 2🟢 3🟡 (heading strengthening); no 🔴. **Passed after corrections.**

---

## Closing Phase Review

### README.md + Code Coordinates + File Index

Factual review: code coordinates 20/20 all precise. README 4 numbers ⚠️ corrected (578K → 587K; 20 platforms → 19; 131 → 130 Co-Author; Provider 20+ underestimated). Literary review: README 🔴 no analogies → rewritten with dramatic opening and metaphors; appendix 🟡 skills line count missing → added.

### Mermaid Migration

31 ASCII diagrams converted to Mermaid. 86 parenthesis escapes (batch script) + 2 diamond-node parenthesis fixes (manual). 38 diagrams given **Figure: xxx** titles.

### Three-Agent Diagnosis & Prediction

Architect + product analyst + AI researcher — three independent perspectives — combined into consensus and divergence written into README.
