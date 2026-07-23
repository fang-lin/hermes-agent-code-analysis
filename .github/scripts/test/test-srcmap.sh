#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/srcmap.sh"
map="$here/../../chapter-source-map.yml"

assert_eq "05" "$(chapters_for_path "$map" "gateway/router.py")" "gateway 归 05"
assert_eq "01" "$(chapters_for_path "$map" "hermes_cli/main.py")" "hermes_cli 归 01"
assert_eq "14" "$(chapters_for_path "$map" "apps/desktop/electron/main.cjs")" "desktop 归 14"
path_is_covered "$map" "gateway/x.py"; assert_eq "0" "$?" "gateway 有覆盖"
path_is_covered "$map" "brand_new_module/x.py"; assert_eq "1" "$?" "全新模块无覆盖=缺口"

# 目录前缀必须按段匹配,不能靠字符串前缀"蹭"到同名开头的兄弟目录/新模块
assert_eq "02" "$(chapters_for_path "$map" "hermes_agent/agent/loop.py")" "hermes_agent/agent/ 仍归 02"
assert_eq "" "$(chapters_for_path "$map" "hermes_agent/agent_new_module/x.py")" \
  "hermes_agent/agent_new_module 是全新模块,不该被 hermes_agent/agent 前缀蹭到,应判缺口"
assert_eq "" "$(chapters_for_path "$map" "hermes_agent/agents/registry.py")" \
  "hermes_agent/agents 是兄弟目录,不该被 hermes_agent/agent 前缀蹭到"
echo "test-srcmap: PASS"
