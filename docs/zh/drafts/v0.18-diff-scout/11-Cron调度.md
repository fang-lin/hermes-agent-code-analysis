# 11 章 diff 侦察报告（3bace071b → v2026.7.7.2）

> 侦察 agent 输出的工作底稿。**行号/数字未经主线核实，修改时逐条验证。**

## 工作量评估：中高（原判"轻章"完全不成立——cron 代码近乎翻倍）

## A. 过期断言要点

- **行数**：jobs.py 1,203→2,033；scheduler.py 1,972→3,638；cronjob_tools.py 775→1,137；hermes_cli/cron.py 322→456
- **行号全体大漂移**：tick() 1790→3400；parse_schedule 187→362；compute_next_run 354→565；_compute_grace_seconds 322→533；SILENT_MARKER 定义 132→245；mark_job_run 901-918→1331-1421；croniter 基准 386-393→601-606；flock 1813→3423；advance_next_run 1835→3448；sequential/parallel jobs 1915/1919→3550/3565；_start_cron_ticker 17767→19989（且已变成弃用 shim）
- **Job 字段变化**：删 `profile`（隔离改为 per-profile HERMES_HOME，#4707）；新增 8 个字段：attach_to_session / provider_snapshot / model_snapshot / paused_at / paused_reason / schedule_display / fire_claim / run_claim

## B. 新增机制要点（15 项，选材成段）

优先级高：
1. **调度器 Provider 接口**（scheduler_provider.py 194 行）：内置调度器与外部 provider（Chronos 等）解耦，run_one_job()（:3253）提取为共享执行体
2. **自动化蓝图**（blueprint_catalog.py 713 行）：参数化蓝图目录 CATALOG，单一真相源，多表面渲染（表单/CLI/Agent/deep-link）
3. **建议任务**（suggestions.py 260 行）：consent-first 的自动化建议
4. **镜像投递**（mirror delivery）：cron 输出可镜像回源会话（USER turn 不破坏交替），cron.mirror_delivery + attach_to_session
5. **provider/model 快照**（jobs.py:793-829，#44585）：创建时锁定 resolved provider/model，防全局默认切换后行为漂移
6. **一次性任务 run claim**（#59229）：防 mid-run 重复执行
7. **ticker 心跳**（#32612）：TICKER_HEARTBEAT_FILE 区分"gateway 活着但 ticker 线程死了"
8. **网关生命周期守卫**（lifecycle_guard.py 141 行，#30719）：拦截 cron 任务里调 `hermes gateway restart` 的循环

优先级中：跨进程 jobs.json flock（jobs.py:138-183）、per-profile HERMES_HOME 动态解析、tick(sync=True) 新参数、scripts/classify_items.py 示例

## C. 注意

- 文档现有的"tick 四机制/三层并发安全"骨架大概率仍成立，但每个机制的行号和细节全要重核；并发安全从三层扩成更多层（flock + run claim + ticker heartbeat + lifecycle guard）——叙事结构要调
