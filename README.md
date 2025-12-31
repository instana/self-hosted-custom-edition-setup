# Instana Self-Hosted Custom Edition Setup

This repository contains scripts and configuration files to deploy Instana Self-Hosted Custom Edition on Kubernetes clusters. This README provides detailed information on how to modify the default configuration values to customize your Instana deployment.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
    - [Helm](#helm)
    - [Storageclass](#storageclass)
    - [Kubernetes Version](#kubernetes-version)
    - [Openshift](#ocp-cluster-and-version)
    - [yq](#install-yq)
3. [Configuration Files Structure](#configuration-files-structure)
4. [Modifying Default Values](#modifying-default-values)
   - [Environment Configuration](#environment-configuration)
   - [Core Configuration](#core-configuration)
   - [Unit Configuration](#unit-configuration)
   - [Datastores Configuration](#datastores-configuration)
     - [Cassandra](#cassandra)
     - [Elasticsearch](#elasticsearch)
     - [Clickhouse](#clickhouse)
     - [Postgres](#postgres)
     - [Kafka](#kafka)
     - [BeeInstana](#beeinstana)
5. [Storage Configuration](#storage-configuration)
   - [PVC Configuration](#pvc-configuration)
   - [S3 Configuration](#s3-configuration)
   - [Azure Storage Configuration](#azure-storage-configuration)
6. [Network and DNS Configuration](#network-and-dns-configuration)
   - [Base Domain](#base-domain)
   - [Agent Acceptor](#agent-acceptor)
   - [Gateway Configuration](#gateway-configuration)
7. [Feature Flags](#feature-flags)
8. [Installation Commands](#installation-commands)
    - [Show Help](#getting-help)
9. [Troubleshooting](#troubleshooting)

## Overview

The Instana Self-Hosted Custom Edition setup uses Helm charts to deploy various components on Kubernetes clusters. The deployment is orchestrated by shell scripts that apply the configuration values to the Helm charts.

## Prerequisites

Before installing Instana Self-Hosted Custom Edition, ensure you have the following prerequisites in place:

| #   | Prerequisite                   | Reason                                             |
| --- | ------------------------------ | -------------------------------------------------- |
| 1   | Helm is installed              | Needed to deploy Helm charts                       |
| 2   | A default storage class is set | Required for successful data store installations   |
| 3   | Kubernetes version > 1.25      | Instana requires Kubernetes version 1.25 or higher |
| 4   | OCP version > 4.13             | Required to deploy Instana on OpenShift            |
| 5   | yq                             | Required to parse yaml                             |

- ### Helm

  Helm is required to deploy Helm charts. To install Helm:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  ```

- ### Storageclass

  Instana requires `ReadWriteMany` (RWX) or `ReadWriteOnce` (RWO) storage for raw spans and monitoring data. Ensure a default
  storage class is set on the cluster, otherwise the installation of data stores will fail.

  To verify the default storage class:

  ```bash
  kubectl get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}{"\n"}'
  ```

  If no default is set, run:

  ```bash
  kubectl patch storageclass <storageclass_name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  ```

- ### Kubernetes version

  Kubectl must be installed and its version should be >1.25.

  To install the latest stable version:

  ```bash
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  ```

  Verify your kubectl installation:

  ```bash
  kubectl version --client=true
  ```

  Kubernetes version must be >1.25. Check the server version:

  ```bash
  kubectl version
  ```

- ### OCP cluster and version

  If using OpenShift, the OCP version must be >4.13 and OpenShift CLI (`oc`) must be installed. Check the OpenShift version:

  ```bash
  oc version
  ```

- ### Install yq

  yq is a command-line tool for reading and writing YAML files

  Mac (Homebrew):

  ```bash
  brew install yq
  ```

  Ubuntu / Debian:

  ```bash
  sudo snap install yq
  ```

  Check version:

  ```bash
  yq --version
  ```

## Configuration Files Structure

The configuration files are organized as follows:

```text
self-hosted-custom-edition-setup/
├── deploy/
│   ├── config.env.template               # Environment variables template
│   ├── shce.sh                   # Main installation script
│   ├── helper.sh                 # Helper functions
│   ├── datastores.sh             # Datastore installation functions
│   ├── versions.sh               # Component versions
│   └── values/                   # Default and custom values for components
│       ├── beeinstana/
│       │   └── instana-values.yaml  # Default values
│       ├── beeinstana-operator/
│       │   └── instana-values.yaml
│       ├── cassandra/
│       │   └── instana-values.yaml
│       ├── cassandra-operator/
│       │   └── instana-values.yaml
│       ├── cert-manager/
│       │   └── instana-values.yaml
│       ├── clickhouse/
│       │   ├── instana-values-eks.yaml
│       │   └── instana-values.yaml
│       ├── clickhouse-operator/
│       │   └── instana-values.yaml
│       ├── core/
│       │   ├── instana-values.yaml
│       │   └── pv-template-aks.yaml
│       ├── elasticsearch/
│       │   ├── instana-values-ocp.yaml
│       │   └── instana-values.yaml
│       ├── elasticsearch-operator/
│       │   └── instana-values.yaml
│       ├── instana-operator/
│       │   └── instana-values.yaml
│       ├── kafka/
│       │   └── instana-values.yaml
│       ├── kafka-operator/
│       │   └── instana-values.yaml
│       ├── postgres/
│       │   └── instana-values.yaml
│       ├── postgres-operator/
│       │   └── instana-values.yaml
│       └── unit/
│           └── instana-values.yaml
```

## Modifying Default Values

You can modify the default values by creating a `custom-values.yaml` file in the same directories.

The installation script will first look for `custom-values.yaml` and use those values if present. If not, it will fall back to the default values in `instana-values.yaml`.

### Environment Configuration

The `config.env` file contains environment variables that control the deployment. You can modify the following values:

```bash
# Required values
SALES_KEY=your-sales-key                # Your Instana sales key
DOWNLOAD_KEY=your-download-key          # Your Instana download key
CLUSTER_TYPE=eks                        # Cluster type: ocp, eks, aks, gke, or k8s
AGENT_KEY=your-agent-key                # Your Instana agent key (optional)

# Unit and tenant configuration
INSTANA_UNIT_NAME=unit0                 # Name of the Instana unit
INSTANA_TENANT_NAME=tenant0             # Name of the Instana tenant

# Registry configuration (only needed for custom registry)
REGISTRY_URL=your-registry-url          # Custom registry URL
REGISTRY_USERNAME=your-registry-username # Custom registry username
REGISTRY_PASSWORD=your-registry-password # Custom registry password

# Helm repository configuration (only needed for custom repository)
HELM_REPO_URL=your-helm-repo-url        # Custom Helm repository URL
HELM_REPO_USERNAME=your-helm-repo-username # Custom Helm repository username
HELM_REPO_PASSWORD=your-helm-repo-password # Custom Helm repository password

# Azure configuration (only needed for AKS)
AZURE_STORAGE_ACCOUNT=your-storage-account # Azure storage account name
AZURE_STORAGE_FILESHARE_NAME=your-fileshare # Azure file share name
AZURE_STORAGE_ACCOUNT_KEY=your-account-key # Azure storage account key
AZURE_STORAGE_CAPACITY=100Gi            # Azure storage capacity
```

### Core Configuration

The core component is the main Instana backend. You can modify its configuration in `deploy/values/core/custom-values.yaml`:

```yaml
# Base domain for Instana UI access
baseDomain: "your-domain.example.com"

# Agent acceptor configuration
acceptors:
  agent:
    host: "agent-acceptor.your-domain.example.com"
    port: 443
  otlp:
    http:
      host: "otlp-http.your-domain.example.com"
      port: 443
    grpc:
      host: "otlp-grpc.your-domain.example.com"
      port: 443
  eum:
    host: "eum.your-domain.example.com"
    port: 443
  synthetics:
    host: "synthetics.your-domain.example.com"
    port: 443
  serverless:
    host: "serverless.your-domain.example.com"
    port: 443

# Support for single ingress domain
properties:
  - name: config.url.format.pathStyle
    value: "true"

# Image configuration
imageConfig:
  tag: 3.xxx.xxx-x  # Instana backend version
  # registry: artifact-public.instana.io
  # repository: backend

# Storage configuration for raw spans
storageConfigs:
  rawSpans:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"

# Email configuration
emailConfig:
  smtpConfig:
    from: "your-email@example.com"
    host: "your-smtp-host.example.com"
    port: 587
    username: "your-smtp-username"
    password: "your-smtp-password"
    useTLS: true

# Gateway configuration
gatewayConfig:
  enabled: true  # Set to false to disable gateway-v2
  gateway:
    loadBalancerConfig:
      enabled: true  # Enables automatic LoadBalancer creation
      # ip: "your-public-ip"  # Optional: Specify a public IP
      # externalTrafficPolicy: Local  # Default
      # annotations:
      #   your-annotation-key: your-annotation-value

# Autoscaling Configuration

## Enable autoscaling
autoscalingConfig:
  # This will enable HPA of all Instana backend components
  enabled: true

## Configure Min/Max replicas of the Instana backend components
autoscalingConfig:
  enabled: true
  minReplicas: 2
  maxReplicas: 10

# Feature flags
featureFlags:
  - name: feature.logging.enabled
    enabled: true
  - name: feature.synthetics.enabled
    enabled: true
  - name: feature.internal.monitoring.unit
    enabled: true
```

### Unit Configuration

The unit component represents an Instana unit and tenant. You can modify its configuration in `deploy/values/unit/custom-values.yaml`:

```yaml
# Admin user configuration
initialAdminUser: "admin@instana.local"
initialAdminPassword: "your-secure-password"

# Resource profile
resourceProfile: medium                 # Resource profile (default: medium)


# Core reference
coreName: "instana-core"
coreNamespace: "instana-core"

```

### Datastores Configuration

#### Cassandra

You can modify Cassandra configuration in `deploy/values/cassandra/custom-values.yaml`. The main customizable parameters include:

```yaml
# Name configuration
nameOverride: cassandra
fullnameOverride: cassandra

# Cluster configuration
size: 3                                 # Number of Cassandra nodes (default: 3)

# Storage configuration
storageClassName: "your-storage-class"  # Storage class for persistent storage
storage: 500Gi                          # Storage size for Cassandra data (default: 500Gi)

# Resource limits
resources:
  requests:
    cpu: "4000m"                        # CPU request (4 cores) (default: 4000m)
    memory: "12Gi"                      # Memory request (12 GB) (default: 12Gi)
  limits:
    memory: "12Gi"                      # Memory limit (12 GB) (default: 12Gi)

# JVM configuration
jvmServerOptions:
  initialHeapSize: "4G"                 # Initial Java heap size (default: 4G)
  maxHeapSize: "8G"                     # Maximum Java heap size (default: 8G)

# Performance tuning
memtableFlushWriters: 8                 # Number of memtable flush writer threads (default: 8)
```

#### Elasticsearch

You can modify Elasticsearch configuration in `deploy/values/elasticsearch/custom-values.yaml`. The main customizable parameters include:

```yaml
# Name configuration
nameOverride: elasticsearch
fullnameOverride: elasticsearch

nodeSets:
  - name: default
    count: 3                            # Number of Elasticsearch nodes (default: 3)
    config:
      node.roles:                       # Node roles
        - master
        - ingest
        - data
      node.store.allow_mmap: false      # Memory map settings
    resources:
      requests:
        cpu: "2000m"                    # CPU request (2 cores) (default: 2000m)
        memory: "8Gi"                   # Memory request (8 GB) (default: 8Gi)
      limits:
        memory: "8Gi"                   # Memory limit (8 GB) (default: 8Gi)
    securityContext:
      fsGroup: 1000
      runAsGroup: 1000
      runAsUser: 1000
    storageClassName: "your-storage-class" # Storage class for persistent storage
    volume:
      resources:
        requests:
          storage: 500Gi                # Storage size for Elasticsearch data (default: 500Gi)
```

#### Clickhouse

You can modify Clickhouse configuration in `deploy/values/clickhouse/custom-values.yaml`. The main customizable parameters include:

```yaml
# Name configuration
nameOverride: clickhouse
fullnameOverride: clickhouse

clickhouse:
  # Cluster configuration
  clusters:
    layout:
      replicasCount: 2                  # Number of Clickhouse replicas (default: 2)

  # Resource configuration
  resources:
    requests:
      cpu: "10000m"                      # CPU request (5 cores) (default: 5000m)
      memory: "20Gi"                    # Memory request (10 GB) (default: 10Gi)
    limits:
      memory: "20Gi"                    # Memory limit (10 GB) (default: 10Gi)

  # Storage configuration
  volumeClaimTemplates:
    # Data storage
    dataStorageClassName: "your-storage-class"  # Storage class for data
    dataStorage: "500Gi"                        # Storage capacity for data (default: 500Gi)

    # Log storage
    logStorageClassName: "your-storage-class"   # Storage class for logs
    logStorage: "50Gi"                          # Storage capacity for logs (default: 50Gi)

    # Cold tier storage
    coldStorageClassName: "your-storage-class"  # Storage class for cold tier
    coldStorage: "100Gi"                        # Storage capacity for cold tier (default: 100Gi)

keeper:
  # Clickhouse Keeper configuration
  clusters:
    layout:
      replicasCount: 3                  # Number of Keeper replicas (default: 3)

  # Resource configuration
  resources:
    requests:
      cpu: "1000m"                      # CPU request (1 core) (default: 1000m)
      memory: "2Gi"                     # Memory request (2 GB) (default: 2Gi)
    limits:
      memory: "2Gi"                     # Memory limit (2 GB) (default: 2Gi)

  # Storage configuration
  volumeClaimTemplates:
    logStorageClassName: "your-storage-class"       # Storage class for logs
    logStorage: "50Gi"                              # Storage capacity for logs (default: 50Gi)
    snapshotStorageClassName: "your-storage-class"  # Storage class for snapshots
    snapshotStorage: "50Gi"                         # Storage capacity for snapshots (default: 50Gi)
```

#### Postgres

You can modify Postgres configuration in `deploy/values/postgres/custom-values.yaml`. The main customizable parameters include:

```yaml
# Name configuration
nameOverride: postgres
fullnameOverride: postgres

# Instance configuration
instances: 3                            # Number of Postgres instances (default: 3)

# Resource configuration
resources:
  requests:
    cpu: "500m"                         # CPU request (0.5 core) (default: 500m)
    memory: "1Gi"                       # Memory request (1 GB) (default: 1Gi)
  limits:
    memory: "1Gi"                       # Memory limit (1 GB) (default: 1Gi)

# Storage configuration
storage:
  size: "50Gi"                          # Storage size for Postgres data (default: 50Gi)
  storageClass: "your-storage-class"    # Storage class for persistent storage
```

#### Kafka

Kafka configuration can be modified in `deploy/values/kafka/custom-values.yaml`. The main customizable parameters include:

```yaml
# Name configuration
nameOverride: kafka
fullnameOverride: kafka

# Replica configuration
replicas:
  kafka: 3                              # Number of Kafka broker nodes (default: 3)
  controller: 3                         # Number of controller nodes (default: 3)

# Storage configuration
storage:
  size:
    kafka: 500Gi                        # Storage size for Kafka data (default: 500Gi)
    controller: 50Gi                    # Storage size for controller data (default: 50Gi)
  deleteClaim:
    kafka: "true"                       # Delete PVC on deletion (default: true)
    controller: "true"                  # Delete PVC on deletion (default: true)

# Temporary directory size limits
template:
  pod:
    tmpDirSizeLimit:
      kafka: 500Mi                      # Temp directory size for Kafka (default: 500Mi)
      controller: 500Mi                 # Temp directory size for controller (default: 500Mi)
      entityOperator: 500Mi             # Temp directory size for entity operator (default: 500Mi)

# Image configuration
image:
  tag: "0.47.0-kafka-3.9.1_v0.24.0"    # Kafka image tag

# Kafka version
version: 3.9.1                          # Kafka version

# KRaft mode (recommended)
kraft: "enabled"                        # Enable KRaft mode (default: enabled)
nodePools: "enabled"                    # Enable node pools (default: enabled)

# Resource configuration
resources:
  kafka:
    requests:
      cpu: "4000m"                      # CPU request for Kafka (4 cores) (default: 4000m)
      memory: "20Gi"                    # Memory request for Kafka (20 GB) (default: 20Gi)
    limits:
      memory: "20Gi"                    # Memory limit for Kafka (20 GB) (default: 20Gi)
  controller:
    requests:
      cpu: "1000m"                      # CPU request for controller (1 core) (default: 1000m)
      memory: "2Gi"                     # Memory request for controller (2 GB) (default: 2Gi)
    limits:
      memory: "2Gi"                     # Memory limit for controller (2 GB) (default: 2Gi)

# Kafka broker configuration
config:
  kafka:
    offsets.topic.replication.factor: 3                 # Replication factor for offsets topic (default: 3)
    transaction.state.log.replication.factor: 3         # Replication factor for transaction log (default: 3)
    transaction.state.log.min.isr: 2                    # Minimum in-sync replicas for transaction log (default: 2)
    default.replication.factor: 3                       # Default replication factor (default: 3)
    min.insync.replicas: 2                              # Minimum in-sync replicas (default: 2)
    max.message.bytes: 52428800                         # Max message size in bytes (50 MB) (default: 52428800)
    message.max.bytes: 52428800                         # Max message size in bytes (50 MB) (default: 52428800)
    replica.fetch.max.bytes: 52428800                   # Max fetch size for replicas (50 MB) (default: 52428800)
```

#### BeeInstana

You can modify BeeInstana configuration in `deploy/values/beeinstana/custom-values.yaml`:

```yaml

version: "1.3.24"

# Aggregator configuration
aggregator:
  image:
    tag: v1.85.76-release
  cpu: 4                                # CPU request (4 cores) (default: 4)
  memory: 48Gi                          # Memory request (48 GB) (default: 48Gi)
  limitMemory: true                     # Limit memory (default: true)
  mirrors: 2                            # Number of mirrors (default: 2)
  shards: 1                             # Number of shards (default: 1)
  volumes:
    live:
      size: 500Gi                       # Storage size for live data (default: 500Gi)
      storageClass: "your-storage-class" # Storage class for persistent storage

# Config configuration
config:
  image:
    tag: v2.44.0
  cpu: 200m                             # CPU request (0.2 core) (default: 200m)
  memory: 200Mi                         # Memory request (200 MB) (default: 200Mi)
  limitMemory: true                     # Limit memory (default: true)
  replicas: 1                           # Number of replicas (default: 1)

# Ingestor configuration
ingestor:
  image:
    tag: v1.85.76-release
  cpu: 2                                # CPU request (2 cores) (default: 2)
  memory: 4Gi                           # Memory request (4 GB) (default: 4Gi)
  limitMemory: true                     # Limit memory (default: true)
  replicas: 1                           # Number of replicas (default: 1)
  workerPoolSize: 20                    # Worker pool size (default: 20)
  flushInterval: 10000                  # Flush interval in milliseconds (default: 10000)
  maxQueueSize: 5000                    # Maximum queue size (default: 5000)
```

## Storage Configuration

### PVC Configuration

For components that use Persistent Volume Claims (PVCs), you can configure the storage as follows:

```yaml
storageConfigs:
  rawSpans:
    pvcConfig:
      accessModes:
        - ReadWriteMany  # or ReadWriteOnce
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"
```

### S3 Configuration

For components that can use S3 storage, you can configure it as follows:

```yaml
storageConfigs:
  rawSpans:
    s3Config:
      endpoint: s3.your-region.amazonaws.com
      region: your-region
      bucket: your-bucket-name
      prefix: your-prefix
      storageClass: STANDARD
      bucketLongTerm: your-longterm-bucket
      prefixLongTerm: your-longterm-prefix
      storageClassLongTerm: STANDARD
```

### Azure Storage Configuration

For Azure Kubernetes Service (AKS), you can configure Azure File storage as follows:

1. Set the environment variables in `config.env`:

    ```bash
    AZURE_STORAGE_ACCOUNT=your-storage-account
    AZURE_STORAGE_FILESHARE_NAME=your-fileshare
    AZURE_STORAGE_ACCOUNT_KEY=your-account-key
    AZURE_STORAGE_CAPACITY=100Gi
    ```

2. Configure the storage in `deploy/values/core/custom-values.yaml`:

    ```yaml
    storageConfigs:
      rawSpans:
        pvcConfig:
          accessModes:
            - ReadWriteMany
          resources:
            requests:
              storage: 100Gi
          volumeName: "azure-volume"
    ```

## Network and DNS Configuration

**NOTE**: By default, the script supports single ingress domain and is configurable with `custom_values.yaml`.

### Base Domain

The base domain is the main domain for accessing the Instana UI. Configure it in `deploy/values/core/custom-values.yaml`:

```yaml
baseDomain: "your-domain.example.com"
```

### Agent Acceptor

The agent acceptor is the endpoint that Instana agents use to send data. Configure it in `deploy/values/core/custom-values.yaml`:

```yaml
acceptors:
  agent:
    host: "agent-acceptor.your-domain.example.com"
    port: 443
```

### Gateway Configuration

The gateway handles incoming traffic. Configure it in `deploy/values/core/custom-values.yaml`:

```yaml
gatewayConfig:
  enabled: true  # Set to false to disable gateway-v2
  gateway:
    loadBalancerConfig:
      enabled: true  # Enables automatic LoadBalancer creation
```

For more advanced configurations, you can use subdomains with a single port:

```yaml
acceptors:
  agent:
    host: agent-acceptor.your-domain.example.com
    port: 443
  otlp:
    http:
      host: otlp-http.your-domain.example.com
      port: 443
    grpc:
      host: otlp-grpc.your-domain.example.com
      port: 443
  eum:
    host: eum.your-domain.example.com
    port: 443
  synthetics:
    host: synthetics.your-domain.example.com
    port: 443
  serverless:
    host: serverless.your-domain.example.com
    port: 443
```

Or use a single domain with different ports:

```yaml
acceptors:
  agent:
    port: 1443
  otlp:
    http:
      port: 4318
    grpc:
      port: 4317
  eum:
    port: 1555
  synthetics:
    port: 1666
  serverless:
    port: 1777
```

## Feature Flags

You can enable or disable features using feature flags in `deploy/values/core/custom-values.yaml`:

```yaml
featureFlags:
  - name: feature.logging.enabled
    enabled: true
  - name: feature.synthetics.enabled
    enabled: true
  - name: feature.internal.monitoring.unit
    enabled: true
  - name: feature.beeinstana.infra.metrics.enabled
    enabled: true
```

Common feature flags include:

| Feature Flag | Description |
| -------------- | ------------- |
| `feature.logging.enabled` | Enables logging |
| `feature.synthetics.enabled` | Enables synthetic monitoring |
| `feature.internal.monitoring.unit` | Enables internal monitoring |
| `feature.beeinstana.infra.metrics.enabled` | Enables BeeInstana infrastructure metrics (enabled by default) |

For a complete list of feature flags, refer to the [Instana documentation](https://www.ibm.com/docs/en/instana-observability/current?topic=edition-enabling-optional-features).

## Installation Commands

After modifying the configuration files, you can install Instana using the following commands:

### Getting Help

```bash
./shce.sh help
```

```bash
# Install everything
./shce.sh apply

# Install only datastores
./shce.sh datastores apply

# Install a specific datastore
./shce.sh datastores apply kafka

# Install backend components only (operator, core, unit)
./shce.sh backend apply
```

### Uninstallation Commands

```bash
# Uninstall everything
./shce.sh delete

# Uninstall backend components only (operator, core, unit)
./shce.sh backend delete

# Uninstall a specific datastore
./shce.sh datastores delete kafka
```

## Troubleshooting

If you encounter issues during installation, check the following:

1. Ensure all required environment variables are set in `config.env`.
2. Verify that the Kubernetes cluster is accessible and has the required resources.
3. Check that the storage class exists and is properly configured.
4. Verify that DNS records are properly configured for the base domain and agent acceptor.
5. Check the logs of the pods in the respective namespaces for errors.
6. Cleanup old persistent volume claims of datastores, if present.

For more detailed troubleshooting, refer to the [Instana documentation](https://www.ibm.com/docs/en/instana-observability/current?topic=backend-installing-custom-edition).
