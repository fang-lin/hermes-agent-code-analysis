# should_bump_pin <cycle> —— 同步循环合并要 bump pin,复核循环不 bump。
should_bump_pin() {
  case "$1" in
    sync)  return 0 ;;
    audit) return 1 ;;
    *)     echo "unknown cycle: $1" >&2; return 2 ;;
  esac
}
