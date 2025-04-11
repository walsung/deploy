# deploy

A Helm chart for deploy

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
# Standard Helm install
$ helm install  my-release deploy

# To use a custom namespace and force the creation of the namespace
$ helm install my-release --namespace my-namespace --create-namespace deploy

# To use a custom values file
$ helm install my-release -f my-values.yaml deploy
```

See the [Helm documentation](https://helm.sh/docs/intro/using_helm/) for more information on installing and managing the chart.

## Configuration

The following table lists the configurable parameters of the deploy chart and their default values.

| Parameter                                        | Default                  |
| ------------------------------------------------ | ------------------------ |
| `backend-api.imagePullPolicy`                    | `IfNotPresent`           |
| `backend-api.replicas`                           | `1`                      |
| `backend-api.repository.image`                   | `hummingbot/backend-api` |
| `backend-api.repository.tag`                     | `latest`                 |
| `backend-api.serviceAccount`                     | ``                       |
| `dashboard.imagePullPolicy`                      | `IfNotPresent`           |
| `dashboard.replicas`                             | `1`                      |
| `dashboard.repository.image`                     | `hummingbot/dashboard`   |
| `dashboard.repository.tag`                       | `latest`                 |
| `dashboard.serviceAccount`                       | ``                       |
| `emqx.imagePullPolicy`                           | `IfNotPresent`           |
| `emqx.persistence.emqx_data.accessMode[0].value` | `ReadWriteOnce`          |
| `emqx.persistence.emqx_data.enabled`             | `true`                   |
| `emqx.persistence.emqx_data.size`                | `1Gi`                    |
| `emqx.persistence.emqx_data.storageClass`        | `-`                      |
| `emqx.persistence.emqx_etc.accessMode[0].value`  | `ReadWriteOnce`          |
| `emqx.persistence.emqx_etc.enabled`              | `true`                   |
| `emqx.persistence.emqx_etc.size`                 | `1Gi`                    |
| `emqx.persistence.emqx_etc.storageClass`         | `-`                      |
| `emqx.persistence.emqx_log.accessMode[0].value`  | `ReadWriteOnce`          |
| `emqx.persistence.emqx_log.enabled`              | `true`                   |
| `emqx.persistence.emqx_log.size`                 | `1Gi`                    |
| `emqx.persistence.emqx_log.storageClass`         | `-`                      |
| `emqx.replicas`                                  | `1`                      |
| `emqx.repository.image`                          | `emqx`                   |
| `emqx.repository.tag`                            | `5`                      |
| `emqx.serviceAccount`                            | ``                       |


