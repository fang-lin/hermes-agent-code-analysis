# S01 — 把每层的完整记录写进 issue

- **优先级**:P1
- **规模**:大
- **状态**:核心已完成(token 采集拆到 [S07](S07-真实token采集.md))
- **依赖**:无

## 为什么

设计里最看重的一件事是"可审计":每一层每跑一次,都往这次的 issue 追加一条**人能读懂的完整记录**,想深看还能点开折叠块看复核 agent 的评语全文和逐处改动。

但实际建出来的差得远。第一次真跑(issue #7)里,② 只贴了一行 `route=proceed_flagged complexity=deep overturned=0`,别的什么都没有——看不出评估了哪些章、打算改什么、凭什么这么判。这套"完整记录 + 复核评语进 issue"的代码在构建时被标成 TODO 往后推了,一直没接上。**所以"可审计"这个目标现在基本是空的,这是硬伤。**

`format_record`(拼标准记录)和 `format_details`(拼折叠块)两个函数早就建好、也有单测,但没被真正用起来;`RUN_URL` 在工作流里接了却没脚本读;`--output-format json` 的 token 采集也没做。

## 做什么

让 ②、③、复核循环三层都往对应 issue 写完整记录。验收条件:

- [x] **② 评估+规划**:往 issue 写一条标准记录(触发 / 评估范围 / 复杂度 / 挑错 / 去向),外加一个折叠块放**完整的 work plan**(要改哪几处、现状、改成什么、源码依据)。不再是干巴巴一行。 ✅ 1a8a4cf
- [x] **③ 同步**:往 issue 写标准记录,外加两个折叠块——**每个复核 agent 的评语全文** + **本次逐处改动**。 ✅ 1a8a4cf(折叠块原本就有,补了记录)
- [x] **复核循环**:往 audit issue 写标准记录 + 查出的错折叠块。 ✅ 1a8a4cf
- [x] **RUN_URL 接上**:标准记录标题带这次运行的 Actions 链接。 ✅ 1a8a4cf
- [x] 折叠块用 `format_details`,标准记录用 `format_record`。 ✅
- [x] 每层测试加了"记录真的贴进 issue"的断言(破坏性测试验证过能挡回归)。 ✅ 1a8a4cf
- [ ] **token 用量**:每个用 agent 的层记 `total_cost_usd` / token 的"本层 + 累计"。→ 拆到 [S07](S07-真实token采集.md),现在记录里先写"见运行页"。

## 涉及文件

- `.github/scripts/assess-finalize.sh` — ② 的记录 + work plan 折叠块。
- `.github/scripts/lib/_finalize.sh` — ③ 的记录 + 复核评语 + 改动折叠块(目前有个 `# TODO(Plan 4/wire-up)` 标记就在这)。
- `.github/scripts/sync-run.sh` — 从复核 agent 的 `claude -p` 输出采 token;把 RUN_URL 传下去。
- `.github/scripts/audit-finalize.sh` — 复核循环的记录 + 评语。
- 三个跑 agent 的工作流 — 确认把 `RUN_URL`(运行链接)传进脚本。
- 已有可复用:`.github/scripts/lib/issue.sh` 的 `format_record` / `format_details`。

## 备注

- 大块原始数据(完整运行日志)才留运行附件;评语和改动清单直接进 issue 折叠块,别塞附件——设计明确要求。
- 采 token 时注意:`--output-format json` 会改变 `claude -p` 的输出形态,现在脚本是按纯文本用的,改的时候别把改写/复核 agent 写文件的行为搞坏,记得跑单测。
