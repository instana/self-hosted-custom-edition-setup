#!/usr/bin/env bash
set -o errexit

validate_k8s_access() {
  info "Checking if Kubernetes cluster is accessible..."
  kubectl get node >/dev/null 2>&1 || error "You must be logged in to the Kubernetes server before running this tool."
}

validate_cluster_type() {
  if [ -z "$CLUSTER_TYPE" ]; then
    error "Cluster type is not set. Please set the CLUSTER_TYPE environment variable to one of the following: ocp, eks, aks, gke, or k8s."
  else
    CLUSTER_TYPE=$(echo "$CLUSTER_TYPE" | tr '[:upper:]' '[:lower:]')
    if ! echo "$CLUSTER_TYPE" | grep -Ew "ocp|k8s|eks|aks|gke" >/dev/null; then
      error "Invalid CLUSTER_TYPE: $CLUSTER_TYPE. It must be set to one of the following: ocp, eks, aks, gke, or k8s."
    fi
    info "CLUSTER_TYPE is set to $CLUSTER_TYPE."
  fi
}

validate_config() {
  info "Validating configuration..."

  verify_non_empty "DOWNLOAD_KEY" "$DOWNLOAD_KEY"
  verify_non_empty "SALES_KEY" "$SALES_KEY"
  verify_non_empty "INSTANA_UNIT_NAME" "$INSTANA_UNIT_NAME"
  verify_non_empty "INSTANA_TENANT_NAME" "$INSTANA_TENANT_NAME"
    # Check YAML config keys
  local yaml_file="values/core/custom-values.yaml"
  [ ! -f "$yaml_file" ] && yaml_file="values/core/instana-values.yaml"
  info "Validating YAML config file: $yaml_file"
  verify_yaml_key_or_host_port_non_empty "$yaml_file" "baseDomain" "baseDomain"
  verify_yaml_key_or_host_port_non_empty "$yaml_file" "acceptors.agent" "agent acceptor"
}

precheck() {
  if [ ! -f ./config.env ]; then
    error "Customer configuration file 'config.env' is not found."
  fi

  validate_cluster_type
  validate_k8s_access
  validate_config
  check_storage
}

install_cert_manager() {
  create_namespace_if_not_exist cert-manager
  install_instana_registry cert-manager

  helm_upgrade "cert-manager" "instana/cert-manager" "cert-manager" "${CERT_MANAGER_VERSION}" \
    --set-string image.registry="${REGISTRY_URL}" \
    --set-string image.repository="jetstack/cert-manager-controller" \
    --set-string webhook.image.registry="${REGISTRY_URL}" \
    --set-string webhook.image.repository="jetstack/cert-manager-webhook" \
    --set-string cainjector.image.registry="${REGISTRY_URL}" \
    --set-string cainjector.image.repository="jetstack/cert-manager-cainjector" \
    --set-string acmesolver.image.registry="${REGISTRY_URL}" \
    --set-string acmesolver.image.repository="jetstack/cert-manager-acmesolver" \
    --set-string startupapicheck.image.registry="${REGISTRY_URL}" \
    --set-string startupapicheck.image.repository="jetstack/cert-manager-startupapicheck" \
    -f values/cert-manager/instana-values.yaml
}

uninstall_cert_manager() {
  helm_uninstall "cert-manager" "cert-manager"
  helm_uninstall "instana-registry" "cert-manager"

  delete_namespace "cert-manager"
}

install_instana_registry() {
  local ns=$1
  helm_upgrade "instana-registry" "instana/instana-registry" "$ns" "${INSTANA_REGISTRY_CHART_VERSION}" \
    --set-string url="${REGISTRY_URL}" \
    --set-literal username="${REGISTRY_USERNAME}" \
    --set-literal password="${REGISTRY_PASSWORD}"
}

install_instana_operator() {
  info "Installing Instana operator..."

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments instana-operator)"

  create_namespace_if_not_exist instana-operator
  install_instana_registry instana-operator

  helm_upgrade "instana-enterprise-operator" "instana/instana-enterprise-operator" "instana-operator" "${INSTANA_OPERATOR_CHART_VERSION}" \
    --set-string image.registry="${REGISTRY_URL}" \
    --set-string operator.image.registry="${REGISTRY_URL}" \
    --set-string operator.image.repository="infrastructure/instana-enterprise-operator" \
    --set-string webhook.image.registry="${REGISTRY_URL}" \
    --set-string webhook.image.repository="infrastructure/instana-enterprise-operator-webhook" \
    "${file_args[@]}"

  check_pods_ready "instana-operator" "app.kubernetes.io/name=instana"
}

get_yaml_value() {
  local component="$1"
  local key="$2"
  local value

  local custom_yaml="values/${component}/custom-values.yaml"
  local default_yaml="values/${component}/instana-values.yaml"

  if [ -f "$custom_yaml" ]; then
    value=$(yq e "$key" "$custom_yaml")
  fi

  if [[ "$value" == "null" || -z "$value" ]]; then
    value=$(yq e "$key" "$default_yaml")
  fi

  echo "$value"
}

