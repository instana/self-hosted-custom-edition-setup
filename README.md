# Self hosted custom edition installation script

This script helps you install the Instana Self Hosted Custom Edition on OCP (Red Hat OpenShift Container Platform), EKS (Amazon Elastic Kubernetes Service), AKS (Azure Kubernetes Service), GKE (Google Kubernetes Engine), ARO (Azure Red Hat OpenShift) and ROSA (Red Hat OpenShift Service on AWS) clusters, with support only for both x86_64 and ARM64 architectures.

The tool is based on Helm charts and values and allows for custom installations tailored to your needs.


## Contents
  1. [Configure loadbalancer and dns](#setting-up-load-balancers-and-dns)
  2. [Configure storageconfig](#storageconfig)
  3. [Configure necessary values](#necessary-custom-values)
  3. [Installation](#to-install-all-data-stores-and-the-instana-backend)
      1. [Install datastores](#to-install-only-data-stores)
      2. [Configure Instana backend](#instana-backend-configurations)

## Prerequisite and preparing

Before installation, ensure the following prerequisites are met:

| #   | Prerequisite                   | Reason                                             |
| --- | ------------------------------ | -------------------------------------------------- |
| 1   | Helm is installed              | Needed to deploy Helm charts                       |
| 2   | A default storage class is set | Required for successful data store installations   |
| 3   | Kubernetes version > 1.25      | Instana requires Kubernetes version 1.25 or higher |
| 4   | OCP version > 4.13             | Required to deploy Instana on OpenShift            |
| 5   | yq                             | Required to parse yaml            |

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

- ### How to access the code?
  Clone the repository
  ```bash
  git clone https://github.com/instana/self-hosted-custom-edition-setup.git
  ```
  Navigate to the Project Directory
  ```bash
  cd ./self-hosted-custom-edition-setup/deploy
  ```


## Configuration

Before running the installation script, ensure the following configurations are set.
> [!NOTE]
> All the below configuration and steps should be added and executed within the project directory (deploy/) .

- ### `config.env`

  Create a `config.env` file in the same directory as the tool. It should include the Instana `DOWNLOAD_KEY`, `SALES_KEY`, `AGENT_KEY` and `CLUSTER_TYPE`

> [!NOTE]
> If `AGENT_KEY` is not configured, an auto-generated key will be used.

  Example:

  ```bash
  SALES_KEY=
  DOWNLOAD_KEY=
  AGENT_KEY=
  CLUSTER_TYPE=

  INSTANA_UNIT_NAME=unit0
  INSTANA_TENANT_NAME=tenant0

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

## Necessary custom values

Make sure to customize these values in the respective value files.
> [!NOTE]
> To configure custom values for components, update file `instana-values.yaml` or create `custom-values.yaml` under respective component.

**_For Example_**: To configure Instana tenant/unit admin and password, update `deploy/values/unit/instana-values.yaml` or create `custom-values.yaml` under `deploy/values/unit` to use custom values.
```yaml
initialAdminUser: admin@instana.local
initialAdminPassword: "mypass"
```


### BeeInstana

In `values/beeinstana/custom-values.yaml`, set the `aggregator.volumes.live.storageClass` to your default storage class:

```yaml
aggregator:
  volumes:
    live:
      storageClass: "your-storage-class"
```

### Instana Enterprise Operator

_Example of_ configuring the Instana Enterprise Operator

In `values/instana-operator/custom-values.yaml`, configure image tag.

```yaml
operator:
  image:
    tag: x.x.x
webhook:
  image:
    tag: x.x.x
```

### Core

#### Configure instana backend versions

> [!NOTE]
> We can configure the Instana backend version in the `CoreSpec` [Reference](https://www.ibm.com/docs/en/instana-observability/current?topic=edition-api-reference#imageconfig)

_Example of_ configuring the Instana backend release:

In `values/core/custom-values.yaml`, configure the `imageConfig`.

```yaml
imageConfig:
  tag: 3.x.x-x
  # registry: artifact-public.instana.io
  # repository: backend
```

#### Email configuration:

_Example of_ `emailConfig`:

In `values/core/custom-values.yaml`, update the SMTP host and storage configurations as per the deployment environment:

```yaml
emailConfig:
  smtpConfig:
    from: "your-email-address"
    host: "your-smtp-host"
```

### Storageconfig

- #### Storageconfig with `pvcConfig`
  
_Example of_ `storageConfigs` with `pvcConfig`:

- `storageConfigs.rawSpans.pvcConfig`
- `storageConfigs.eumSourceMaps.pvcConfig`

```yaml
storageConfigs:
  rawSpans:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"
  eumSourceMaps:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"
```

- #### Storageconfig with `s3Config`

_Example of_ `storageConfigs` with `s3Config`:

- Provision IAM Role with S3 Access
- Create IAM Trust Relationship with Service Account
- ServiceAccountAnnotations should be configured in the core spec

* `storageConfigs.rawSpans.s3Config`
* `storageConfigs.eumSourceMaps.s3Config`

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

- #### Storageconfig with `Azure`

_Example of_ `storageConfigs` for `Azure`:

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
```

_Example of_ `pv_template` for `azure`:

> [!NOTE]
> Modify the `pv_template_aks.yaml` and update the `storageClassName`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: azure-volume
spec:
  capacity:
    storage: {{ AZURE_STORAGE_CAPACITY }}
  accessModes:
    - ReadWriteMany
  azureFile:
    secretName: azure-storage-account
    secretNamespace: instana-core
    shareName: {{ AZURE_STORAGE_FILESHARE_NAME }}
    readOnly: false
  storageClassName: "" # use "azurefile" if you have azurefile as one of the storage classes on aks
  persistentVolumeReclaimPolicy: Retain
```

---

Configuration fields for s3Config:
| Field | Description |
|------------------------|-----------------------------------------------------------------------------------------------|
| `endpoint` | The S3 endpoint for the specified AWS region. Replace `<s3-region>` with your desired region (e.g., `us-west-2`). |
| `region` | The AWS region where the S3 bucket is located (e.g., `us-west-2`). |
| `bucket` | The name of the S3 bucket where the data will be stored (e.g., `my-data-bucket`). |
| `prefix` | The path or folder in the S3 bucket where the data is stored (e.g., `rawspans/`). |
| `storageClass` | The storage class for primary data (e.g., `STANDARD`, `Intelligent-Tiering`, `Glacier`). |
| `bucketLongTerm` | The name of the S3 bucket for long-term storage of data (e.g., `my-longterm-backups`). |
| `prefixLongTerm` | The path or folder in the long-term storage bucket for organizing the data (e.g., `archives/`).|
| `storageClassLongTerm` | The storage class for long-term data storage (e.g., `STANDARD`, `Deep_Archive`). |

### Configuring FeatureFlags

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

For additional feature flags visit the [link](https://www.ibm.com/docs/en/instana-observability/current?topic=edition-enabling-optional-features)

> [!NOTE]
> Before enabling Synthetic monitoring, configure storage configurations in the storageConfigs section in the Core spec (`synthetics`, `syntheticsKeystore`)

_Example of_ `storageConfigs` with `pvcConfig` for `synthetics` and `syntheticsKeystore`:

- `storageConfigs.synthetics.pvcConfig`
- `storageConfigs.syntheticsKeystore.pvcConfig`

```yaml
storageConfigs:
  synthetics:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"
  syntheticsKeystore:
    pvcConfig:
      accessModes:
        - ReadWriteMany
      resources:
        requests:
          storage: 100Gi
      storageClassName: "your-storage-class"
```

_Example of_ `storageConfigs` with `s3Config` for `synthetics` and `syntheticsKeystore`:

- `storageConfigs.synthetics.s3Config`
- `storageConfigs.syntheticsKeystore.s3Config`

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
```

## Installation

### Tool usage

The main script for installation is `shce.sh`.

#### To install all data stores and the Instana backend:

```bash
./shce.sh apply
```

#### To install only data stores:

```bash
./shce.sh datastores apply
```

#### Install specific data stores

To install individual data stores, such as Kafka or Postgres:

```bash
./shce.sh datastores apply kafka
./shce.sh datastores apply postgres
```

#### Instana backend configurations

At any time during or after the Instana backend installation, you can update the Instana Core configuration values in `values/core/custom-values.yaml` and `values/unit/custom-values.yaml`. Run the following command to apply the backend configurations:

```bash
./shce.sh backend apply
```

## Setting up load balancers and DNS

Depending on your cluster type, you may need to setup DNS for the Acceptor and Gateway components so that these components can be
exposed to the public Internet and allow you to access the Instana UI.
For Red Hat OpenShift, those services are exposed via `route`, and for Kubernetes(EKS/AKS/GKE), they are `LoadBalancer` services
in `instana-core` namespace.

### DNS settings

All the DNS related changes needs to be specified on the core/instana-values.yaml or core/custom-values.yaml

- <u> **Base Domain** </u>
  Base domain is a mandatory field , which will represent the DNS for the instana application
  ```yaml
  baseDomain: "instana.example.com"
  ```

- <u> **Agent Acceptor** </u>
The acceptor is the endpoint that Instana agents need to reach to deliver traces or metrics to the Instana backend. The acceptor is usually a subdomain for the baseDomain that is configured previously in the Basic configuration section.
  ```yaml
  acceptors:
    agent:
      host: "agent.instana.example.com"
  ```

- <u> **Gateway configuration** </u>
  To disable gateway configuration , modify the below on core/custom-values.yaml. By default its enabled
  ```yaml
  gatewayConfig:
    enabled: false
  ```
  Creating LoadBalancer services automatically. Your Custom Edition environment supports automatically creating the Kubernetes LoadBalancer services for the gateway-v2 component. You need not create the LoadBalancer services manually.

  ```yaml
  gatewayConfig:
    gateway:
      loadBalancerConfig:
        enabled: true
  ```

> [!NOTE]
> For vanilla Openshift cluster, you dont need to enable the loadBalancerConfig. For other Kubernetes flavours like ARO , ROSA , AKS , GKE & AWS you can enable this . Also if you have your own public ip you can add that under the loadBalancerConfig

  ```yaml
  gatewayConfig:
    enabled: true
    gateway:
      loadBalancerConfig:
        enabled: true # enables automatic loadbalancer creation
        ip: <your public IP>
        externalTrafficPolicy: Local # default
        annotations:
          your-annotation-key: your-annotation-value
  ````

  You can configure the hosts and ports for the following types of ingress traffic:

  ```Instana Agent
  Synthetics
  Serverless
  OTLP (HTTP/gRPC)
  EUM
  ```
  
  - The following examples show how to configure your acceptor traffic ingestion based on different requirements:
  #### **Use subdomains with a single port (443)** 
  
  This approach allows you to expose only one port (443) while using subdomains to differentiate traffic for each acceptor.

  ```yaml
  spec:
    acceptors:
      agent:
        host: ingress.<instana.example.com>
        port: 443
      otlp:
        http:
          host: otlp-http.<instana.example.com>
          port: 443
        grpc:
          host: otlp-grpc.<instana.example.com>
          port: 443
      eum:
        host: eum.<instana.example.com>
        port: 443
      synthetics:
        host: synthetics.<instana.example.com>
        port: 443
      serverless:
        host: serverless.<instana.example.com>
        port: 443
  ```

  #### **Use a single domain with different ports**
  
  This approach allows you to use a single domain while differentiating acceptor traffic based on port numbers.

  ```yaml
  spec:
    acceptors:
      agent:
        port: 1444
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
- <u>Enabling support for single ingress domain</u>
  Custom Edition environment can route traffic for all tenants through a single base domain . After enabling this behaviour, the URL for accessing the UI of all your Instana tenants is served at basedomain.com/tenantname/unitname instead of unitname-tenantname.basedomain.com.

  ```yaml
  properties:
  - name: config.url.format.pathStyle
    value: "true"
  ```

Make sure you have a domain name and a DNS zone for your Instana environment. Then, add DNS A records in the zone for the
following domains:

| Domain                                                                    | Description                                                                                                             | Example name                         |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Base domain </br> `<base_domain>`                                         | The fully qualified domain name (FQDN) that you can use to reach Instana. Points to the public IP address of your host. | `instana.example.com`                |
| Agent acceptor subdomain </br> `agent-acceptor.<base_domain>`             | Domain name for Instana agent traffic. Points to the public IP address of your host.                                    | `agent-acceptor.instana.example.com` |
| OTLP HTTP acceptor subdomain </br> `otlp-http.<base_domain>`              | Domain name for OpenTelemetry collector `OTLP/HTTP` traffic. Points to the public IP address of your host.              | `otlp-http.instana.example.com`      |
| OTLP gRPC acceptor subdomain </br> `otlp-grpc.<base_domain>`              | Domain name for OpenTelemetry collector `OTLP/gRPC` traffic. Points to the public IP address of your host.              | `otlp-grpc.instana.example.com`      |
| Tenant and unit subdomain </br> `<unit-name>-<tenant-name>.<base_domain>` | Domain name for a unit and its tenant. Points to the public IP address of your host.                                    | `test-marketing.instana.example.com` |

For detailed steps about adding DNS A records, refer to the documentation of your domain registrar.

> [!NOTE]
> For all further custom configurations, consult the public [doc](https://www.ibm.com/docs/en/instana-observability/current?topic=backend-installing-custom-edition)

## Remove Instana
To delete all data stores and the Instana backend:

```bash
./shce.sh delete
```
### Delete specific data stores

To delete individual data stores, such as Kafka or Postgres:

```bash
./shce.sh datastores delete kafka
./shce.sh datastores delete postgres
```
