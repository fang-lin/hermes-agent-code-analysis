# 项目规则

## 项目概况

本项目分析 NousResearch/hermes-agent 源码，产出一套 15 章的中英双语文档。文档定位：**既能深度理解源码架构，又能直接指导使用**。源码在 `hermes-agent/` 子目录（git-ignored）。

## 文档结构（15 章）

```
第一部分：认识系统
  00 — 项目全景（含架构分析）
  01 — 基础设施层：hermes_cli

第二部分：核心运行时
  02 — Agent 核心（含 LSP、transports 专题）
  03 — 工具系统（含 Computer Use、environments 专题）
  04 — 技能系统
  05 — 网关层：gateway
  06 — 协议适配层（acp_adapter、mcp_serve）

第三部分：插件与扩展生态
  07 — 插件框架
  08 — 内置插件（记忆/模型Provider/平台/观测性等）

第四部分：独立子系统
  09 — Kanban 系统
  10 — 交互界面与运行模式
  11 — Cron 调度

第五部分：运维与工程
  12 — 批量运行与轨迹生成（原"批量运行与 RL"；RL 训练环境已移出 v0.14.0 主仓）
  13 — 工程实践

第六部分：桌面客户端（v0.18.2 新增）
  14 — 桌面应用（apps/desktop、bootstrap-installer、shared；架构层面分析：
       Electron 双进程、bootstrap 安装器、JSON-RPC 对接契约、功能模块地图，
       不逐个深挖 React 组件。与后端的对接机制归 10 章）
```

## 每章内部结构

每章必须遵循 `docs/CHAPTER_TEMPLATE.md` 的结构：
1. **使用指南**（先讲）— 是什么、怎么用、怎么配、常见场景、排错、官方文档链接
2. **架构与实现**（后讲）— 代码组织、数据结构、关键流程（必须配图）、设计决策

## 官方文档引用规范

- 使用指南部分引用官方文档时附链接，格式：`https://hermes-agent.nousresearch.com/docs/<path>`
- 讲模式不讲枚举：不逐个列举 30 个 provider 或 27 个平台，讲共性模式 + 典型案例
- 具体案例必须标注"以 X 为例"

## 每次新对话必须做的事

1. 读本文件（CLAUDE.md）
2. 读 `docs/WORKFLOW.md` — 工作流程手册
3. 读 `docs/PROGRESS.md` — 当前进度
4. 读 `docs/zh/99-工作日志.md` 的最后一节 — 上次做到哪
5. 告知用户当前进度，等用户确认后再开始

## 必须遵守

1. **只谈计划不执行** — 除非用户明确说"开始"/"做"/"执行"，否则只讨论方案
2. **防幻觉** — 每个结论必须基于实际读过的代码，标注文件:行号，不确定的标"待确认"
3. **审核发现问题必须二次验证** — 审核 Agent 标记 ⚠️/❌ 的断言，必须再做一次独立代码阅读验证，两次结论一致才可采纳写入文档
4. **禁黑话** — 对话和文档都用大白话，绝不用自造词，也不用借来的比喻当术语（如 闸/筛子/机械硬门/回炉/爆炸半径/载体/落刀/收官/战役）。**动手前自检**：每个非通用词问一句"这是大白话，还是我造的/借的词？"是就换成平实说法。区分：用户自己引入并在用的词（锚点/漂移/交叉对抗审核 等）是共享词汇，保留；只清自己造的。

## 每步完成后的流程

按顺序执行，不得跳步：

```
1. 主线 (opus) 读源码写草稿（读 v1 对应章节作为深度基准）
2. 深度审核 Agent (sonnet) — 用 subagent_type: depth-reviewer 启动（最先跑，审草稿）
3. 主线 (opus) 补充深度缺失
4. 文学性审核 Agent (sonnet) — 用 subagent_type: literary-reviewer 启动（审深度补充后的草稿）
5. 主线 (opus) 采纳文学性建议，写入正式文档
6. 事实审核 Agent (sonnet) — 用 subagent_type: factual-reviewer 启动（最后跑，审最终版本）
   注意：系统提示已锁在 agent 文件，不读取手册、不内联验证项；只传文档路径 + 源码路径
7. 主线 (opus) 二次验证 ⚠️/❌，修正错误
8. 更新 docs/zh/98-审核报告汇总.md + 工作日志
```

