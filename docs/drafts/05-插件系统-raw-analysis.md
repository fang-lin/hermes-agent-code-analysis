# 05-插件系统 — 分析 Agent 原始数据

> 暂存。关键行号：
> - hermes_cli/plugins.py: 60-96(VALID_HOOKS), 161-191(PluginManifest), 210-511(PluginContext), 518+(PluginManager), 573-575(skip memory/context_engine), 596-656(加载规则), 679-692(两种布局), 1085-1121(pre_tool_call veto)
> - plugins/context_engine/__init__.py: 33-76(discover), 79-97(load), 175-194(两种模式)
> - plugins/memory/__init__.py: 50-63(启发式识别), 66-97(两级扫描), 122-156(discover), 159-181(load), 195(user模块名前缀), 264-282(_ProviderCollector), 322-406(CLI发现)
> - agent/memory_manager.py: 207(最多一个), 267(build_system_prompt), 288(prefetch_all), 320(sync_all), 406(on_pre_compress), 451(on_memory_write), 481(on_delegation), 495(shutdown)
> - agent/memory_provider.py: 42-241(MemoryProvider ABC)
> - plugins/memory/honcho: 204(recall_mode), 330-341(lazy session), 722-774(开销感知), 825-831(指数退避), 949-989(dialectic深度), 1153-1181(内置记忆镜像)
