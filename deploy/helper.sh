#!/usr/bin/env bash

: "${AGENT_KEY:=$DOWNLOAD_KEY}"
: "${HELM_INSTALL_TIMEOUT:=1200s}"
: "${HELM_UNINSTALL_TIMEOUT:=300s}"
: "${K8S_READINESS_TIMEOUT:=900s}"
: "${REGISTRY_URL:=artifact-public.instana.io}"
: "${REGISTRY_USERNAME:=_}"
: "${REGISTRY_PASSWORD:=$DOWNLOAD_KEY}"
: "${HELM_REPO_URL:=https://artifact-public.instana.io/artifactory/rel-helm-customer-virtual}"
: "${HELM_REPO_USERNAME:=_}"
: "${HELM_REPO_PASSWORD:=$DOWNLOAD_KEY}"
: "${DELETE_NAMESPACE_WHEN_UNINSTALL:=false}"

info() {
  echo '[INFO] ' "$@"
}

warn() {
  echo '[WARN] ' "$@" >&2
}

error() {
  echo '[ERROR] ' "$@" >&2
  exit 1
}

helm_repo_add() {
  info "Adding helm repo..."
  helm repo add instana "$HELM_REPO_URL" --username "$HELM_REPO_USERNAME" --password "$HELM_REPO_PASSWORD" --force-update >/dev/null
  helm repo update >/dev/null
}

helm_repo_remove() {
  info "Removing helm repo ..."
  helm repo remove instana >/dev/null
}

helm_upgrade() {
  local release_name=$1
  local chart_name=$2
  local namespace=$3
  local version=$4
  local extra_args=("${@:5}") # Capture all remaining arguments as an array

  info "Installing $release_name in $namespace namespace..."

  helm upgrade --wait --wait-for-jobs --timeout "${HELM_INSTALL_TIMEOUT}" --install "$release_name" "$chart_name" -n "$namespace" \
    --version "$version" "${extra_args[@]}" >/dev/null
}

helm_uninstall() {
  local release_name=$1
  local namespace=$2

  info "Uninstalling $release_name in $namespace namespace..."

  helm uninstall --ignore-not-found --wait --timeout "${HELM_UNINSTALL_TIMEOUT}" "$release_name" -n "$namespace" >/dev/null
}

verify_non_empty() {
  if [ -z "$2" ]; then
    error "$1 must not be empty."
  fi
}

get_secret_password() {
  kubectl get secret "$1" -n "$2" --template='{{index .data.password | base64decode}}'
}

generate_helm_file_arguments() {
  local component=$1
  local file_args=()

  # Check and append file arguments if the files exist
  file_args+=("--values=values/${component}/instana_values.yaml")

  if [ -f "values/${component}/instana_values_${CLUSTER_TYPE}.yaml" ]; then
    file_args+=("--values=values/${component}/instana_values_${CLUSTER_TYPE}.yaml")
  fi

  if [ -f "values/${component}/custom_values.yaml" ]; then
    file_args+=("--values=values/${component}/custom_values.yaml")
  fi

  # Output as a space-separated string
  echo "${file_args[@]}"
}

generate_extra_args() {
  local component=$1

  if [ -x ./"${CLUSTER_TYPE}".sh ]; then
    ./"${CLUSTER_TYPE}".sh generate_"${component}"_extra_args
  else
    echo ""
  fi
}

get_default_storageclass() {
  kubectl get storageclass --output=jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{end}'
}

check_storage() {
  scs=$(kubectl get sc 2>/dev/null | grep -vc NAME || true)
  defaultsc=$(get_default_storageclass)

  if [ "$scs" == "0" ]; then
    error "No storage class found, you must install storage class in advance. "
  else
    if [ "$defaultsc" == "" ]; then
      error "No default storage class set, you must set default storage class in advance. "
    fi
  fi
}

check_cr_condition() {
  local namespace=$1
  local cr_type=$2
  local cr_name=$3
  local condition=$4

  info "Checking $cr_name for condition $condition in namespace $namespace..."
  if kubectl wait "$cr_type" "$cr_name" --for="condition=$condition" --timeout="${K8S_READINESS_TIMEOUT}" -n "$namespace"; then
    echo "$cr_name in $namespace is ready."
  else
    error "$cr_name in $namespace is not ready."
  fi
}

wait_for_k8s_object() {
  local object_type="$1"
  local object_name="$2"
  local namespace="$3"

  local end_time=$(($(date +%s) + ${K8S_READINESS_TIMEOUT%s}))
  local current_time

  info "Waiting for $object_type/$object_name in namespace $namespace..."
  while true; do
    if kubectl get "$object_type"/"$object_name" -n "$namespace" &>/dev/null; then
      info "$object_type/$object_name is ready."
      break
    else
      info "Waiting for $object_type/$object_name in namespace $namespace..."
    fi

    current_time=$(date +%s)
    if [[ $current_time -ge $end_time ]]; then
      error "Timed out while waiting for $object_type/$object_name in namespace $namespace."
    fi
    sleep 10
  done
}

wait_status_for_k8s_object() {
  local object_type="$1"
  local object_name="$2"
  local namespace="$3"
  local status_to_check="$4"
  local status_expect="$5"

  local end_time=$(($(date +%s) + ${K8S_READINESS_TIMEOUT%s}))
  local current_time

  info "Waiting for $object_type/$object_name status '$status_to_check' to be '$status_expect' in namespace $namespace..."
  while true; do
    status=$(kubectl get "$object_type" "$object_name" -n "$namespace" -o jsonpath="{$status_to_check}" 2>/dev/null)
    if [[ "$status" == "$status_expect" ]]; then
      info "$object_type/$object_name status '$status_to_check' in $namespace is ready."
      break
    else
      info "Waiting for $object_type/$object_name status '$status_to_check' to be '$status_expect' in namespace $namespace..."
    fi

    current_time=$(date +%s)
    if [[ $current_time -ge $end_time ]]; then
      error "Timed out while waiting for $object_type/$object_name status' $status_to_check' in namespace $namespace."
    fi

    sleep 10
  done
}

check_pods_ready() {
  local namespace=$1
  local label=$2
  local end_time=$(($(date +%s) + ${K8S_READINESS_TIMEOUT%s}))
  local pods current_time

  info "Waiting for readiness of pods in namespace $namespace..."
  while true; do
    pods=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -z "$pods" ]; then
      info "No pods found with label $label in namespace $namespace. Waiting..."
    else
      if kubectl wait --for=condition=ready pod -l "$label" --namespace="$namespace" --timeout="10s" &>/dev/null; then
        info "Pods in namespace $namespace are ready."
        return 0
      else
        info "Waiting for readiness of pods in namespace $namespace..."
      fi
    fi

    current_time=$(date +%s)
    if [[ $current_time -ge $end_time ]]; then
      error "Timed out while waiting for pods to be ready in namespace $namespace with label $label."
    fi
    # Only need to wait for beeinstana pods usually, which takes several minutes to be ready
    sleep 10
  done
}

create_namespace_if_not_exist() {
  local ns=$1
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    kubectl create namespace "$ns"
  fi
}

delete_namespace() {
  if [ "$DELETE_NAMESPACE_WHEN_UNINSTALL" == "true" ]; then
    local namespace=$1

    info "Deleting ${namespace} namespace..."
    kubectl delete namespace "$namespace" --ignore-not-found --wait=true
  fi
}
