# Nemo Retriever Embedding Helm Chart

This Helm Chart simplifies Embedding NIM deployment on Kubernetes. It aims to support deployment with a variety of possible cluster, GPU and storage confurations.

NIMs are intended to be run on a system with NVIDIA GPUs, with the type and number of GPUs depending on the model. To use helm, you must have a Kubernetes cluster with appropriate GPU nodes and the [GPU Operator](https://github.com/NVIDIA/gpu-operator) installed.

## Setting up the environment

If you haven't set up your NGC API key and do not know exactly which NIM you want to download and deploy,
see the information in the [User Guide](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#generating-api-key).

This helm chart requires that you have a secret with your NGC API key configured for downloading private images, and one with your NGC API key (below named ngc-api). These will likely have the same key in it, but they will have different formats (dockerconfig.json vs opaque). See [Creating Secrets](#Creating-Secrets) below.

These instructions will assume that you have your `NGC_API_KEY` exported in the environment.

```bash
export NGC_API_KEY="<YOUR NGC API KEY>"
```

### Fetching the Helm Chart

You can fetch the helm chart from NGC by executing the following command:

```bash
helm fetch https://helm.ngc.nvidia.com/nim/nvidia/charts/text-embedding-nim-1.0.0.tgz --username='$oauthtoken' --password=$NGC_API_KEY
```

### Namespace

You can choose to deploy to whichever namespace is appropriate, but for documentation purposes we will deploy to a namespace named `nrem`.

```bash
kubectl create namespace nrem
```

### Creating Secrets

Use the following script below to create the expected secrets for this helm chart.
```bash

DOCKER_CONFIG='{"auths":{"nvcr.io":{"username":"$oauthtoken", "password":"'${NGC_API_KEY}'" }}}'
echo -n $DOCKER_CONFIG | base64 -w0
NGC_REGISTRY_PASSWORD=$(echo -n $DOCKER_CONFIG | base64 -w0 )

cat <<EOF > imagepull.yaml
apiVersion: v1
kind: Secret
metadata:
  name: nvcrimagepullsecret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ${NGC_REGISTRY_PASSWORD}
EOF

cat <<EOF > ngc-cli.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ngc-api
type: Opaque
data:
  NGC_CLI_API_KEY: ${NGC_API_KEY}
EOF

kubectl apply -n nrem -f imagepull.yaml
kubectl apply -n nrem -f ngc-cli.yaml
```

### Configuration Considerations

The following deployment commands will by default create a single deployment with one replica using the NV-EmbedQA-E5-V5 model. The following options can be used to make modifications to the behavior. See below for all parameters.

 - `image.repository` -- The container (Embedder NIM) to deploy
 - `image.tag` -- The version of that container (Embedder NIM)
 - Storage options, based on the environment and cluster in use
 - `resources` -- Use this option when a model requires more than the default of one GPU. See below for [support matrix](#support-matrix) and resource requirements.
 - `env` -- Which is an array of environment variables presented to the container, if advanced configuration is needed

 <!-- See [support matrix](../support-matrix.md) for details about the GPUs to request to meet the GPU memory requirements of the model on the available hardware. -->

### Deploying

Basic deploymnet

```bash
helm upgrade --install \
  --namespace nrem \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
```

After deploying check the pods to ensure that it is running, initial image pull and model download can take upwards of 15 minutes.

```bash
kubectl get pods -n nrem
```

The pod should eventually end up in the running state.

```bash
NAME              READY   STATUS    RESTARTS   AGE
nemo-embedding-ms-0   1/1     Running   0          8m44s
```


### Storage

Storage is a particular concern when setting up NIMs. Models can be quite large, and you can fill disk downloading things to emptyDirs or other locations around your pod image. It is best to ensure you have persistent storage of some kind mounted on your pod.

This chart supports two general categories:
  1. Persistent Volume Claims (enabled with `persistence.enabled`)
  2. hostPath (enabled with `persistences.hostPath`)

The chart will default to use the `standard` storage class and will create a `PersistentVolume` and a `PersistentVolumeClaim`.

If you do not have a `Storage Class Provisioner` which creates `PersistentVolume`s automatically, then set the value `persistence.createPV=true`. This is also necessary when you are using `persistence.hostPath` on minikube.

If you have an existing `PersistentVolumeClaim` where you'd like the models to be stored at, then pass that value in at `persistence.exsitingClaimName`.

See additional options below in [Parameters](#parameters).

#### Recommended configuration for Minikube

Minkube will create a hostPath based PV and PVC by default with this chart.
We recommend that you add the following to your helm commands.

```bash
--set persistence.class=standard
```


### Deploying Snowflake Arctic Embedding

Run the helm command with the following parameters, update your version in `image.tag`:

```bash
helm upgrade --install \
  --namespace nrem \
  --set image.repository=nvcr.io/nim/snowflake/arctic-embed-l \
  --set image.tag=1.0.0 \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
```

### Deploying Mistral 7B

Create a values files for the resource requirements of the 7B Model:

```yaml
# values-mistral.yaml
resources:
  limits:
    ephemeral-storage: 28Gi
    nvidia.com/gpu: 1
    memory: 32Gi
    cpu: "16000m"
  requests:
    ephemeral-storage: 28Gi
    nvidia.com/gpu: 1
    memory: 16Gi
    cpu: "4000m"
```
Then deploy the model:

```bash
helm upgrade --install \
  --namespace nrem \
  -f values-mistral.yaml \
  --set image.repository=nvcr.io/nim/nvidia/nv-embedqa-mistral-7b-v2 \
  --set image.tag=1.0.0 \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
```

## Running inference

In the previous example the API endpoint is exposed on port 8080 through the Kubernetes service of the default type with no ingress, since authentication is not handled by the NIM itself. The following commands assume the `NV-EmbedQA-E5-V5` model was deployed.

Adjust the "model" value in the request JSON body to use a different model.

Use the following command to port-forward the service to your local machine to test inference.

```bash
kubectl port-forward -n nrem service/nemo-embedding-ms 8080:8080
```

Then try a request:

```bash
curl -X 'POST' \
  'http://localhost:8080/v1/embeddings' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "input": "hello world",
    "model": "nv-embedqa-e5-v5",
    "input_type": "passage"
  }'
```

## Parameters

### Deployment parameters

| Name                              | Description                                                                                                                                                              | Value   |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- |
| `affinity`                        | Affinity settings for deployment. Allows to constraint pods to nodes.                                                                                      | `{}`    |
| `securityContext`                 | Specify privilege and access control settings for Container(Only affects the main container)                                                                             | `{}`    |
| `envVars`                         | Adds arbitrary environment variables to the main container - Key Value Pairs                                                                                             | `{}`    |
| `extraVolumes`                    | Adds arbitrary additional volumes to the deployment set definition                                                                                                       | `{}`    |
| `image.repository`                | NIM-LLM Image Repository                                                                                                                                                 | `""`    |
| `image.tag`                       | Image tag                                                                                                                                                                | `""`    |
| `image.pullPolicy`                | Image pull policy                                                                                                                                                        | `""`    |
| `imagePullSecrets`                | Specify secret names that are needed for the main container and any init containers. Object keys are the names of the secrets                                            | `{}`    |
| `nodeSelector`                    | Specify labels to ensure that NeMo Inference is deployed only on certain nodes (likely best to set this to `nvidia.com/gpu.present: "true"` depending on cluster setup). | `{}`    |
| `podAnnotations`                  | Specify additional annotation to the main deployment pods                                                                                                                | `{}`    |
| `podSecurityContext`              | Specify privilege and access control settings for pod (Only affects the main pod).                                                                                       |         |
| `podSecurityContext.runAsUser`    | Specify user UID for pod.                                                                                                                                                | `1000`  |
| `podSecurityContext.runAsGroup`   | Specify group ID for pod.                                                                                                                                                | `1000`  |
| `podSecurityContext.fsGroup`      | Specify file system owner group id.                                                                                                                                      | `1000`  |
| `replicaCount`                    | Specify replica count for deployment.                                                                                                                                    | `1`     |
| `resources`                       | Specify resources limits and requests for the running service.                                                                                                           |         |
| `resources.limits.nvidia.com/gpu` | Specify number of GPUs to present to the running service.                                                                                                                | `1`     |
| `serviceAccount.create`           | Specifies whether a service account should be created.                                                                                                                   | `false` |
| `serviceAccount.annotations`      | Specifies annotations to be added to the service account.                                                                                                                | `{}`    |
| `serviceAccount.automount`        | Specifies whether to automatically mount the service account to the container.                                                                                           | `{}`    |
| `serviceAccount.name`             | Specify name of the service account to use. If it is not set and create is true, a name is generated using a fullname template.                                          | `""`    |
| `tolerations`                     | Specify tolerations for pod assignment. Allows the scheduler to schedule pods with matching taints.                                                                      |         |

### Autoscaling parameters

Values used for autoscaling. If autoscaling is not enabled, these are ignored.
They should be overridden on a per-model basis based on quality-of-service metrics as well as cost metrics.
This isn't recommended except with usage of the custom metrics API using something like the prometheus-adapter.
Standard metrics of CPU and memory are of limited use in scaling NIM

| Name                      | Description                               | Value   |
| ------------------------- | ----------------------------------------- | ------- |
| `autoscaling.enabled`     | Enable horizontal pod autoscaler.         | `false` |
| `autoscaling.minReplicas` | Specify minimum replicas for autoscaling. | `1`     |
| `autoscaling.maxReplicas` | Specify maximum replicas for autoscaling. | `10`    |
| `autoscaling.metrics`     | Array of metrics for autoscaling.         | `[]`    |

### Ingress parameters

| Name                                    | Description                                                                                                   | Value                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `ingress.enabled`                       | Enables ingress.                                                                                              | `false`                  |
| `ingress.className`                     | Specify class name for Ingress.                                                                               | `""`                     |
| `ingress.annotations`                   | Specify additional annotations for ingress.                                                                   | `{}`                     |
| `ingress.hosts`                         | Specify list of hosts each containing lists of paths.                                                         |                          |
| `ingress.hosts[0].host`                 | Specify name of host.                                                                                         | `chart-example.local`    |
| `ingress.hosts[0].paths[0].path`        | Specify ingress path.                                                                                         | `/`                      |
| `ingress.hosts[0].paths[0].pathType`    | Specify path type.                                                                                            | `ImplementationSpecific` |
| `ingress.hosts[0].paths[0].serviceType` | Specify service type. It can be can be nemo or openai -- make sure your model serves the appropriate port(s). | `openai`                 |
| `ingress.tls`                           | Specify list of pairs of TLS secretName and hosts.                                                            | `[]`                     |

### Probe parameters

| Name                                 | Description                                                       | Value              |
| ------------------------------------ | ----------------------------------------------------------------- | ------------------ |
| `livenessProbe.enabled`              | Enable livenessProbe                                              | `true`             |
| `livenessProbe.method`               | LivenessProbe http or script, but no script is currently provided | `http`             |
| `livenessProbe.path`                 | LivenessProbe endpoint path                                       | `/v1/health/live`  |
| `livenessProbe.initialDelaySeconds`  | Initial delay seconds for livenessProbe                           | `15`               |
| `livenessProbe.timeoutSeconds`       | Timeout seconds for livenessProbe                                 | `1`                |
| `livenessProbe.periodSeconds`        | Period seconds for livenessProbe                                  | `10`               |
| `livenessProbe.successThreshold`     | Success threshold for livenessProbe                               | `1`                |
| `livenessProbe.failureThreshold`     | Failure threshold for livenessProbe                               | `3`                |
| `readinessProbe.enabled`             | Enable readinessProbe                                             | `true`             |
| `readinessProbe.path`                | Readiness Endpoint Path                                           | `/v1/health/ready` |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe                          | `15`               |
| `readinessProbe.timeoutSeconds`      | Timeout seconds for readinessProbe                                | `1`                |
| `readinessProbe.periodSeconds`       | Period seconds for readinessProbe                                 | `10`               |
| `readinessProbe.successThreshold`    | Success threshold for readinessProbe                              | `1`                |
| `readinessProbe.failureThreshold`    | Failure threshold for readinessProbe                              | `3`                |
| `startupProbe.enabled`               | Enable startupProbe                                               | `true`             |
| `startupProbe.path`                  | StartupProbe Endpoint Path                                        | `/v1/health/ready` |
| `startupProbe.initialDelaySeconds`   | Initial delay seconds for startupProbe                            | `40`               |
| `startupProbe.timeoutSeconds`        | Timeout seconds for startupProbe                                  | `1`                |
| `startupProbe.periodSeconds`         | Period seconds for startupProbe                                   | `10`               |
| `startupProbe.successThreshold`      | Success threshold for startupProbe                                | `1`                |
| `startupProbe.failureThreshold`      | Failure threshold for startupProbe                                | `180`              |


### Storage parameters

| Name                                                              | Description                                                                                                                                                                                                                       | Value                    |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `persistence`                                                     | Specify settings to modify the path `/model-store` if `model.legacyCompat` is enabled else `/.cache` volume where the model is served from.                                                                                       |                          |
| `persistence.enabled`                                             | Enable persistent volumes.                                                                                                                                                                                                        | `false`                  |
| `persistence.existingClaimName`                                   | Secify existing claim. If using existingClaim, run only one replica or use a ReadWriteMany storage setup.                                                                                                                         | `""`                     |
| `persistence.class       `                                        | Specify persistent volume storage class. If null (the default), no storageClassName spec is set, choosing the default provisioner. | `""`                     |
| `persistence.retain       `                                        | Specify whether the Persistent Volume should survive when the helm chart is upgraded or deleted. | `""`                     |
| `persistence.createPV       `                                        | True if you need to have the chart create a PV for hostPath use cases. | `false`                     |
| `persistence.accessMode`                                          | Specify accessModes. If using an NFS or similar setup, you can use ReadWriteMany.                                                                                                                                                 | `ReadWriteOnce`          |
| `persistence.size`                                                | Specify size of claim (e.g. 8Gi).                                                                                                                                                                                                 | `50Gi`                   |
| l`hostPath`                                                        | Configures model cache on local disk on the nodes using hostPath -- for special cases. One should investigate and understand the security implications before using this option.                                                  |        `""`              |

### Service parameters

| Name                  | Description                                            | Value       |
| --------------------- | ------------------------------------------------------ | ----------- |
| `service.type`        | Specify service type for the deployment.               | `ClusterIP` |
| `service.name`        | Override the default service name                      | `""`        |
| `service.http_port`   | Specify HTTP Port for the service.                     | `8080`      |
| `service.annotations` | Specify additional annotations to be added to service. | `{}`        |


### Monitoring

| Name                  | Description                                                                  | Value       |
| --------------------- | ---------------------------------------------------------------------------- | ----------- |
| `zipkinDeployed`      | Specify if this chart should deploy zipkin for metrics.                      | `false`     |
| `otelDeployed`        | Specify if this chart should deploy OpenTelemetry for metrics.               | `false`     |
| `otelEnabled`         | Specify if this chart should sink metrics to OpenTelemetry.                  | `false`     |
| `otelEnvVars`         | Env variables to configure OTEL in the container, sane defaults in chart.    | `{}`        |
| `logLevel`            | Log Level to set for the container and metrics collection.                   | `{}`        |

Opentelemetry configurations can be found [here](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/main/charts/opentelemetry-collector/values.yaml)


## Support Matrix

Hardware

NVIDIA NIMs will run on any NVIDIA GPU, as long as the GPU has sufficient memory, or on multiple, homogeneous NVIDIA GPUs with sufficient aggregate memory and [CUDA compute capability](https://developer.nvidia.com/cuda-gpus) > 7.0 or higher (8.0 for bfloat16). Some model/GPU combinations are optimized. See the following Supported Models section for further information.

## Software

- Linux operating systems (Ubuntu 20.04 or later recommended)
- Docker >= 23.0.1
- NVIDIA Driver >= 535

## Supported Models

These models are optimized using TRT-LLM and are available as pre-built, optimized engines on NGC.

### NV-EmbedQA-Mistral-7b-v2

Load this NIM by adding the following to the `helm upgrade` command.

```bash
--set image.repository=nvcr.io/nim/nvidia/nv-embedqa-mistral-7b-v2 \
--set image.tag=1.0.0 \
```

#### Optimized configurations

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model; **Profile** is for what the model is optimized.

| GPU | GPU Memory | Precision  | Disk Space |
|--------|------|------|------|
| H100 | 7 | FP8 | 14 |
| A100 | 14 | FP16 | 28 |
| L40S PCIe | 7 | FP8 | 14 |
| L40S PCIe | 14 | FP16 | 28 |
| A10G PCIe | 14 | FP16 | 28 |

#### Non-optimized configuration

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model.

| GPUs | GPU Memory | Precision | Disk Space |
|------|------|------|------|
| Any NVIDIA GPU with sufficient GPU memory or on multiple, homogeneous NVIDIA GPUs with sufficient aggregate memory and compute capability > 7.0 or higher (8.0 for bfloat16) | 26 | FP16 | 16 |


### NV-EmbedQA-E5-V5

Load this NIM by adding the following to the `helm upgrade` command.

```bash
--set image.repository=nvcr.io/nim/nvidia/nv-embedqa-e5-v2 \
--set image.tag=1.0.0 \
```


#### Optimized configurations

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model; **Profile** is for what the model is optimized.

| GPU | GPU Memory | Precision  | Disk Space |
|--------|------|------|------|
| A100 | 4 | FP16 | 8 |
| A100 | 4 | FP16 | 8 |
| L40S PCIe | 4 | FP16 | 8 |
| A10G PCIe | 4 | FP16 | 8 |
| A10 PCIe | 4 | FP16 | 8 |

#### Non-optimized configuration

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model.

| GPUs | GPU Memory | Precision | Disk Space |
|------|------|------|------|
| Any NVIDIA GPU with sufficient GPU memory or on multiple, homogeneous NVIDIA GPUs with sufficient aggregate memory and compute capability > 7.0 or higher (8.0 for bfloat16) | 26 | FP16 | 16 |


### Snowflake Arctic

Load this NIM by adding the following to the `helm upgrade` command.

```bash
--set image.repository=nvcr.io/nim/nvidia/arctic-embed-l \
--set image.tag=1.0.0 \
```

#### Optimized configurations

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model; **Profile** is for what the model is optimized.


| GPU | GPU Memory | Precision  | Disk Space |
|--------|------|------|------|
| H100 | 4 | FP16 | 4 |
| A100 | 4 | FP16 | 8 |
| L4 PCIe | 4 | FP16 | 8 |
| L40S PCIe | 4 | FP16 | 8 |
| A10G PCIe | 4 | FP16 | 8 |
| A10 PCIe | 4 | FP16 | 8 |

#### Non-optimized configuration

The **GPU Memory** and **Disk Space** values are in GB; **Disk Space** is for both the container and the model.

| GPUs | GPU Memory | Precision | Disk Space |
|------|------|------|------|
| Any NVIDIA GPU with sufficient GPU memory or on multiple, homogeneous NVIDIA GPUs with sufficient aggregate memory and compute capability > 7.0 or higher (8.0 for bfloat16) | 26 | FP16 | 16 |


<!--
### Using GTE

Run the helm command with the following parameters:

```bash
helm upgrade --install \
  --namespace nrem \
  --set compilation.enabled=true \
  --set compilation.source=git \
  --set compilation.directoryName=thenlper/gte-large \
  --set compilation.template.file="gte_template.yaml" \
  --set compilation.template.custom=null \
  --set compilation.path=https://huggingface.co/thenlper/gte-large \
  --set compilation.checkpoint="" \
  --set compilation.revision="1" \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
```

### Using GTR

Run the helm command with the following parameters:

```bash
helm upgrade --install \
  --namespace nrem \
  --set persistence.class=standard \
  --set persistence.createPV=true \
  --set compilation.enabled=true \
  --set compilation.source=git \
  --set compilation.directoryName=sentence-transformers/gtr-t5-base \
  --set compilation.template.file="gtr_template.yaml" \
  --set compilation.template.custom=null \
  --set compilation.path=https://huggingface.co/sentence-transformers/gtr-t5-base \
  --set compilation.checkpoint="" \
  --set compilation.revision="1" \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
```

### Using E5 - CPU Only mode

Run the helm command with the following parameters:

```bash
helm upgrade --install \
  --namespace nrem \
  --set compilation.enabled=true \
  --set compilation.source=git \
  --set compilation.directoryName=intfloat/e5-small-v2 \
  --set compilation.template.file="e5_cpu_template.yaml" \
  --set compilation.template.custom=null \
  --set compilation.path=https://huggingface.co/intfloat/e5-small-v2 \
  --set compilation.checkpoint="" \
  --set compilation.revision="1" \
  nemo-embedder \
  text-embedding-nim-1.0.0.tgz
``` -->
