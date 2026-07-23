你是 hermes-agent 文档的维护者。严格照下面这份 work plan 逐条修改文档和 skill 锚点,不要多改、不要少改。

这次要改的 work plan 是一个 JSON 数组,存在文件 ${PLAN_FILE} 里。先读这个文件拿到全部条目,再逐条修改。

真实源码已拉到 ./hermes-agent/ 目录(该目录含 run_agent.py);所有源码引用/grep/read 都用这个路径,例如 hermes-agent/gateway/run.py。

要求:
1. 逐条按 `位置` 定位到 `docs/` 或 `.claude/skills/` 里的文件,把 `现状` 改成 `改成什么`。
2. 每条改动都要先用 grep 到当前 pin(${PIN})的真实源码里核对 `源码依据`,确认无误再改。
3. 如果同一处的锚点行号变了,顺手更新 `.claude/skills/hermes-agent-expert/scripts/anchors.txt`。
4. 只改 work plan 点到的地方。改完不要自己提交、不要开 PR——外层脚本会处理。
