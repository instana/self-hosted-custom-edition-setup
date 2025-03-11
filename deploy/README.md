# Self Hosted Custom Edition Installation Script

This script helps you install the Self Hosted Custom Edition on OCP (Red Hat OpenShift Container Platform), EKS (Amazon Elastic
Kubernetes Service), AKS (Azure Kubernetes Service), GKE (Google Kubernetes Engine), ARO (Azure Redhat Openshift) and ROSA (Red Hat OpenShift Service on AWS) clusters.

The tool is based on Helm charts and values and allows for custom installations tailored to your needs.

## Prerequisite and Preparing

Before installation, ensure the following prerequisites are met:

| #   | Prerequisite                    | Reason                                              |
| --- |---------------------------------| --------------------------------------------------- |
| 1   | Helm is installed               | Needed to deploy Helm charts                        |
| 2   | A default storage class is set  | Required for successful data store installations    |
| 3   | Kubernetes version > 1.25       | Instana requires Kubernetes version 1.25 or higher  |
| 4   | OCP version > 4.13              | Required to deploy Instana on OpenShift             |

### Helm

Helm is required to deploy Helm charts. To install Helm:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
```

### Storage Class

Instana requires `ReadWriteMany` (RWX) or `ReadWriteOnce` (RWO) storage for raw spans and monitoring data. Ensure a default
storage class is set on the cluster, otherwise the installation of data stores will fail.

To verify the default storage class:

```bash
kubectl get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

If no default is set, run:

```bash
kubectl patch storageclass <storageclass_name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Kubernetes Version

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
kubectl version --short
```

### OCP Cluster and Version

If using OpenShift, the OCP version must be >4.13 and OpenShift CLI (`oc`) must be installed. Check the OpenShift version:

```bash
oc version
```

## Configuration

Before running the installation script, ensure the following configurations are set.

### CLUSTER_TYPE Environment Variable

Set the `CLUSTER_TYPE` environment variable based on your cluster type (`ocp`, `eks`, `aks`, `gke`).
For ARO and ROSA set the `CLUSTER_TYPE` environment variable as `ocp`.
For more details on setting up ARO and ROSA infrastructure and setup follow [ARO&ROSA](/docs/ARO&ROSA.md)

```bash
export CLUSTER_TYPE=ocp
```

### config.env File

Create a `config.env` file in the same directory as the tool. It should include the Instana `DOWNLOAD_KEY`, `SALES_KEY`
, `BASE_DOMAIN`, and `AGENT_ACCEPTOR` information.

Example:

```bash
SALES_KEY=
DOWNLOAD_KEY=

BASE_DOMAIN=<base-domain>
AGENT_ACCEPTOR=agent-acceptor.<base-domain>

INSTANA_UNIT_NAME=unit0
INSTANA_TENANT_NAME=tenant0

INSTANA_ADMIN_USER=admin@instana.local
INSTANA_ADMIN_PASSWORD=mypass

# Registry configuration environment variables are needed only if a custom registry is used.
REGISTRY_URL=<registry url>
REGISTRY_USERNAME=<registry username>
REGISTRY_PASSWORD=<registry password>

# Helm repository configuration environment variables are needed only if a custom repository is used.
HELM_REPO_URL=<helm repository url>
HELM_REPO_USERNAME=<helm repository username>
HELM_REPO_PASSWORD=<helm repository password>

# The following environment variables are only required if the cluster type is aks (Azure Cloud).
AZURE_STORAGE_ACCOUNT=<azure file storage account name>
AZURE_STORAGE_FILESHARE_NAME=<name of the fileshare in azure storage account>
AZURE_STORAGE_ACCOUNT_KEY=<azure storage account key>
AZURE_STORAGE_CAPACITY=<PersistentVolume size> # By default 100Gi
```

## Necessary Custom Values

Make sure to customize these values in the respective value files.

### BeeInstana

In `values/beeinstana/custom_values.yaml`, set the `aggregator.volumes.live.storageClass` to your default storage class:

```yaml
aggregator:
  volumes:
    live:
      storageClass: "your-storage-class"
```

