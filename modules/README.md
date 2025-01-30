# Modules

Generate XRD:

```shell
./hack/definition-gen.bash metrics-server
```

Publish a configuration package:

```shell
./hack/push-package.bash metrics-server v0.0.1
```

Verify that there are no diffs between the existing release and the module payload:

```shell
./hack/test.bash diff-release service_cluster opensearch opensearch-master
```

While developing you might want to diff against the template on main:

```shell
./hack/test.bash diff-template service_cluster opensearch opensearch-master
```

To validate the XR against the XRD:

```shell
./hack/test.bash validate service_cluster opensearch opensearch-master
```

Diff against main and validate:

```shell
./hack/test.bash dev service_cluster opensearch opensearch-master
```
