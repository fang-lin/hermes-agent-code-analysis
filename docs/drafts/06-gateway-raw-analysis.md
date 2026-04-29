# 06-Gateway — 原始数据暂存

> 关键行号：
> - run.py: 620(GatewayRunner), 41-42(cache 128/3600s), 643(__init__), 682-710(状态), 2129(start), 2761(stop), 3383(_handle_message), 2472(expiry watcher), 2634(reconnect watcher), 2112(request_restart), 3017(_create_adapter)
> - base.py: 1121(BasePlatformAdapter), 1325(connect), 1334(disconnect), 1339(send), 1368(edit_message), 2221(handle_message), 2414-2510(响应管道), 1618(extract_media), 1477(extract_images)
> - session.py: 70(SessionSource), 413(SessionEntry), 572(build_session_key), 716(_generate_session_key), 762(_should_reset), 828(get_or_create_session)
> - config.py: 101(SessionResetPolicy), 192(StreamingConfig)
> - stream_consumer.py: 57(GatewayStreamConsumer), 159(on_delta), 281(run), 333-379(长消息拆分), 183(think block过滤)
> - cron/scheduler.py: 777(run_job), 302(_deliver_result), 236(_resolve_delivery_targets), 634(_build_job_prompt), 115(SILENT)
> - cron/jobs.py: 37(存储路径)
