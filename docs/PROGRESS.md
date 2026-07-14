# 进度追踪

> **每次新对话必须先读本文件。**
>
> 基于 hermes-agent tag `v2026.7.7.2`（v0.18.2，commit `9de9c25f6`，2026-07-07）；v1 历史基准为 `3bace071b`（v0.14.0）

## 当前状态

**阶段：v0.18.2 版本更新收尾（00-14 全部改写 + 全部审核已闭环；完整性终审进行中）**
**下一步：完整性终审结果处理 → 全绿；英文翻译推迟到更新完成后**

> **版本更新（2026-07-09 启动）**：源码基准从 `3bace071b`（v0.14.0）换到 tag `v2026.7.7.2`（v0.18.2，commit `9de9c25f6`），落后 5,617 提交。已完成：① factual-reviewer 手册补 5 条验证方法（commit 22fff60）；② 源码已 checkout 新 tag；③ 14 份逐章 diff 侦察报告落盘 `docs/zh/drafts/v0.18-diff-scout/`（commit 177a4e7）；④ **三个跨章一致性定论落盘** `docs/zh/drafts/v0.18-consistency-memo.md`（平台迁移/moa 重构/上帝文件分解，逐章修改的统一口径真相源）；⑤ **00 章已更新并过 factual 认证审**（4❌+6⚠️ 全部二次验证处理，见 98 报告）。**用户已定**：新增第 14 章「桌面应用」（apps/desktop，架构层面、控制深度）。待做：01-13 按侦察清单逐章修改 + 审核（重章 01/02/05/07/08/10/13 depth+factual 双审、其余 factual 认证审）、新写 14 章（完整流程）、完整性收口、旧版本号清扫。更新完成前不动英文翻译。
>
> 历史：中文 14 篇 + 终审 + 全 14 章加强版事实复审已于 2026-06-26 完成（61 真错修正，见 98 报告）。

---

## 章节进度

| 章节 | 状态 | 备注 |
|------|------|------|
| 00 — 项目全景 | ✅ 已完成 🔄 已更新至 v0.18.2 | 含架构分析（一条消息的旅程）；2026-07-09 全景统计稳定法重测 + factual 认证审 |
| 01 — 基础设施层 | ✅ 已完成 🔄 已更新至 v0.18.2 | 五个用户问题结构；2026-07-10 重章双审（depth 4🔴4🟡 全采纳 + factual 3❌6⚠️ 修正），新增托管作用域/env denylist/8 级 provider 链/五分支插件分诊 |
| 02 — Agent 核心 | ✅ 已完成 🔄 已更新至 v0.18.2 | 2026-07-10 重章双审（depth 4🔴5🟡 全采纳 + factual 1❌2⚠️）；新增 MoA 双路径/turn_context+finalizer/三态凭证/压缩失败闭环/恢复四分叉 |
| 03 — 工具系统 | ✅ 已完成 🔄 已更新至 v0.18.2 | 2026-07-10 factual 认证审（3❌5⚠️ 修正）；69 工具/DANGEROUS 73/写入审批/威胁模式库/tool_search 渐进披露/后台委托 |
| 04 — 技能系统 | ✅ 已完成 🔄 已更新至 v0.18.2 | 2026-07-10 factual 认证审（8❌6⚠️ 修正）；72+102 技能索引重列、审查模型路由/DIGEST、Curator prune_builtins、Skills Hub 十源聚合重写 |
| 05 — 网关层 | ✅ 已完成 🔄 v0.18.2 双审闭环 | depth 5🔴5🟡 + factual 3❌3⚠️（SessionResetPolicy 默认 none/fresh-final 默认关/handler 46）全修 |
| 06 — 协议适配层 | ✅ 已完成 🔄 v0.18.2 factual 闭环 | V4A 审批反转/provenance(v0.17)；factual 10❌4⚠️（工具集 49→29/messages_send 无审批/permissions 未接线）全修 |
| 07 — 插件框架 | ✅ 已完成 🔄 v0.18.2 双审闭环 | 22 成员/23 钩子/中间件；depth 3🔴3🟡 + factual 2❌5⚠️（3 注册面 v0.15 归属纠正）全修 |
| 08 — 内置插件 | ✅ 已完成 🔄 v0.18.2 双审闭环 | 平台大迁移/18 类；depth 3🔴5🟡 + factual 8❌3⚠️（版本归属系统性纠偏/teams sink 行为）全修 |
| 09 — Kanban 系统 | ✅ 已完成 🔄 v0.18.2 factual 闭环 | Task 35 字段/类型化阻塞熔断/per-profile 上限/7 表；factual 11❌7⚠️ 全修 |
| 10 — 交互界面与运行模式 | ✅ 已完成 🔄 v0.18.2 双审闭环 | depth 3🔴7🟡（三线程打断/goal/PtyBridge 四层）+ factual 21❌6⚠️（行号系统性漂移全重测/HERMES_LOCAL_STT_COMMAND）全修 |
| 11 — Cron 调度 | ✅ 已完成 🔄 v0.18.2 factual 闭环 | 扩容六方向；factual 8❌8⚠️（代码组织行数/ticker 拆分/script_timeout 3600/profile 字段删除）全修 |
| 12 — 批量运行与轨迹生成 | ✅ 已完成 🔄 v0.18.2 factual 闭环 | moa 全分布移除/_snap_boundary(v0.17)；factual 11❌（行号漂移/save_trajectories 非 config 键）全修 |
| 13 — 工程实践 | ✅ 已完成 🔄 v0.18.2 双审闭环 | depth 4🔴3🟡（state.db 自愈/compression_locks/日志异步队列/发布工程）+ factual 6❌6⚠️（测试计数 2017/per-file 归因）全修 |
| 14 — 桌面应用 | ✅ 已完成 🆕 v0.18.2 全流程闭环 | 三件套/后端托管/JSON-RPC 契约/20 模块地图；draft→depth→literary→factual 4❌3⚠️（终端 IPC/模块 33/自更新轨道）全修 |

