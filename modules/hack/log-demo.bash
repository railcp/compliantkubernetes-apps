#!/bin/bash

set -euo pipefail

helmfile -e service_cluster apply -l name=crossplane-packages --include-transitive-needs

kubectl wait --for condition=Healthy=true providers.pkg.crossplane.io/provider-helm --timeout 120s
kubectl wait --for condition=Healthy=true providers.pkg.crossplane.io/provider-kubernetes --timeout 120s
kubectl wait --for condition=Healthy=true functions.pkg.crossplane.io/function-patch-and-transform --timeout 120s
kubectl wait --for condition=Healthy=true functions.pkg.crossplane.io/function-environment-configs --timeout 120s
kubectl wait --for condition=Healthy=true configurations.pkg.crossplane.io/opensearch --timeout 120s

helmfile -e service_cluster apply -l name=module-opensearch --include-transitive-needs
