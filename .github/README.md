# 文档 / skill 与上游 hermes 的同步自动化

本仓的文档(`docs/`)和 skill(`.claude/skills/hermes-agent-expert/`)钉在 hermes-agent 的某个版本(见根目录 `.hermes-pin`)。上游发展很快(近期 ~712 commit / 版、约每周一版),所以这套自动化负责**及时发现上游变化、有把握地把文档拉回同步**——而不追求无人值守全自动。

## 三个阶段

| 阶段 | 干什么 | 成本 | 现状 |
|------|--------|------|------|
| **①哨兵 Sentinel** | 侦测有没有比 pin 新的 release,跑机械自检,开 drift issue 报警 | 脚本、**零 token** | ✅ 已建并 CI 验证 |
| **②定级 Triage** | 读 drift issue 里的覆盖路径 diff,判爆炸半径(化妆/浅层/深层),定同步范围 | 初期人工 | ⬜ 规划中 |
| **③同步 Sync** | agent 按定好的范围**真正改 docs/skill** → 跑 check-anchors 到绿 → 开 PR → 人 review 合并 | 走 Max 订阅额度 | ⬜ 规划中(卡在 token,见下) |

铁律贯穿始终:**只改 docs 的口子是③的 PR,人始终在闭环里合并**(守住本项目"每条发现独立二次验证")。`.hermes-pin` **只在③的同步 PR 里 bump**,哨兵永不动它。

原则:**够格的 release 及时同步、每次保持小;控频靠②定级筛掉没动到文档语义的 no-op release,不靠攒**(累计只会把小改攒成大改,review 更难、爆炸半径更大)。

---

## ①哨兵(已建)

**文件**
- `.hermes-pin` —— 记录 docs/skill 分析到的 tag/commit(现 `v2026.7.7.2` / `9de9c25f6`)。
- `.github/scripts/hermes-release-watch.sh` —— 哨兵逻辑(可本地跑)。
- `.github/workflows/hermes-release-watch.yml` —— 每日 06:00 UTC + 手动 `workflow_dispatch`。

**行为**
1. 查上游最新 release。
2. 若 = `.hermes-pin` 的 tag → 输出 `UPTODATE`,**什么都不做**(惰性,不刷 issue)。
3. 若有更新 → 只看**最新**那一版,收集:落后几个 release、`gh compare` 算落后多少 commit / 变更多少文件、其中多少落在**文档覆盖路径**;再浅 clone 最新 tag 跑 `orient.sh` + `check-anchors.sh`;把这些写成一份 drift 报告,按 tag **去重**开/更新一个带 `hermes-drift` 标签的 issue。

**drift issue 里有什么**(就是②定级的输入):落后版本列表、落后 commit/文件数、**覆盖路径变更文件清单**(爆炸半径线索)、机械自检结果(行漂表 + 锚点校验)。

**一句诚实话**:机械自检只抓**结构漂移**(锚点挪位/断裂)。**同一行的语义变化**(比如某个默认值从 3 改成 5)不会显示出来——所以②定级必须读那份覆盖路径 diff,不能只看哨兵的绿灯。

**本地手动跑**
```bash
# 正常(对当前 pin):
bash .github/scripts/hermes-release-watch.sh
# 模拟"有新版"(拿旧 pin + 复用本地 clone 免下载):
HERMES_PIN_TAG=v2026.7.1 HERMES_PIN_COMMIT=v2026.7.1 \
  HERMES_SRC_DIR=./hermes-agent bash .github/scripts/hermes-release-watch.sh
```

---

## ②定级 / ③同步(规划中)

- **②定级**:定一套判级 rubric(化妆级→重新 pin 锚点;浅层→定点改受影响的锚点+文档段;深层→整章重审),你读 drift issue 后用 label(如 `resync:scoped` / `resync:chapter`)确认范围。多 agent 自动评估先不做,等真实版本跑几轮证明需要再上。
- **③同步**:`resync:*` label / 手动触发(带 scope 入参)→ `anthropics/claude-code-action` 用 `CLAUDE_CODE_OAUTH_TOKEN` → 喂 agent:drift 报告 + 范围过滤 diff + `CLAUDE.md` 规则 + `hermes-agent-expert` skill → 按范围改 → check-anchors 到绿 → 开 PR。绝不 push main;`.hermes-pin` 在 PR 里 bump;`--max-turns` 封顶控额度。

**③启用前你要做一步**(我替不了):
```bash
claude setup-token          # 本地浏览器登录 Max 账号,生成一年期 token
```
再到 repo → Settings → Secrets and variables → Actions,加 secret **`CLAUDE_CODE_OAUTH_TOKEN`**(用它而非 `ANTHROPIC_API_KEY`,走订阅额度、不额外按 token 计费)。注意:CI 用量与你交互式写代码**共用** Max 的 5 小时/周窗口;token 约一年后需轮换。

---

## 维护速查

- **同步完成后**:合并③的 PR;`.hermes-pin` 已在该 PR 里更新到新 tag/commit;哨兵下次自动以新基准比对。
- **暂停哨兵**:在 `hermes-release-watch.yml` 注释掉 `schedule:`(留 `workflow_dispatch` 手动)。
- **token 过期**:重跑 `claude setup-token`,更新 secret。
- **进度**:任务拆解见 `/tasks`(#25–#33)。
