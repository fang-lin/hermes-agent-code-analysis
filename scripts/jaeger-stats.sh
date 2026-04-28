#!/bin/bash
# 从 Jaeger 查询 Claude Code 遥测数据
# 用法: ./scripts/jaeger-stats.sh [分钟数，默认30]

MINUTES=${1:-30}
JAEGER_URL="http://localhost:16686"
SERVICE="claude-code"

START=$(date -u -v-${MINUTES}M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${MINUTES} minutes ago" +"%Y-%m-%dT%H:%M:%SZ")
END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

curl -s "${JAEGER_URL}/api/v3/traces?query.service_name=${SERVICE}&query.num_traces=200&query.start_time_min=${START}&query.start_time_max=${END}" | python3 -c "
import json, sys

data = json.load(sys.stdin)

llm_requests = []
tools = []
blocked = []
tool_exec = []

for rs in data.get('result', {}).get('resourceSpans', []):
    for ss in rs.get('scopeSpans', []):
        for span in ss.get('spans', []):
            name = span.get('name', '')
            attrs = {}
            for a in span.get('attributes', []):
                v = a['value']
                val = v.get('stringValue') or v.get('intValue') or v.get('doubleValue')
                attrs[a['key']] = val

            if name == 'claude_code.llm_request':
                llm_requests.append(attrs)
            elif name == 'claude_code.tool':
                tools.append(attrs)
            elif name == 'claude_code.tool.blocked_on_user':
                blocked.append(attrs)
            elif name == 'claude_code.tool.execution':
                tool_exec.append(attrs)

# LLM 汇总
total_input = sum(int(r.get('input_tokens', 0)) for r in llm_requests)
total_output = sum(int(r.get('output_tokens', 0)) for r in llm_requests)
total_cache_read = sum(int(r.get('cache_read_tokens', 0)) for r in llm_requests)
total_cache_create = sum(int(r.get('cache_creation_tokens', 0)) for r in llm_requests)
total_duration = sum(int(r.get('duration_ms', 0)) for r in llm_requests)
ttfts = [int(r.get('ttft_ms', 0)) for r in llm_requests if r.get('ttft_ms')]
avg_ttft = sum(ttfts) // len(ttfts) if ttfts else 0
models = set(r.get('model', 'unknown') for r in llm_requests)

# 工具汇总
tool_counts = {}
for t in tools:
    tn = t.get('tool_name', 'unknown')
    tool_counts[tn] = tool_counts.get(tn, 0) + 1
tool_total_ms = sum(int(t.get('duration_ms', 0)) for t in tools)

# 等待用户汇总
blocked_total_ms = sum(int(b.get('duration_ms', 0)) for b in blocked)

print('## Jaeger 遥测统计')
print()
print(f'- **时间范围**: 最近 {${MINUTES}} 分钟')
print(f'- **模型**: {\", \".join(models)}')
print()
print('### LLM 请求')
print(f'- 请求次数: {len(llm_requests)}')
print(f'- Input tokens: {total_input:,}')
print(f'- Output tokens: {total_output:,}')
print(f'- Cache read tokens: {total_cache_read:,}')
print(f'- Cache creation tokens: {total_cache_create:,}')
print(f'- **总 tokens: {total_input + total_output + total_cache_read + total_cache_create:,}**')
print(f'- LLM 总耗时: {total_duration / 1000:.1f}s')
print(f'- 平均 TTFT: {avg_ttft}ms')
print()
print('### 工具调用')
print(f'- 总调用次数: {len(tools)}')
print(f'- 工具总耗时: {tool_total_ms / 1000:.1f}s')
for tn, cnt in sorted(tool_counts.items(), key=lambda x: -x[1]):
    print(f'  - {tn}: {cnt} 次')
print()
print('### 等待用户审批')
print(f'- 次数: {len(blocked)}')
print(f'- 总等待时间: {blocked_total_ms / 1000:.1f}s')
"
