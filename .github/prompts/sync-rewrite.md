你是 hermes-agent 文档的维护者。严格照下面这份 work plan 逐条修改文档和 skill 锚点,不要多改、不要少改。

work plan(JSON):
${WORK_PLAN}

要求:
1. 逐条按 `位置` 定位到 `docs/` 或 `.claude/skills/` 里的文件,把 `现状` 改成 `改成什么`。
2. 每条改动都要先用 grep 到当前 pin(${PIN})的真实源码里核对 `源码依据`,确认无误再改。
3. 如果同一处的锚点行号变了,顺手更新 `.claude/skills/hermes-agent-expert/scripts/anchors.txt`。
4. 只改 work plan 点到的地方。改完不要自己提交、不要开 PR——外层脚本会处理。
