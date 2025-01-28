#!/usr/bin/env bash

install_datastore_beeinstana() {
  create_namespace_if_not_exist instana-beeinstana
  install_instana_registry instana-beeinstana

  helm_upgrade "beeinstana-operator" "instana/beeinstana-operator" "instana-beeinstana" "${BEEINSTANA_OPERATOR_CHART_VERSION}" \
    --set-string image.registry="${REGISTRY_URL}" \
    --set-string image.repository="beeinstana/operator" \
    --set-string image.tag="${BEEINSTANA_OPERATOR_IMAGE_TAG}" \
    --set-string imagePullSecrets[0].name="instana-registry" \
    -f values/beeinstana-operator/instana_values.yaml

  wait_for_k8s_object secret kafka-user instana-kafka

  local args=(
    "--set-literal=kafkaSettings.password=$(get_secret_password kafka-user instana-kafka)"
  )

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    args+=(
      "--set=fsGroup=$(kubectl get namespace instana-beeinstana -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d/ -f 1)"
    )
  fi

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments beeinstana)"

  helm_upgrade "beeinstana" "instana/instana-beeinstana" "instana-beeinstana" "${BEEINSTANA_INSTANCE_CHART_VERSION}" "${args[@]}" \
    --set-string aggregator.image.registry="${REGISTRY_URL}" \
    --set-string aggregator.image.name="beeinstana/aggregator" \
    --set-string aggregator.image.tag="${BEEINSTANA_AGGREGATOR_IMAGE_TAG}" \
    --set-string config.image.registry="${REGISTRY_URL}" \
    --set-string config.image.name="beeinstana/monconfig" \
    --set-string config.image.tag="${BEEINSTANA_CONFIG_IMAGE_TAG}" \
    --set-string ingestor.image.registry="${REGISTRY_URL}" \
    --set-string ingestor.image.name="beeinstana/ingestor" \
    --set-string ingestor.image.tag="${BEEINSTANA_INGESTOR_IMAGE_TAG}" \
    --set-string version="${BEEINSTANA_VERSION}" \
    "${file_args[@]}"
}

install_datastore_cassandra() {
  create_namespace_if_not_exist instana-cassandra
  install_instana_registry instana-cassandra

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    kubectl apply -f values/cassandra/cassandra-scc.yaml
  fi

  helm_upgrade "cass-operator" "instana/cass-operator" "instana-cassandra" "${CASSANDRA_OPERATOR_CHART_VERSION}" \
    --set-string image.registry="${REGISTRY_URL}" \
    --set-string image.repository="self-hosted-images/3rd-party/operator/cass-operator" \
    --set-string image.tag="${CASSANDRA_OPERATOR_IMAGE_TAG}" \
    --set-string imagePullSecrets[0].name="instana-registry" \
    --set-string appVersion="${CASSANDRA_OPERATOR_APPVERSION}" \
    --set-string imageConfig.systemLogger="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/system-logger:${CASSANDRA_OPERATOR_SYSTEMLOGGER_IMAGE_TAG}" \
    --set-string imageConfig.k8ssandraClient="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/k8ssandra-client:${CASSANDRA_OPERATOR_K8SSANDRACLIENT_IMAGE_TAG}" \
    --set securityContext.runAsGroup=999 \
    --set securityContext.runAsUser=999

  # Ensure Webhook Service and configuration are ready, preventing potential installation failures
  check_webhook_and_service "instana-cassandra" "cass-operator-webhook-service" "cass-operator-validating-webhook-configuration"

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments cassandra)"

  helm_upgrade "cassandra" "instana/instana-cassandra" "instana-cassandra" "${CASSANDRA_INSTANCE_CHART_VERSION}" \
    --set-string image="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/cassandra:${CASSANDRA_IMAGE_TAG}" \
    --set-string version="${CASSANDRA_VERSION}" \
    "${file_args[@]}"
}

install_datastore_clickhouse() {
  create_namespace_if_not_exist instana-clickhouse
  install_instana_registry instana-clickhouse

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    kubectl apply -f values/clickhouse/clickhouse-scc.yaml
  fi

  helm_upgrade "clickhouse-operator" "instana/ibm-clickhouse-operator" "instana-clickhouse" "${CLICKHOUSE_OPERATOR_CHART_VERSION}" \
    --set-string operator.image.repository="${REGISTRY_URL}/clickhouse-operator" \
    --set-string operator.image.tag="${CLICKHOUSE_OPERATOR_IMAGE_TAG}" \
    --set-string imagePullSecrets[0].name="instana-registry"

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments clickhouse)"

  helm_upgrade "clickhouse" "instana/instana-clickhouse" "instana-clickhouse" "${CLICKHOUSE_INSTANCE_CHART_VERSION}" \
    --set-string image="${REGISTRY_URL}/clickhouse-openssl:${CLICKHOUSE_IMAGE_TAG}" \
    "${file_args[@]}"
}

