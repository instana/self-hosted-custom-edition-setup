# Self Hosted Custom Edition Installation Script

This script helps you install the Self Hosted Custom Edition on OCP (Red Hat OpenShift Container Platform), EKS (Amazon Elastic
Kubernetes Service), AKS (Azure Kubernetes Service), and GKE (Google Kubernetes Engine) clusters.

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

Set the `CLUSTER_TYPE` environment variable based on your cluster type (`ocp`, `eks`, `aks`, `gke`):

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

In `values/core/custom_values.yaml`, update the SMTP host and storage configurations:

- `emailConfig.smtpConfig.host`
- `storageConfigs.rawSpans.pvcConfig.storageClassName`
- `storageConfigs.eumSourceMaps.pvcConfig.storageClassName`

Example:

```yaml
emailConfig:
  smtpConfig:
    host: "your-smtp-host"
```

```yaml
storageConfigs:
  rawSpans:
    pvcConfig:
      storageClassName: "your-storage-class"
  eumSourceMaps:
    pvcConfig:
      storageClassName: "your-storage-class"
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