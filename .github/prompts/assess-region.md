你在评估 hermes-agent 从 ${PIN} 到 ${NEW_TAG} 的一版改动,对某一文档区域(${REGION})的影响。

这个区域涉及的改动文件:
${FILES}

材料:上面这些文件的 diff 片段,以及该区域当前的文档原文(在 docs/ 里,章号见 ${REGION})。

真实源码已拉到 ./hermes-agent/ 目录(该目录含 run_agent.py);所有源码引用/grep/read 都用这个路径,例如 hermes-agent/gateway/run.py。

请一次判断两样:
1. 复杂度,四选一并说明理由:none(文档说法没受影响)/ cosmetic(只是行号挪了)/ shallow(几处事实或锚点要更新)/ deep(行为或架构变了,得重读源码)。
2. 规划:列出具体要改的每一处(位置、现状、改成什么、源码依据 文件:行:符号、类型)。deep 的可以给粗清单。

若 ${REGION} 是 "gap"(覆盖缺口,即这些是没有任何章覆盖的新代码):判断要不要开新文档——够大够独立→新开一章(类型 new-chapter),现有某章容得下→加一节(new-section),小工具/配置→加锚点(new-anchor),无关紧要→plan_items 留空、complexity 记 none。

**输出**:把结果写成符合 schema ${SCHEMA} 的 JSON 到 ${OUT}。只写这个文件。
