#!/usr/bin/env bats

load _helpers

setup() {
  source_repo_scripts

  # reset call log for each test
  calls=()
  record() { calls+=("$*"); }

  # Stub helpers used by datastores.sh
  wait_for_k8s_object() { record "wait_for_k8s_object $*"; }
  wait_for_webhook_cabundle() { record "wait_for_webhook_cabundle $*"; }
  check_pods_ready() { record "check_pods_ready $*"; }
  check_cr_condition() { record "check_cr_condition $*"; }
  wait_status_for_k8s_object() { record "wait_status_for_k8s_object $*"; }

  install_cert_manager() { record "install_cert_manager"; }
  install_datastore_kafka() { record "install_datastore_kafka"; }
  install_datastore_es() { record "install_datastore_es"; }
  install_datastore_postgres() { record "install_datastore_postgres"; }
  install_datastore_cassandra() { record "install_datastore_cassandra"; }
  install_datastore_clickhouse() { record "install_datastore_clickhouse"; }
  install_datastore_beeinstana() { record "install_datastore_beeinstana"; }

  uninstall_kafka() { record "uninstall_kafka"; }
  uninstall_es() { record "uninstall_es"; }
  uninstall_postgres() { record "uninstall_postgres"; }
  uninstall_cassandra() { record "uninstall_cassandra"; }
  uninstall_clickhouse() { record "uninstall_clickhouse"; }
  uninstall_beeinstana() { record "uninstall_beeinstana"; }

  check_datastores_readiness() { record "check_datastores_readiness"; }
}

@test "check_webhook_and_service waits for service, webhook, then cabundle" {
  check_webhook_and_service "ns1" "svc-webhook" "validatingwebhookconfigurations" "hook-name"

  [[ "${#calls[@]}" -eq 3 ]]
  [[ "${calls[0]}" = "wait_for_k8s_object svc svc-webhook ns1" ]]
  [[ "${calls[1]}" = "wait_for_k8s_object validatingwebhookconfigurations hook-name ns1" ]]
  [[ "${calls[2]}" = "wait_for_webhook_cabundle validatingwebhookconfigurations hook-name" ]]
}

@test "check_datastore_readiness branches per datastore" {
  check_datastore_readiness "ns-kafka" "kafka"
  [[ "${calls[0]}" = "check_pods_ready ns-kafka app.kubernetes.io/instance=kafka" ]]
  [[ "${calls[1]}" = "check_cr_condition ns-kafka kafka kafka Ready" ]]
  calls=()

  check_datastore_readiness "ns-es" "elasticsearch"
  [[ "${calls[0]}" = "check_pods_ready ns-es common.k8s.elastic.co/type=elasticsearch" ]]
  [[ "${calls[1]}" = "check_cr_condition ns-es elasticsearch elasticsearch ReconciliationComplete" ]]
  [[ "${calls[2]}" = "wait_status_for_k8s_object elasticsearches.elasticsearch.k8s.elastic.co elasticsearch ns-es .status.health green" ]]
  calls=()

  check_datastore_readiness "ns-pg" "postgres"
  [[ "${calls[0]}" = "check_pods_ready ns-pg cnpg.io/cluster=postgres" ]]
  [[ "${calls[1]}" = "check_cr_condition ns-pg clusters.postgresql.cnpg.io postgres Ready" ]]
  calls=()

  check_datastore_readiness "ns-cass" "cassandra"
  [[ "${calls[0]}" = "check_pods_ready ns-cass app.kubernetes.io/instance=cassandra-instana" ]]
  [[ "${calls[1]}" = "check_cr_condition ns-cass cassandradatacenter cassandra Ready" ]]
  calls=()

  check_datastore_readiness "ns-click" "clickhouse"
  [[ "${calls[0]}" = "check_pods_ready ns-click app.kubernetes.io/instance=chi-clickhouse" ]]
  [[ "${calls[1]}" = "check_pods_ready ns-click app=clickhouse-keeper" ]]
  [[ "${calls[2]}" = "wait_status_for_k8s_object clickhouseinstallations.clickhouse.altinity.com clickhouse ns-click .status.status Completed" ]]
  calls=()

  check_datastore_readiness "ns-bee" "beeinstana"
  [[ "${calls[0]}" = "check_pods_ready ns-bee app.kubernetes.io/component=aggregator" ]]
  [[ "${calls[1]}" = "check_pods_ready ns-bee app.kubernetes.io/component=ingestors" ]]
}

@test "install_datastores dispatches to specific datastore" {
  install_datastores "kafka"
  [[ "${calls[0]}" = "install_datastore_kafka" ]]
  calls=()

  install_datastores "cassandra"
  [[ "${calls[0]}" = "install_cert_manager" ]]
  [[ "${calls[1]}" = "install_datastore_cassandra" ]]
  calls=()

  install_datastores ""
  expected=(
    "install_cert_manager"
    "install_datastore_kafka"
    "install_datastore_es"
    "install_datastore_postgres"
    "install_datastore_cassandra"
    "install_datastore_clickhouse"
    "install_datastore_beeinstana"
    "check_datastores_readiness"
  )
  [[ "${calls[*]}" = "${expected[*]}" ]]
}

@test "uninstall_datastores dispatches to specific datastore" {
  uninstall_datastores "postgres"
  [[ "${calls[0]}" = "uninstall_postgres" ]]
  calls=()

  uninstall_datastores ""
  expected=(
    "uninstall_beeinstana"
    "uninstall_clickhouse"
    "uninstall_cassandra"
    "uninstall_postgres"
    "uninstall_es"
    "uninstall_kafka"
  )
  [[ "${calls[*]}" = "${expected[*]}" ]]
}
