# 08-Cron/ACP/MCP — 原始数据暂存

> 关键行号：
> Cron:
> - cron/jobs.py: 503-535(Job dict), 123-209(调度解析), 290-325(next_run_at), 37(存储路径)
> - cron/scheduler.py: 1197-1354(tick), 777-1195(run_job), 302-486(deliver), 634(_build_job_prompt), 115(SILENT), 44-72(toolsets), 120-122(文件锁)
> - tools/cronjob_tools.py: 225(工具注册点), 40-68(_scan_cron_prompt), 153-189(_validate_script_path), 71-88(_origin_from_env), 536-548(check_requirements), 554-581(register)
>
> ACP:
> - acp_adapter/entry.py: main()
> - acp_adapter/server.py: 102(HermesACPAgent), 322(initialize), 380(new_session), 501-678(prompt执行), 876(set_session_model)
> - acp_adapter/events.py: tool/thinking/step/message 回调
> - acp_adapter/tools.py: 21-51(TOOL_KIND_MAP)
> - acp_adapter/permissions.py: approval桥接
> - acp_adapter/session.py: SessionManager, _restore(), _register_task_cwd
> - acp_registry/agent.json: 元数据
>
> MCP serve:
> - mcp_serve.py: 452-809(10个工具), 185-425(EventBridge), 200ms轮询+mtime比较
