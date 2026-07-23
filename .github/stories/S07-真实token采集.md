# S07 — 真实 token 采集

- **优先级**:P2
- **规模**:中
- **状态**:完成(A:③ / B:②+audit;累计靠 prior_cost 传递)
- **依赖**:S01(记录框架已就位,现在 token 那行写的是"见运行页")

## 为什么

S01 把每层的标准记录做实了,但里面的 `token` 一行现在是占位("见运行页")。设计要求记"本层 + 累计"的真实用量,方便一眼看清每次同步烧了多少。这块单独拆出来,因为它比"写记录"复杂:要改 `claude -p` 的调用方式、跨 matrix 分支收集、还要跨运行累计。

## 做什么

- [x] **本层用量**:③ 的 rewrite+复核在 `sync-run.sh` 里加 `--output-format json`、stdout 存 cost 文件、`sum_cost_usd` 加总。 ✅ f9514b4/7a9feff(A)
- [x] **跨 matrix 汇总**:②/audit 的 agent 在 matrix 步加 `--output-format json`,cost 随 region-/review- artifact 一起上传,finalize 里 `sum_cost_usd` 加总。 ✅ 637c25e(B)
- [x] **累计**:每层 dispatch 下一层时多传 `-f prior_cost=<本层累计>`;③ 收到后 累计 = prior + 本层。①免费、②/audit prior=0。 ✅
- [x] 把 `token=见运行页` 换成 `token=本层 X 美元 / 累计 Y 美元`。 ✅
- [x] 抽出 `lib/cost.sh` 的 `sum_cost_usd`(逐文件累加,坏文件跳过不连累正常文件),`test-cost.sh` 单测覆盖损坏场景。 ✅
- [x] 尽力而为:cost 取不到/损坏 → 记 0,绝不改 exit code、绝不让流水线失败。 ✅(桩验证)

## 涉及文件

- `.github/scripts/sync-run.sh`
- `.github/workflows/hermes-assess-plan.yml` · `hermes-audit.yml`(matrix 步采集 + 上传)
- `.github/scripts/assess-finalize.sh` · `audit-finalize.sh` · `lib/_finalize.sh`(加总 + 写进记录)

## 备注

- 走订阅额度时 `total_cost_usd` 是"用量的度量",不是"另外一笔账单"——记它是为了看清消耗,不是计费。
- 这条不阻塞流水线正常跑;没有它,记录照样可读,只是 token 那格是占位。
