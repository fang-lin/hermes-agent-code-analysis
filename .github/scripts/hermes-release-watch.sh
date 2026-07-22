#!/usr/bin/env bash
set -uo pipefail
# ① 新版本检测:比 NousResearch/hermes-agent 的最新 release 和 .hermes-pin。
# 相同 → UPTODATE;更新 → NEW <tag>。纯脚本、不花 token、不碰 diff、不动 pin。
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
GH="${GH_CMD:-gh}"
pin="${HERMES_PIN_TAG:-$(grep '^tag=' "$ROOT/.hermes-pin" | cut -d= -f2)}"
latest="${HERMES_LATEST:-$("$GH" api repos/NousResearch/hermes-agent/releases/latest --jq .tag_name)}"
if [ "$latest" = "$pin" ]; then
  echo "UPTODATE ($pin)"
else
  echo "NEW $latest"
fi
