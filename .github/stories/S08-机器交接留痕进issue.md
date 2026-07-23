# S08 — issue 也留机器交接原文

- **优先级**:P2
- **状态**:待做
- **规模**:小
- **依赖**:S01(记录框架已就位)

## 为什么

设计文档里承诺:issue 不只给人看,还是"每层交给下一层什么"的留痕——上一层把传给下一层的结构化产出也贴进 issue,想审的时候一眼看到。

但实际建出来,机器之间传数据走的是派发输入(`gh workflow run -f work_plan=... -f new_tag=...`),issue 里只有人类可读的记录(S01 补的),**没有那份机器交接的原文**。于是"上一层精确传了什么给下一层"其实藏在 `gh workflow run` 的调用里,issue 上看不到。可审计差这一口气。

## 做什么

每层在派发下一层之前,把这次交接的原文也贴进 issue(折叠块,默认收起,不刷屏)。验收条件:

- [ ] **①→②**:① 开 issue 后,把交给 ② 的输入(`new_tag`、pin)贴一个折叠块。
- [ ] **②→③**:`assess-finalize.sh` 派 ③ 之前,把完整的 `work_plan` JSON(就是 `-f work_plan=` 那份原文)贴一个折叠块"交给 ③ 的输入"。
- [ ] **复核→③**:`audit-finalize.sh` 派 ③ 之前,同样把 `work_plan` JSON 贴进 audit issue。
- [ ] 用 `format_details` 装(和 S01 的折叠块一致),summary 写清"交给下一层的输入(机器原文)"。
- [ ] 补测:断言派发前 issue 里出现了这个折叠块,且内容是那份 JSON。

## 涉及文件

- `.github/workflows/hermes-release-watch.yml`(①→② 的输入折叠块)
- `.github/scripts/assess-finalize.sh`(②→③)
- `.github/scripts/audit-finalize.sh`(复核→③)
- 复用 `.github/scripts/lib/issue.sh` 的 `format_details`

## 备注

- 派发输入本身没问题、也更可靠——这条不是要改传数据的方式,只是**额外**把那份原文也留一份到 issue,补上可审计。
- work_plan 可能较大,折叠块默认收起就不刷屏;真超大的话(极少)可考虑挂附件,但目前直接贴折叠块即可。