install_datastore_es() {
  create_namespace_if_not_exist instana-elastic
  install_instana_registry instana-elastic

  helm_upgrade "elastic-operator" "instana/eck-operator" "instana-elastic" "${ES_OPERATOR_CHART_VERSION}" \
    --set-string image.repository="${REGISTRY_URL}/self-hosted-images/3rd-party/operator/elasticsearch" \
    --set-string image.tag="${ES_OPERATOR_IMAGE_TAG}" \
    --set-string imagePullSecrets[0].name="instana-registry"

  # Ensure Webhook Service and configuration are ready, preventing potential installation failures
  check_webhook_and_service "instana-elastic" "elastic-operator-webhook" "elastic-operator.instana-elastic.k8s.elastic.co"

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments elasticsearch)"

  helm_upgrade "elasticsearch" "instana/instana-elasticsearch" "instana-elastic" "${ES_INSTANCE_CHART_VERSION}" \
    --set-string image="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/elasticsearch:${ES_IMAGE_TAG}" \
    --set-string version="${ES_VERSION}" \
    "${file_args[@]}"
}

install_datastore_kafka() {
  create_namespace_if_not_exist instana-kafka
  install_instana_registry instana-kafka

  helm_upgrade "strimzi-kafka-operator" "instana/strimzi-kafka-operator" "instana-kafka" "${KAFKA_OPERATOR_CHART_VERSION}" \
    --set-string image.registry="${REGISTRY_URL}" \
    --set-string image.repository="self-hosted-images/3rd-party/operator" \
    --set-string image.name="strimzi" \
    --set-string image.tag="${KAFKA_OPERATOR_IMAGE_TAG}" \
    --set-string topicOperator.image.registry="${REGISTRY_URL}" \
    --set-string topicOperator.image.repository="self-hosted-images/3rd-party/operator" \
    --set-string topicOperator.image.name="strimzi" \
    --set-string topicOperator.image.tag="${KAFKA_OPERATOR_IMAGE_TAG}" \
    --set-string userOperator.image.registry="${REGISTRY_URL}" \
    --set-string userOperator.image.repository="self-hosted-images/3rd-party/operator" \
    --set-string userOperator.image.name="strimzi" \
    --set-string userOperator.image.tag="${KAFKA_OPERATOR_IMAGE_TAG}" \
    --set-string tlsSidecarEntityOperator.image.registry="${REGISTRY_URL}" \
    --set-string tlsSidecarEntityOperator.image.repository="self-hosted-images/3rd-party/datastore" \
    --set-string tlsSidecarEntityOperator.image.name="kafka" \
    --set-string tlsSidecarEntityOperator.image.tag="${KAFKA_IMAGE_TAG}" \
    --set-string image.imagePullSecrets[0].name="instana-registry"

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments kafka)"

  helm_upgrade "kafka" "instana/instana-kafka" "instana-kafka" "${KAFKA_INSTANCE_CHART_VERSION}" \
    --set-string image="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/kafka:${KAFKA_IMAGE_TAG}" \
    --set-string version="${KAFKA_VERSION}" \
    "${file_args[@]}"
}

install_datastore_postgres() {
  create_namespace_if_not_exist instana-postgres
  install_instana_registry instana-postgres

  local args=(
    "--set-string=image.repository=${REGISTRY_URL}/self-hosted-images/3rd-party/operator/cloudnative-pg"
    "--set-string=image.tag=${POSTGRES_OPERATOR_IMAGE_TAG}"
    "--set-string=imagePullSecrets[0].name=instana-registry"
  )

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    args+=(
      "--set=containerSecurityContext.runAsUser=$(kubectl get namespace instana-postgres -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d/ -f 1)"
      "--set=containerSecurityContext.runAsGroup=$(kubectl get namespace instana-postgres -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d/ -f 1)"
    )
  fi

  helm_upgrade "cnpg" "instana/cloudnative-pg" "instana-postgres" "${POSTGRES_OPERATOR_CHART_VERSION}" \
    "${args[@]}"

  # Ensure Webhook Service and configuration are ready, preventing potential installation failures
  check_webhook_and_service "instana-postgres" "cnpg-webhook-service" "cnpg-validating-webhook-configuration"

  local file_args
  read -ra file_args <<<"$(generate_helm_file_arguments postgres)"

  helm_upgrade "postgres" "instana/instana-postgres" "instana-postgres" "${POSTGRES_INSTANCE_CHART_VERSION}" \
    --set-string image="${REGISTRY_URL}/self-hosted-images/3rd-party/datastore/cnpg-containers:${POSTGRES_IMAGE_TAG}" \
    "${file_args[@]}"
}

uninstall_kafka() {
  helm_uninstall "kafka" "instana-kafka"
  helm_uninstall "strimzi-kafka-operator" "instana-kafka"
  helm_uninstall "instana-registry" "instana-kafka"

  delete_namespace "instana-kafka"
}

uninstall_es() {
  helm_uninstall "elasticsearch" "instana-elastic"
  helm_uninstall "elastic-operator" "instana-elastic"
  helm_uninstall "instana-registry" "instana-elastic"

  delete_namespace "instana-elastic"
}

