#!/usr/bin/env bash

# Common helpers for Bats tests

repo_root() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd
}

source_repo_scripts() {
  local root
  root="$(repo_root)"
  # shellcheck source=/dev/null
  source "$root/deploy/helper.sh"
  # shellcheck source=/dev/null
  source "$root/deploy/datastores.sh"
}

# Prepare a kubectl stub for caBundle polling tests.
# Args:
#   1: mode (success_after_empty | always_empty)
#   2: webhook name
#   3: webhook type (validatingwebhookconfigurations | mutatingwebhookconfigurations)
setup_kubectl_cabundle_stub() {
  export KUBECTL_MODE="$1"
  export WEBHOOK_NAME_UNDER_TEST="$2"
  export WEBHOOK_TYPE_UNDER_TEST="$3"
  export KUBECTL_CALLS_FILE="$BATS_TEST_TMPDIR/kubectl_calls"
  : >"$KUBECTL_CALLS_FILE"

  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MODE="${KUBECTL_MODE:-}"
NAME="${WEBHOOK_NAME_UNDER_TEST:-}"
TYPE="${WEBHOOK_TYPE_UNDER_TEST:-}"
CALLS_FILE="${KUBECTL_CALLS_FILE:-}"

calls=0
if [[ -n "$CALLS_FILE" && -f "$CALLS_FILE" ]]; then
  calls=$(cat "$CALLS_FILE")
fi

if [[ $1 == "get" && $2 == "$TYPE" && $3 == "$NAME" ]]; then
  calls=$((calls + 1))
  if [[ -n "$CALLS_FILE" ]]; then
    echo "$calls" >"$CALLS_FILE"
  fi

  case "$MODE" in
  success_after_empty)
    if [[ $calls -eq 1 ]]; then
      printf '\n'
    else
      printf 'abc123\n'
    fi
    exit 0
    ;;
  always_empty)
    printf '\n'
    exit 0
    ;;
  esac
fi

echo "unexpected kubectl call: $*" >&2
exit 1
EOF

  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  PATH="$BATS_TEST_TMPDIR:$PATH"
}
