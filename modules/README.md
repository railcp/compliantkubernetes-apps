# Modules

Publish a configuration package:

```shell
./hack/push-package.bash metrics-server v0.0.1
```

Verify that there are no diffs between the existing release and the module payload:

```shell
helmfile -f ../helmfile.d -e service_cluster template --selector name=opensearch-master |
    ./hack/crossplane-helm.bash diff opensearch opensearch-master
```