uninstall_postgres() {
  helm_uninstall "postgres" "instana-postgres"
  helm_uninstall "cnpg" "instana-postgres"
  helm_uninstall "instana-registry" "instana-postgres"

  delete_namespace "instana-postgres"
}

uninstall_cassandra() {
  helm_uninstall "cassandra" "instana-cassandra"
  helm_uninstall "cass-operator" "instana-cassandra"
  helm_uninstall "instana-registry" "instana-cassandra"

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    kubectl delete scc cassandra-scc --ignore-not-found --wait=true
  fi

  delete_namespace "instana-cassandra"
}

uninstall_clickhouse() {
  helm_uninstall "clickhouse" "instana-clickhouse"
  helm_uninstall "clickhouse-operator" "instana-clickhouse"
  helm_uninstall "instana-registry" "instana-clickhouse"

  if [ "$CLUSTER_TYPE" == "ocp" ]; then
    kubectl delete scc clickhouse-scc --ignore-not-found --wait=true
  fi

  delete_namespace "instana-clickhouse"
}

uninstall_beeinstana() {
  helm_uninstall "beeinstana" "instana-beeinstana"
  helm_uninstall "beeinstana-operator" "instana-beeinstana"
  helm_uninstall "instana-registry" "instana-beeinstana"

  delete_namespace "instana-beeinstana"
}

check_webhook_and_service() {
  local namespace=$1
  local service_name=$2
  local webhook_name=$3

  wait_for_k8s_object svc "$service_name" "$namespace"
  wait_for_k8s_object validatingwebhookconfigurations "$webhook_name" "$namespace"
}

check_datastore_readiness() {
  local namespace=$1
  local datastore=$2

  case $datastore in
  "kafka")
    check_pods_ready "$namespace" "app.kubernetes.io/instance=kafka"
    check_cr_condition "$namespace" "kafka" "kafka" "Ready"
    ;;
  "elasticsearch")
    check_pods_ready "$namespace" "common.k8s.elastic.co/type=elasticsearch"
    check_cr_condition "$namespace" "elasticsearch" "elasticsearch" "ReconciliationComplete"
    wait_status_for_k8s_object "elasticsearches.elasticsearch.k8s.elastic.co" "elasticsearch" "$namespace" ".status.health" "green"
    ;;
  "postgres")
    check_pods_ready "$namespace" "cnpg.io/cluster=postgres"
    check_cr_condition "$namespace" "clusters.postgresql.cnpg.io" "postgres" "Ready"
    ;;
  "cassandra")
    check_pods_ready "$namespace" "app.kubernetes.io/instance=cassandra-instana"
    check_cr_condition "$namespace" "cassandradatacenter" "cassandra" "Ready"
    ;;
  "clickhouse")
    check_pods_ready "$namespace" "app.kubernetes.io/instance=chi-clickhouse"
    check_pods_ready "$namespace" "app=clickhouse-keeper"
    wait_status_for_k8s_object "clickhouseinstallations.clickhouse.altinity.com" "clickhouse" "$namespace" ".status.status" "Completed"
    ;;
  "beeinstana")
    check_pods_ready "$namespace" "app.kubernetes.io/component=aggregator"
    check_pods_ready "$namespace" "app.kubernetes.io/component=ingestors"
    ;;
  esac
}

check_datastores_readiness() {
  check_datastore_readiness "instana-kafka" "kafka"
  check_datastore_readiness "instana-elastic" "elasticsearch"
  check_datastore_readiness "instana-cassandra" "cassandra"
  check_datastore_readiness "instana-clickhouse" "clickhouse"
  check_datastore_readiness "instana-postgres" "postgres"
  check_datastore_readiness "instana-beeinstana" "beeinstana"
}

install_datastores() {
  local datastore=$1

  case $datastore in
  "kafka")
    install_datastore_kafka
    ;;
  "elasticsearch")
    install_datastore_es
    ;;
  "postgres")
    install_datastore_postgres
    ;;
  "cassandra")
    install_cert_manager
    install_datastore_cassandra
    ;;
  "clickhouse")
    install_datastore_clickhouse
    ;;
  "beeinstana")
    install_datastore_beeinstana
    ;;
  *)
    install_datastore_kafka
    install_datastore_es
    install_datastore_postgres
    install_datastore_cassandra
    install_datastore_clickhouse
    install_datastore_beeinstana
    check_datastores_readiness
    ;;
  esac
}

uninstall_datastores() {
  local datastore=$1

  case $datastore in
  "kafka")
    uninstall_kafka
    ;;
  "elasticsearch")
    uninstall_es
    ;;
  "postgres")
    uninstall_postgres
    ;;
  "cassandra")
    uninstall_cassandra
    ;;
  "clickhouse")
    uninstall_clickhouse
    ;;
  "beeinstana")
    uninstall_beeinstana
    ;;
  *)
    uninstall_beeinstana
    uninstall_clickhouse
    uninstall_cassandra
    uninstall_postgres
    uninstall_es
    uninstall_kafka
    ;;
  esac
}