BASE_DOMAIN=$(get_yaml_value "core" ".baseDomain")
AGENT_ACCEPTOR=$(get_yaml_value  "core" ".acceptors.agent.host")
IS_GATEWAY_V2_ENABLED=$(get_yaml_value "core" ".gatewayConfig.enabled")
INSTANA_ADMIN_USER=$(get_yaml_value "unit" ".initialAdminUser")

create_instana_routes() {
  if [ "$CLUSTER_TYPE" != "ocp" ]; then
    return
  fi

  info "Creating routes..."

  local GATEWAY_SERVICE="gateway"
  if [[ "$IS_GATEWAY_V2_ENABLED" == "true" ]]; then
    GATEWAY_SERVICE="gateway-v2"
  fi

  # create UI routes
  oc create route passthrough ui-client-tenant \
    --hostname="${INSTANA_UNIT_NAME}-${INSTANA_TENANT_NAME}.${BASE_DOMAIN}" \
    --service="$GATEWAY_SERVICE" \
    --port=https \
    -n instana-core

  oc create route passthrough ui-client-ssl \
    --hostname="${BASE_DOMAIN}" \
    --service="$GATEWAY_SERVICE" \
    --port=https \
    -n instana-core

  # optionally create agent acceptor route
  if [ -n "$AGENT_ACCEPTOR" ]; then
    local ACCEPTOR_SERVICE_NAME="acceptor"
    local ACCEPTOR_SERVICE_PORT="http-service"
    if [[ "$IS_GATEWAY_V2_ENABLED" == "true" ]]; then
      # if gateway-v2 is enabled send agent traffic to gateway-v2
      ACCEPTOR_SERVICE_NAME="gateway-v2"
      ACCEPTOR_SERVICE_PORT="https"
    fi

    oc create route passthrough acceptor \
      --hostname="${AGENT_ACCEPTOR}" \
      --service="$ACCEPTOR_SERVICE_NAME" \
      --port="$ACCEPTOR_SERVICE_PORT" \
      -n instana-core
  else
    info "AGENT_ACCEPTOR not set, skipping acceptor route."
  fi
}

delete_instana_routes() {
  if [ "$CLUSTER_TYPE" != "ocp" ]; then
    return
  fi

  info "Delete routes..."
  oc delete route ui-client-tenant --ignore-not-found -n instana-core
  oc delete route ui-client-ssl --ignore-not-found -n instana-core
  oc delete route acceptor --ignore-not-found -n instana-core
}

install_instana_core() {
  info "Installing Instana core..."

  create_namespace_if_not_exist instana-core
  kubectl label ns/instana-core app.kubernetes.io/name=instana-core
  install_instana_registry instana-core

  if [ "$CLUSTER_TYPE" == "aks" ]; then

    # Create the secret for Azure storage account
    kubectl create secret generic azure-storage-account \
      --from-literal=azurestorageaccountname="${AZURE_STORAGE_ACCOUNT}" \
      --from-literal=azurestorageaccountkey="${AZURE_STORAGE_ACCOUNT_KEY}" \
      -n instana-core

    # Check if capacity is provided, else default to 100Gi
    CAPACITY="${AZURE_STORAGE_CAPACITY:-100Gi}"

    # Apply the PersistentVolume definition
    sed "s/{{AZURE_STORAGE_FILESHARE_NAME}}/${AZURE_STORAGE_FILESHARE_NAME}/g; s/{{AZURE_STORAGE_CAPACITY}}/${CAPACITY}/g" ./values/core/pv_template_aks.yaml | kubectl apply -f -
  fi

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments core)"
  #gateway cnfiguration checks
  HELM_ARGS=()

  if [ "$IS_GATEWAY_V2_ENABLED" == "true" ] && [ -n "$REGISTRY_URL" ]; then
    HELM_ARGS+=(
      --set-string gatewayConfig.gateway.imageConfig.registry="${REGISTRY_URL}"
      --set-string gatewayConfig.controller.imageConfig.registry="${REGISTRY_URL}"
    )
  fi

  helm_upgrade "instana-core" "instana/instana-core" "instana-core" "${INSTANA_CORE_CHART_VERSION}" \
    --set-string imageConfig.registry="${REGISTRY_URL}" \
    --set-literal salesKey="${SALES_KEY}" \
    --set-literal repositoryPassword="${DOWNLOAD_KEY}" \
    "${HELM_ARGS[@]}" \
    "${file_args[@]}"

  check_instana_backend_ready "instana-core" "core" "instana-core"
}

install_instana_unit() {
  info "Installing Instana unit..."

  create_namespace_if_not_exist instana-units
  kubectl label ns/instana-units app.kubernetes.io/name=instana-units
  install_instana_registry instana-units

  info "Downloading the license file to license ..."
  license_content=$(curl -H "Content-Type: text/plain" -s "https://instana.io/onprem/license/download?salesId=$SALES_KEY")

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments unit)"

  helm_upgrade "${INSTANA_UNIT_NAME}-${INSTANA_TENANT_NAME}" "instana/instana-unit" "instana-units" "${INSTANA_UNIT_CHART_VERSION}" \
    --set tenantName="${INSTANA_TENANT_NAME}" \
    --set unitName="${INSTANA_UNIT_NAME}"\
    --set licenses="{$license_content}" \
    --set agentKeys="{$AGENT_KEY}" \
    --set-literal downloadKey="$DOWNLOAD_KEY" \
    --set-string cleanupJob.image.registry="${REGISTRY_URL}" \
    "${file_args[@]}"

  check_instana_backend_ready "instana-units" "unit" "${INSTANA_UNIT_NAME}-${INSTANA_TENANT_NAME}"
}

