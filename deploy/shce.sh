#!/usr/bin/env bash
set -o errexit

source ./config.env
source ./versions.sh
source ./helper.sh
source ./datastores.sh

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
  verify_non_empty "BASE_DOMAIN" "$BASE_DOMAIN"
  verify_non_empty "AGENT_ACCEPTOR" "$AGENT_ACCEPTOR"
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
    --set crds.enabled=true \
    --set global.imagePullSecrets[0].name="instana-registry"
}

uninstall_cert_manager() {
  helm_uninstall "cert-manager" "cert-manager"
  helm_uninstall "instana-registry" "cert-manager"

  delete_namespace "cert-manager"
}

install_instana_registry() {
  local ns=$1
  helm_upgrade "instana-registry" "instana/instana-registry" "$ns" "${INSTANA_REGISTRY_CHART_VERSION}" \
    --set password="$DOWNLOAD_KEY"
}

install_instana_operator() {
  info "Installing Instana operator..."

  create_namespace_if_not_exist instana-operator
  install_instana_registry instana-operator

  helm_upgrade "instana-enterprise-operator" "instana/instana-enterprise-operator" "instana-operator" "${INSTANA_OPERATOR_CHART_VERSION}" \
    --set image.tag="$INSTANA_OPERATOR_IMAGE_TAG" \
    --set imagePullSecrets[0].name=instana-registry

  check_pods_ready "instana-operator" "app.kubernetes.io/name=instana"
}

create_instana_routes() {
  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    info "Creating routes..."
    oc create route passthrough ui-client-tenant --hostname="${INSTANA_UNIT_NAME}-${INSTANA_TENANT_NAME}.${BASE_DOMAIN}" --service=gateway --port=https -n instana-core
    oc create route passthrough ui-client-ssl --hostname="${BASE_DOMAIN}" --service=gateway --port=https -n instana-core
    oc create route passthrough acceptor --hostname="${AGENT_ACCEPTOR}" --service=acceptor --port=http-service -n instana-core
  fi
}

delete_instana_routes() {
  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    info "Delete routes..."
    oc delete route ui-client-tenant --ignore-not-found -n instana-core
    oc delete route ui-client-ssl --ignore-not-found -n instana-core
    oc delete route acceptor --ignore-not-found -n instana-core
  fi
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
    sed "s/{{AZURE_STORAGE_ACCOUNT}}/${AZURE_STORAGE_ACCOUNT}/g; s/{{AZURE_STORAGE_CAPACITY}}/${CAPACITY}/g" ./values/core/pv_template_aks.yaml | kubectl apply -f -
  fi

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments core)"

  helm_upgrade "instana-core" "instana/instana-core" "instana-core" "${INSTANA_CORE_CHART_VERSION}" \
    --set baseDomain="$BASE_DOMAIN" \
    --set agentAcceptor.host="$AGENT_ACCEPTOR" \
    --set salesKey="$SALES_KEY" \
    --set repositoryPassword="${DOWNLOAD_KEY}" \
    --set datastores.beeInstana.password="$(get_secret_password beeinstana-admin instana-beeinstana)" \
    --set datastores.cassandra.adminPassword="$(get_secret_password cassandra-admin instana-cassandra)" \
    --set datastores.cassandra.password="$(get_secret_password cassandra-user instana-cassandra)" \
    --set datastores.clickhouse.adminPassword="$(get_secret_password clickhouse-admin instana-clickhouse)" \
    --set datastores.clickhouse.password="$(get_secret_password clickhouse-admin instana-clickhouse)" \
    --set datastores.postgres.adminPassword="$(get_secret_password postgres-admin instana-postgres)" \
    --set datastores.postgres.password="$(get_secret_password postgres-user instana-postgres)" \
    --set datastores.elasticsearch.adminPassword="$(get_secret_password elasticsearch-admin instana-elastic)" \
    --set datastores.elasticsearch.password="$(get_secret_password elasticsearch-user instana-elastic)" \
    --set datastores.kafka.adminPassword="$(get_secret_password kafka-admin instana-kafka)" \
    --set datastores.kafka.consumerPassword="$(get_secret_password kafka-user instana-kafka)" \
    --set datastores.kafka.producerPassword="$(get_secret_password kafka-user instana-kafka)" \
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
    --set coreName=instana-core \
    --set coreNamespace=instana-core \
    --set resourceProfile=small \
    --set licenses="{$license_content}" \
    --set downloadKey="$DOWNLOAD_KEY" \
    --set agentKeys="{$SALES_KEY}" \
    --set initialAdminUser="$INSTANA_ADMIN_USER" \
    --set initialAdminPassword="$INSTANA_ADMIN_PASSWORD" \
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

  delete_instana_routes

  # The registry is used when uninstalling by pods.
  helm_uninstall "instana-registry" "instana-units"

  delete_namespace "instana-units"
}

uninstall_instana_operator() {
  helm_uninstall "instana-enterprise-operator" "instana-operator"

  info "Waiting for Instana operator pods to be terminated..."
  kubectl -n instana-operator wait --for=delete pod -lapp.kubernetes.io/name=instana --timeout="$HELM_UNINSTALL_TIMEOUT"

  helm_uninstall "instana-registry" "instana-operator"

  delete_namespace "instana-operator"
}

welcome_to_instana() {
  echo "
*******************************************************************************
* Successfully installed Instana Self-Hosted Custom Edition on ${CLUSTER_TYPE}!
*
*  URL: https://${BASE_DOMAIN}
*   Username : $INSTANA_ADMIN_USER
*   Password : $INSTANA_ADMIN_PASSWORD
*
*******************************************************************************
"
}

main() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
  pushd "$script_dir" >/dev/null 2>&1 || exit

  precheck

  local action=$1
  case $action in
  "apply")
    helm_repo_add
    install_cert_manager
    install_datastores
    install_instana_operator
    install_instana_core
    install_instana_unit
    create_instana_routes
    welcome_to_instana
    ;;
  "delete")
    uninstall_instana_unit
    uninstall_instana_core
    uninstall_instana_operator
    uninstall_datastores
    uninstall_cert_manager
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
  esac

  popd >/dev/null 2>&1 || exit
}

main "$@"
