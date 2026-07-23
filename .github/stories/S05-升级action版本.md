# S05 — 升级 Actions 到 Node 24 版本

- **优先级**:P3
- **规模**:小
- **状态**:待做
- **依赖**:无

## 为什么

第一次真跑,GitHub 在日志里报了一堆 `Node.js 20 is deprecated` 的**警告**:`actions/checkout@v4`、`actions/upload-artifact@v4` 还在用 Node 20,被强制跑在 Node 24 上。现在只是警告、不影响运行,但 GitHub 在淘汰 Node 20,早晚要升。趁早升掉,日志干净、也不用等哪天真跑不了才手忙脚乱。

## 做什么

把用到的官方 action 升到跑 Node 24 的大版本。验收条件:

- [ ] 四个工作流里的 `actions/checkout@v4` → `@v5`。
- [ ] `actions/upload-artifact@v4` / `actions/download-artifact@v4` → `@v5`(或当时最新且跑 Node 24 的版本)。
- [ ] actionlint 过。
- [ ] 手动触发一次(比如 ① 的 workflow_dispatch)确认没了那批警告、且跑通。

## 涉及文件

- `.github/workflows/hermes-release-watch.yml`
- `.github/workflows/hermes-assess-plan.yml`
- `.github/workflows/hermes-sync.yml`
- `.github/workflows/hermes-audit.yml`

## 备注

- 升 upload/download-artifact 大版本时留意:v4 和更早版本的 artifact 不互通,但本项目只在同一次运行内上传+下载,不跨版本,应该无碍——升完验证一下 finalize 能正常拿到各 matrix 分支的产出。
