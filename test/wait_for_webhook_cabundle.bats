#!/usr/bin/env bats

load _helpers

setup() {
  source_repo_scripts
  export K8S_READINESS_TIMEOUT=10s
}

@test "succeeds once caBundle is populated" {
  WEBHOOK_NAME_UNDER_TEST="my-webhook"
  WEBHOOK_TYPE_UNDER_TEST="validatingwebhookconfigurations"
  KUBECTL_MODE="success_after_empty"

  setup_kubectl_cabundle_stub "$KUBECTL_MODE" "$WEBHOOK_NAME_UNDER_TEST" "$WEBHOOK_TYPE_UNDER_TEST"

  if output=$(wait_for_webhook_cabundle "validatingwebhookconfigurations" "my-webhook" 2>&1); then
    status=0
  else
    status=$?
  fi

  [[ "$status" -eq 0 ]]
  [[ $(cat "$KUBECTL_CALLS_FILE") -ge 2 ]]
  [[ "$output" == *"caBundle injection detected"* ]]
}

@test "times out when caBundle never appears" {
  WEBHOOK_NAME_UNDER_TEST="my-webhook"
  WEBHOOK_TYPE_UNDER_TEST="validatingwebhookconfigurations"
  KUBECTL_MODE="always_empty"

  setup_kubectl_cabundle_stub "$KUBECTL_MODE" "$WEBHOOK_NAME_UNDER_TEST" "$WEBHOOK_TYPE_UNDER_TEST"

  if output=$(wait_for_webhook_cabundle "validatingwebhookconfigurations" "my-webhook" 2>&1); then
    status=0
  else
    status=$?
  fi

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Timed out waiting for caBundle injection"* ]]
}