### Core

#### Configure Instana Backend Versions

> [! NOTE]
> We can configure the Instana backend version in the `CoreSpec` [Reference](https://www.ibm.com/docs/en/instana-observability/current?topic=edition-api-reference#imageconfig)

_Example of_ configuring the Instana backend release:

In `values/core/custom_values.yaml`, configure the `imageConfig`.

```yaml
imageConfig:
  tag: 3.289.617.0
  # registry: artifact-public.instana.io
  # repository: backend
```

#### Email Configuration:

_Example of_ `emailConfig`:

In `values/core/custom_values.yaml`, update the SMTP host and storage configurations as per the deployment environment:

```yaml
emailConfig:
  smtpConfig:
    from: "your-email-address"
    host: "your-smtp-host"
```

_Example of_ `storageConfigs` with `pvcConfig`:

- `storageConfigs.rawSpans.pvcConfig.storageClassName`
- `storageConfigs.eumSourceMaps.pvcConfig.storageClassName`

```yaml
storageConfigs:
  rawSpans:
    pvcConfig:
      storageClassName: "your-storage-class"
  eumSourceMaps:
    pvcConfig:
      storageClassName: "your-storage-class"
```
for enabling syntetics with pvc configs:
```yaml
storageConfigs:
  synthetics:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 10Gi
      storageClassName: "your-storage-class"
  syntheticsKeystore:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 10Gi
      storageClassName: "your-storage-class"
```

_Example of_ `storageConfigs` with `s3Config`:
* Provision IAM Role with S3 Access
* Create IAM Trust Relationship with Service Account
* ServiceAccountAnnotations should be configured in the core spec

- `storageConfigs.rawSpans.s3Config`
- `storageConfigs.eumSourceMaps.s3Config`

```yaml
storageConfigs:
  rawSpans:
    s3Config:
      endpoint: s3.<s3-region>.amazonaws.com
      region: <s3-region>
      bucket: <bucket-name>
      prefix: <prefix-name>
      storageClass: <storage-class>
      bucketLongTerm: <bucket-name-longterm>
      prefixLongTerm: <prefix-name-longterm>
      storageClassLongTerm: <storage-class-longterm>
  eumSourceMaps:
    s3Config:
      endpoint: s3.<s3-region>.amazonaws.com
      region: <s3-region>
      bucket: <bucket-name>
      prefix: <prefix-name>
      storageClass: <storage-class>
      bucketLongTerm: <bucket-name-longterm>
      prefixLongTerm: <prefix-name-longterm>
      storageClassLongTerm: <storage-class-longterm>
serviceAccountAnnotations:
  eks.amazonaws.com/role-arn: "arn:aws:iam::<ReplaceAccountID>:role/<IAM Role>"
```
_Example of_ `storageConfigs` for `azure`:
modify the instana_values_aks.yaml or create custom_values.yaml and add the below
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
      storageClassName: ""
  eumSourceMaps:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      volumeName: "azure-volume"
      storageClassName: "" ## provide the sc which support read write many operation , eg: azurefile
```
_Example of_ `pv_template` for `azure`:
modify the pv_template_aks.yaml and add the storageclass name :
```yaml
storageClassName: azurefile ##use "azurefile" if your aks cluster is having the preconfigured storageclasses
```

Configuration fields:
| Field                  | Description                                                                                   |
|------------------------|-----------------------------------------------------------------------------------------------|
| `endpoint`             | The S3 endpoint for the specified AWS region. Replace `<s3-region>` with your desired region (e.g., `us-west-2`). |
| `region`               | The AWS region where the S3 bucket is located (e.g., `us-west-2`).                             |
| `bucket`               | The name of the S3 bucket where the data will be stored (e.g., `my-data-bucket`).              |
| `prefix`               | The path or folder in the S3 bucket where the data is stored (e.g., `rawspans/`).              |
| `storageClass`         | The storage class for primary data (e.g., `Standard`, `Intelligent-Tiering`, `Glacier`).        |
| `bucketLongTerm`       | The name of the S3 bucket for long-term storage of data (e.g., `my-longterm-backups`).         |
| `prefixLongTerm`       | The path or folder in the long-term storage bucket for organizing the data (e.g., `archives/`).|
| `storageClassLongTerm` | The storage class for long-term data storage (e.g., `Standard`, `Deep_Archive`).                |

_Example of_ `featureflags`
```yaml
featureFlags:
  - name: feature.logging.enabled
    enabled: true
  - name: feature.synthetics.enabled
    enabled: true
  - name: feature.internal.monitoring.unit
    enabled: true

```
note: Before enabling Synthetic monitoring, configure two external storage configurations in the storageConfigs section in the Core spec (synthetics, syntheticsKeystore)

```yaml
storageConfigs:
  synthetics:
    s3Config:
      endpoint: s3.<s3-region>.amazonaws.com
      region: <s3-region>
      bucket: <bucket-name>
      prefix: <prefix-name>
      storageClass: <storage-class>
      bucketLongTerm: <bucket-name-longterm>
      prefixLongTerm: <prefix-name-longterm>
      storageClassLongTerm: <storage-class-longterm>
  syntheticsKeystore:
    s3Config:
      endpoint: s3.<s3-region>.amazonaws.com
      region: <s3-region>
      bucket: <bucket-name>
      prefix: <prefix-name>
      storageClass: <storage-class>
      bucketLongTerm: <bucket-name-longterm>
      prefixLongTerm: <prefix-name-longterm>
      storageClassLongTerm: <storage-class-longterm>
serviceAccountAnnotations:
  eks.amazonaws.com/role-arn: "arn:aws:iam::<ReplaceAccountID>:role/<IAM Role>"
```

## Installation

### Tool Usage

The main script for installation is `shce.sh`.

To install all data stores and the Instana backend:

```bash
./shce.sh apply
```

To install only data stores:

```bash
./shce.sh datastores apply
```

### Install Specific Data Stores

To install individual data stores, such as Kafka or Postgres:

```bash
./shce.sh datastores apply kafka
./shce.sh datastores apply postgres
```

### Instana backend configurations

At any time during or after the Instana backend installation, you can update the Instana Core configuration values in `values/core/custom_values.yaml` and `values/unit/custom_values.yaml`. Run the following command to apply the backend configurations:

```bash
./shce.sh backend apply
```

## Setting up load balancers and DNS

Depending on your cluster type, you may need to setup DNS for the Acceptor and Gateway components so that these components can be
exposed to the public Internet and allow you to access the Instana UI.
For Red Hat OpenShift, those services are exposed via `route`, and for Kubernetes(EKS/AKS/GKE), they are `LoadBalancer` services
in `instana-core` namespace.

### DNS settings

Make sure you have a domain name and a DNS zone for your Instana environment. Then, add DNS A records in the zone for the
following domains:

| Domain | Description                                  | Example name            |
|-------------|----------------------------------------------|---------------------|
|Base domain </br> `<base_domain>` |The fully qualified domain name (FQDN) that you can use to reach Instana. Points to the public IP address of your host. |`instana.example.com`|
|Agent acceptor subdomain </br> `agent-acceptor.<base_domain>` |Domain name for Instana agent traffic. Points to the public IP address of your host.|`agent-acceptor.instana.example.com`|
|OTLP HTTP acceptor subdomain </br> `otlp-http.<base_domain>` |Domain name for OpenTelemetry collector `OTLP/HTTP` traffic. Points to the public IP address of your host.|`otlp-http.instana.example.com`|
|OTLP gRPC acceptor subdomain </br> `otlp-grpc.<base_domain>` |Domain name for OpenTelemetry collector `OTLP/gRPC` traffic. Points to the public IP address of your host.|`otlp-grpc.instana.example.com`|
|Tenant and unit subdomain </br> `<unit-name>-<tenant-name>.<base_domain>` |Domain name for a unit and its tenant. Points to the public IP address of your host. |`test-marketing.instana.example.com`|

For detailed steps about adding DNS A records, refer to the documentation of your domain registrar.
