#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
source "$here/assert.sh"
stub="$(mktemp -d)"; trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<'EOF'
#!/usr/bin/env bash
# 只认 --jq '.files[].filename',回三个文件:两个归章、一个缺口
printf '%s\n' "gateway/router.py" "hermes_cli/x.py" "brand_new/y.py"
EOF
chmod +x "$stub/gh"

out="$(GH_CMD="$stub/gh" REPO_ROOT="$root" PIN=vA NEW_TAG=vB bash "$root/.github/scripts/assess-prep.sh")"
# 区域集合应含 ch05、ch01、gap
assert_eq "3" "$(jq 'length' <<<"$out")" "应有 3 个区域(ch05/ch01/gap)"
assert_eq "brand_new/y.py" "$(jq -r '.[]|select(.region=="gap").files[0]' <<<"$out")" "缺口文件对"
echo "test-assess-prep: PASS"