check_instana_backend_ready() {
  local namespace=$1
  local cr_type=$2
  local cr_name=$3

  wait_for_k8s_object "$cr_type" "$cr_name" "$namespace"
  wait_status_for_k8s_object "$cr_type" "$cr_name" "$namespace" ".status.dbMigrationStatus" "Ready"
  wait_status_for_k8s_object "$cr_type" "$cr_name" "$namespace" ".status.componentsStatus" "Ready"
}

uninstall_instana_core() {
  info "Uninstalling Instana core..."

  # Get all CRs of type 'core' in the 'instana-core' namespace
  for core in $(kubectl get core -n instana-core -o jsonpath='{.items[*].metadata.name}'); do
    # Patch each core to remove the finalizers, otherwise 'helm uninstall' hangs forever
    kubectl patch core "$core" -n instana-core --type=merge -p '{"metadata":{"finalizers":[]}}'

    helm_uninstall "$core" "instana-core"
  done

  helm_uninstall "instana-registry" "instana-core"

  if [ "$CLUSTER_TYPE" == "aks" ]; then
    # Check if the Azure storage account secret exists, then delete it
    kubectl get secret azure-storage-account -n instana-core &> /dev/null && kubectl delete secret azure-storage-account -n instana-core

    # Check if the PersistentVolume exists, then delete it
    kubectl get pv azure-volume &> /dev/null && kubectl delete pv azure-volume

    # Delete the PVC with volume name 'azure-volume' if it exists
    pvc_name=$(kubectl get pvc -n instana-core -o jsonpath='{.items[?(@.spec.volumeName=="azure-volume")].metadata.name}')
    [ -n "$pvc_name" ] && kubectl delete pvc "$pvc_name" -n instana-core
  fi

  delete_namespace "instana-core"
}

uninstall_instana_unit() {
  info "Uninstalling Instana units..."

  # Get all CRs of type 'unit' in the 'instana-units' namespace
  for unit in $(kubectl get unit -n instana-units -o jsonpath='{.items[*].metadata.name}'); do
    # Patch each unit to remove the finalizers, otherwise 'helm uninstall' hangs forever
    kubectl patch unit "$unit" -n instana-units --type=merge -p '{"metadata":{"finalizers":[]}}'

    helm_uninstall "$unit" "instana-units"
  done

  # The registry is used when uninstalling by pods.
  helm_uninstall "instana-registry" "instana-units"

  delete_namespace "instana-units"
}

uninstall_instana_operator() {
  helm_uninstall "instana-enterprise-operator" "instana-operator"

  info "Waiting for Instana operator pods to be terminated..."
  kubectl -n instana-operator wait --for=delete pod -lapp.kubernetes.io/name=instana --timeout="${HELM_UNINSTALL_TIMEOUT}"

  helm_uninstall "instana-registry" "instana-operator"

  delete_namespace "instana-operator"
}

welcome_to_instana() {
  echo "
*******************************************************************************
* Successfully installed Instana Self-Hosted Custom Edition on ${CLUSTER_TYPE}!
*
*  URL: https://${BASE_DOMAIN}
*  Username : ${INSTANA_ADMIN_USER}
*
*******************************************************************************
"
}

main() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
  pushd "$script_dir" >/dev/null 2>&1 || exit

  # Source general scripts and configuration files
  source ./config.env
  source ./versions.sh
  source ./helper.sh
  source ./datastores.sh

  # Process command line arguments
  local action=$1
  case $action in
  "apply")
    helm_repo_add
    install_cert_manager
    install_datastores
    install_instana_operator
    install_instana_core
    install_instana_unit
    delete_instana_routes
    create_instana_routes
    welcome_to_instana
    ;;
  "delete")
    uninstall_instana_unit
    uninstall_instana_core
    uninstall_instana_operator
    uninstall_datastores
    uninstall_cert_manager
    delete_instana_routes
    helm_repo_remove
    ;;
  "datastores")
    local sub_action=$2
    local datastore=$3
    case $sub_action in
    "apply")
      helm_repo_add
      install_datastores "$datastore"
      ;;
    "delete")
      uninstall_datastores "$datastore"
      ;;
    esac
    ;;
  "backend")
    local sub_action=$2
    case $sub_action in
    "apply")
      helm_repo_add
      install_instana_operator
      install_instana_core
      install_instana_unit
      delete_instana_routes
      create_instana_routes
      welcome_to_instana
      ;;
    esac
    ;;
  esac

  popd >/dev/null 2>&1 || exit
}

main "$@"
