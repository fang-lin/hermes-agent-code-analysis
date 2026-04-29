# Hermes Agent 源码分析

对 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) v0.11.0 的完整源码分析。578,000 行 Python 代码，12 篇叙事风格的技术文档。

## 分析对象

Hermes Agent 是 Nous Research 开源的自改进 AI 智能体框架。它支持 20+ 个模型 Provider、20 个消息平台、66 个内置工具、83 个预置技能，能在本地、Docker、云端等 6 种环境运行，并自带批量轨迹生成和 RL 训练基础设施。

## 文档索引

| 编号 | 文档 | 主题 |
|------|------|------|
| 00 | [项目概述](docs/00-项目概述.md) | Hermes 是什么、为什么这样设计、模块全景、代码库文件索引 |
| 01 | [架构分析](docs/01-架构分析.md) | 一条消息从输入到输出的完整路径 |
| 02 | [Agent 核心](docs/02-agent核心.md) | AIAgent 的角色、协作关系和内部机制 |
| 03 | [工具系统](docs/03-工具系统.md) | 66 个工具的注册、调度、安全审批和结果治理 |
| 04 | [技能系统](docs/04-技能系统.md) | 程序性记忆：渐进式披露、自改进、Skills Hub |
| 05 | [插件系统](docs/05-插件系统.md) | Python 代码级扩展：16 种钩子、记忆插件、上下文引擎 |
| 06 | [Gateway 网关](docs/06-gateway网关.md) | 一个进程服务 20 个消息平台的架构 |
| 07 | [TUI 与 Web](docs/07-tui与web.md) | 三种用户界面：prompt_toolkit / Ink / Web Dashboard |
| 08 | [Cron 调度与外部协议](docs/08-cron调度.md) | 定时任务、ACP 编辑器集成、MCP 服务端 |
| 10 | [环境与部署](docs/10-环境与部署.md) | 六种终端后端、Docker、安装向导、多 Profile |
| 11 | [批量运行与 RL](docs/11-批量运行与rl.md) | 轨迹生成、压缩、RL 训练环境 |
| 12 | [工程实践](docs/12-工程实践.md) | SQLite 存储、日志、测试、安全政策 |

## 分析方法

采用三 Agent 编排流程：

```
分析 Agent (sonnet)     → 读源码产出草稿
  ↓
[事实审核 Agent (sonnet) ‖ 文学性审核 Agent (sonnet)]  → 并行五维度审核
  ↓
主线 (opus)             → 二次验证 + 修正 + 增量复核
```

每个概念用 9 问模板分析（是什么/从哪来/在哪里/依赖关系/怎么工作/解决什么/替代方案/失败模式/可配置性），自然织入 Martin Fowler 风格的叙事中。

## 关键发现

1. **AI 深度参与开发**。Teknium 在 2026 年 3-4 月日均 53 次提交，凌晨比白天还活跃，git 历史中有 131 次 Claude Co-Author 标记——推测 60-80% 代码行数由 AI 生成。
2. **两个"上帝文件"**。`run_agent.py`（13,293 行）和 `cli.py`（11,395 行）集中了核心逻辑，`agent/` 子目录是从 `run_agent.py` 逐步抽离出去的。
3. **Transport 抽象层是新近提取的**。v0.11.0 release notes 明确记载 Transport ABC 从 `run_agent.py` 的 if-else 分支提取而来。
4. **安全是多层纵深**。从硬核封锁到 LLM 自动判断的 smart 模式、从路径安全到 SSRF 防护到 Tirith 内容扫描，共 8+ 层安全防线。
5. **研究就绪不是口号**。`batch_runner.py`、`trajectory_compressor.py`、`environments/` 和 `tinker-atropos/` 构成了完整的从 Agent 运行到模型训练的管线。

## 声明

本项目是对 hermes-agent 源码的独立分析，非 Nous Research 官方文档。所有代码引用均经过独立验证。分析基于 v0.11.0 源码，后续版本可能有变化。

## 过程文档

- [审核报告汇总](docs/98-审核报告汇总.md) — 所有审核发现和修正记录
- [工作日志](docs/99-工作日志.md) — 完整工作过程、方法论演进和教训
