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

# 输出必须是单行 JSON(files 子数组若用 jq -s 会被 pretty-print 成多行,写进
# GITHUB_OUTPUT 就会截断/破坏 matrix 输入)
case "$out" in *$'\n'*) echo "FAIL: 输出含换行,不是单行 JSON"; exit 1;; esac

# gh 调用失败时必须大声失败,不能悄悄输出 []
cat > "$stub/gh-fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$stub/gh-fail"
GH_CMD="$stub/gh-fail" REPO_ROOT="$root" PIN=vA NEW_TAG=vB bash "$root/.github/scripts/assess-prep.sh" >/dev/null 2>&1
assert_eq "1" "$?" "gh 失败应退出非0,不能输出 []"

# kill-switch:sync-policy.enabled=false 时应直接输出 [],不调用 gh
polfile="$stub/policy-off.yml"
cat > "$polfile" <<'EOF'
enabled: false
EOF
out_off="$(GH_CMD="$stub/gh" REPO_ROOT="$root" POLICY_FILE="$polfile" PIN=vA NEW_TAG=vB bash "$root/.github/scripts/assess-prep.sh")"
assert_eq "[]" "$out_off" "sync-policy.enabled=false 时应输出 []"

echo "test-assess-prep: PASS"