## 完整性审核进度

| 节点 | 状态 | 备注 |
|------|------|------|
| 阶段 1（00-01 完成后） | ✅ 已完成 | 3 处跨章不一致修正，5 个遗漏文件补入 |
| 阶段 2（02-06 完成后） | ✅ 已完成 | auxiliary_client/ContextEngine/Computer Use 补入，链接修正 |
| 阶段 3（07-08 完成后） | ✅ 已完成 | 标题编号对齐、方法名修正、钩子计数修正、browser 后端补全 |
| 终审（全部完成后） | ✅ 已完成 | 已修：第12章重定名遗漏旧称（00/10/11）、09章失效链接（→delegation-patterns）。**两处真遗漏已补齐**：① 02 章补 LSP 集成专题（CLAUDE.md 承诺的）；② 10 章补语音模式小节。两节走深度+文学性+事实审核（22 断言，二次验证修正 reporter 行号/ServerDef 25/LSP 仅本地后端/STT 含 xai/流式 TTS 仅 ElevenLabs 等）。平台数 00「约20」/05「约19」属轻微近似差异，不改 |

## 翻译进度

> 质量维护文件已就绪：`docs/TRANSLATION_GLOSSARY.md`（术语词库）+ 翻译审核 Agent（`subagent_type: translation-reviewer`，系统提示锁在 `.claude/agents/`）。范围：00–13 共 14 篇；98/99 不译（过程性元文档）。

| 章节 | 状态 |
|------|------|
| 质量维护文件 | ✅ 词库（docs/）+ 翻译审核 Agent（.claude/agents/）就绪 |
| 00 项目全景 | ⬜ 待翻（定调篇） |
| 01–13 | ⬜ 待翻（00 定调后批量） |
| 98 / 99 | — 不译（保中文） |

---

## 状态图例

- ⬜ 未开始
- 🔵 进行中
- ✅ 已完成
- 🔄 已修订
