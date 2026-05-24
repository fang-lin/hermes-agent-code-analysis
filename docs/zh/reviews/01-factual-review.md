# 事实审核报告：01-基础设施层

## 审核摘要

- 检查断言数：32
- ✅ 通过：22
- ⚠️ 存疑：4
- ❌ 错误：6

## 修正汇总

| 项目 | 修正前 | 修正后 |
|------|--------|--------|
| DEFAULT_CONFIG 大小 | 约 200 行，约 15 个顶层分组 | 1289 行，约 60 个顶层 key |
| resolve_alias 别名来源 | ~/.hermes/model_aliases.yaml | config.yaml 的 model_aliases: 节 |
| 认证方式数 | 5 种 | 6 种（加 external_process） |
| 内置皮肤 | 6 个（ocean/forest/void/sakura 等） | 9 个（default/ares/mono/slate/daylight/warm-lightmode/poseidon/sisyphus/charizard） |
| _model_flow_* 数量 | 约 30 个 | 约 19 个 |
| VALID_HOOKS | 18 种 | 17 种 |
| COMMAND_REGISTRY | 约 120 个 | 约 70 个（含别名约 90） |
