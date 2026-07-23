# S07 — 真实 token 采集

- **优先级**:P2
- **规模**:中
- **状态**:待做
- **依赖**:S01(记录框架已就位,现在 token 那行写的是"见运行页")

## 为什么

S01 把每层的标准记录做实了,但里面的 `token` 一行现在是占位("见运行页")。设计要求记"本层 + 累计"的真实用量,方便一眼看清每次同步烧了多少。这块单独拆出来,因为它比"写记录"复杂:要改 `claude -p` 的调用方式、跨 matrix 分支收集、还要跨运行累计。

## 做什么

- [ ] **本层用量**:跑 agent 的地方(③ 的 `sync-run.sh` 改写+复核;② 的 assess-region matrix 步;复核循环的 audit-review matrix 步)给 `claude -p` 加 `--output-format json`,从输出里取 `total_cost_usd` / `usage`(输入/输出 token)。
  - 注意:`--output-format json` 只改 stdout 的形态,agent 该写的文件照写;改的时候务必跑单测确认改写/复核 agent 写文件的行为没坏。
- [ ] **跨 matrix 汇总**:② 和复核循环的 agent 在各 matrix 分支里跑,用量得随 region-/review- 产出一起上传,finalize 里加总。
- [ ] **累计**:"累计"要跨 ①→②→③ 三个独立运行。要么从这次 issue 里已有的记录累加,要么每层把累计值往下传。挑一个简单可靠的。
- [ ] 把 `token=见运行页` 换成 `token=本层 <x> / 累计 <y>`。
- [ ] 补测:能从桩的 JSON 输出里正确取到用量、加总。

## 涉及文件

- `.github/scripts/sync-run.sh`
- `.github/workflows/hermes-assess-plan.yml` · `hermes-audit.yml`(matrix 步采集 + 上传)
- `.github/scripts/assess-finalize.sh` · `audit-finalize.sh` · `lib/_finalize.sh`(加总 + 写进记录)

## 备注

- 走订阅额度时 `total_cost_usd` 是"用量的度量",不是"另外一笔账单"——记它是为了看清消耗,不是计费。
- 这条不阻塞流水线正常跑;没有它,记录照样可读,只是 token 那格是占位。
