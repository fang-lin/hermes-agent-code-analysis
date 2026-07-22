# 极简断言:相等则静默,不等则报错退出。供各 test-*.sh source。
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "ASSERT FAIL: ${msg}"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    exit 1
  fi
}