## 审核 Agent 规则

### 启动审核 Agent 时必须做的事：

**优先用 `.claude/agents/` 里定义的命名 agent**（系统提示被文件锁定，主线无法忘传或临时改写）：

| 用途 | subagent_type | 系统提示来源（真相源） |
|------|---------------|----------------------|
| 深度审核 | `depth-reviewer` | `.claude/agents/depth-reviewer.md` |
| 文学性审核 | `literary-reviewer` | `.claude/agents/literary-reviewer.md` |
| 事实审核 | `factual-reviewer` | `.claude/agents/factual-reviewer.md` |
| 完整性审核 | `completeness-reviewer` | `.claude/agents/completeness-reviewer.md` |
| 翻译审核 | `translation-reviewer` | `.claude/agents/translation-reviewer.md` |

1. **用 `subagent_type: <上表名字>` 启动**——系统提示已锁定在 `.claude/agents/` 文件里，无需也不应在 prompt 里重述审核标准。
2. **在消息（prompt 参数）里只传"本次具体对象"**：待审文档路径 + 对应源码目录路径（+ 翻译审核额外传 `docs/TRANSLATION_GLOSSARY.md` 词库路径）。不要内联列出具体验证项。
3. **不得临时编写审核指令**——审核标准只在 `.claude/agents/` 里，主线不得绕过、不得内联重写，也不得用 `general-purpose` + 自写 prompt 顶替命名 agent。
4. **真相源就是 `.claude/agents/*.md`**：要改审核标准，直接改对应 agent 文件的 body，无需再同步任何副本（旧的 `prompts/` 镜像已废除）。
5. **新建/改 agent 文件后当前 session 不即时生效**——磁盘新增的 subagent 需重启 session 或用 `/agents` 创建才被识别。

> 注：`.claude/agents/` 已纳入 git（团队共享审核 agent 定义）；`.claude/` 下的 commands/settings.local 仍 ignore。

### 事实审核 Agent 五维度（详见 `.claude/agents/factual-reviewer.md`）：
- 事实准确性（必须贴代码片段举证）
- 完整性（9 问覆盖）
- 一致性（跨章节）
- 举例准确性
- 图表覆盖

### 文学性审核 Agent 六维度（详见 `.claude/agents/literary-reviewer.md`）：
- 叙事流畅性（必须附改写示例）
- 概念引入节奏
- 比喻和类比质量
- 信息密度
- 语言一致性
- 禁黑话（逐段揪自造词/借来当术语的比喻，列清单 + 给平实替换；见必须遵守第 4 条）

### 反橡皮图章机制：
- 事实审核必须至少报告 2 个 ⚠️ 或改进建议
- 文学性审核必须至少提出 3 个改进建议
- 没有举证（代码片段/改写示例）的审核意见不算数

## 完整性审核（阶段性）

在以下节点启动完整性审核 Agent（用 subagent_type: completeness-reviewer 启动）：
- 第一部分（00-01）完成后
- 第二部分（02-05）完成后
- 第三部分（06-09）完成后
- 全部完成后终审

完整性审核五项检查：源码覆盖、官方文档覆盖、跨章一致性、链接完整性、9 问跨章完整性。

## 语言与翻译

- 中文先写，英文后翻
- 中文文档在 docs/zh/，英文在 docs/en/
- 每个文档顶部加语言切换链接

## 工作日志

简化版工作日志记录在 docs/zh/99-工作日志.md：
- 每章开始/完成时间
- 审核发现的重大问题
- 与 v1 的关键差异
- 不做 token 监控
